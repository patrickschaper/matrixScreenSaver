"""Tiny deterministic release archives; not executable screen savers."""
import plistlib
import struct
import zipfile


def write_archive(path, version="1.2.3", cpu=0x0100000C, minimum=15, root="MatrixScreenSaver.saver"):
    command = struct.pack("<6I", 0x32, 24, 1, minimum << 16, minimum << 16, 0)
    binary = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 8, 1, len(command), 0, 0) + command
    info = plistlib.dumps({"CFBundleIdentifier": "dev.patsch.MatrixScreenSaver",
                          "CFBundleShortVersionString": version, "CFBundleVersion": version,
                          "CFBundleExecutable": "MatrixScreenSaver"})
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in [(f"{root}/Contents/Info.plist", info),
                           (f"{root}/Contents/MacOS/MatrixScreenSaver", binary)]:
            archive.writestr(zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)), data)
