#!/usr/bin/env python3
"""Validate published release bytes and produce a pinned, offline tap handoff."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import subprocess
import tempfile
import zipfile

REPOSITORY = "patrickschaper/matrixScreenSaver"
TEMPLATE = Path(__file__).resolve().parents[1] / "Homebrew/Casks/matrix-screen-saver.rb"


def validate_version(version):
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version):
        raise ValueError("Expected a release version such as 1.2.3")
    return version


def asset_url(version):
    return f"https://github.com/{REPOSITORY}/releases/download/{validate_version(version)}/{version}.zip"


def binary_minimum(data):
    if len(data) < 32:
        raise ValueError("Truncated Mach-O header")
    magic, cpu, _, kind, count, size, _, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 8:
        raise ValueError("Release must contain a thin ARM64 Mach-O bundle")
    end = 32 + size
    if end > len(data):
        raise ValueError("Truncated Mach-O commands")
    offset, minimum = 32, None
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("Truncated Mach-O command")
        command, length = struct.unpack_from("<2I", data, offset)
        if length < 8 or offset + length > end:
            raise ValueError("Invalid Mach-O command size")
        if command == 0x32:
            if length < 24:
                raise ValueError("Truncated build version")
            platform, minimum = struct.unpack_from("<2I", data, offset + 8)
            if platform != 1:
                raise ValueError("Binary does not target macOS")
        elif command == 0x24:
            if length < 16:
                raise ValueError("Truncated minimum macOS version")
            minimum = struct.unpack_from("<I", data, offset + 8)[0]
        offset += length
    if minimum is None or offset != end:
        raise ValueError("Missing or malformed minimum macOS version")
    return (minimum >> 16, (minimum >> 8) & 255, minimum & 255)


def render(archive_path, version, url, digest, provenance, output):
    validate_version(version)
    if url != asset_url(version):
        raise ValueError("Asset URL must be the immutable versioned release URL")
    sha256 = hashlib.sha256(Path(archive_path).read_bytes()).hexdigest()
    if digest != f"sha256:{sha256}":
        raise ValueError("Downloaded asset does not match the release SHA-256 digest")
    with zipfile.ZipFile(archive_path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)) or sum(e.file_size for e in entries) > 100_000_000:
            raise ValueError("Duplicate or oversized archive entries")
        for entry in entries:
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in entry.filename:
                raise ValueError("Unsafe archive path")
            if not path.parts or path.parts[0] not in ("MatrixScreenSaver.saver", "__MACOSX"):
                raise ValueError("Unexpected saver archive layout")
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Symlinks are not supported in release archives")
        info = plistlib.loads(archive.read("MatrixScreenSaver.saver/Contents/Info.plist"))
        if (info.get("CFBundleIdentifier") != "dev.patsch.MatrixScreenSaver"
                or info.get("CFBundleShortVersionString") != version
                or info.get("CFBundleVersion") != version
                or info.get("CFBundleExecutable") != "MatrixScreenSaver"):
            raise ValueError("Bundle identity, executable, or version mismatch")
        minimum = binary_minimum(archive.read("MatrixScreenSaver.saver/Contents/MacOS/MatrixScreenSaver"))
    # Select the next known OS floor, never silently understate the binary requirement.
    if minimum <= (15, 0, 0):
        floor, symbol = "15.0", "sequoia"
    elif minimum <= (26, 0, 0):
        floor, symbol = "26.0", "tahoe"
    else:
        raise ValueError("Unsupported macOS floor: update compatibility mapping before release")
    cask = TEMPLATE.read_text()
    cask, versions = re.subn(r'^  version "[^"]+"$', f'  version "{version}"', cask, flags=re.M)
    cask, hashes = re.subn(r'^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{sha256}"', cask, flags=re.M)
    cask, floors = re.subn(r'^  depends_on macos: :\w+$', f'  depends_on macos: :{symbol}', cask, flags=re.M)
    if (versions, hashes, floors) != (1, 1, 1):
        raise ValueError("Cask template no longer matches renderer contract")
    manifest = {"version": version, "asset_url": url, "sha256": sha256,
                "architecture": "arm64", "minimum_macos": ".".join(map(str, minimum)),
                "cask_macos_floor": floor, "bundle_identifier": info["CFBundleIdentifier"],
                "provenance": provenance}
    output = Path(output)
    (output / "Casks").mkdir(parents=True, exist_ok=True)
    (output / "Casks/matrix-screen-saver.rb").write_text(cask)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def fetch_release(version, directory):
    """Always retrieve the published asset, including on workflow reruns; never build."""
    validate_version(version)
    response = subprocess.run(["gh", "release", "view", version, "--repo", REPOSITORY,
                               "--json", "assets"], check=True, capture_output=True, text=True)
    assets = [a for a in json.loads(response.stdout)["assets"] if a["name"] == f"{version}.zip"]
    if len(assets) != 1 or assets[0].get("url") != asset_url(version):
        raise ValueError("Missing or unexpected published release asset")
    asset = assets[0]
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", asset.get("digest", "")):
        raise ValueError("Release asset has no SHA-256 digest")
    subprocess.run(["gh", "release", "download", version, "--repo", REPOSITORY,
                    "--pattern", f"{version}.zip", "--dir", str(directory)], check=True)
    return Path(directory) / f"{version}.zip", asset["url"], asset["digest"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--archive")
    parser.add_argument("--asset-url")
    parser.add_argument("--digest")
    parser.add_argument("--provenance", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        with tempfile.TemporaryDirectory(prefix="matrix-release-") as temp:
            if args.archive:
                archive, url, digest = args.archive, args.asset_url, args.digest
            else:
                archive, url, digest = fetch_release(args.version, temp)
            manifest = render(archive, args.version, url, digest, args.provenance, args.output)
            print(json.dumps(manifest, sort_keys=True))
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Homebrew handoff failed: {error}\n")


if __name__ == "__main__":
    main()
