#!/usr/bin/env bash
# Builds KeepMyMacClean.app into dist/. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="dist/KeepMyMacClean.app"

swift build -c "$CONFIG" --product KeepMyMacClean
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KeepMyMacClean" "$APP/Contents/MacOS/KeepMyMacClean"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with: swift scripts/make-icon.swift

# Stamp the build: build number = commit count, plus the commit and build date (shown in Settings → About).
PLIST="$APP/Contents/Info.plist"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then COMMIT="$COMMIT-dirty"; fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :KMMCGitCommit string $COMMIT" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :KMMCBuildDate string $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PLIST"

# Ad-hoc signature: enough to run locally, use notifications and register as a login item.
codesign --force --sign - "$APP"
echo "Built $APP (build $BUILD_NUMBER, $COMMIT)"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x KeepMyMacClean 2>/dev/null || true
  # Wait for it to quit (up to 5 s): reopening too soon fails with error -600.
  for _ in $(seq 25); do pgrep -x KeepMyMacClean >/dev/null || break; sleep 0.2; done
  rm -rf "$HOME/Applications/KeepMyMacClean.app"
  mkdir -p "$HOME/Applications"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/KeepMyMacClean.app"
  echo "Installed to ~/Applications and launched"
fi
