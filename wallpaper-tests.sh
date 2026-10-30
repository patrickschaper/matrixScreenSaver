#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$ROOT_DIR/Sources/MatrixScreenSaver"
WALLPAPER_DIR="$ROOT_DIR/Sources/MatrixWallpaper"
TEST_DIR="$ROOT_DIR/Tests/MatrixWallpaperTests"
# Keep bundled font lookup identical in the app tests and the consumer-host copy.
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/matrix-wallpaper-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
TEST_CONTENTS="$TEST_ROOT/Tests.app/Contents"
HOST_DIR="$TEST_CONTENTS/MacOS"
TEST_BIN="$HOST_DIR/matrix-wallpaper-tests"
mkdir -p "$HOST_DIR" "$TEST_CONTENTS/Resources"
cp -R "$ROOT_DIR/Resources/Fonts" "$TEST_CONTENTS/Resources/Fonts"

OPTIMIZATION="-Onone"
if [[ "${1:-}" == "--gpu-composition-benchmark" || "${1:-}" == "--composition-benchmark" ]]; then
  OPTIMIZATION="-O"
fi

swiftc "$OPTIMIZATION" -framework Foundation -framework AppKit -framework ScreenSaver -framework ServiceManagement \
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
  "$WALLPAPER_DIR/DesktopWallpaperController.swift" \
  "$WALLPAPER_DIR/WallpaperApp.swift" \
  "$TEST_DIR/SharedSaverTests.swift" \
  "$TEST_DIR/ConsumerHost.swift" \
  "$TEST_DIR/SharedCompositionTests.swift" \
  "$TEST_DIR/GPUCompositionTests.swift" \
  "$TEST_DIR/WallpaperAppTests.swift" \
  "$TEST_DIR/LoginItemTests.swift" \
  "$TEST_DIR/DesktopWallpaperTests.swift" \
  "$TEST_DIR/main.swift" \
  -o "$TEST_BIN"

if [[ "${1:-}" == "--composition-benchmark" || "${1:-}" == "--composition-tests" || "${1:-}" == "--gpu-composition-tests" || "${1:-}" == "--gpu-composition-benchmark" ]]; then
  "$TEST_BIN" "$1"
  exit
fi
if [[ "${1:-}" == "--consumer-host" ]]; then
  cp "$TEST_BIN" "$HOST_DIR/ScreenSaverEngine"
  "$HOST_DIR/ScreenSaverEngine" --consumer-host
  exit
fi
"$TEST_BIN"
cp "$TEST_BIN" "$HOST_DIR/ScreenSaverEngine"
"$HOST_DIR/ScreenSaverEngine" --consumer-host
