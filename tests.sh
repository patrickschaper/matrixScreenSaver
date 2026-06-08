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
  "$SRC/MatrixRendererLimits.swift" \
  "$SRC/ScreenSyncCoordinator.swift" \
  "$SRC/NativeMatrixRenderer.swift" \
  "$TESTS/Xorshift64Tests.swift" \
  "$TESTS/ScreenSyncCoordinatorTests.swift" \
  "$TESTS/NativeMatrixRendererTests.swift" \
  "$TESTS/main.swift" \
  -o "$TEST_BIN"

"$TEST_BIN"
