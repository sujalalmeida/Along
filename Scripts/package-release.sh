#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid version.\n' >&2; exit 1; }
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"
mkdir -p "$DIST_DIR" "$PROJECT_ROOT/.build"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"
NAME="TileMe-$VERSION-apple-silicon"
FINAL="$DIST_DIR/$NAME"
if [[ -e "$FINAL" ]]; then printf 'Release output already exists: %s\nUse a new version or DIST_DIR.\n' "$FINAL" >&2; exit 1; fi
SIGNING_IDENTITY=- APP_PATH="$PROJECT_ROOT/build/distribution/TileMe.app" CONFIGURATION=release ./Scripts/build-app.sh
./Scripts/prepare-packaging.sh
WORK="$(mktemp -d "$PROJECT_ROOT/.build/dmg.XXXXXX")"
MOUNT="$WORK/mounted"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then
        if ! hdiutil detach "$MOUNT"; then
            printf 'Temporary image is still mounted at %s; eject it before deleting %s\n' "$MOUNT" "$WORK" >&2
            return
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
STAGE="$WORK/content"
OUTPUT="$WORK/output"
mkdir -p "$STAGE/.background" "$OUTPUT" "$MOUNT"
ditto --norsrc --noextattr "$PROJECT_ROOT/build/distribution/TileMe.app" "$STAGE/TileMe.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/InstallerReadMe.txt "$STAGE/Read Me.txt"
cp Resources/Artwork/InstallerBackground.png "$STAGE/.background/installer.png"
hdiutil create -quiet -fs HFS+ -format UDRW -volname "TileMe $VERSION" -srcfolder "$STAGE" "$WORK/writable.dmg"
hdiutil attach -quiet -nobrowse -readwrite -mountpoint "$MOUNT" "$WORK/writable.dmg"
MOUNTED=1
"$PROJECT_ROOT/.build/packaging/venv/bin/python" Scripts/layout-dmg.py "$MOUNT"
sync
hdiutil detach -quiet "$MOUNT"
MOUNTED=0
hdiutil convert -quiet "$WORK/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/TileMe.app" "$OUTPUT/$NAME.zip"
cp Resources/InstallerReadMe.txt "$OUTPUT/INSTALL.txt"
cp LICENSE "$OUTPUT/LICENSE"
cp docs/release-notes.md "$OUTPUT/RELEASE-NOTES.md"
python3 - "$OUTPUT" "$VERSION" <<'PY'
import json, pathlib, subprocess, sys
out = pathlib.Path(sys.argv[1])
try:
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, stderr=subprocess.DEVNULL).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip())
except subprocess.CalledProcessError:
    commit, dirty = None, True
(out / 'release.json').write_text(json.dumps({
    'name': 'TileMe', 'version': sys.argv[2], 'channel': 'preview',
    'architectures': ['arm64'], 'minimumMacOS': '13.0',
    'signing': 'ad-hoc', 'notarized': False,
    'sourceCommit': commit, 'sourceHasUncommittedChanges': dirty,
}, indent=2) + '\n')
PY
mkdir -p "$WORK/zip-check"
ditto -x -k "$OUTPUT/$NAME.zip" "$WORK/zip-check"
./Scripts/verify-release.sh "$WORK/zip-check/TileMe.app"
# Validate the exact compressed image, not only its staging directory.
hdiutil verify "$OUTPUT/$NAME.dmg"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$OUTPUT/$NAME.dmg"
MOUNTED=1
./Scripts/verify-release.sh "$MOUNT/TileMe.app"
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]]
[[ -f "$MOUNT/.DS_Store" && -f "$MOUNT/Read Me.txt" && -f "$MOUNT/.background/installer.png" ]]
hdiutil detach -quiet "$MOUNT"
MOUNTED=0
(cd "$OUTPUT" && shasum -a 256 "$NAME.dmg" "$NAME.zip" INSTALL.txt LICENSE RELEASE-NOTES.md release.json > SHA256SUMS.txt)
mv "$OUTPUT" "$FINAL"
printf '\nRelease files: %s\nPreview build: ad-hoc signed, not notarized. Test a downloaded copy before publishing.\n' "$FINAL"
