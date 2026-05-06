#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT_NAME="MatrixScreenSaver"
BUILD_DIR="$ROOT_DIR/build"
BUNDLE_DIR="$BUILD_DIR/$PRODUCT_NAME.saver"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_DIR="$ROOT_DIR/Sources/$PRODUCT_NAME"
INPUT_RESOURCES_DIR="$ROOT_DIR/Resources"
BUNDLE_VERSION="$(date +%s)"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc \
  -O \
  -parse-as-library \
  -module-name "$PRODUCT_NAME" \
  -emit-library \
  -Xlinker -bundle \
  -o "$MACOS_DIR/$PRODUCT_NAME" \
  -framework Foundation \
  -framework AppKit \
  -framework ScreenSaver \
  "$SOURCE_DIR/TerminalSupport.swift" \
  "$SOURCE_DIR/MatrixScreenSaverOptions.swift" \
  "$SOURCE_DIR/NativeMatrixRenderer.swift" \
  "$SOURCE_DIR/MatrixScreenSaverView.swift"

cp "$INPUT_RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$CONTENTS_DIR/Info.plist"
fi

chmod +x "$MACOS_DIR/$PRODUCT_NAME"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null
fi

echo "Built $BUNDLE_DIR"
