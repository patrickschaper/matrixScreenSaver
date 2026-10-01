from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DocumentationTest(unittest.TestCase):
    def test_user_lifecycle_and_security(self):
        text = (ROOT / "README.md").read_text()
        for command in ["brew install --cask", "brew install --cask --force",
                        "brew upgrade --cask", "brew uninstall --cask"]:
            self.assertIn(f'{command} "$TAP/matrix-screen-saver"', text)
        for phrase in ['TAP="patrickschaper/tap"', 'brew tap "$TAP"',
                       "https://github.com/patrickschaper/homebrew-tap", "Gatekeeper quarantine checks",
                       "notarized or Apple-approved", "retains", "manually select",
                       "upgrades do not open", "Apple Silicon", "macOS 15",
                       "https://www.buymeacoffee.com/yesman82"]:
            self.assertIn(phrase, text)
        self.assertNotIn("--zap", text)
        self.assertNotIn("YOUR_OWNER/YOUR_TAP", text)
        self.assertNotIn("tap not live yet", text)
        self.assertIn("brew trust --cask patrickschaper/tap/matrix-screen-saver", text)
        self.assertIn("trusts only this cask", text)

    def test_maintainer_permissions_and_compatibility(self):
        text = (ROOT / "Homebrew/README.md").read_text()
        for phrase in ["HOMEBREW_TAP_REPOSITORY", "HOMEBREW_TAP_TOKEN", "contents",
                       "pull requests", "Human review", "manifest.json", "Developer mode",
                       "Cask/InstallSteps", "7.0.7", "unconfigured",
                       "patrickschaper/homebrew-tap", "token pending"]:
            self.assertIn(phrase, text)


if __name__ == "__main__":
    unittest.main()
