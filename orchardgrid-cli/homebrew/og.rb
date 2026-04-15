# NOTE — this stand-alone formula is no longer the recommended install path.
#
# OrchardGrid now ships as a single Homebrew cask that bundles BOTH the GUI
# app AND the og CLI. The cask file in the homebrew-orchardgrid tap adds a
# `binary` stanza that automatically symlinks
#
#   /opt/homebrew/bin/og → /Applications/OrchardGrid.app/Contents/Resources/og
#
# at install time. End users should run:
#
#   brew install --cask bingowon/orchardgrid/orchardgrid
#
# This formula is kept around only for users who want a head-of-source CLI
# build without installing the GUI. It builds from the in-repo SPM package.

class Og < Formula
  desc "OrchardGrid CLI — Apple Intelligence from the command line"
  homepage "https://github.com/BingoWon/orchardgrid-apple"
  url "https://github.com/BingoWon/orchardgrid-apple/archive/refs/tags/og-v0.1.0.tar.gz"
  sha256 "REPLACE_ON_RELEASE"
  license "MIT"
  head "https://github.com/BingoWon/orchardgrid-apple.git", branch: "main"

  depends_on macos: :tahoe   # macOS 26+, FoundationModels
  depends_on xcode: ["26.0", :build]

  def install
    cd "orchardgrid-cli" do
      system "swift", "build",
             "-c", "release",
             "--disable-sandbox",
             "--arch", "arm64",
             "--arch", "x86_64"
      bin.install ".build/apple/Products/Release/og"
    end
  end

  test do
    assert_match "og v", shell_output("#{bin}/og --version")
  end
end
