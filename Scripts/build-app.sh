#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
swift build -c "$CONFIGURATION" --jobs 1 "${BUILD_FLAGS[@]}"
BINARY_DIRECTORY="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_PATH="$PROJECT_ROOT/build/TileMe.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_DIRECTORY/TileMe" "$APP_PATH/Contents/MacOS/TileMe"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist" Resources/TileMe.entitlements
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --entitlements Resources/TileMe.entitlements "$APP_PATH"
/usr/bin/codesign --verify --strict "$APP_PATH"
printf 'Built and signed: %s\n' "$APP_PATH"
