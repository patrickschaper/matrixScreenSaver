#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT_NAME="MatrixScreenSaver"
BUILD_BUNDLE="$ROOT_DIR/build/$PRODUCT_NAME.saver"

"$ROOT_DIR/build.sh"
"$ROOT_DIR/Scripts/install-saver.sh" "$BUILD_BUNDLE"
