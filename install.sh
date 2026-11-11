#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -eq 0 ]]; then
  "$ROOT_DIR/build.sh"
  "$ROOT_DIR/build-wallpaper.sh" --saver "$ROOT_DIR/build/MatrixScreenSaver.saver"
  set -- "$ROOT_DIR/build/Matrix Wallpaper.app" "$ROOT_DIR/build/MatrixScreenSaver.saver"
fi
exec /bin/bash "$ROOT_DIR/Scripts/product-lifecycle.sh" install "$@"
