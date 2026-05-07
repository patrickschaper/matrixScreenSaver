# macOS Matrix Screen Saver

![macOS Matrix Screen Saver demo](docs/matrix-screensaver.gif)

This is a macOS screen saver based on the iconic rain of characters and symbols known from the movie The Matrix.

## Quick install

1. Open the [latest release](https://github.com/patrickschaper/matrixScreenSaver/releases/latest) in this repository's Releases section.
2. Download the versioned `.zip` file from the release assets and unzip it.
3. Double-click the extracted `.saver` file and confirm the macOS install prompt.
4. Open **System Settings > Wallpaper > Screen saver** and select **MatrixScreenSaver**.

## Options

The saver exposes a native **Options…** sheet. The values are stored with `ScreenSaverDefaults`.

| Option | Description | Default |
| --- | --- | --- |
| Number scene | Show the startup number scene before continuous rain. | On |
| Twinkle | Turn on/off the twinkling effect. | On |
| Diffuse | Turn on/off the background-color effect. | On |
| Character size | Set the character cell width and height in pixels. | 8 x 15 |
| Rain density | Set the factor for the density of rain drops. A positive number. | 1.0 |
| Frame rate | Set the frame rate per second. A positive number less than or equal to 1000. | 25 |
| Error rate | Set the factor for the rate of character changes. A non-negative number. | 1.0 |

## Development

### Current state

- Native Swift/AppKit screen saver bundle
- Edge-to-edge full-screen saver output, with terminal-style chrome kept in the preview host
- In-process renderer for `rain-forever` with an optional upstream `number` intro
- Native **Options…** sheet for Number scene, Twinkle, Diffuse, Character size, Rain density, Frame rate, and Error rate
- Preview app for fast iteration without reinstalling

### Repository layout

- `Sources/MatrixScreenSaver/MatrixScreenSaverView.swift` - screen saver view, layout, drawing, and option wiring
- `Sources/MatrixScreenSaver/NativeMatrixRenderer.swift` - native Matrix scene renderer
- `Sources/MatrixScreenSaver/MatrixScreenSaverOptions.swift` - options model and native configure sheet
- `Sources/MatrixScreenSaver/TerminalSupport.swift` - small shared terminal types used by the active renderer
- `Tools/PreviewHost.swift` - local preview host used by `./preview.sh`
- `Resources/Info.plist` - bundle metadata

### Requirements

- macOS
- Xcode Command Line Tools with `swiftc`

Full Xcode is not required.

### Build

```bash
./build.sh
```

This creates the screen saver bundle:

```text
build/MatrixScreenSaver.saver
```

`build.sh` reads the current version from `./VERSION` and writes it into the saver bundle metadata.

### Release

Run the manual **Release** workflow from the **main** branch in GitHub Actions and choose a semantic version bump (`patch`, `minor`, or `major`).

The workflow now uses a protected-branch-safe two-step flow:

1. bumps `VERSION` with pinned `semver@7.6.3`
2. validates the build with `./build.sh`
3. creates and pushes a `release/v${version}` branch
4. opens a pull request into `main` or reuses the existing one for that release branch if you rerun the manual job
5. after that PR is merged, the push-to-`main` release job builds from the merged commit, creates `${version}.zip` from `./build/`, tags that commit with `${version}`, and publishes the archive to GitHub Releases

This keeps direct workflow commits off `main`, so you can protect `main` with required pull requests and still publish releases. The `publish` job is intentionally skipped on the manual run; it only runs on the later push to `main` after the release PR merges.

### Preview without installing

```bash
./preview.sh
```

This rebuilds the bundle, compiles the preview host, and opens the saver in a normal macOS window for quick iteration.

### Install

```bash
./install.sh
```

`install.sh`:

1. rebuilds the saver bundle
2. copies it to `~/Library/Screen Savers/MatrixScreenSaver.saver`
3. verifies the installed executable matches the build output
4. stops running `ScreenSaverEngine` / `legacyScreenSaver` processes so macOS reloads the updated bundle

After installing:

1. open **System Settings > Wallpaper > Screen saver...**
2. select **MatrixScreenSaver**

To relaunch the screen saver host manually:

```bash
open -a ScreenSaverEngine
```

### Origin

This project started as an attempt to wrap `cxxmatrix` inside a macOS screen saver.

The current implementation is based on the upstream [`akinomyoga/cxxmatrix`](https://github.com/akinomyoga/cxxmatrix) project and keeps its look and scene behavior, but it no longer launches an external terminal process at runtime. The active saver is a native in-process Swift/AppKit renderer because `ScreenSaverEngine` did not reliably render the external terminal stream.

The active renderer currently ports `rain-forever` and can optionally start with the upstream `number` intro.
