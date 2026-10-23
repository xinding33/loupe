#!/bin/bash
# Builds dist/Loupe.app and dist/Loupe.zip.
#
#   APP_VERSION        version to stamp (releases pass it from the tag; default: latest tag, else 0.0.0)
#   SIGN_IDENTITY      codesign identity (default: this Mac's Developer ID if it has one, else ad hoc)
#   APP_BUILD          "development" (default) or "release". Only release builds install updates.
#   ARCHS              "arm64" (default) or "arm64 x86_64" (releases)
#   SWIFT_BUILD_FLAGS  extra `swift build` flags, e.g. the Makefile's sandbox and cache paths
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${APP_VERSION:-$( (git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true) | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
BUILD="${APP_BUILD:-development}"
# A stable identity keeps Screen Recording and Accessibility grants across rebuilds. Ad hoc
# signatures change every build, so macOS treats each build as a new app.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
IDENTITY="${IDENTITY:--}"
# Identifies the exact sources in diagnostic reports, so a replay can name the build it ran.
FINGERPRINT="sha256-$( { find Sources -type f -name '*.swift' -exec shasum -a 256 {} \; ; shasum -a 256 Package.swift scripts/Info.plist scripts/build.sh; } | LC_ALL=C sort | shasum -a 256 | cut -d ' ' -f 1)"

FLAGS=(-c release)
for arch in ${ARCHS:-arm64}; do FLAGS+=(--arch "$arch"); done
# shellcheck disable=SC2206
FLAGS+=(${SWIFT_BUILD_FLAGS:-})
swift build "${FLAGS[@]}"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

rm -rf dist
APP="$PWD/dist/Loupe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Loupe" "$APP/Contents/MacOS/Loupe"
cp scripts/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace LoupeBuild -string "$BUILD" "$APP/Contents/Info.plist"
plutil -replace LoupeBuildFingerprint -string "$FINGERPRINT" "$APP/Contents/Info.plist"
if [ -f LICENSE ]; then cp LICENSE "$APP/Contents/Resources/LICENSE"; fi
swift scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns"

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
elif [ "$BUILD" = release ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  # Only notarization needs Apple's timestamp, and a local build shouldn't need the internet.
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Loupe.zip"
printf 'Built: %s (%s, %s, signed by %s)\n' "$APP" "$VERSION" "$BUILD" "$IDENTITY"
