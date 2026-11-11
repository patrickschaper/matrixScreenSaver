#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$ROOT_DIR/Scripts/product-lifecycle.sh" uninstall
