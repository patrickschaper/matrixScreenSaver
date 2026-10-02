#!/usr/bin/env python3
"""Publish verified release metadata to the tap's default branch, failing closed."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request

TEMPLATE = Path(__file__).resolve().parents[1] / "Homebrew/Casks/matrix-screen-saver.rb"


def cask_metadata(content):
    """Separate the three release fields from the cask text without executing Ruby."""
    fields = []
    for pattern in (r'^  version "((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))"$',
                    r'^  sha256 "([0-9a-f]{64})"$', r'^  depends_on macos: :(sequoia|tahoe)$'):
        matches = re.findall(pattern, content, flags=re.M)
        if len(matches) != 1:
            raise ValueError("Cask release metadata is missing or invalid; inspect the manual handoff")
        fields.append(matches[0])
        content = re.sub(pattern, "", content, flags=re.M)
    return fields, content


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
    metadata, structure = cask_metadata(content)
    if metadata[0] != version or structure != cask_metadata(TEMPLATE.read_text())[1]:
        raise ValueError("Generated cask differs from the release template or version")
    repo = f"repos/{target}"
    default = api.request("GET", repo)["default_branch"]
    path = f"{repo}/contents/Casks/matrix-screen-saver.rb"
    existing = api.request("GET", path + "?" + urllib.parse.urlencode({"ref": default}), missing_ok=True)
    if existing is None or existing.get("type") != "file" or existing.get("encoding") != "base64":
        raise ValueError("Tap cask is missing or not a regular file; inspect it before publication")
    current = base64.b64decode(existing["content"]).decode()
    previous, previous_structure = cask_metadata(current)
    if previous_structure != structure:
        raise ValueError("Tap cask has unrelated edits; review the manual handoff (no overwrite)")
    if tuple(map(int, previous[0].split("."))) > tuple(map(int, version.split("."))):
        return f"Tap already has newer version {previous[0]}; skipped {version}"
    if previous[0] == version:
        if current != content:
            raise ValueError("Same-version cask differs; inspect the published asset and tap (no overwrite)")
        return f"Tap already matches {version}; no update needed"
    # The file SHA is a compare-and-swap guard: never retry a stale write blindly.
    return api.request("PUT", path, {
        "message": f"chore: update matrix-screen-saver to {version}",
        "content": base64.b64encode(content.encode()).decode(), "branch": default,
        "sha": existing["sha"]})["commit"]["html_url"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True)
    parser.add_argument("--handoff", required=True)
    parser.add_argument("--publish", action="store_true", required=True,
                        help="Explicitly allow a guarded commit to the tap's default branch")
    args = parser.parse_args()
    token = os.environ.get("HOMEBREW_TAP_TOKEN")
    if not token:
        parser.exit(1, "No HOMEBREW_TAP_TOKEN configured. Download the manual handoff artifact; configure a tap-scoped token to retry.\n")
    try:
        handoff = Path(args.handoff)
        manifest = json.loads((handoff / "manifest.json").read_text())
        content = (handoff / "Casks/matrix-screen-saver.rb").read_text()
        metadata, _ = cask_metadata(content)
        expected_url = ("https://github.com/patrickschaper/matrixScreenSaver/releases/download/"
                        f"{manifest['version']}/{manifest['version']}.zip")
        if (manifest["asset_url"] != expected_url or metadata[1] != manifest["sha256"]
                or {"sequoia": "15.0", "tahoe": "26.0"}[metadata[2]] != manifest["cask_macos_floor"]):
            raise ValueError("Cask does not match the verified handoff manifest")
        print(update(GitHubAPI(token), args.target, manifest["version"], content))
    except (ValueError, RuntimeError, OSError, KeyError) as error:
        parser.exit(1, f"Automatic tap update failed: {error}\n")


if __name__ == "__main__":
    main()
