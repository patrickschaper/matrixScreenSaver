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
- Shell scripts for build/install/preview: `build.sh`, `install.sh`, `preview.sh`

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
- Use `./preview.sh` for fast iteration and `./install.sh` for the real saver bundle.

## Git commits

- Follow Conventional Commits, for example: `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`
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

Example:

```text
feat: add character size options

- add width/height fields
- persist values in defaults
- apply size to cell layout
```

## Releases

- Trigger releases by running the **Release** GitHub Actions workflow (`workflow_dispatch`) — never manually.
- The workflow bumps the version, updates `CHANGELOG.md`, and opens a `release/*` PR targeting `main`.
- Merging that `release/*` PR into `main` triggers the publish job, which creates the actual GitHub release.
