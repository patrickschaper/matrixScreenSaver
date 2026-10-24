#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$ROOT_DIR/Sources/MatrixScreenSaver"
WALLPAPER_DIR="$ROOT_DIR/Sources/MatrixWallpaper"
BUNDLE_DIR="$ROOT_DIR/build/MatrixWallpaper.app"

if [[ ! -s "$ROOT_DIR/VERSION" ]]; then
  echo "VERSION file is missing or empty." >&2
  exit 1
fi
BUNDLE_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
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
  "$WALLPAPER_DIR/WallpaperApp.swift" \
  "$WALLPAPER_DIR/main.swift" \
  -o "$BUNDLE_DIR/Contents/MacOS/MatrixWallpaper"

cp "$ROOT_DIR/Resources/Wallpaper-Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/WallpaperIcon.icns" "$ROOT_DIR/Resources/MenuBarIcon.pdf" "$BUNDLE_DIR/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BUNDLE_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -lint "$BUNDLE_DIR/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null
echo "Built $BUNDLE_DIR"
