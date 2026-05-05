#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT_NAME="MatrixScreenSaver"
BUNDLE_PATH="$ROOT_DIR/build/$PRODUCT_NAME.saver"
HOST_BINARY="$ROOT_DIR/build/$PRODUCT_NAME-preview"

"$ROOT_DIR/build.sh"

swiftc \
  -parse-as-library \
  -o "$HOST_BINARY" \
  "$ROOT_DIR/Tools/PreviewHost.swift" \
  -framework AppKit \
  -framework ScreenSaver

"$HOST_BINARY" "$BUNDLE_PATH" "$@"
