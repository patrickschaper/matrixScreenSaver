import base64
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/update-homebrew-tap.py"
TEMPLATE = (ROOT / "Homebrew/Casks/matrix-screen-saver.rb").read_text()


def cask(version="1.2.3", digest="a" * 64, floor="sequoia"):
    import re
    text = re.sub(r'^  version "[^"]+"$', f'  version "{version}"', TEMPLATE, flags=re.M)
    text = re.sub(r'^  sha256 "[^"]+"$', f'  sha256 "{digest}"', text, flags=re.M)
    return re.sub(r'^  depends_on macos: :\w+$', f'  depends_on macos: :{floor}', text, flags=re.M)


class FakeAPI:
    def __init__(self, content=TEMPLATE):
        self.calls = []
        self.content = content

    def request(self, method, path, body=None, missing_ok=False):
        self.calls.append((method, path, body))
        if path == "repos/owner/homebrew-test":
            return {"default_branch": "stable/tap"}
        if "/contents/" in path:
            if method == "GET":
                return {"sha": "content-sha", "content": base64.b64encode(self.content.encode()).decode(),
                        "type": "file", "encoding": "base64"} if self.content is not None else None
            self.content = base64.b64decode(body["content"]).decode()
            return {"commit": {"html_url": "https://github.com/owner/homebrew-test/commit/new"}}
        raise AssertionError(path)


class TapUpdateTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("tap_update", SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_newer_release_is_published_once_to_default_branch(self):
        api = FakeAPI()
        content = cask(floor="tahoe")
        for _ in range(2):
            self.module.update(api, "owner/homebrew-test", "1.2.3", content)
        writes = [(path, body) for method, path, body in api.calls if method != "GET"]
        self.assertEqual(1, len(writes))
        path, body = writes[0]
        self.assertEqual("repos/owner/homebrew-test/contents/Casks/matrix-screen-saver.rb", path)
        self.assertEqual("stable/tap", body["branch"])
        self.assertEqual("content-sha", body["sha"])
        self.assertEqual(content, api.content)
        self.assertIn("ref=stable%2Ftap", api.calls[1][1])

    def test_stale_release_never_downgrades_and_versions_compare_numerically(self):
        api = FakeAPI(cask("1.10.0"))
        self.module.update(api, "owner/homebrew-test", "1.9.0", cask("1.9.0"))
        self.assertTrue(all(method == "GET" for method, _, _ in api.calls))
        self.module.update(api, "owner/homebrew-test", "1.11.0", cask("1.11.0"))
        self.assertEqual(cask("1.11.0"), api.content)

    def test_conflicting_same_version_and_hand_edits_are_not_overwritten(self):
        for content in (cask(digest="b" * 64), cask(floor="tahoe"),
                        TEMPLATE.replace('  name "MatrixScreenSaver"', '  name "Hand edited"'),
                        TEMPLATE + "# keep this human comment\n", None):
            with self.subTest(content=content):
                api = FakeAPI(content)
                with self.assertRaises(ValueError):
                    self.module.update(api, "owner/homebrew-test", "1.2.3", cask())
                self.assertEqual(content, api.content)
                self.assertTrue(all(method == "GET" for method, _, _ in api.calls))

    def test_bad_target_version_and_payload_fail_before_requests(self):
        for target, version, content in [("bad/target/extra", "1.2.3", cask()),
                                         ("-bad/tap", "1.2.3", cask()),
                                         ("owner/homebrew-test", "../bad", cask()),
                                         ("owner/homebrew-test", "1.2.3", cask("1.2.4")),
                                         ("owner/homebrew-test", "1.2.3", cask(digest="bad")),
                                         ("owner/homebrew-test", "1.2.3", cask() + "evil\n")]:
            api = FakeAPI()
            with self.assertRaises(ValueError):
                self.module.update(api, target, version, content)
            self.assertEqual([], api.calls)

    def test_concurrent_conflict_is_not_retried(self):
        api = FakeAPI()
        request = api.request

        def conflict(method, path, body=None, missing_ok=False):
            if method == "PUT":
                api.content = cask("2.0.0")
                raise RuntimeError("Tap API failed (HTTP 409)")
            return request(method, path, body, missing_ok)

        with patch.object(api, "request", side_effect=conflict) as mocked:
            with self.assertRaisesRegex(RuntimeError, "409"):
                self.module.update(api, "owner/homebrew-test", "1.2.3", cask())
            self.assertEqual(1, sum(call.args[0] == "PUT" for call in mocked.call_args_list))
        self.assertEqual(cask("2.0.0"), api.content)

    def test_api_errors_do_not_expose_credentials(self):
        import urllib.error
        api = self.module.GitHubAPI("never-log-this-token")
        with patch("urllib.request.urlopen", side_effect=urllib.error.HTTPError("url", 403, "secret", {}, None)):
            with self.assertRaisesRegex(RuntimeError, "HTTP 403") as error:
                api.request("GET", "repos/owner/tap")
        self.assertNotIn("never-log-this-token", str(error.exception))

    def test_verified_fixture_handoff_reaches_publication_and_tampering_fails(self):
        import hashlib
        import json
        import tempfile
        from fixtures.release_fixture import write_archive
        spec = importlib.util.spec_from_file_location("renderer", ROOT / "Scripts/render-homebrew-release.py")
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as temp:
            handoff = Path(temp) / "handoff"
            archive = Path(temp) / "fixture.zip"
            write_archive(archive)
            renderer.render(archive, "1.2.3", renderer.asset_url("1.2.3"),
                            "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest(),
                            "offline fixture", handoff)
            command = [str(SCRIPT), "--target", "owner/homebrew-test", "--handoff", str(handoff), "--publish"]
            api = FakeAPI()
            with patch.dict("os.environ", {"HOMEBREW_TAP_TOKEN": "fixture-only"}), \
                    patch("sys.argv", command), patch.object(self.module, "GitHubAPI", return_value=api), \
                    patch("builtins.print"):
                self.module.main()
                self.assertEqual((handoff / "Casks/matrix-screen-saver.rb").read_text(), api.content)
                manifest = json.loads((handoff / "manifest.json").read_text())
                for field, value in [("sha256", "b" * 64), ("asset_url", "https://example.com/evil.zip"),
                                     ("cask_macos_floor", "26.0")]:
                    with self.subTest(field=field):
                        tampered = dict(manifest, **{field: value})
                        (handoff / "manifest.json").write_text(json.dumps(tampered))
                        api.calls.clear()
                        with patch("sys.stderr"), self.assertRaises(SystemExit):
                            self.module.main()
                        self.assertEqual([], api.calls)

    def test_publication_requires_opt_in_and_missing_token_preserves_handoff(self):
        import os
        import subprocess
        import sys
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            handoff = Path(temp)
            (handoff / "manifest.json").write_text('{"version":"1.2.3"}')
            env = {key: value for key, value in os.environ.items() if key != "HOMEBREW_TAP_TOKEN"}
            command = [sys.executable, str(SCRIPT), "--target", "owner/homebrew-test", "--handoff", temp]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("--publish", result.stderr)
            result = subprocess.run(command + ["--publish"], env=env, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("manual handoff artifact", result.stderr)
            self.assertTrue((handoff / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
