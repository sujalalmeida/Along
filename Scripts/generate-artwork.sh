#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
mkdir -p .build/artwork Resources
COMPILER_FLAGS=()
for flag in ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}; do
    [[ "$flag" == '-Xswiftc' ]] || COMPILER_FLAGS+=("$flag")
done
xcrun swiftc ${COMPILER_FLAGS[@]+"${COMPILER_FLAGS[@]}"} Resources/Artwork/GenerateArtwork.swift -o .build/artwork/generate
.build/artwork/generate "$PROJECT_ROOT/.build/artwork"
iconutil --convert icns .build/artwork/Along.iconset --output Resources/AppIcon.icns
cp .build/artwork/AppIcon.png Resources/Artwork/AppIcon.png
cp .build/artwork/InstallerBackground.png Resources/Artwork/InstallerBackground.png
printf 'Generated app icon and installer artwork.\n'
