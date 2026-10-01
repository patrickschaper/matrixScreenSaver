# Homebrew tap payload

The public tap is [patrickschaper/homebrew-tap](https://github.com/patrickschaper/homebrew-tap).
`Casks/matrix-screen-saver.rb` here is the source payload for the same path in
that repository. Users add it with `brew tap patrickschaper/tap`.

The payload uses Homebrew's native `screen_saver` artifact, not the local installer.
It retains the `dev.patsch.MatrixScreenSaver` preferences domain and has no zap
or preference-cleanup hook. Its published binary requires Apple Silicon (ARM64)
and macOS 15 (Sequoia) or newer.

Homebrew 7.0.7 ordinary mode supports the deprecated preflight/postflight blocks.
Developer mode rejects them. The narrow `Cask/InstallSteps` style exception is
intentional: initial-install-only settings launch needs the prior receipt snapshot.
Do not disable other audit checks or claim universal future Homebrew support.
For style verification, use the single-cop command-line exception rather than
source directives (Homebrew prohibits those):

```bash
brew style --except-cops Cask/InstallSteps "$PWD/Homebrew/Casks/matrix-screen-saver.rb"
```

## Release handoff

After publication, the Release workflow downloads the **existing published**
versioned zip, including on reruns. It checks the asset digest, bundle identity
and version, archive layout, thin ARM64 Mach-O bundle, and minimum macOS version.
It uploads `homebrew-handoff-VERSION`, containing `Casks/matrix-screen-saver.rb`
and `manifest.json` with version, URL, SHA-256, architecture, OS floor, and provenance.
Copy the generated cask into `patrickschaper/homebrew-tap` and review it before
merging. The source repository's `HOMEBREW_TAP_REPOSITORY` variable is configured
to that target. Automatic update PRs remain unconfigured until the separate
`HOMEBREW_TAP_TOKEN` secret is supplied and the release workflow changes reach
the published source branch.

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

## Optional tap PR (token pending)

The tap exists and the target variable is set. To enable update PRs, configure
a dedicated credential on the source repository:

- Variable `HOMEBREW_TAP_REPOSITORY`: `patrickschaper/homebrew-tap` (already set).
- Secret `HOMEBREW_TAP_TOKEN`: separate fine-grained credential limited to that
  tap's **contents** and **pull requests** write permissions (plus metadata read).
  The source-repository `GITHUB_TOKEN` is not cross-repository authorization.

The workflow creates a version-specific branch and one PR, reusing matching
content and the PR on reruns. It never pushes to the tap's default branch or
merges a PR. Human review and merge are required. A failed upload can be retried
only while its branch still matches the current default-branch commit. An existing
divergent branch fails without overwriting it; inspect the branch before retrying. A closed,
unmerged version PR must be reopened manually rather than duplicated.

Missing credentials or API failure affect only the optional step. The published
release and manual handoff artifact remain available. Download that artifact to
update the tap manually, or fix configuration and rerun the existing publish job
with explicit authorization. Tests use mock API calls and do not receive this
credential, including on fork pull requests. No repository or secret is provisioned
by these scripts.

## Verification

Run the offline suites with Ruby 3.4+ (or Homebrew's portable Ruby) and Python 3:

```bash
ruby Tests/Homebrew/cask_lifecycle_test.rb
python3 -B -m unittest discover -s Tests/Homebrew -p '*_test.py'
ruby -c Homebrew/Casks/matrix-screen-saver.rb
bash -n Tests/Homebrew/integration_lifecycle.sh
./tests.sh
./build.sh
```

`.github/workflows/homebrew-tests.yml` runs offline tests without publishing secrets,
uploads a clearly labeled fixture handoff, and pins Homebrew 7.0.7 for disposable
macOS native lifecycle tests. To run the native test locally, obtain explicit
authorization for a disposable environment first, then run:

```bash
bash Tests/Homebrew/integration_lifecycle.sh
```

The test requires an ARM64 macOS host and Homebrew 7.0.7. It redirects the native
destination, all artifact directories, Caskroom, cache, logs, and fixture tap into
one temporary directory. It uses real installers, upgrade orchestration, downloads,
native moves, and quarantine operations. It intercepts only the exact absolute
`/usr/bin/open` Wallpaper Settings call and never opens real settings. A separate
sentinel outside the artifact destination verifies preference retention; it does
not access the actual defaults domain. HOME alone is not used as isolation.

The cask's prior-receipt snapshot lives outside the `cask` block because Homebrew
refreshes that block when assigning the final config after staging. Recomputing
the snapshot inside the block would suppress first-install setup.

Native integration covers install, conflict failure, forced migration, upgrade,
reinstall, uninstall, quarantine removal, failed settings launch, and the expected
developer-mode deprecation error. Ordinary-mode warnings are expected, not a claim
of a clean developer audit. Run workflow lint (for example `actionlint`) separately;
never conceal unrelated style/audit failures with broad exclusions.
