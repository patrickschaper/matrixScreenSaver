#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/Sources/MatrixScreenSaver"
TEST_BIN=/tmp/matrix_screensaver_tests

swiftc \
  -framework Foundation \
  -framework AppKit \
  -framework ScreenSaver \
  "$SRC/TerminalSupport.swift" \
  "$SRC/MatrixScreenSaverOptions.swift" \
  "$SRC/Xorshift64.swift" \
  "$SRC/NeoMessageScene.swift" \
  "$SRC/NativeMatrixRenderer.swift" \
  "$SRC/MatrixScreenSaverView.swift" \
  "$ROOT/Tests/MatrixScreenSaverTests/main.swift" \
  -o "$TEST_BIN"

"$TEST_BIN"
