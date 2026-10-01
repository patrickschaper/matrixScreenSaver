import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "Scripts/update-homebrew-tap.py"


class FakeAPI:
    def __init__(self):
        self.calls = []
        self.branch = False
        self.content = None
        self.prs = []

    def request(self, method, path, body=None, missing_ok=False):
        self.calls.append((method, path, body))
        if path == "repos/owner/homebrew-test":
            return {"default_branch": "main"}
        if "/git/ref/heads/main" in path:
            return {"object": {"sha": "base"}}
        if "/git/ref/heads/" in path:
            return {"object": {"sha": "base"}} if self.branch else None
        if path.endswith("/git/refs"):
            self.branch = True
            return {}
        if "/contents/" in path:
            if method == "GET":
                return {"sha": "content-sha", "content": self.content} if self.content else None
            self.content = body["content"]
            return {}
        if "/pulls?" in path:
            return self.prs
        if path.endswith("/pulls"):
            pr = {"html_url": "https://github.com/owner/homebrew-test/pull/1", "state": "open"}
            self.prs.append(pr)
            return pr
        raise AssertionError(path)


class TapUpdateTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("tap_update", SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_one_pr_and_no_default_branch_write_on_rerun(self):
        api = FakeAPI()
        for _ in range(2):
            self.module.update(api, "owner/homebrew-test", "1.2.3", 'cask "matrix-screen-saver" do\nend\n')
        self.assertEqual(1, sum(method == "POST" and path.endswith("/pulls") for method, path, _ in api.calls))
        writes = [body for method, path, body in api.calls if method == "PUT"]
        self.assertEqual(1, len(writes))
        self.assertEqual("matrix-screen-saver-1.2.3", writes[0]["branch"])
        self.assertFalse(any("merge" in path for _, path, _ in api.calls))

    def test_bad_target_and_version_fail_before_requests(self):
        for target, version in [("bad/target/extra", "1.2.3"), ("-bad/tap", "1.2.3"),
                                ("owner/homebrew-test", "../bad")]:
            api = FakeAPI()
            with self.assertRaises(ValueError):
                self.module.update(api, target, version, "cask")
            self.assertEqual([], api.calls)

    def test_api_errors_do_not_expose_credentials(self):
        from unittest.mock import patch
        import urllib.error
        api = self.module.GitHubAPI("never-log-this-token")
        with patch("urllib.request.urlopen", side_effect=urllib.error.HTTPError("url", 403, "secret", {}, None)):
            with self.assertRaisesRegex(RuntimeError, "HTTP 403") as error:
                api.request("GET", "repos/owner/tap")
        self.assertNotIn("never-log-this-token", str(error.exception))

    def test_missing_credentials_leave_manual_artifact_available(self):
        import os
        import subprocess
        import sys
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            handoff = Path(temp)
            (handoff / "manifest.json").write_text('{"version":"1.2.3"}')
            env = {key: value for key, value in os.environ.items() if key != "HOMEBREW_TAP_TOKEN"}
            result = subprocess.run([sys.executable, str(SCRIPT), "--target", "owner/homebrew-test",
                                     "--handoff", temp], env=env, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("manual handoff artifact", result.stderr)
            self.assertTrue((handoff / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
