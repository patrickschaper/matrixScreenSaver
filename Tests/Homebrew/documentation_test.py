from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DocumentationTest(unittest.TestCase):
    def test_user_lifecycle_and_security(self):
        text = (ROOT / "README.md").read_text()
        quick = text.split("## Quick install\n", 1)[1].split("\n## ", 1)[0]
        self.assertIn("brew trust --cask patrickschaper/tap/matrix-screen-saver", quick)
        self.assertIn("brew install --cask patrickschaper/tap/matrix-screen-saver", quick)
        self.assertLessEqual(len(quick.strip().splitlines()), 5)
        self.assertNotIn("## Homebrew install", text)
        self.assertNotIn("## Manual quick install", text)
        self.assertIn("## Buy me a coffee", text)
        self.assertIn("https://www.buymeacoffee.com/yesman82", text)
        self.assertIn("docs/bmc_qr.png", text)

    def test_maintainer_permissions_and_compatibility(self):
        text = (ROOT / "Homebrew/README.md").read_text()
        for phrase in ["HOMEBREW_TAP_REPOSITORY", "HOMEBREW_TAP_TOKEN", "contents",
                       "No pull-request write permission", "default branch", "manifest.json", "Developer mode",
                       "Cask/InstallSteps", "7.0.7", "main",
                        "patrickschaper/homebrew-tap", "token pending"]:
            self.assertIn(phrase, text)

    def test_release_publishes_tap_after_verified_handoff_without_blocking_release(self):
        text = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertLess(text.index("Scripts/render-homebrew-release.py"), text.index("Scripts/update-homebrew-tap.py"))
        self.assertLess(text.index("Upload manual Homebrew handoff"), text.index("Scripts/update-homebrew-tap.py"))
        step = text.split("- name: Publish automatic tap update", 1)[1].split("- name:", 1)[0]
        self.assertIn("continue-on-error: true", step)
        self.assertIn("secrets.HOMEBREW_TAP_TOKEN", step)
        self.assertIn("--publish", step)
        self.assertIn("steps.tap_update.outcome == 'failure'", text)
        upload = text.split("- name: Upload manual Homebrew handoff", 1)[1].split("- name:", 1)[0]
        self.assertIn("name: homebrew-handoff-${{ steps.version.outputs.value }}-${{ github.run_attempt }}", upload)


if __name__ == "__main__":
    unittest.main()
