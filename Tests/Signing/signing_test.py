"""Exercise signing and notarization without accessing real Apple credentials."""

import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.log = self.directory / "commands"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        COMMAND_LOG=str(self.log), SIGNING_IDENTITY="-",
                        NOTARY_KEYCHAIN_PROFILE="test-profile")
        self.env.pop("NOTARY_KEYCHAIN", None)
        self.stub("codesign", '''printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [[ "$1" == --display ]]; then
  echo "Authority=${TEST_AUTHORITY:-Developer ID Application: Test (TEAMID)}" >&2
fi
exit "${SIGN_FAILURE:-0}"
''')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run(["bash", str(ROOT / "Scripts" / name), *map(str, args)],
                              env=self.env, text=True, capture_output=True)

    def test_release_signing_rejects_missing_or_adhoc_identity(self):
        for identity in (None, "-"):
            with self.subTest(identity=identity):
                if identity is None:
                    self.env.pop("SIGNING_IDENTITY", None)
                else:
                    self.env["SIGNING_IDENTITY"] = identity
                result = self.run_script("sign-bundle.sh", "test bundle.app")
                self.assertNotEqual(0, result.returncode)
                self.assertIn("Developer ID Application", result.stderr)
                self.assertFalse(self.log.exists())

    def test_developer_id_build_requires_runtime_and_timestamp(self):
        self.env["SIGNING_IDENTITY"] = "Developer ID Application: Test (TEAMID)"
        result = self.run_script("sign-bundle.sh", "test.saver")
        self.assertEqual(0, result.returncode, result.stderr)
        commands = self.log.read_text()
        self.assertIn("--options runtime", commands)
        self.assertIn("--timestamp", commands)
        self.assertIn("--sign Developer ID Application: Test (TEAMID)", commands)

    def test_development_certificate_is_not_distribution_signing(self):
        self.env["SIGNING_IDENTITY"] = "Apple Development: Test (TEAMID)"
        result = self.run_script("sign-bundle.sh", "test.app")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Developer ID Application", result.stderr)
        self.assertFalse(self.log.exists())

    def test_signing_failure_never_falls_back(self):
        self.env["SIGNING_IDENTITY"] = "Developer ID Application: Missing (TEAMID)"
        self.env["SIGN_FAILURE"] = "1"
        self.assertNotEqual(0, self.run_script("sign-bundle.sh", "test.app").returncode)
        self.assertEqual(1, len(self.log.read_text().splitlines()))

    def prepare_notary(self, status="Accepted"):
        response = self.directory / "response.plist"
        response.write_bytes(plistlib.dumps({"status": status, "id": "test-id"}))
        self.env["NOTARY_RESPONSE"] = str(response)
        self.stub("ditto", 'printf "%s\\n" "$*" >> "$COMMAND_LOG"\n')
        self.stub("xcrun", '''printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [[ "$1 $2" == 'notarytool submit' ]]; then cat "$NOTARY_RESPONSE"; fi
if [[ "$1 $2" == 'stapler staple' ]]; then exit "${STAPLE_FAILURE:-0}"; fi
''')

    def test_accepted_submission_staples_and_validates_both_bundles(self):
        self.prepare_notary()
        result = self.run_script("notarize.sh")
        self.assertEqual(0, result.returncode, result.stderr)
        commands = self.log.read_text()
        self.assertIn("--keychain-profile test-profile --wait", commands)
        for bundle in ("MatrixScreenSaver.saver", "MatrixWallpaper.app"):
            self.assertIn(f"stapler staple {ROOT}/build/{bundle}", commands)
            self.assertIn(f"stapler validate {ROOT}/build/{bundle}", commands)

    def test_rejected_submission_is_not_stapled(self):
        self.prepare_notary("Invalid")
        result = self.run_script("notarize.sh")
        self.assertNotEqual(0, result.returncode)
        self.assertNotIn("stapler", self.log.read_text())

    def test_ci_profile_uses_its_temporary_keychain(self):
        self.prepare_notary()
        self.env["NOTARY_KEYCHAIN"] = str(self.directory / "temporary.keychain-db")
        result = self.run_script("notarize.sh")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"--keychain {self.env['NOTARY_KEYCHAIN']}", self.log.read_text())

    def test_release_notarizes_before_staging_and_cleans_up_on_failure(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        prepare, publish = workflow.split("  publish:", 1)
        self.assertNotIn("secrets.DEVELOPER_ID", prepare)
        self.assertIn("SIGNING_IDENTITY: ${{ secrets.SIGNING_IDENTITY }}", publish)
        self.assertIn("APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}", publish)
        for bundle in ("MatrixScreenSaver.saver", "MatrixWallpaper.app"):
            sign_command = f'bash Scripts/sign-bundle.sh "build/{bundle}"'
            self.assertIn(sign_command, publish)
            self.assertLess(publish.index("./build-wallpaper.sh"), publish.index(sign_command))
            self.assertLess(publish.index(sign_command), publish.index("bash Scripts/notarize.sh"))
        self.assertIn("NOTARY_KEYCHAIN: ${{ runner.temp }}/matrix-signing.keychain-db", publish)
        self.assertLess(publish.index("bash Scripts/notarize.sh"),
                        publish.index("- name: Stage release files"))
        cleanup = publish.split("- name: Remove signing credentials", 1)[1].split("- name:", 1)[0]
        self.assertIn("if: always()", cleanup)
        self.assertIn('security delete-keychain "$RUNNER_TEMP/matrix-signing.keychain-db"', cleanup)

    def test_adhoc_bundle_is_not_submitted(self):
        self.prepare_notary()
        self.env["TEST_AUTHORITY"] = "adhoc"
        self.assertNotEqual(0, self.run_script("notarize.sh").returncode)
        self.assertNotIn("notarytool submit", self.log.read_text())

    def test_missing_profile_is_not_submitted(self):
        self.env.pop("NOTARY_KEYCHAIN_PROFILE")
        self.assertNotEqual(0, self.run_script("notarize.sh").returncode)
        self.assertFalse(self.log.exists())

    def test_staple_failure_aborts(self):
        self.prepare_notary()
        self.env["STAPLE_FAILURE"] = "1"
        self.assertNotEqual(0, self.run_script("notarize.sh").returncode)
        self.assertNotIn("stapler validate", self.log.read_text())


if __name__ == "__main__":
    unittest.main()
