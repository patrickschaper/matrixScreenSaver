# AGENTS.md

## Project

MatrixScreenSaver is a native macOS `.saver` bundle that renders a terminal-style Matrix effect in process.

## Tech stack

- Swift
- AppKit
- `ScreenSaver.framework`
- `ScreenSaverDefaults` for persisted options
- Native renderer in `Sources/MatrixScreenSaver/`
- Local preview host in `Tools/PreviewHost.swift`
- Shell scripts for build/install/preview: `build.sh`, `install.sh`, `preview.sh`

## Implementation notes

- Keep the renderer native; do not reintroduce an external terminal or runtime wrapper.
- Keep the options UI native AppKit.
- Use `./preview.sh` for fast iteration and `./install.sh` for the real saver bundle.

## Git commits

- Follow Conventional Commits, for example: `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`
- Use a short title line.
- Add a few very concise bullet points for the meaningful changes.

## Pushing

- Never push automatically.
- Always wait for explicit user instruction before running `git push`.

## Branch workflow

- Do not commit directly to `main`.
- Use a feature branch for changes.
- Use conventional branch names, for example: `feat/...`, `fix/...`, `docs/...`, `refactor/...`
- Merge to `main` only through a pull request.
- Require approval before merging.

Example:

```text
feat: add character size options

- add width/height fields
- persist values in defaults
- apply size to cell layout
```
