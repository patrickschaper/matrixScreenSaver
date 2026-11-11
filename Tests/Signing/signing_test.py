"""Exercise signing and notarization without accessing real Apple credentials."""

import os
from pathlib import Path
import plistlib
import shutil
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
        self.stub("ditto", '''printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [[ "$1" == -c ]]; then [[ "$#" == 5 ]]; else [[ "$#" == 2 ]]; fi
''')
        self.stub("xcrun", '''printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [[ "$1 $2" == 'notarytool submit' ]]; then cat "$NOTARY_RESPONSE"; fi
if [[ "$1" == stapler ]]; then [[ "$#" == 3 ]]; fi
if [[ "$1 $2" == 'stapler staple' ]]; then exit "${STAPLE_FAILURE:-0}"; fi
''')

    def test_accepted_submission_staples_and_validates_both_bundles(self):
        self.prepare_notary()
        result = self.run_script("notarize.sh")
        self.assertEqual(0, result.returncode, result.stderr)
        commands = self.log.read_text()
        self.assertIn("--keychain-profile test-profile --wait", commands)
        for bundle in ("MatrixScreenSaver.saver", "Matrix Wallpaper.app"):
            self.assertIn(f"stapler staple {ROOT}/build/{bundle}", commands)
            self.assertIn(f"stapler validate {ROOT}/build/{bundle}", commands)

    def test_explicit_bundle_is_the_only_notarized_payload(self):
        """The saver and app can be notarized in separate packaging stages."""
        self.prepare_notary()
        saver = self.directory / "Prepared Saver.saver"
        result = self.run_script("notarize.sh", saver)
        self.assertEqual(0, result.returncode, result.stderr)
        commands = self.log.read_text()
        self.assertIn(f"stapler staple {saver}", commands)
        self.assertNotIn("Matrix Wallpaper.app", commands)
        self.assertNotIn(f"{ROOT}/build/MatrixScreenSaver.saver", commands)

    def prepare_recovery_build(self):
        """Create an isolated build fixture whose fake compiler writes executables."""
        root = self.directory / "project"
        resources = root / "Resources"
        (resources / "Fonts").mkdir(parents=True)
        (resources / "Fonts" / "fixture.ttf").write_text("font")
        for name in ("WallpaperIcon.icns", "MenuBarIcon.pdf", "BuyMeACoffee.png"):
            (resources / name).touch()
        shutil.copy(ROOT / "Resources/Wallpaper-Info.plist", resources)
        shutil.copy(ROOT / "build-wallpaper.sh", root)
        (root / "Scripts").mkdir()
        (root / "Scripts/product-lifecycle.sh").write_text("#!/bin/bash\nexit 0\n")
        (root / "VERSION").write_text("1.2.3\n")
        saver = root / "build/MatrixScreenSaver.saver"
        (saver / "Contents/MacOS").mkdir(parents=True)
        (saver / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.patsch.MatrixScreenSaver",
            "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "1.2.3"}))
        binary = saver / "Contents/MacOS/MatrixScreenSaver"
        binary.write_text("prepared saver")
        binary.chmod(0o755)
        builder = root / "build.sh"
        builder.write_text('#!/bin/bash\nset -eu\ncd "$(dirname "$0")"\n'
                           'printf fresh > "build/MatrixScreenSaver.saver/Contents/MacOS/MatrixScreenSaver"\n'
                           'touch saver-rebuilt\n')
        builder.chmod(0o755)
        self.stub("swiftc", '''while [[ "$1" != -o ]]; do shift; done
shift
printf compiled > "$1"
chmod +x "$1"
''')
        return root, saver

    def run_recovery_build(self, root, *args):
        """Run the copied build script without compiling or signing real products."""
        return subprocess.run(["bash", str(root / "build-wallpaper.sh"), *map(str, args)],
                              env=self.env, text=True, capture_output=True)

    def test_default_build_embeds_a_fresh_saver_and_installer(self):
        """Local builds must not reuse an old saver left in the build directory."""
        root, _ = self.prepare_recovery_build()
        result = self.run_recovery_build(root)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue((root / "saver-rebuilt").exists())
        app = root / "build/Matrix Wallpaper.app"
        archive = app / "Contents/Resources/ScreenSaver/MatrixScreenSaver.zip"
        extraction = self.directory / "extracted"
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(archive), str(extraction)], check=True)
        self.assertEqual("fresh", (extraction / "MatrixScreenSaver.saver/Contents/MacOS/MatrixScreenSaver").read_text())
        self.assertTrue((app / "Contents/MacOS/MatrixScreenSaverInstaller").exists())
        self.assertTrue((app / "Contents/Resources/ScreenSaver/product-lifecycle.sh").exists())

    def test_prepared_saver_requires_the_recoverable_archive_root(self):
        """A renamed payload must not produce an app whose recovery helper rejects its archive."""
        root, saver = self.prepare_recovery_build()
        renamed = saver.with_name("Renamed.saver")
        saver.rename(renamed)
        result = self.run_recovery_build(root, "--saver", renamed)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Invalid recovery screen saver", result.stderr)

    def test_prepared_saver_is_not_rebuilt(self):
        """Release builds retain the already signed and stapled saver bytes."""
        root, saver = self.prepare_recovery_build()
        result = self.run_recovery_build(root, "--saver", saver)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse((root / "saver-rebuilt").exists())
        archive = root / "build/Matrix Wallpaper.app/Contents/Resources/ScreenSaver/MatrixScreenSaver.zip"
        extraction = self.directory / "extracted"
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(archive), str(extraction)], check=True)
        self.assertEqual("prepared saver", (extraction / "MatrixScreenSaver.saver/Contents/MacOS/MatrixScreenSaver").read_text())

    def test_prepared_saver_with_stale_version_is_rejected(self):
        """A supplied payload cannot mismatch either application version field."""
        root, saver = self.prepare_recovery_build()
        metadata = saver / "Contents/Info.plist"
        values = plistlib.loads(metadata.read_bytes())
        values["CFBundleVersion"] = "1.2.2"
        metadata.write_bytes(plistlib.dumps(values))
        result = self.run_recovery_build(root, "--saver", saver)
        self.assertNotEqual(0, result.returncode)
        self.assertFalse((root / "saver-rebuilt").exists())

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
        """Release packaging seals the stapled saver before the app is signed."""
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        prepare, publish = workflow.split("  publish:", 1)
        self.assertNotIn("secrets.DEVELOPER_ID", prepare)
        self.assertIn("SIGNING_IDENTITY: ${{ secrets.SIGNING_IDENTITY }}", publish)
        self.assertIn("APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}", publish)
        ordered = [
            './build.sh',
            'bash Scripts/sign-bundle.sh "build/MatrixScreenSaver.saver"',
            'bash Scripts/notarize.sh "build/MatrixScreenSaver.saver"',
            './build-wallpaper.sh --saver "build/MatrixScreenSaver.saver"',
            'bash Scripts/sign-bundle.sh "build/Matrix Wallpaper.app/Contents/MacOS/MatrixScreenSaverInstaller"',
            'bash Scripts/sign-bundle.sh "build/Matrix Wallpaper.app"',
            'bash Scripts/notarize.sh "build/Matrix Wallpaper.app"',
            '- name: Stage release files',
        ]
        for first, second in zip(ordered, ordered[1:]):
            self.assertLess(publish.index(first), publish.index(second))
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
