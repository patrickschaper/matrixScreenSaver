#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT_NAME="MatrixScreenSaver"
BUILD_BUNDLE="$ROOT_DIR/build/$PRODUCT_NAME.saver"
INSTALL_BUNDLE="$HOME/Library/Screen Savers/$PRODUCT_NAME.saver"
BUILD_EXECUTABLE="$BUILD_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
INSTALL_EXECUTABLE="$INSTALL_BUNDLE/Contents/MacOS/$PRODUCT_NAME"

terminate_matching_processes() {
  local process_name="$1"
  local pids
  pids="$(pgrep -x "$process_name" || true)"

  [[ -z "$pids" ]] && return

  echo "Stopping running $process_name processes: $pids"

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    kill "$pid" 2>/dev/null || true
  done <<<"$pids"

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    for _ in {1..20}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done

    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  done <<<"$pids"
}

"$ROOT_DIR/build.sh"

mkdir -p "$(dirname "$INSTALL_BUNDLE")"
rm -rf "$INSTALL_BUNDLE"
ditto "$BUILD_BUNDLE" "$INSTALL_BUNDLE"

BUILD_HASH="$(shasum -a 256 "$BUILD_EXECUTABLE" | awk '{print $1}')"
INSTALL_HASH="$(shasum -a 256 "$INSTALL_EXECUTABLE" | awk '{print $1}')"

if [[ "$BUILD_HASH" != "$INSTALL_HASH" ]]; then
  echo "Installed bundle does not match the build output." >&2
  echo "build:    $BUILD_HASH" >&2
  echo "installed:$INSTALL_HASH" >&2
  exit 1
fi

terminate_matching_processes "ScreenSaverEngine"
terminate_matching_processes "legacyScreenSaver"

echo "Installed $INSTALL_BUNDLE"
echo "Relaunch with: open -a ScreenSaverEngine"
