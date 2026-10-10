#!/usr/bin/env bash
# Prints Vibe Clean's version (CFBundleShortVersionString in Resources/Info.plist), or sets it:
# scripts/version.sh 0.5.0
set -euo pipefail
cd "$(dirname "$0")/.."

plist="Resources/Info.plist"
if [[ $# -gt 0 ]]; then
  if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Use a version like 1.2.0" >&2
    exit 1
  fi
  # sed rather than PlistBuddy, which would reorder every key in the file.
  sed -i '' -E "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]*</string>|<string>$1</string>|;}" "$plist"
fi
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist"
