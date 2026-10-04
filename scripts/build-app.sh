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

# Ad-hoc signature: enough to run locally, use notifications and register as a login item.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x KeepMyMacClean 2>/dev/null || true
  rm -rf "$HOME/Applications/KeepMyMacClean.app"
  mkdir -p "$HOME/Applications"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/KeepMyMacClean.app"
  echo "Installed to ~/Applications and launched"
fi
