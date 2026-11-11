#!/usr/bin/env bash
# Compatibility entrypoint: a wallpaper install always includes its sibling saver.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -eq 1 ]]; then set -- "$1" "$(dirname "$1")/MatrixScreenSaver.saver"; fi
exec /bin/bash "$ROOT_DIR/install.sh" "$@"
