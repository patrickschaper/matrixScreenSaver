# Homebrew tap payload

The public tap is [patrickschaper/homebrew-tap](https://github.com/patrickschaper/homebrew-tap).
`Casks/matrix-screen-saver.rb` here is the source payload for the same path in
that repository. Users add it with `brew tap patrickschaper/tap`.

The payload uses Homebrew's native `screen_saver` artifact, not the local installer.
It retains the `dev.patsch.MatrixScreenSaver` preferences domain and has no zap
or preference-cleanup hook. Its published binary requires Apple Silicon (ARM64)
and macOS 15 (Sequoia) or newer.

Homebrew 7.0.7 runs the modern `preflight_steps` and `postflight_steps` in its
supported sandbox. Developer mode accepts the definition without deprecation
warnings. Full cask style, including `Cask/InstallSteps`, needs no exclusions:

```bash
brew style "$PWD/Homebrew/Casks/matrix-screen-saver.rb"
```

## Installation, lifecycle, and security

```bash
brew trust --cask patrickschaper/tap/matrix-screen-saver
brew install --cask patrickschaper/tap/matrix-screen-saver
```

The fully qualified install trusts this cask, not the entire tap. Explicit
`brew trust --cask` also permits subsequent installs using the short name.

**Security:** preflight removes quarantine recursively only from the
checksum-verified staged `MatrixScreenSaver.saver`, before Homebrew moves it.
This bypasses Gatekeeper quarantine checks; it does not make the bundle notarized
or Apple-approved. Install only if you trust the release publisher. The cask
prints this disclosure before invoking `/usr/bin/xattr`; failure aborts installation.

After installation, open **System Settings > Wallpaper > Screen Saver** and
select **MatrixScreenSaver** manually. Modern Homebrew's sandbox blocks opening
Settings, so automatic opening was intentionally removed. The cask never selects
the saver or opens a browser. Successful install, upgrade, and reinstall print:

> There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82

An existing manual bundle is not silently replaced. The native artifact rejects
an unforced conflict; opt in to replacement while retaining saved options with:

```bash
brew install --cask --force patrickschaper/tap/matrix-screen-saver
```

The conditional guidance honors Homebrew's configured `screen_saverdir`.
Homebrew 7.0.7's `if_path_exists` checks `exist?`, not `symlink?`: a dangling
symlink is still rejected by the native artifact, but does not print the custom
migration message. Use the same explicit `--force` command to replace it.
The echo step narrowly declares the native target in `writable_paths` because
Homebrew uses that declaration to grant guard read access under HOME; echo does
not modify it. Only the staged bundle is passed to xattr. No sandbox disabling
or custom unsandboxed installer is used.

```bash
brew upgrade --cask patrickschaper/tap/matrix-screen-saver
brew uninstall --cask patrickschaper/tap/matrix-screen-saver
```

Upgrades and reinstalls remain native Homebrew operations. An upgrade may print
the existing-target guidance because Homebrew can leave an empty target directory
during replacement; no prior-receipt snapshot or initial-install-only behavior
is needed. Custom destinations are honored, and other saver copies are not removed.
Migration, upgrade, reinstall, and ordinary uninstall retain the
`dev.patsch.MatrixScreenSaver` options domain. There is no zap hook or preference
rewrite. Uninstall prints neither coffee nor installation guidance.

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
native moves, sandboxed install steps, echo stdout, and quarantine operations.
There is no Settings-launch mock: the cask contains no Settings-launch command.
A separate
sentinel outside the artifact destination verifies preference retention; it does
not access the actual defaults domain. HOME alone is not used as isolation.

Native integration covers install, conflict failure, forced migration, upgrade,
reinstall, uninstall, quarantine removal, broken-symlink conflict/force semantics,
and developer-mode acceptance without legacy warnings on definition load or
uninstall. Run workflow lint (for example `actionlint`) separately; never conceal
unrelated style/audit failures with exclusions. Compatibility is verified against
7.0.7, not promised for every future Homebrew release.
