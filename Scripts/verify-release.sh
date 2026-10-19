#!/bin/bash
set -euo pipefail
APP="${1:?Usage: verify-release.sh /path/to/TileMe.app}"
BIN="$APP/Contents/MacOS/TileMe"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$APP"
[[ "$(xcrun lipo -archs "$BIN")" == arm64 ]] || { printf 'Expected Apple Silicon only.\n' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == 13.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" == true ]]
xcrun vtool -show-build "$BIN" | /usr/bin/grep -E 'minos[[:space:]]+13\.0$' >/dev/null
[[ -s "$APP/Contents/Resources/AppIcon.icns" && -s "$APP/Contents/Resources/LICENSE" ]]
if otool -L "$BIN" | tail -n +2 | /usr/bin/grep -E '/Users/|/opt/|/usr/local/' >/dev/null; then
    printf 'Found a dependency on a local development path.\n' >&2; exit 1
fi
printf 'Verified Apple Silicon bundle: %s\n' "$APP"
