#!/bin/bash
# Source from scripts after setting PROJECT_ROOT.
# Some Command Line Tools upgrades leave an older private manifest interface.
# Use a local copy of the matching public interface; never modify system files.
TOOLCHAIN_PM="$(dirname "$(xcrun --find swift)")/../lib/swift/pm"
PUBLIC_INTERFACE="$TOOLCHAIN_PM/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
PRIVATE_INTERFACE="$TOOLCHAIN_PM/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
if [[ -z "${SWIFTPM_CUSTOM_LIBS_DIR:-}" && -f "$PUBLIC_INTERFACE" && -f "$PRIVATE_INTERFACE" ]]; then
    PUBLIC_VERSION="$(sed -n '2p' "$PUBLIC_INTERFACE")"
    PRIVATE_VERSION="$(sed -n '2p' "$PRIVATE_INTERFACE")"
    if [[ "$PUBLIC_VERSION" != "$PRIVATE_VERSION" ]]; then
        LOCAL_PM="$PROJECT_ROOT/.build/tileme-toolchain-libs"
        mkdir -p "$LOCAL_PM/ManifestAPI"
        cp -R "$TOOLCHAIN_PM/ManifestAPI/." "$LOCAL_PM/ManifestAPI/"
        find "$LOCAL_PM/ManifestAPI" -name '*.private.swiftinterface' -delete
        export SWIFTPM_CUSTOM_LIBS_DIR="$LOCAL_PM"
        printf 'Using local manifest interfaces to work around mismatched Command Line Tools.\n'
    fi
fi
BUILD_FLAGS=()
SWIFT_HEADERS="$(dirname "$(xcrun --find swift)")/../include/swift"
if [[ -f "$SWIFT_HEADERS/module.modulemap" && -f "$SWIFT_HEADERS/bridging.modulemap" ]] &&
   /usr/bin/grep -q 'module SwiftBridging' "$SWIFT_HEADERS/module.modulemap" &&
   /usr/bin/grep -q 'module SwiftBridging' "$SWIFT_HEADERS/bridging.modulemap"; then
    mkdir -p "$PROJECT_ROOT/.build/tileme-toolchain-libs"
    OVERLAY="$PROJECT_ROOT/.build/tileme-toolchain-libs/overlay.json"
    python3 - "$SWIFT_HEADERS" "$OVERLAY" <<'PYOVERLAY'
import json, pathlib, sys
headers = pathlib.Path(sys.argv[1]).resolve()
overlay = pathlib.Path(sys.argv[2])
empty = overlay.with_name("empty.modulemap")
empty.write_text("// Duplicate legacy module definition hidden for this build.\n")
overlay.write_text(json.dumps({"version": 0, "roots": [{"type": "file", "name": str(headers / "module.modulemap"), "external-contents": str(empty)}]}))
PYOVERLAY
    BUILD_FLAGS=(-Xswiftc -vfsoverlay -Xswiftc "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")
    printf 'Using a local overlay for duplicate SwiftBridging definitions.\n'
fi
