import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile

from fixtures.release_fixture import write_archive

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/render-homebrew-release.py"


class ReleaseMetadataTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.archive = self.root / "release.zip"
        write_archive(self.archive)

    def tearDown(self):
        self.temp.cleanup()

    def run_render(self, version="1.2.3", digest=None, url=None):
        digest = digest or "sha256:" + hashlib.sha256(self.archive.read_bytes()).hexdigest()
        return subprocess.run([sys.executable, "-B", str(SCRIPT), "--archive", str(self.archive),
                               "--version", version, "--digest", digest,
                               "--asset-url", url or f"https://github.com/patrickschaper/matrixScreenSaver/releases/download/{version}/{version}.zip",
                               "--provenance", "fixture", "--output", str(self.root / "out")],
                              capture_output=True, text=True)

    def test_pinned_handoff_and_deterministic_rerun(self):
        result = self.run_render()
        self.assertEqual(0, result.returncode, result.stderr)
        manifest = json.loads((self.root / "out/manifest.json").read_text())
        self.assertEqual("1.2.3", manifest["version"])
        self.assertEqual("arm64", manifest["architecture"])
        self.assertEqual("dev.patsch.MatrixScreenSaver", manifest["bundle_identifier"])
        self.assertEqual(["dev.patsch.MatrixScreenSaver", "dev.patsch.MatrixWallpaper"],
                         manifest["bundle_identifiers"])
        self.assertEqual(hashlib.sha256(self.archive.read_bytes()).hexdigest(), manifest["sha256"])
        cask = (self.root / "out/Casks/matrix-screen-saver.rb").read_text()
        self.assertIn('version "1.2.3"', cask)
        self.assertIn(manifest["sha256"], cask)
        self.assertIn('app "Matrix Wallpaper.app", target: "Matrix Wallpaper.app"', cask)
        self.assertIn('"{{staged_path}}/Matrix Wallpaper.app"', cask)
        self.assertNotIn("MatrixWallpaper.app", cask)
        self.assertNotIn("PLACEHOLDER", cask)
        self.assertEqual(0, self.run_render().returncode)
        self.assertEqual(cask, (self.root / "out/Casks/matrix-screen-saver.rb").read_text())

    def test_immutable_old_archive_installs_with_new_name(self):
        write_archive(self.archive, wallpaper_root="MatrixWallpaper.app")
        result = self.run_render()
        self.assertEqual(0, result.returncode, result.stderr)
        cask = (self.root / "out/Casks/matrix-screen-saver.rb").read_text()
        self.assertIn('app "MatrixWallpaper.app", target: "Matrix Wallpaper.app"', cask)
        self.assertIn('"{{staged_path}}/MatrixWallpaper.app"', cask)
        self.assertIn("Open {{appdir}}/Matrix Wallpaper.app", cask)

    def test_rejects_archives_containing_both_app_names(self):
        with zipfile.ZipFile(self.archive, "a") as archive:
            archive.writestr("MatrixWallpaper.app/Contents/Info.plist", b"ambiguous")
        result = self.run_render()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("exactly one wallpaper app", result.stderr)
        self.assertFalse((self.root / "out").exists())

    def test_rejects_invalid_inputs_without_handoff(self):
        cases = [dict(version="../oops"), dict(digest="sha256:" + "0" * 64),
                 dict(url="https://github.com/patrickschaper/matrixScreenSaver/releases/latest/download/1.2.3.zip")]
        for case in cases:
            with self.subTest(case=case):
                self.assertNotEqual(0, self.run_render(**case).returncode)
                self.assertFalse((self.root / "out").exists())
        for kwargs in [dict(version="9.9.9"), dict(cpu=0x01000007), dict(root="Unexpected.saver"), dict(minimum=27)]:
            with self.subTest(kwargs=kwargs):
                write_archive(self.archive, **kwargs)
                self.assertNotEqual(0, self.run_render().returncode)
                self.assertFalse((self.root / "out").exists())
        self.archive.unlink()
        self.assertNotEqual(0, self.run_render(digest="sha256:" + "0" * 64).returncode)

    def test_floor_never_lower_than_binary(self):
        write_archive(self.archive, minimum=26)
        result = self.run_render()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("depends_on macos: :tahoe", (self.root / "out/Casks/matrix-screen-saver.rb").read_text())

    def test_wallpaper_sets_aggregate_floor(self):
        write_archive(self.archive, wallpaper_minimum=26)
        result = self.run_render()
        self.assertEqual(0, result.returncode, result.stderr)
        manifest = json.loads(result.stdout)
        self.assertEqual("26.0.0", manifest["minimum_macos"])
        self.assertEqual("26.0", manifest["cask_macos_floor"])

    def test_rejects_missing_bundles(self):
        write_archive(self.archive, wallpaper=False)
        self.assertNotEqual(0, self.run_render().returncode)
        write_archive(self.archive)
        with zipfile.ZipFile(self.archive) as archive:
            app = [(entry, archive.read(entry)) for entry in archive.infolist()
                   if entry.filename.startswith("Matrix Wallpaper.app/")]
        with zipfile.ZipFile(self.archive, "w") as archive:
            for entry, data in app:
                archive.writestr(entry, data)
        self.assertNotEqual(0, self.run_render().returncode)
        self.assertFalse((self.root / "out").exists())

    def test_rejects_invalid_wallpaper_metadata_and_binary(self):
        plist_path = "Matrix Wallpaper.app/Contents/Info.plist"
        binary_path = "Matrix Wallpaper.app/Contents/MacOS/MatrixWallpaper"
        cases = [(plist_path, key, value) for key, value in [
            ("CFBundleIdentifier", "dev.patsch.Other"),
            ("CFBundleShortVersionString", "9.9.9"), ("CFBundleVersion", "9.9.9"),
            ("CFBundleExecutable", "Other")]]
        # Mach-O offsets: CPU, file type, platform, minimum OS, load command type.
        cases += [(binary_path, offset, value) for offset, value in [
            (4, 0x01000007), (12, 8), (40, 2), (44, 27 << 16), (32, 0)]]
        cases.append(("MatrixScreenSaver.saver/Contents/MacOS/MatrixScreenSaver", 12, 2))
        for path, field, value in cases:
            with self.subTest(field=field, value=value):
                write_archive(self.archive)
                with zipfile.ZipFile(self.archive) as archive:
                    entries = [(entry, archive.read(entry)) for entry in archive.infolist()]
                with zipfile.ZipFile(self.archive, "w") as archive:
                    for entry, data in entries:
                        if entry.filename == path:
                            if path == plist_path:
                                info = plistlib.loads(data)
                                info[field] = value
                                data = plistlib.dumps(info)
                            else:
                                data = bytearray(data)
                                struct.pack_into("<I", data, field, value)
                        archive.writestr(entry, data)
                self.assertNotEqual(0, self.run_render().returncode)
                self.assertFalse((self.root / "out").exists())

    def test_rejects_oversized_archive_before_reading_entries(self):
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location("render_release", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        entry = zipfile.ZipInfo("Matrix Wallpaper.app/large")
        entry.file_size = 100_000_001
        digest = "sha256:" + hashlib.sha256(self.archive.read_bytes()).hexdigest()
        with patch.object(module.zipfile.ZipFile, "infolist", return_value=[entry]):
            with self.assertRaisesRegex(ValueError, "oversized"):
                module.render(self.archive, "1.2.3", module.asset_url("1.2.3"), digest,
                              "fixture", self.root / "out")
        self.assertFalse((self.root / "out").exists())

    def test_archive_guards(self):
        for name, mode in [("../escape", 0), ("/absolute", 0), ("bad\\path", 0),
                           ("Unexpected/file", 0), ("Matrix Wallpaper.app/link", 0o120777),
                           ("MatrixScreenSaver.saver/Contents/Info.plist", 0)]:
            with self.subTest(name=name):
                write_archive(self.archive)
                entry = zipfile.ZipInfo(name)
                entry.external_attr = mode << 16
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    with zipfile.ZipFile(self.archive, "a") as archive:
                        archive.writestr(entry, b"unsafe")
                self.assertNotEqual(0, self.run_render().returncode)
                self.assertFalse((self.root / "out").exists())

    def test_release_workflow_builds_and_stages_both_bundles(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        prepare, publish = workflow.split("  publish:", 1)
        for job in (prepare, publish):
            self.assertIn("./build.sh\n", job)
            self.assertIn("./build-wallpaper.sh\n", job)
            for bundle in ("MatrixScreenSaver.saver", "Matrix Wallpaper.app"):
                self.assertIn(f'codesign --verify --deep --strict "build/{bundle}"', job)
        self.assertLess(prepare.index('printf \'%s\\n\' "${{ steps.version.outputs.next }}" > VERSION'),
                        prepare.index("./build.sh\n"))
        self.assertIn('ditto "build/Matrix Wallpaper.app" "${release_dir}/Matrix Wallpaper.app"', publish)

    def test_release_uses_highest_version_tag_not_nearest(self):
        repository = self.root / "repository"
        repository.mkdir()

        def git(*args):
            return subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                                   "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false",
                                   "-c", "core.hooksPath=/dev/null", *args], cwd=repository,
                                  check=True, capture_output=True, text=True)

        git("init", "--quiet")
        git("commit", "--allow-empty", "-m", "older release commit")
        git("tag", "0.4.0")
        git("tag", "0.10.0")
        git("commit", "--allow-empty", "-m", "nearer older version tag")
        git("tag", "0.3.0")
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        assignment = next(line.strip() for line in workflow.splitlines()
                          if line.strip().startswith('current_version="$('))
        result = subprocess.run(["bash", "-euo", "pipefail", "-c",
                                 assignment + '\nprintf "%s" "$current_version"'],
                                cwd=repository, check=True, capture_output=True, text=True)
        self.assertEqual("0.10.0", result.stdout)

    def test_fetch_consumes_existing_asset_and_missing_asset_fails(self):
        from unittest.mock import Mock, call, patch
        spec = importlib.util.spec_from_file_location("render_release", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        asset = {"name": "1.2.3.zip", "url": module.asset_url("1.2.3"),
                 "digest": "sha256:" + hashlib.sha256(self.archive.read_bytes()).hexdigest()}
        view = ["gh", "release", "view", "1.2.3", "--repo", module.REPOSITORY, "--json", "assets"]
        download = ["gh", "release", "download", "1.2.3", "--repo", module.REPOSITORY,
                    "--pattern", "1.2.3.zip", "--dir", str(self.root)]

        def fetch(command, **kwargs):
            if command == view:
                return Mock(stdout=json.dumps({"assets": [asset]}))
            self.assertEqual(download, command)
            (self.root / "1.2.3.zip").write_bytes(self.archive.read_bytes())

        with patch.object(module.subprocess, "run", side_effect=fetch) as run:
            for attempt in range(2):
                archive, url, digest = module.fetch_release("1.2.3", self.root)
                self.assertEqual((self.root / "1.2.3.zip", asset["url"], asset["digest"]), (archive, url, digest))
                manifest = module.render(archive, "1.2.3", url, digest, "fixture", self.root / f"fetched-{attempt}")
                self.assertEqual(asset["digest"], "sha256:" + manifest["sha256"])
                archive.unlink()
            self.assertEqual([
                call(view, check=True, capture_output=True, text=True), call(download, check=True),
                call(view, check=True, capture_output=True, text=True), call(download, check=True),
            ], run.call_args_list)
            run.reset_mock()
            run.side_effect = None
            run.return_value.stdout = json.dumps({"assets": []})
            with self.assertRaises(ValueError):
                module.fetch_release("1.2.3", self.root)
            self.assertEqual(1, run.call_count)


if __name__ == "__main__":
    unittest.main()
