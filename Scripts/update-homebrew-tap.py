#!/usr/bin/env python3
"""Optionally propose a tap update; never write the default branch or merge."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request


class GitHubAPI:
    def __init__(self, token):
        self.token = token

    def request(self, method, path, body=None, missing_ok=False):
        request = urllib.request.Request(
            "https://api.github.com/" + path,
            data=json.dumps(body).encode() if body is not None else None,
            method=method,
            headers={"Authorization": f"Bearer {self.token}", "Accept": "application/vnd.github+json",
                     "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "MatrixScreenSaver-release"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404 and missing_ok:
                return None
            # Never log response bodies, request headers, or token-bearing exceptions.
            raise RuntimeError(f"Tap API failed (HTTP {error.code}); manual handoff remains available") from None
        except urllib.error.URLError:
            raise RuntimeError("Tap API unavailable; retry or use the manual handoff") from None


def update(api, target, version, content):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", target):
        raise ValueError("Tap target must be owner/repository")
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version):
        raise ValueError("Invalid release version")
    repo = f"repos/{target}"
    default = api.request("GET", repo)["default_branch"]
    branch = f"matrix-screen-saver-{version}"
    branch_ref = api.request("GET", f"{repo}/git/ref/heads/{branch}", missing_ok=True)
    if branch_ref is None:
        base = api.request("GET", f"{repo}/git/ref/heads/{urllib.parse.quote(default, safe='')}")["object"]["sha"]
        api.request("POST", f"{repo}/git/refs", {"ref": f"refs/heads/{branch}", "sha": base})
    path = f"{repo}/contents/Casks/matrix-screen-saver.rb"
    existing = api.request("GET", path + "?" + urllib.parse.urlencode({"ref": branch}), missing_ok=True)
    encoded = base64.b64encode(content.encode()).decode()
    matches = existing is not None and base64.b64decode(existing["content"]).decode() == content
    if branch_ref is not None and not matches:
        base = api.request("GET", f"{repo}/git/ref/heads/{urllib.parse.quote(default, safe='')}")["object"]["sha"]
        # Retry a failed upload only while the branch is untouched; never replace divergent work.
        if branch_ref["object"]["sha"] != base:
            raise ValueError("Existing version branch differs; inspect it before retrying (no overwrite)")
    if not matches:
        body = {"message": f"chore: update matrix-screen-saver to {version}", "content": encoded, "branch": branch}
        if existing:
            body["sha"] = existing["sha"]
        api.request("PUT", path, body)
    query = urllib.parse.urlencode({"head": f"{target.split('/')[0]}:{branch}", "base": default, "state": "all"})
    prs = api.request("GET", f"{repo}/pulls?{query}")
    if prs:
        pr = prs[0]
        if pr["state"] == "closed" and not pr.get("merged_at"):
            raise ValueError("Version PR was closed; reopen it manually rather than creating a duplicate")
        return pr["html_url"]
    return api.request("POST", f"{repo}/pulls", {
        "head": branch, "base": default, "title": f"Update matrix-screen-saver to {version}",
        "body": "Pinned to the downloaded release asset and its SHA-256. Human review and merge required."})["html_url"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True)
    parser.add_argument("--handoff", required=True)
    args = parser.parse_args()
    token = os.environ.get("HOMEBREW_TAP_TOKEN")
    if not token:
        parser.exit(1, "No HOMEBREW_TAP_TOKEN configured. Download the manual handoff artifact; configure a tap-scoped token to retry.\n")
    try:
        handoff = Path(args.handoff)
        manifest = json.loads((handoff / "manifest.json").read_text())
        print(update(GitHubAPI(token), args.target, manifest["version"],
                     (handoff / "Casks/matrix-screen-saver.rb").read_text()))
    except (ValueError, RuntimeError, OSError, KeyError) as error:
        parser.exit(1, f"Optional tap update failed: {error}\n")


if __name__ == "__main__":
    main()
