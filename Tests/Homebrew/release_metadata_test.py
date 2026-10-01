import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

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

    def run_render(self, version="1.2.3", digest=None):
        digest = digest or "sha256:" + hashlib.sha256(self.archive.read_bytes()).hexdigest()
        return subprocess.run([sys.executable, str(SCRIPT), "--archive", str(self.archive),
                               "--version", version, "--digest", digest,
                               "--asset-url", f"https://github.com/patrickschaper/matrixScreenSaver/releases/download/{version}/{version}.zip",
                               "--provenance", "fixture", "--output", str(self.root / "out")],
                              capture_output=True, text=True)

    def test_pinned_handoff_and_deterministic_rerun(self):
        result = self.run_render()
        self.assertEqual(0, result.returncode, result.stderr)
        manifest = json.loads((self.root / "out/manifest.json").read_text())
        self.assertEqual("1.2.3", manifest["version"])
        self.assertEqual("arm64", manifest["architecture"])
        self.assertEqual(hashlib.sha256(self.archive.read_bytes()).hexdigest(), manifest["sha256"])
        cask = (self.root / "out/Casks/matrix-screen-saver.rb").read_text()
        self.assertIn('version "1.2.3"', cask)
        self.assertIn(manifest["sha256"], cask)
        self.assertNotIn("PLACEHOLDER", cask)
        self.assertEqual(0, self.run_render().returncode)
        self.assertEqual(cask, (self.root / "out/Casks/matrix-screen-saver.rb").read_text())

    def test_rejects_invalid_inputs_without_handoff(self):
        cases = [dict(version="../oops"), dict(digest="sha256:" + "0" * 64)]
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

    def test_fetch_consumes_existing_asset_and_missing_asset_fails(self):
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location("render_release", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        asset = {"name": "1.2.3.zip", "url": module.asset_url("1.2.3"),
                 "digest": "sha256:" + "a" * 64}
        with patch.object(module.subprocess, "run") as run:
            run.return_value.stdout = json.dumps({"assets": [asset]})
            for _ in range(2):
                module.fetch_release("1.2.3", self.root)
            self.assertEqual(4, run.call_count)
            self.assertTrue(all(call.args[0][:2] == ["gh", "release"] for call in run.call_args_list))
            self.assertFalse(any("build" in str(call) for call in run.call_args_list))
            run.reset_mock()
            run.return_value.stdout = json.dumps({"assets": []})
            with self.assertRaises(ValueError):
                module.fetch_release("1.2.3", self.root)
            self.assertEqual(1, run.call_count)


if __name__ == "__main__":
    unittest.main()
