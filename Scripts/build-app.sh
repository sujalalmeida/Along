#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP_PATH="$PROJECT_ROOT/build/TileMe.app"
# Never invalidate the identity of an executable that is still running.
assert_app_stopped() {
    if /bin/ps -axo comm= | /usr/bin/grep -F -x "$APP_PATH/Contents/MacOS/TileMe" >/dev/null; then
        printf 'Quit TileMe using its menu before rebuilding. This also restores managed windows.\n' >&2
        exit 1
    fi
}
assert_app_stopped
source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
swift build -c "$CONFIGURATION" --jobs 1 "${BUILD_FLAGS[@]}"
BINARY_DIRECTORY="$(swift build -c "$CONFIGURATION" --show-bin-path)"
assert_app_stopped
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_DIRECTORY/TileMe" "$APP_PATH/Contents/MacOS/TileMe"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist" Resources/TileMe.entitlements
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --entitlements Resources/TileMe.entitlements "$APP_PATH"
/usr/bin/codesign --verify --strict "$APP_PATH"
printf 'Built and signed: %s\n' "$APP_PATH"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    printf 'Ad-hoc build: if Accessibility stays denied despite an enabled switch, remove and re-add this exact app in System Settings.\n'
fi
