# Releasing

Releases are fully automated on push to `main`. You don't run a `make release` by hand.

## The pipeline

```
git push main
     │
     ├──▶ release.yml parses commits since last tag
     │       │
     │       ├── match ^(feat|fix|perf|refactor)? ──▶ proceed
     │       └── otherwise                          ──▶ skip
     │
     ├──▶ Bump MARKETING_VERSION + CURRENT_PROJECT_VERSION in pbxproj
     ├──▶ Create git tag vX.Y.Z + push
     ├──▶ Create GitHub Release with auto-generated notes
     │
     ├──▶ build-macos job (macOS runner)
     │       ├── Build og CLI release (universal arm64 + x86_64)
     │       ├── Bundle og into OrchardGrid.app/Contents/Resources/
     │       ├── Codesign app + og with Developer ID + entitlements
     │       ├── Create DMG, notarize, staple
     │       └── Upload DMG to the GitHub Release
     │
     └──▶ update-tap job (ubuntu runner)
             ├── Download DMG, compute sha256
             ├── Clone homebrew-orchardgrid via SSH deploy key
             ├── sed version + sha256 in Casks/orchardgrid.rb
             └── Commit + push → users get the update on `brew upgrade`
```

Typical end-to-end: ~6 minutes. No human intervention once the commit lands.

## Conventional Commits → version bump

| Prefix | Bump |
|---|---|
| `feat:` | minor (1.17.x → 1.18.0) |
| `fix:` · `perf:` · `refactor:` | patch (1.18.0 → 1.18.1) |
| any other | no release |

Multiple commits in one push? The pipeline sees them as one release — **highest** prefix wins. Two `fix:` commits + one `feat:` → minor bump.

## Secrets the pipeline depends on

| Secret | Used by | Purpose |
|---|---|---|
| `APPLE_TEAM_ID`, `APPLE_DEVELOPER_CERT_P12`, `APPLE_DEVELOPER_CERT_PASSWORD` | build-macos | Codesign with Developer ID |
| `APPLE_NOTARIZE_API_KEY_P8`, `APPLE_NOTARIZE_API_KEY_ID`, `APPLE_NOTARIZE_API_ISSUER_ID` | build-macos | Notarytool upload |
| `HOMEBREW_TAP_DEPLOY_KEY` | update-tap | SSH private key for pushing to homebrew-orchardgrid (public key is a deploy key with write access on the tap) |

All configured on the `orchardgrid-apple` repo's Actions secrets. Rotating them is a GitHub UI action; the pipeline picks up the new value on the next run.

## Intervening when something breaks

### update-tap failed but DMG uploaded

The release is half-shipped — users on Homebrew won't see it until the tap catches up. Fix:

```sh
# locally
git clone git@github.com:BingoWon/homebrew-orchardgrid.git
cd homebrew-orchardgrid
# Edit Casks/orchardgrid.rb: version + sha256
git commit -am "chore: bump to vX.Y.Z"
git push
```

SHA256 of the DMG is `shasum -a 256 OrchardGrid-vX.Y.Z-macos.dmg`.

### Build or notarize failed

The pipeline aborts; no git tag is created, no partial release shows up. Open the failed run on GitHub Actions, read the step that failed, fix forward (a new `fix(ci):` commit re-runs the whole thing).

**Never** try to manually upload a DMG to a release — notarization requires the exact workflow identity + certificates.

### Need to unship a release

Delete the GitHub Release (not the tag — deleting tags breaks clones). Then either:
- Ship a `fix:` on top that supersedes the bad one (preferred)
- If the cask already points to the bad DMG: edit the tap by hand to revert `version` + `sha256` to the last known-good values

## Local sanity before pushing a `feat:` or `fix:`

```sh
make test                             # every tier
make smoke-live-capabilities          # six capabilities end-to-end, requires running app
make -C orchardgrid-cli smoke-live    # og CLI end-to-end
```

`smoke-live*` are release-gate only — they hit real Apple Intelligence and can't run on any CI runner. If one fails after a risky change, don't push.

## Manual fallback

If CI is permanently broken, the manual path is documented in-line in [.github/workflows/release.yml](../.github/workflows/release.yml). Never build the DMG locally for release under normal circumstances — notarization requires the exact workflow identity + certificates.

## Cloud backend

The worker + dashboard live in [BingoWon/orchardgrid](https://github.com/BingoWon/orchardgrid). Its release model is different — `pnpm deploy` from a dev machine ships to Cloudflare Workers whenever the maintainer runs it; no commit-triggered automation.
