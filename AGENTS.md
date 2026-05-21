# AGENTS.md

## Context management

- Always re-read this file (`AGENTS.md`) after conversation history has finished compacting (i.e. when a compaction summary appears at the top of the conversation).

## Project

MatrixScreenSaver is a native macOS `.saver` bundle that renders a terminal-style Matrix effect in process.

This repository is hosted on GitHub. When relevant, assume GitHub-native features and conventions apply, including GitHub Actions workflows, pull requests, releases, and GitHub-flavored Markdown rendering.

## Tech stack

- Swift
- AppKit
- `ScreenSaver.framework`
- `ScreenSaverDefaults` for persisted options
- Native renderer in `Sources/MatrixScreenSaver/`
- Local preview host in `Tools/PreviewHost.swift`
- Shell scripts for build/install/preview/test: `build.sh`, `install.sh`, `preview.sh`, `tests.sh`
- GitHub Actions for CI and releases

## Repository layout

### Source — `Sources/MatrixScreenSaver/`

| File | Purpose |
|---|---|
| `MatrixScreenSaverView.swift` | Main `.saver` view — drawing, lifecycle, layout, options wiring |
| `NativeMatrixRenderer.swift` | Core in-process Matrix animation engine |
| `MatrixScreenSaverOptions.swift` | Persisted options model and native **Options…** configure sheet |
| `MatrixRendererLimits.swift` | Shared numeric clamps/limits (Foundation-only, no AppKit/ScreenSaver dependency) |
| `NeoMessageScene.swift` | "Neo" intro message state machine |
| `Xorshift64.swift` | Deterministic 64-bit RNG |
| `TerminalSupport.swift` | Shared terminal-like types: `TerminalSize`, `TerminalColor` |

### Tools

| File | Purpose |
|---|---|
| `Tools/PreviewHost.swift` | Standalone preview window host used by `./preview.sh` |

### Tests — `Tests/MatrixScreenSaverTests/`

| File | Purpose |
|---|---|
| `main.swift` | TAP harness entry point — `ok()` helper, orchestrates test files, prints plan |
| `Xorshift64Tests.swift` | Tests for `Xorshift64` RNG determinism |
| `NativeMatrixRendererTests.swift` | Tests for renderer `seedOffset` default and per-display divergence |

### Scripts

| Script | Purpose |
|---|---|
| `build.sh` | Builds `build/MatrixScreenSaver.saver` via `swiftc` |
| `tests.sh` | Compiles and runs the TAP test suite via `swiftc` (no Xcode required) |
| `install.sh` | Builds and installs to `~/Library/Screen Savers/`, kills `ScreenSaverEngine` |
| `preview.sh` | Builds and launches the saver in the preview host for fast iteration |
| `Scripts/install-saver.sh` | Shared installer (strips quarantine, copies with `ditto`, verifies hash) |

### CI — `.github/workflows/`

| Workflow | Trigger | Purpose |
|---|---|---|
| `tests.yml` | Push to `development`/`feat/**`/`fix/**`; PRs to `development` or `main` | Runs `./tests.sh` on `macos-latest` |
| `release.yml` | `workflow_dispatch` on `main`; push to `main` when `VERSION` changes | Bumps version, updates changelog, opens release PR; on merge publishes GitHub Release |

### Resources

- `Resources/Info.plist` — bundle metadata; version injected at build time from `VERSION`
- `Resources/Preview.png`, `Resources/Preview@2x.png` — saver thumbnail assets
- `VERSION` — single source of truth for the bundle and release version

## Build

```bash
./build.sh
```

Outputs `build/MatrixScreenSaver.saver`. Reads `VERSION`, compiles with `-O -parse-as-library -emit-library -Xlinker -bundle`, injects version into plist, ad-hoc codesigns.

## Tests

```bash
./tests.sh
```

Compiles a test binary with `swiftc` and runs it. Emits **TAP** (Test Anything Protocol) output — `ok N - description` / `not ok N - description` lines, then a `1..N` plan. Exits non-zero on failure. Command Line Tools only; no Xcode required.

Tests cover:
- `Xorshift64` — same seed → same sequence; different seeds → different sequences
- `NativeMatrixRenderer` — `seedOffset` defaults to `0`; two renderers with different `seedOffset` values diverge after 60 frames

## Code documentation

Use Swift doc comments (`///`) for all public and internal declarations — types, properties, methods, and parameters. Follow the standard Swift/Xcode documentation style:

```swift
/// A single falling column of Matrix characters.
///
/// Each column tracks its own position, speed, and glyph sequence
/// so the renderer can update it independently each frame.
class MatrixColumn {

    /// The horizontal position of the column in grid units.
    let x: Int

    /// Initializes a new column at the given grid position.
    ///
    /// - Parameters:
    ///   - x: Horizontal grid index for this column.
    ///   - speed: Fall speed in cells per frame.
    init(x: Int, speed: Int) { … }

    /// Advances the column by one frame, updating character positions.
    ///
    /// - Returns: `true` if the column is still visible, `false` if it has scrolled off screen.
    func tick() -> Bool { … }
}
```

- Use `///` (triple-slash) for doc comments; `//` for inline clarifications only.
- Include a `- Parameters:` block whenever a function takes non-obvious arguments.
- Include `- Returns:` and `- Throws:` blocks where applicable.
- Use `// MARK: -` to separate logical sections within a file.
- Do not comment self-evident code; focus comments on *why*, not *what*.

## Implementation notes

- Keep the renderer native; do not reintroduce an external terminal or runtime wrapper.
- Keep the options UI native AppKit.
- `MatrixRendererLimits.swift` is Foundation-only — do not import `AppKit` or `ScreenSaver` there; it must compile as part of the test binary without those frameworks.
- Use `./preview.sh` for fast iteration and `./install.sh` for the real saver bundle.
- When adding a new source file that should be testable, add it to the `swiftc` invocation in `tests.sh`.
- When adding a new source file, also add it to the `swiftc` invocation in `build.sh`.

## Git commits

- Follow Conventional Commits, for example: `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`, `test: ...`
- Use a short title line.
- Add a few very concise bullet points for the meaningful changes.

## Pull requests

- Use a concise title that summarizes the branch changes.
- Write a short message with concise bullet points that summarize the meaningful changes from the commits in the branch.

## Git operations — require explicit instruction

**Never perform any of the following automatically.** Always wait for the user to explicitly ask:

- Create a branch (`git checkout -b`)
- Commit (`git commit`)
- Push (`git push`)
- Create a pull request (`gh pr create`)
- Merge a pull request (`gh pr merge`)
- Enable auto-merge on a pull request (`gh pr merge --auto`)
- Trigger or re-run GitHub Actions workflows

## Pushing

- Never push automatically.
- Always wait for explicit user instruction before running `git push`.

## Branch workflow

- Do not commit directly to `main`.
- Use a feature branch for changes.
- Use conventional branch names, for example: `feat/...`, `fix/...`, `docs/...`, `refactor/...`
- Merge feature branches into `development` first, then merge `development` into `main`.
- Merges to `main` must only come from `development` or `release/*` branches.
- Merge to `main` only through a pull request.
- Require approval before merging.
- The `development` branch is the default branch for new PRs.

Example commit:

```text
feat: add character size options

- add width/height fields
- persist values in defaults
- apply size to cell layout
```

## Releases

- Trigger releases by running the **Release** GitHub Actions workflow (`workflow_dispatch`) — never manually.
- The workflow bumps the version, updates `CHANGELOG.md`, and opens a `release/*` PR targeting `main`.
- Merging that `release/*` PR into `main` triggers the publish job, which creates the actual GitHub release with a zipped `.saver` bundle attached.

