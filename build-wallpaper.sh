#!/usr/bin/env bash
# Build the wallpaper app and its recovery payload; --saver PATH retains a prepared release saver.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$ROOT_DIR/Sources/MatrixScreenSaver"
WALLPAPER_DIR="$ROOT_DIR/Sources/MatrixWallpaper"
BUNDLE_DIR="$ROOT_DIR/build/Matrix Wallpaper.app"

if [[ ! -s "$ROOT_DIR/VERSION" ]]; then
  echo "VERSION file is missing or empty." >&2
  exit 1
fi
BUNDLE_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

# Explicit payloads have already been signed and stapled by the release workflow.
if [[ $# -eq 0 ]]; then
  "$ROOT_DIR/build.sh"
  SAVER_BUNDLE="$ROOT_DIR/build/MatrixScreenSaver.saver"
elif [[ $# -eq 2 && "$1" == --saver ]]; then
  SAVER_BUNDLE="$2"
else
  echo "Usage: $0 [--saver PATH]" >&2
  exit 1
fi
if [[ "$(basename "$SAVER_BUNDLE")" != MatrixScreenSaver.saver ]] ||
   [[ ! -x "$SAVER_BUNDLE/Contents/MacOS/MatrixScreenSaver" ]] ||
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SAVER_BUNDLE/Contents/Info.plist")" != dev.patsch.MatrixScreenSaver ]]; then
  echo "Invalid recovery screen saver: $SAVER_BUNDLE" >&2
  exit 1
fi
for key in CFBundleShortVersionString CFBundleVersion; do
  if [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$SAVER_BUNDLE/Contents/Info.plist")" != "$BUNDLE_VERSION" ]]; then
    echo "Recovery screen saver $key must match VERSION ($BUNDLE_VERSION)." >&2
    exit 1
  fi
done
codesign --verify --deep --strict "$SAVER_BUNDLE"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"

swiftc -O -module-name MatrixWallpaper \
  -framework Foundation -framework AppKit -framework ScreenSaver -framework ServiceManagement \
  "$SOURCE_DIR/TerminalSupport.swift" \
  "$SOURCE_DIR/MatrixScreenSaverOptions.swift" \
  "$SOURCE_DIR/Xorshift64.swift" \
  "$SOURCE_DIR/NeoMessageScene.swift" \
  "$SOURCE_DIR/CmdCaptureScene.swift" \
  "$SOURCE_DIR/MatrixRendererLimits.swift" \
  "$SOURCE_DIR/NativeMatrixRenderer.swift" \
  "$SOURCE_DIR/ScreenSyncCoordinator.swift" \
  "$SOURCE_DIR/SharedWallpaperFrame.swift" \
  "$SOURCE_DIR/WallpaperFrameReader.swift" \
  "$SOURCE_DIR/SharedWallpaperCompositor.swift" \
  "$SOURCE_DIR/MatrixScreenSaverView.swift" \
  "$WALLPAPER_DIR/DesktopWindow.swift" \
  "$WALLPAPER_DIR/WallpaperPlaybackState.swift" \
  "$WALLPAPER_DIR/LoginItemController.swift" \
  "$WALLPAPER_DIR/ScreenSaverInstallationController.swift" \
  "$WALLPAPER_DIR/WallpaperApp.swift" \
  "$WALLPAPER_DIR/main.swift" \
  -o "$BUNDLE_DIR/Contents/MacOS/MatrixWallpaper"

swiftc -O "$ROOT_DIR/Tools/ScreenSaverInstaller.swift" \
  -o "$BUNDLE_DIR/Contents/MacOS/MatrixScreenSaverInstaller"

# PaperSaver is linked into a helper so the native host retains its existing deployment target.
SELECTOR_PACKAGE="$ROOT_DIR/Tools/ScreenSaverSelector"
swift build --package-path "$SELECTOR_PACKAGE" -c release --product MatrixScreenSaverSelector
# Ask SwiftPM for the architecture-specific output directory instead of assuming its layout.
SELECTOR_BIN="$(swift build --package-path "$SELECTOR_PACKAGE" -c release --show-bin-path)"
cp "$SELECTOR_BIN/MatrixScreenSaverSelector" "$BUNDLE_DIR/Contents/MacOS/MatrixScreenSaverSelector"
mkdir -p "$BUNDLE_DIR/Contents/Resources/ThirdParty"
cp "$ROOT_DIR/Resources/ThirdParty/PaperSaver-LICENSE.txt" "$BUNDLE_DIR/Contents/Resources/ThirdParty/"

cp "$ROOT_DIR/Resources/Wallpaper-Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
mkdir -p "$BUNDLE_DIR/Contents/Resources/Fonts"
cp "$ROOT_DIR/Resources/Fonts/"* "$BUNDLE_DIR/Contents/Resources/Fonts/"
cp "$ROOT_DIR/Resources/WallpaperIcon.icns" "$ROOT_DIR/Resources/MenuBarIcon.pdf" "$BUNDLE_DIR/Contents/Resources/"
cp "$ROOT_DIR/Resources/BuyMeACoffee.png" "$BUNDLE_DIR/Contents/Resources/BuyMeACoffee.png"
# Archive the final saver bytes before sealing the outer app signature.
RECOVERY_DIR="$BUNDLE_DIR/Contents/Resources/ScreenSaver"
mkdir -p "$RECOVERY_DIR"
cp "$ROOT_DIR/Scripts/product-lifecycle.sh" "$RECOVERY_DIR/product-lifecycle.sh"
rm -f "$RECOVERY_DIR/MatrixScreenSaver.zip"
ditto -c -k --sequesterRsrc --keepParent "$SAVER_BUNDLE" "$RECOVERY_DIR/MatrixScreenSaver.zip"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BUNDLE_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -lint "$BUNDLE_DIR/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null
echo "Built $BUNDLE_DIR"
