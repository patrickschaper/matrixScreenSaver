#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/Sources/MatrixScreenSaver"
TESTS="$ROOT/Tests/MatrixScreenSaverTests"
TEST_BIN=/tmp/matrix_screensaver_tests

swiftc \
  -framework Foundation \
  -framework AppKit \
  -framework ScreenSaver \
  "$SRC/TerminalSupport.swift" \
  "$SRC/Xorshift64.swift" \
  "$SRC/NeoMessageScene.swift" \
  "$SRC/CmdCaptureScene.swift" \
  "$SRC/MatrixRendererLimits.swift" \
  "$SRC/ScreenSyncCoordinator.swift" \
  "$SRC/SharedWallpaperFrame.swift" \
  "$SRC/WallpaperFrameReader.swift" \
  "$SRC/NativeMatrixRenderer.swift" \
  "$ROOT/Sources/MatrixWallpaper/WallpaperPlaybackState.swift" \
  "$TESTS/Xorshift64Tests.swift" \
  "$TESTS/ScreenSyncCoordinatorTests.swift" \
  "$TESTS/CmdCaptureSceneTests.swift" \
  "$TESTS/NativeMatrixRendererTests.swift" \
  "$TESTS/WallpaperPlaybackStateTests.swift" \
  "$TESTS/SharedWallpaperFrameTests.swift" \
  "$TESTS/main.swift" \
  -o "$TEST_BIN"

"$TEST_BIN"
