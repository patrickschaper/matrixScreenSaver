"""Tiny deterministic release archives; not runnable bundles."""
import plistlib
import struct
import zipfile
from pathlib import Path


def write_archive(path, version="1.2.3", cpu=0x0100000C, minimum=15, root="MatrixScreenSaver.saver",
                  *, wallpaper=True, wallpaper_minimum=15, wallpaper_root="Matrix Wallpaper.app"):
    command = struct.pack("<6I", 0x32, 24, 1, minimum << 16, minimum << 16, 0)
    binary = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 8, 1, len(command), 0, 0) + command
    info = plistlib.dumps({"CFBundleIdentifier": "dev.patsch.MatrixScreenSaver",
                          "CFBundleShortVersionString": version, "CFBundleVersion": version,
                          "CFBundleExecutable": "MatrixScreenSaver"})
    with zipfile.ZipFile(path, "w") as archive:
        repo = Path(__file__).resolve().parents[3]
        for installer in ["Install.command", "Scripts/product-lifecycle.sh"]:
            archive.write(repo / installer, installer)
        for name, data in [(f"{root}/Contents/Info.plist", info),
                           (f"{root}/Contents/MacOS/MatrixScreenSaver", binary)]:
            archive.writestr(zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)), data)
        if wallpaper:
            command = struct.pack("<6I", 0x32, 24, 1, wallpaper_minimum << 16, wallpaper_minimum << 16, 0)
            binary = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, len(command), 0, 0) + command
            info = plistlib.dumps({"CFBundleIdentifier": "dev.patsch.MatrixWallpaper",
                                  "CFBundleShortVersionString": version, "CFBundleVersion": version,
                                  "CFBundleExecutable": "MatrixWallpaper",
                                  "CFBundlePackageType": "APPL", "CFBundleName": "Matrix Wallpaper"})
            for name, data in [(f"{wallpaper_root}/Contents/Info.plist", info),
                               (f"{wallpaper_root}/Contents/MacOS/MatrixWallpaper", binary)]:
                archive.writestr(zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)), data)
