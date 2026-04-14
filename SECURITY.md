# Security policy

## Supported versions

Only the **latest released version** on Homebrew / App Store receives security fixes. Older versions are unsupported — upgrade to stay secure.

## Reporting a vulnerability

**Do not open a public issue.** Report privately via GitHub's security advisory form:

https://github.com/BingoWon/orchardgrid-app/security/advisories/new

Include:

- OrchardGrid version (`About OrchardGrid` → version & build).
- macOS / iOS version and device model.
- Minimal reproduction steps.
- Impact assessment (who can trigger it, what they gain).

### Response timeline

| Step | Target |
|---|---|
| Acknowledge receipt | 3 business days |
| Initial assessment | 10 business days |
| Fix released | 30 days for high/critical; best-effort otherwise |

Credit is given in the release notes unless the reporter prefers anonymity.

## Scope

In scope:

- **Cloud relay worker** (WebSocket `/device/connect`, `/observe`) — token auth, message validation, rate limits.
- **Local HTTP API** (`:8888`) — endpoint auth, request parsing, capability dispatch.
- **Auth flow** — Clerk session handling, token storage, account deletion.
- **CLI OAuth loopback** (`orchardgrid.com/cli/login`) — PKCE exchange, management-scope key issuance, `~/.config/orchardgrid` handling.
- **API key scopes** — `inference` vs `management` separation; privilege escalation between scopes.
- **App Group `group.com.orchardgrid.shared`** — state shared between app and `og` CLI; any cross-process trust assumption.
- **Build & release pipeline** — signing, notarization, Homebrew tap integrity (both `app` and `binary` stanzas).
- **Entitlements** — any over-scoped capability on macOS or iOS (5 app entitlement files + `og.entitlements`).

Out of scope:

- Vulnerabilities in Apple frameworks (FoundationModels, Vision, etc.) — report to Apple.
- Vulnerabilities in third-party SDKs (Clerk) — report to the respective vendor. We will track the upstream fix and bump.
- Social engineering, physical access, or issues requiring a compromised device.
- Denial of service against your own device (the local API server is explicitly for your LAN).

## Design principles (for reviewers)

- **Cloud never sees model I/O.** Only task ids, device ids, and capability names flow through the relay. Payloads are end-to-end between the requesting client and the executing device.
- **Auth tokens are never cached.** Every outbound request fetches a fresh Clerk token. No keychain writes of bearer tokens.
- **Local API binds to all interfaces by design.** The port 8888 server is meant for LAN use. If you expose it to the public internet, that's on you — we document this in the README.
- **Fail-loud config.** Missing `API_BASE_URL` or `CLERK_PUBLISHABLE_KEY` crashes on launch rather than falling back to an unsafe default.
- **No telemetry.** The app does not phone home beyond the cloud relay you explicitly sign in to.

## Handling reports publicly

Once a fix ships, we publish a GitHub Security Advisory with:

- Affected versions.
- Fixed version.
- Credit (if desired).
- Mitigation for users who cannot upgrade immediately.

---

*Last reviewed: 2026-04-15*
