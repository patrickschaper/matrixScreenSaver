"""Exercise the real lifecycle script with isolated files and mocked macOS services."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/product-lifecycle.sh"


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="matrix-lifecycle-")
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin",
                        FIXTURE=str(self.root))
        # All OS effects stay inside the fixture; copies and metadata use production tools.
        stub = f"#!{sys.executable}\n" + '''import os, pathlib, subprocess, sys
r = pathlib.Path(os.environ['FIXTURE'])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
if name == 'launchctl':
    if args[0] == 'print': sys.exit(0 if (r/'job').exists() else 1)
    if args[0] == 'bootstrap':
        if (r/'fail-register').exists():
            (r/'fail-register').unlink(); sys.exit(1)
        (r/'job').touch()
    elif args[0] == 'bootout': (r/'job').unlink(missing_ok=True)
elif name == 'date': print((r/'clock').read_text())
elif name == 'mv':
    if (r/'fail-promotion').exists() and args[0].endswith('/MatrixScreenSaver.saver'):
        sys.exit(1)
    sys.exit(subprocess.call(['/bin/mv', *args]))
elif name == 'rm':
    if (r/'fail-removal').exists() and any(a.endswith('/MatrixScreenSaver.saver') for a in args):
        sys.exit(1)
    sys.exit(subprocess.call(['/bin/rm', *args]))
elif name == 'osascript':
    sys.stdin.read(); (r/'quit-request').touch()
elif name not in ('codesign', 'pkill'): sys.exit(1)
'''
        for name in ["launchctl", "date", "mv", "rm", "osascript", "codesign", "pkill"]:
            path = self.bin / name
            path.write_text(stub)
            path.chmod(0o755)
        self.clock(1000)
        self.app = self.bundle("payload/Matrix Wallpaper.app", "MatrixWallpaper")
        self.saver = self.bundle("payload/MatrixScreenSaver.saver", "MatrixScreenSaver")
        self.installed_app = self.home / "Applications/Matrix Wallpaper.app"
        self.installed_saver = self.home / "Library/Screen Savers/MatrixScreenSaver.saver"
        self.state = self.home / "Library/Application Support/MatrixWallpaper/Installation"
        self.agent = self.home / "Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist"

    def tearDown(self):
        self.temp.cleanup()

    def bundle(self, path, name):
        bundle = self.root / path
        executable = bundle / "Contents/MacOS" / name
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        self.metadata(bundle, CFBundleIdentifier=f"dev.patsch.{name}",
                      CFBundleShortVersionString="1.2.3", CFBundleVersion="1.2.3")
        return bundle

    def metadata(self, bundle, **changes):
        path = bundle / "Contents/Info.plist"
        values = plistlib.loads(path.read_bytes()) if path.exists() else {}
        values.update(changes)
        path.write_bytes(plistlib.dumps(values))

    def clock(self, now):
        (self.root / "clock").write_text(str(now))

    def run_script(self, *args, success=True, installed=False):
        script = self.state / "product-lifecycle.sh" if installed else SCRIPT
        result = subprocess.run(["/bin/bash", str(script), *map(str, args)], env=self.env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def install(self):
        self.run_script("install", self.app, self.saver)

    def test_pair_registration_and_explicit_removal_preserve_preferences(self):
        self.install()
        self.assertTrue(self.installed_app.exists() and self.installed_saver.exists())
        job = plistlib.loads(self.agent.read_bytes())
        self.assertEqual(job["StartInterval"], 60)
        self.assertTrue(job["RunAtLoad"])
        self.assertEqual(job["ProgramArguments"][1], str(self.state / "product-lifecycle.sh"))
        prefs = self.home / "Library/Preferences/sentinel"
        prefs.parent.mkdir()
        prefs.write_text("keep")
        self.run_script("uninstall", installed=True)
        self.assertFalse(self.installed_app.exists() or self.installed_saver.exists() or self.agent.exists())
        self.assertEqual(prefs.read_text(), "keep")

    def test_missing_or_mismatched_payload_changes_nothing(self):
        self.run_script("install", self.app, self.root / "missing.saver", success=False)
        for field in ["CFBundleVersion", "CFBundleShortVersionString"]:
            self.metadata(self.saver, **{field: "9"})
            self.run_script("install", self.app, self.saver, success=False)
            self.metadata(self.saver, **{field: "1.2.3"})
        self.assertFalse(self.installed_app.exists() or self.installed_saver.exists())

    def test_failed_second_promotion_and_registration_restore_both(self):
        self.install()
        old_app = self.installed_app.stat().st_ino
        old_saver = self.installed_saver.stat().st_ino
        old_record = (self.state / "installation.plist").read_bytes()
        for failure in ["fail-promotion", "fail-register"]:
            (self.root / failure).touch()
            self.run_script("install", self.app, self.saver, success=False)
            (self.root / failure).unlink(missing_ok=True)
            self.assertEqual(self.installed_app.stat().st_ino, old_app)
            self.assertEqual(self.installed_saver.stat().st_ino, old_saver)
            self.assertEqual((self.state / "installation.plist").read_bytes(), old_record)
            self.assertTrue((self.root / "job").exists())

    def test_manual_relocation_grace_restore_and_self_removal(self):
        self.install()
        moved = self.root / "moved.app"
        self.installed_app.rename(moved)
        self.run_script("check", installed=True)
        self.clock(1299)
        self.run_script("check", installed=True)
        self.assertTrue(self.installed_saver.exists())
        moved.rename(self.installed_app)
        self.run_script("check", installed=True)
        self.assertFalse((self.state / "missing-since").exists())
        shutil.rmtree(self.installed_app)
        self.run_script("check", installed=True)
        self.clock(1600)
        (self.root / "quit-request").unlink()
        self.run_script("check", installed=True)
        self.assertTrue((self.root / "quit-request").exists())
        self.assertFalse(self.installed_saver.exists() or self.state.exists() or self.agent.exists())
        self.assertFalse((self.root / "job").exists())

    def test_failed_rollback_keeps_recovery_bundle_outside_destination(self):
        self.install()
        original = self.installed_saver.stat().st_ino
        (self.root / "fail-register").touch()
        (self.root / "fail-removal").touch()
        result = self.run_script("install", self.app, self.saver, success=False)
        self.assertIn("backups preserved", result.stderr)
        backups = list(self.installed_saver.parent.glob(".MatrixSaver-install.*/previous.saver"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_ino, original)
        self.assertFalse((self.installed_saver / "previous.saver").exists())

    def test_active_upgrade_and_installer_lock_prevent_cleanup(self):
        self.install()
        shutil.rmtree(self.installed_app)
        lock = self.state.parent / ".installation-lock"
        lock.write_text(str(os.getpid()))
        self.run_script("check", success=False)
        self.clock(9999)
        self.assertFalse((self.state / "missing-since").exists())
        self.run_script("check", success=False)
        self.assertTrue(self.installed_saver.exists())

    def test_removal_failure_retries_and_unrelated_bundle_is_preserved(self):
        self.install()
        shutil.rmtree(self.installed_app)
        self.run_script("check")
        self.clock(1300)
        self.metadata(self.installed_saver, CFBundleIdentifier="unrelated")
        self.run_script("check", success=False)
        self.metadata(self.installed_saver, CFBundleIdentifier="dev.patsch.MatrixScreenSaver")
        (self.root / "fail-removal").touch()
        self.run_script("check", success=False)
        self.assertTrue(self.agent.exists() and self.installed_saver.exists())
        (self.root / "fail-removal").unlink()
        self.run_script("check")
        self.assertFalse(self.installed_saver.exists())

    def test_custom_destinations_and_conflicting_installation(self):
        self.run_script("register", self.app, self.saver, "homebrew")
        self.run_script("install", self.app, self.saver, success=False)
        self.run_script("uninstall", success=False)
        shutil.rmtree(self.app)
        self.run_script("check")
        self.clock(1300)
        self.run_script("check")
        self.assertFalse(self.saver.exists())

    def test_symlink_and_malformed_record_are_rejected(self):
        self.install()
        shutil.rmtree(self.installed_app)
        self.run_script("check")
        self.clock(1300)
        shutil.rmtree(self.installed_saver)
        self.installed_saver.symlink_to(self.saver)
        self.run_script("check", success=False)
        self.assertTrue(self.saver.exists())
        self.installed_saver.unlink()
        (self.state / "installation.plist").write_text("bad plist")
        self.run_script("check", success=False)
        self.assertTrue(self.agent.exists())


if __name__ == "__main__":
    unittest.main()
