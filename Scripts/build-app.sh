#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP_PATH="${APP_PATH:-$PROJECT_ROOT/build/Along.app}"
case "$APP_PATH" in /*.app) ;; *) printf 'APP_PATH must be an absolute .app path.\n' >&2; exit 1 ;; esac
assert_app_stopped() {
    if /bin/ps -axo comm= | /usr/bin/grep -F -x "$APP_PATH/Contents/MacOS/Along" >/dev/null; then
        printf 'Quit this copy of Along using its menu before rebuilding: %s\n' "$APP_PATH" >&2
        exit 1
    fi
}
assert_app_stopped
source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
if [[ ! -f Resources/AppIcon.icns ]]; then ./Scripts/generate-artwork.sh; fi
mkdir -p "$(dirname "$APP_PATH")"
STAGING="$(mktemp -d "$(dirname "$APP_PATH")/.along-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/Along.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
triple="arm64-apple-macosx13.0"
swift build -c "$CONFIGURATION" --product Along --triple "$triple" --jobs "${BUILD_JOBS:-2}" ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}
binary_directory="$(swift build -c "$CONFIGURATION" --triple "$triple" --show-bin-path)"
cp "$binary_directory/Along" "$BUNDLE/Contents/MacOS/Along"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp LICENSE "$BUNDLE/Contents/Resources/LICENSE"
/usr/bin/plutil -lint "$BUNDLE/Contents/Info.plist" Resources/Along.entitlements
SIGN_FLAGS=()
if [[ "$SIGNING_IDENTITY" != '-' ]]; then SIGN_FLAGS=(--options runtime --timestamp); fi
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} --entitlements Resources/Along.entitlements "$BUNDLE"
/usr/bin/codesign --verify --strict "$BUNDLE"
xcrun lipo "$BUNDLE/Contents/MacOS/Along" -verify_arch arm64
assert_app_stopped
# Only replace the destination after the staged bundle has passed validation.
BACKUP="$STAGING/previous.app"
if [[ -e "$APP_PATH" ]]; then mv "$APP_PATH" "$BACKUP"; fi
if ! mv "$BUNDLE" "$APP_PATH"; then
    if [[ -e "$BACKUP" ]]; then mv "$BACKUP" "$APP_PATH"; fi
    exit 1
fi
printf 'Built: %s\nArchitectures: %s\n' "$APP_PATH" "arm64 (Apple Silicon)"
if [[ "$SIGNING_IDENTITY" == '-' ]]; then
    printf 'Ad-hoc signed. Not Developer ID verified or notarized.\n'
fi
