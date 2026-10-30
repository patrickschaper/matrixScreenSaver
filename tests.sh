#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/Sources/MatrixScreenSaver"
TESTS="$ROOT/Tests/MatrixScreenSaverTests"
# A bundle exercises the same font-resource lookup used by both shipping products.
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/matrix-screensaver-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
TEST_CONTENTS="$TEST_ROOT/Tests.app/Contents"
TEST_BIN="$TEST_CONTENTS/MacOS/matrix_screensaver_tests"
mkdir -p "$TEST_CONTENTS/MacOS" "$TEST_CONTENTS/Resources"
cp -R "$ROOT/Resources/Fonts" "$TEST_CONTENTS/Resources/Fonts"

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
