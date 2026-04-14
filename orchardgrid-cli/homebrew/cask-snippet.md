# Cask change for the homebrew-orchardgrid tap

To make `brew install --cask bingowon/orchardgrid/orchardgrid` automatically
install both the app and the `og` CLI, add **one line** to the cask file in
the [homebrew-orchardgrid](https://github.com/BingoWon/homebrew-orchardgrid)
repo:

```ruby
cask "orchardgrid" do
  version "1.0.x"
  sha256 "..."
  url "https://github.com/BingoWon/orchardgrid-app/releases/download/#{version}/OrchardGrid-#{version}-macos.dmg"
  name "OrchardGrid"
  desc "Apple Intelligence — local + cloud sharing"
  homepage "https://github.com/BingoWon/orchardgrid-app"

  app "OrchardGrid.app"
  binary "#{appdir}/OrchardGrid.app/Contents/Resources/og"   # ← new

  zap trash: [
    "~/Library/Application Support/com.orchardgrid.app",
    "~/Library/Containers/com.orchardgrid.app",
    "~/Library/Group Containers/group.com.orchardgrid.shared",   # ← new (App Group)
    "~/.config/orchardgrid",                                     # ← new (CLI token)
  ]
end
```

### What `binary "..."` does

Homebrew creates a symlink at `$HOMEBREW_PREFIX/bin/og` pointing into the
installed app bundle. Users get `og` on PATH automatically, and any time
the user upgrades the cask the symlink keeps working — the bundled binary
just gets newer.

### Sanity check after publishing

```sh
brew install --cask bingowon/orchardgrid/orchardgrid
which og                            # → /opt/homebrew/bin/og
readlink $(which og)                # → /Applications/OrchardGrid.app/Contents/Resources/og
og --version
og status                           # reads App Group state from the running app
```
