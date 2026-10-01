#!/bin/bash
# Operates only on temporary Caskroom, native destinations, cache, and fixture tap.
set -euo pipefail
cd "$(dirname "$0")/../.."

test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
root="$(mktemp -d "${TMPDIR:-/tmp}/matrix-homebrew-integration.XXXXXX")"
trap 'rm -rf "$root"' EXIT
export HOMEBREW_CACHE="$root/cache"
export HOMEBREW_LOGS="$root/logs"
export HOMEBREW_TEMP="$root/temp"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_SUDO=1
export HOMEBREW_NO_INSTALL_FROM_API=1
# Prevent brew's developer-command probe from writing its persistent devcmdrun flag.
# The driver unsets this before loading casks; its separate negative check sets it.
export HOMEBREW_DEVELOPER=1
mkdir -p "$HOMEBREW_CACHE" "$HOMEBREW_LOGS" "$HOMEBREW_TEMP"
PYTHONDONTWRITEBYTECODE=1 python3 - "$root" <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, "Tests/Homebrew")
from fixtures.release_fixture import write_archive
root = Path(sys.argv[1])
for version in ("1.2.3", "1.2.4"):
    write_archive(root / f"{version}.zip", version=version)
PY
brew ruby Tests/Homebrew/support/integration_driver.rb "$root"
