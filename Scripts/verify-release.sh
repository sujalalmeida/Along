#!/bin/bash
set -euo pipefail
APP="${1:?Usage: verify-release.sh /path/to/Along.app}"
BIN="$APP/Contents/MacOS/Along"
plutil -lint "$APP/Contents/Info.plist"
for key in CFBundleName CFBundleDisplayName CFBundleExecutable; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist")" == Along ]] || {
        printf 'Expected Along for %s.\n' "$key" >&2; exit 1
    }
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == io.tileme.app ]]
codesign --verify --strict --verbose=2 "$APP"
python3 - "$APP" "${2:-}" <<'PYVERIFY'
import pathlib, plistlib, re, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info.get('CFBundleShortVersionString', '')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
    sys.exit('Invalid app version in Info.plist.')
if sys.argv[2] and version != sys.argv[2]:
    sys.exit(f'Packaged app version {version} does not match release {sys.argv[2]}.')
if not re.fullmatch(r'[1-9][0-9]*', info.get('CFBundleVersion', '')):
    sys.exit('Invalid bundle build number.')
if info.get('CFBundleIconFile') != 'AppIcon':
    sys.exit('The app icon reference is missing or incorrect.')
entitlements = plistlib.loads(subprocess.check_output(
    ['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
if entitlements.get('com.apple.security.app-sandbox') is not False:
    sys.exit('Accessibility window control requires the shipped app to have App Sandbox disabled.')
PYVERIFY
[[ "$(xcrun lipo -archs "$BIN")" == arm64 ]] || { printf 'Expected Apple Silicon only.\n' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == 13.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" == true ]]
xcrun vtool -show-build "$BIN" | /usr/bin/grep -E 'minos[[:space:]]+13\.0$' >/dev/null
[[ -s "$APP/Contents/Resources/AppIcon.icns" && -s "$APP/Contents/Resources/LICENSE" ]]
if otool -L "$BIN" | tail -n +2 | /usr/bin/grep -E '/Users/|/opt/|/usr/local/' >/dev/null; then
    printf 'Found a dependency on a local development path.\n' >&2; exit 1
fi
printf 'Verified Apple Silicon bundle: %s\n' "$APP"
