#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT_DIR/Matrix Wallpaper.app"
[[ -d "$APP" ]] || APP="$ROOT_DIR/MatrixWallpaper.app"
exec /bin/bash "$ROOT_DIR/Scripts/product-lifecycle.sh" install "$APP" "$ROOT_DIR/MatrixScreenSaver.saver"
