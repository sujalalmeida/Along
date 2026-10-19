#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
swift test --disable-xctest --enable-swift-testing --jobs 1 ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}
