#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_BUNDLE="${1:-$ROOT_DIR/build/Matrix Wallpaper.app}"
if [[ ! -d "$SOURCE_BUNDLE" ]]; then
  echo "Build the app with ./build-wallpaper.sh before running installer checks." >&2
  exit 1
fi
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/matrix-wallpaper-install-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
INSTALL_BUNDLE="$HOME/Applications/Matrix Wallpaper.app"
LEGACY_BUNDLE="$HOME/Applications/MatrixWallpaper.app"
EXPECTED_BUNDLE="$INSTALL_BUNDLE"
mkdir -p "$HOME" "$TEST_DIR/bin"
export PATH="$TEST_DIR/bin:$PATH"

# Test copies never start an app or interact with real running processes.
export QUIT_LOG="$TEST_DIR/quit-request"
cat > "$TEST_DIR/bin/osascript" <<'SCRIPT'
#!/bin/bash
cat >/dev/null
[[ "${SIMULATE_QUIT_FAILURE:-0}" != 1 ]] || exit 1
touch "$QUIT_LOG"
SCRIPT
cat > "$TEST_DIR/bin/ditto" <<'SCRIPT'
#!/bin/bash
[[ "${FAIL_COPY:-0}" != 1 ]] || exit 1
/usr/bin/ditto "$@"
if [[ "${CORRUPT_COPY:-0}" == 1 ]]; then
  printf 'corrupt' >> "$2/Contents/MacOS/MatrixWallpaper"
fi
SCRIPT
cat > "$TEST_DIR/bin/mv" <<'SCRIPT'
#!/bin/bash
if [[ "${FAIL_PROMOTION:-0}" == 1 && "$1" == */.MatrixWallpaper-install.*/"Matrix Wallpaper.app" ]]; then
  exit 1
fi
/bin/mv "$@"
SCRIPT
chmod +x "$TEST_DIR/bin/osascript" "$TEST_DIR/bin/ditto" "$TEST_DIR/bin/mv"

install_app() { bash "$ROOT_DIR/install-wallpaper.sh" "$SOURCE_BUNDLE" > "$TEST_DIR/output" 2>&1; }
expect_failure() {
  if install_app; then
    echo "not ok - $1" >&2
    exit 1
  fi
  [[ "$(stat -f %i "$EXPECTED_BUNDLE")" == "$OLD_INODE" ]]
  codesign --verify --deep --strict "$EXPECTED_BUNDLE"
  echo "ok - $1 preserves the working installation"
}

install_app
[[ -f "$QUIT_LOG" ]]
codesign --verify --deep --strict "$INSTALL_BUNDLE"
cmp "$SOURCE_BUNDLE/Contents/MacOS/MatrixWallpaper" "$INSTALL_BUNDLE/Contents/MacOS/MatrixWallpaper"
echo "ok - installs a verified app into user Applications"
OLD_INODE="$(stat -f %i "$INSTALL_BUNDLE")"
mkdir -p "$HOME/Library/Preferences"
printf 'unchanged preferences' > "$HOME/Library/Preferences/dev.patsch.MatrixScreenSaver.plist"
export FAIL_COPY=1
expect_failure "copy failure"
unset FAIL_COPY
export CORRUPT_COPY=1
expect_failure "signature verification failure"
unset CORRUPT_COPY
export FAIL_PROMOTION=1
expect_failure "promotion failure"
unset FAIL_PROMOTION
export SIMULATE_QUIT_FAILURE=1
expect_failure "app refusing to quit"
unset SIMULATE_QUIT_FAILURE
install_app
[[ "$(stat -f %i "$INSTALL_BUNDLE")" != "$OLD_INODE" ]]
[[ "$(cat "$HOME/Library/Preferences/dev.patsch.MatrixScreenSaver.plist")" == 'unchanged preferences' ]]
[[ -z "$(find "$HOME/Applications" -maxdepth 1 -name '.MatrixWallpaper-install.*' -print)" ]]
echo "ok - reinstall replaces the old bundle and cleans staging"

# An old-name-only installation must survive failures at each replacement stage.
/bin/mv "$INSTALL_BUNDLE" "$LEGACY_BUNDLE"
EXPECTED_BUNDLE="$LEGACY_BUNDLE"
OLD_INODE="$(stat -f %i "$LEGACY_BUNDLE")"
for failure in FAIL_COPY CORRUPT_COPY FAIL_PROMOTION; do
  export "$failure=1"
  expect_failure "rename migration $failure"
  unset "$failure"
  [[ ! -e "$INSTALL_BUNDLE" ]]
done
install_app
[[ ! -e "$LEGACY_BUNDLE" ]]
codesign --verify --deep --strict "$INSTALL_BUNDLE"
cmp "$SOURCE_BUNDLE/Contents/MacOS/MatrixWallpaper" "$INSTALL_BUNDLE/Contents/MacOS/MatrixWallpaper"
echo "ok - migrates the old filename to Matrix Wallpaper.app"

# Both prior copies are recoverable when a user already has both filenames.
/usr/bin/ditto "$SOURCE_BUNDLE" "$LEGACY_BUNDLE"
LEGACY_INODE="$(stat -f %i "$LEGACY_BUNDLE")"
EXPECTED_BUNDLE="$INSTALL_BUNDLE"
OLD_INODE="$(stat -f %i "$INSTALL_BUNDLE")"
export FAIL_PROMOTION=1
expect_failure "promotion with both filenames"
unset FAIL_PROMOTION
[[ "$(stat -f %i "$LEGACY_BUNDLE")" == "$LEGACY_INODE" ]]
codesign --verify --deep --strict "$LEGACY_BUNDLE"
install_app
[[ ! -e "$LEGACY_BUNDLE" ]]
echo "ok - rolls back both filenames and removes the legacy copy only after success"

/usr/bin/ditto "$SOURCE_BUNDLE" "$LEGACY_BUNDLE"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.example.Unrelated' "$LEGACY_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$LEGACY_BUNDLE"
LEGACY_INODE="$(stat -f %i "$LEGACY_BUNDLE")"
install_app
[[ "$(stat -f %i "$LEGACY_BUNDLE")" == "$LEGACY_INODE" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_BUNDLE/Contents/Info.plist")" == dev.example.Unrelated ]]
codesign --verify --deep --strict "$LEGACY_BUNDLE"
echo "ok - preserves an unrelated signed bundle at the old filename"

rm -rf "$LEGACY_BUNDLE"
ln -s "$INSTALL_BUNDLE" "$LEGACY_BUNDLE"
install_app
[[ -L "$LEGACY_BUNDLE" && "$(readlink "$LEGACY_BUNDLE")" == "$INSTALL_BUNDLE" ]]
echo "ok - leaves an old-name symlink untouched"

/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.example.Unrelated' "$INSTALL_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$INSTALL_BUNDLE"
OLD_INODE="$(stat -f %i "$INSTALL_BUNDLE")"
expect_failure "unrelated app at the new filename"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_BUNDLE/Contents/Info.plist")" == dev.example.Unrelated ]]
[[ "$(cat "$HOME/Library/Preferences/dev.patsch.MatrixScreenSaver.plist")" == 'unchanged preferences' ]]
[[ -z "$(find "$HOME/Applications" -maxdepth 1 -name '.MatrixWallpaper-install.*' -print)" ]]
