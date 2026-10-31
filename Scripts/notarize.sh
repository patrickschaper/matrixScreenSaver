#!/usr/bin/env bash
# Submit both signed build bundles to Apple, then staple their tickets in place.
# Requires NOTARY_KEYCHAIN_PROFILE created with `xcrun notarytool store-credentials`.
# NOTARY_KEYCHAIN optionally selects a non-default keychain (used by CI).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to your notarytool credential profile.}"
BUNDLES=("$ROOT_DIR/build/MatrixScreenSaver.saver" "$ROOT_DIR/build/Matrix Wallpaper.app")

for bundle in "${BUNDLES[@]}"; do
  codesign --verify --deep --strict "$bundle"
  if ! codesign --display --verbose=4 "$bundle" 2>&1 | grep -q '^Authority=Developer ID Application: '; then
    echo "Notarization requires Developer ID Application signing: $bundle" >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/matrix-notarize.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir "$WORK_DIR/payload"
for bundle in "${BUNDLES[@]}"; do
  ditto "$bundle" "$WORK_DIR/payload/$(basename "$bundle")"
done
ditto -c -k --sequesterRsrc "$WORK_DIR/payload" "$WORK_DIR/submission.zip"

AUTH=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  AUTH+=(--keychain "$NOTARY_KEYCHAIN")
fi
xcrun notarytool submit "$WORK_DIR/submission.zip" \
  "${AUTH[@]}" --wait --output-format plist > "$WORK_DIR/result.plist"
cat "$WORK_DIR/result.plist"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :status' "$WORK_DIR/result.plist")" != "Accepted" ]]; then
  echo 'Apple did not accept the submission. Use `xcrun notarytool log ID --keychain-profile PROFILE` for details.' >&2
  exit 1
fi

# ZIPs cannot carry stapled tickets: staple the originals before release packaging.
for bundle in "${BUNDLES[@]}"; do
  xcrun stapler staple "$bundle"
  xcrun stapler validate "$bundle"
  codesign --verify --deep --strict "$bundle"
done
