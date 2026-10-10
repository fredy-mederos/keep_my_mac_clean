#!/usr/bin/env bash
# Builds Vibe Clean (release, for Apple silicon and Intel) with scripts/build-app.sh, signs it with a Developer ID and
# packs it into dist/VibeClean.dmg, signed too. scripts/release.sh runs this, then scripts/notarize_dmg.sh.
#
# Usage: APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/create_dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APP_SIGN_IDENTITY:?Set APP_SIGN_IDENTITY, e.g. \"Developer ID Application: Your Name (TEAMID)\"}"

name="Vibe Clean"
app="dist/$name.app"
staging="dist/dmg-staging"
dmg="dist/VibeClean.dmg"

# A release is built from a commit: build-app.sh stamps its hash (shown in Settings → About), with "+" for
# uncommitted changes.
if [[ -n "$(git status --porcelain)" && -z "${ALLOW_DIRTY:-}" ]]; then
  echo "There are uncommitted changes. Commit them first, or set ALLOW_DIRTY=1 for a test build." >&2
  exit 1
fi

CONFIG=release ARCHS="arm64 x86_64" scripts/build-app.sh

# The Developer ID signature, with the hardened runtime and a secure timestamp: notarization requires both.
codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$app"
codesign --verify --deep --strict "$app"

rm -rf "$staging" "$dmg"
mkdir -p "$staging"
ditto "$app" "$staging/$name.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "$name" -srcfolder "$staging" -format UDZO -imagekey zlib-level=9 -quiet "$dmg"
codesign --force --timestamp --sign "$APP_SIGN_IDENTITY" "$dmg"
rm -rf "$staging"

plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
commit=$(/usr/libexec/PlistBuddy -c "Print :KMMCGitCommit" "$plist")
echo "Created $dmg: $name $version (build $build, $commit)"
