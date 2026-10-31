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
# Definition loading and all lifecycle operations also run in developer mode.
export HOMEBREW_DEVELOPER=1
mkdir -p "$HOMEBREW_CACHE" "$HOMEBREW_LOGS" "$HOMEBREW_TEMP"
PYTHONDONTWRITEBYTECODE=1 python3 - "$root" <<'PY'
from pathlib import Path
import hashlib
import importlib.util
import sys
sys.path.insert(0, "Tests/Homebrew")
from fixtures.release_fixture import write_archive
root = Path(sys.argv[1])
write_archive(root / "1.2.1.zip", version="1.2.1", wallpaper_root="MatrixWallpaper.app")
write_archive(root / "1.2.2.zip", version="1.2.2", wallpaper=False)
spec = importlib.util.spec_from_file_location("renderer", "Scripts/render-homebrew-release.py")
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)
for version in ("1.2.3", "1.2.4"):
    archive = root / f"{version}.zip"
    write_archive(archive, version=version,
                  wallpaper_root="MatrixWallpaper.app" if version == "1.2.3" else "Matrix Wallpaper.app")
    renderer.render(archive, version, renderer.asset_url(version),
                    "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest(),
                    "native lifecycle fixture", root / f"handoff-{version}")
PY
brew ruby Tests/Homebrew/support/integration_driver.rb "$root"
