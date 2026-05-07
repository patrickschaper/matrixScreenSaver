#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="MatrixScreenSaver"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_BUNDLE_INPUT="${1:-$SCRIPT_DIR/$PRODUCT_NAME.saver}"
SOURCE_BUNDLE="$(cd "$(dirname "$SOURCE_BUNDLE_INPUT")" && pwd)/$(basename "$SOURCE_BUNDLE_INPUT")"
INSTALL_BUNDLE="$HOME/Library/Screen Savers/$PRODUCT_NAME.saver"
SOURCE_EXECUTABLE="$SOURCE_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
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

strip_quarantine() {
  local path="$1"
  if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$path" 2>/dev/null || true
  fi
}

if [[ ! -d "$SOURCE_BUNDLE" ]]; then
  echo "Source screen saver bundle not found at $SOURCE_BUNDLE" >&2
  exit 1
fi

if [[ ! -x "$SOURCE_EXECUTABLE" ]]; then
  echo "Source screen saver executable not found at $SOURCE_EXECUTABLE" >&2
  exit 1
fi

strip_quarantine "$SOURCE_BUNDLE"

mkdir -p "$(dirname "$INSTALL_BUNDLE")"
rm -rf "$INSTALL_BUNDLE"
ditto "$SOURCE_BUNDLE" "$INSTALL_BUNDLE"
strip_quarantine "$INSTALL_BUNDLE"

SOURCE_HASH="$(shasum -a 256 "$SOURCE_EXECUTABLE" | awk '{print $1}')"
INSTALL_HASH="$(shasum -a 256 "$INSTALL_EXECUTABLE" | awk '{print $1}')"

if [[ "$SOURCE_HASH" != "$INSTALL_HASH" ]]; then
  echo "Installed bundle does not match the source bundle." >&2
  echo "source:   $SOURCE_HASH" >&2
  echo "installed:$INSTALL_HASH" >&2
  exit 1
fi

terminate_matching_processes "ScreenSaverEngine"
terminate_matching_processes "legacyScreenSaver"
terminate_matching_processes "legacyScreenSaver-x86_64"

echo "Installed $INSTALL_BUNDLE"
echo "Relaunch with: open -a ScreenSaverEngine"
