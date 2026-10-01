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
                       "pull requests", "Human review", "manifest.json", "Developer mode",
                       "Cask/InstallSteps", "7.0.7", "unconfigured",
                       "patrickschaper/homebrew-tap", "token pending"]:
            self.assertIn(phrase, text)


if __name__ == "__main__":
    unittest.main()
