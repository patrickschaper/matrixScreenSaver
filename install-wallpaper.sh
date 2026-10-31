#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_BUNDLE="${1:-$ROOT_DIR/build/Matrix Wallpaper.app}"
INSTALL_DIR="$HOME/Applications"
INSTALL_BUNDLE="$INSTALL_DIR/Matrix Wallpaper.app"
LEGACY_BUNDLE="$INSTALL_DIR/MatrixWallpaper.app"

if ! osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('dev.patsch.MatrixWallpaper');
for (let i = 0; i < apps.count; i++) {
    if (!apps.objectAtIndex(i).terminate) {
        throw new Error('Matrix Wallpaper refused to quit.');
    }
}
const deadline = Date.now() + 5000;
for (let i = 0; i < apps.count; i++) {
    while (!apps.objectAtIndex(i).terminated) {
        if (Date.now() >= deadline) {
            throw new Error('Matrix Wallpaper did not quit within five seconds.');
        }
        // NSRunningApplication updates termination state through the run loop.
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
    }
}
JXA
then
  echo "Could not quit Matrix Wallpaper. Quit it from its menu and try again; installation cancelled." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  "$ROOT_DIR/build-wallpaper.sh"
fi

if [[ -L "$INSTALL_BUNDLE" || ( -e "$INSTALL_BUNDLE" && ! -d "$INSTALL_BUNDLE" ) ]]; then
  echo "Refusing to replace a symlink or non-directory: $INSTALL_BUNDLE" >&2
  exit 1
fi

verify_bundle() {
  local bundle="$1"
  [[ -x "$bundle/Contents/MacOS/MatrixWallpaper" ]] &&
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" == "dev.patsch.MatrixWallpaper" ]] &&
    codesign --verify --deep --strict "$bundle"
}

if ! verify_bundle "$SOURCE_BUNDLE"; then
  echo "Source is not a valid signed Matrix Wallpaper app: $SOURCE_BUNDLE" >&2
  exit 1
fi

if [[ -d "$INSTALL_BUNDLE" ]] && ! verify_bundle "$INSTALL_BUNDLE"; then
  echo "Refusing to replace an unrecognized app: $INSTALL_BUNDLE" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
STAGING="$(mktemp -d "$INSTALL_DIR/.MatrixWallpaper-install.XXXXXX")"

cleanup() {
  local result=$?
  if [[ -d "$STAGING/previous.app" && ! -e "$INSTALL_BUNDLE" ]]; then
    if ! mv "$STAGING/previous.app" "$INSTALL_BUNDLE"; then
      echo "Restore failed. Your previous app is preserved at $STAGING/previous.app" >&2
      return 1
    fi
  fi
  if [[ "$result" -ne 0 && -d "$STAGING/legacy.app" && ! -e "$LEGACY_BUNDLE" ]]; then
    if ! mv "$STAGING/legacy.app" "$LEGACY_BUNDLE"; then
      echo "Restore failed. Your previous app is preserved at $STAGING/legacy.app" >&2
      return 1
    fi
  fi
  rm -rf "$STAGING"
  return "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$SOURCE_BUNDLE" "$STAGING/Matrix Wallpaper.app"
verify_bundle "$STAGING/Matrix Wallpaper.app"
SOURCE_HASH="$(shasum -a 256 "$SOURCE_BUNDLE/Contents/MacOS/MatrixWallpaper" | awk '{print $1}')"
COPIED_HASH="$(shasum -a 256 "$STAGING/Matrix Wallpaper.app/Contents/MacOS/MatrixWallpaper" | awk '{print $1}')"
if [[ "$SOURCE_HASH" != "$COPIED_HASH" ]]; then
  echo "Copied executable does not match the source; installation cancelled." >&2
  exit 1
fi

if [[ -d "$INSTALL_BUNDLE" ]]; then
  mv "$INSTALL_BUNDLE" "$STAGING/previous.app"
fi
# Keep the old bundle for rollback until promotion succeeds; ignore unrelated bundles and symlinks.
if [[ ! -L "$LEGACY_BUNDLE" && -d "$LEGACY_BUNDLE" ]] && verify_bundle "$LEGACY_BUNDLE" >/dev/null 2>&1; then
  mv "$LEGACY_BUNDLE" "$STAGING/legacy.app"
fi
mv "$STAGING/Matrix Wallpaper.app" "$INSTALL_BUNDLE"
echo "Installed $INSTALL_BUNDLE"
echo "Double-click it in Finder, or run: open \"$INSTALL_BUNDLE\""
