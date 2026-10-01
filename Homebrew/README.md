# Homebrew tap payload

`Casks/matrix-screen-saver.rb` is ready to copy to a user-selected tap as
`Casks/matrix-screen-saver.rb`. No public tap is configured or live yet.

The payload uses Homebrew's native `screen_saver` artifact, not the local installer.
It retains the `dev.patsch.MatrixScreenSaver` preferences domain and has no zap
or preference-cleanup hook. Its published binary requires Apple Silicon (ARM64)
and macOS 15 (Sequoia) or newer.

Homebrew 7.0.7 ordinary mode supports the deprecated preflight/postflight blocks.
Developer mode rejects them. The narrow `Cask/InstallSteps` style exception is
intentional: initial-install-only settings launch needs the prior receipt snapshot.
Do not disable other audit checks or claim universal future Homebrew support.

## Release handoff

After publication, the Release workflow downloads the **existing published**
versioned zip, including on reruns. It checks the asset digest, bundle identity
and version, archive layout, thin ARM64 Mach-O bundle, and minimum macOS version.
It uploads `homebrew-handoff-VERSION`, containing `Casks/matrix-screen-saver.rb`
and `manifest.json` with version, URL, SHA-256, architecture, OS floor, and provenance.
Copy the generated cask into your selected tap and review it before merging.
No tap target is selected by this repository: publication remains unconfigured.

Offline validation:

```bash
python3 -B Scripts/render-homebrew-release.py \
  --version 0.2.0 --archive /path/to/0.2.0.zip \
  --asset-url https://github.com/patrickschaper/matrixScreenSaver/releases/download/0.2.0/0.2.0.zip \
  --digest sha256:7a60c8ec2855a2df4cb008da7f79ea9e8526385897e3048bb53bb42421e07acd \
  --provenance manual-release-download --output /path/to/handoff
```

Omit `--archive`, `--asset-url`, and `--digest` to retrieve the release through
`gh`; the renderer never builds a replacement archive. A new unsupported OS floor
or architecture fails closed until the compatibility policy is updated.

## Optional tap PR (disabled by default)

Only after the user chooses and provisions a tap, configure the source repository:

- Variable `HOMEBREW_TAP_REPOSITORY`: exact `owner/repository` target.
- Secret `HOMEBREW_TAP_TOKEN`: separate fine-grained credential limited to that
  tap's **contents** and **pull requests** write permissions (plus metadata read).
  The source-repository `GITHUB_TOKEN` is not cross-repository authorization.

The workflow creates a version-specific branch and one PR, reusing matching
content and the PR on reruns. It never pushes to the tap's default branch or
merges a PR. Human review and merge are required. An existing branch with different
content fails without overwriting it; inspect the branch before retrying. A closed,
unmerged version PR must be reopened manually rather than duplicated.

Missing credentials or API failure affect only the optional step. The published
release and manual handoff artifact remain available. Download that artifact to
update the tap manually, or fix configuration and rerun the existing publish job
with explicit authorization. Tests use mock API calls and do not receive this
credential, including on fork pull requests. No repository or secret is provisioned
by these scripts.
