#!/usr/bin/env bash
# Compatibility entrypoint: standalone saver installation is no longer supported.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -eq 0 ]]; then exec /bin/bash "$ROOT_DIR/install.sh"; fi
exec /bin/bash "$ROOT_DIR/install.sh" "$(dirname "$1")/Matrix Wallpaper.app" "$1"
