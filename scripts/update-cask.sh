#!/bin/bash
# Writes the loupe cask for a release into a homebrew-tap checkout. The release workflow runs
# this, and it rewrites the whole file, so change the cask here rather than in the tap.
# Usage: scripts/update-cask.sh TAP_DIR VERSION SHA256
#
# Loupe updates itself, so the cask says `auto_updates true` and `brew upgrade` leaves it alone.
# Keep it that way from the first release: adding it later strands installs that can't update.
set -euo pipefail
TAP="$1" VERSION="$2" SHA="$3"
mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/loupe.rb" <<CASK
cask "loupe" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/xinding33/loupe/releases/download/v#{version}/Loupe-#{version}.zip"
  name "Loupe"
  desc "Overlay that tells you which Genshin Impact artifacts to keep, level or feed"
  homepage "https://github.com/xinding33/loupe"

  auto_updates true
  depends_on macos: :sonoma

  app "Loupe.app"

  uninstall quit: "io.github.xinding33.loupe"

  zap trash: [
    "~/Library/Application Support/Loupe",
    "~/Library/Preferences/io.github.xinding33.loupe.plist",
    "~/Library/Saved Application State/io.github.xinding33.loupe.savedState",
  ]
end
CASK
