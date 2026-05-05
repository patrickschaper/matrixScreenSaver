# MatrixScreenSaver

MatrixScreenSaver is a macOS `.saver` bundle that shows a terminal-window version of the Matrix effect.

## Origin

This project started as an attempt to wrap `cxxmatrix` inside a macOS screen saver.

The current implementation is based on the upstream [`akinomyoga/cxxmatrix`](https://github.com/akinomyoga/cxxmatrix) project and keeps its look and scene behavior, but it no longer launches an external terminal process at runtime. The active saver is a native in-process Swift/AppKit renderer because `ScreenSaverEngine` did not reliably render the external terminal stream.

The active renderer currently ports `rain-forever` and can optionally start with the upstream `number` intro.

## Current state

- Native Swift/AppKit screen saver bundle
- Terminal-style window chrome around the animation
- In-process renderer for `rain-forever` with an optional upstream `number` intro
- Native **Options…** sheet for Number scene, Twinkle, Diffuse, Rain density, Frame rate, and Error rate
- Preview app for fast iteration without reinstalling

## Repository layout

- `Sources/MatrixScreenSaver/MatrixScreenSaverView.swift` - screen saver view, layout, drawing, and option wiring
- `Sources/MatrixScreenSaver/NativeMatrixRenderer.swift` - native Matrix scene renderer
- `Sources/MatrixScreenSaver/MatrixScreenSaverOptions.swift` - options model and native configure sheet
- `Sources/MatrixScreenSaver/TerminalSupport.swift` - small shared terminal types used by the active renderer
- `Tools/PreviewHost.swift` - local preview host used by `./preview.sh`
- `Resources/Info.plist` - bundle metadata

## Requirements

- macOS
- Xcode Command Line Tools with `swiftc`

Full Xcode is not required.

## Build

```bash
./build.sh
```

This creates the screen saver bundle:

```text
build/MatrixScreenSaver.saver
```

## Preview without installing

```bash
./preview.sh
```

This rebuilds the bundle, compiles the preview host, and opens the saver in a normal macOS window for quick iteration.

## Install

```bash
./install.sh
```

`install.sh`:

1. rebuilds the saver bundle
2. copies it to `~/Library/Screen Savers/MatrixScreenSaver.saver`
3. verifies the installed executable matches the build output
4. stops running `ScreenSaverEngine` / `legacyScreenSaver` processes so macOS reloads the updated bundle

After installing:

1. open **System Settings > Screen Saver**
2. select **MatrixScreenSaver**

To relaunch the screen saver host manually:

```bash
open -a ScreenSaverEngine
```

## Options

The saver exposes a native **Options…** sheet. The values are stored with `ScreenSaverDefaults`.

| Option | Description | Default |
| --- | --- | --- |
| Number scene | Show the startup number scene before continuous rain. | On |
| Twinkle | Turn on/off the twinkling effect. | On |
| Diffuse | Turn on/off the background-color effect. | On |
| Rain density | Set the factor for the density of rain drops. A positive number. | 1.0 |
| Frame rate | Set the frame rate per second. A positive number less than or equal to 1000. | 25 |
| Error rate | Set the factor for the rate of character changes. A non-negative number. | 1.0 |

The Twinkle, Diffuse, Rain density, Frame rate, and Error rate descriptions are taken from the original `cxxmatrix --help` text.

## Notes

- The old PTY/subprocess wrapper path has been removed; the current codebase only contains the native renderer implementation used by preview and the installed saver.
- Rendering uses cached glyph bitmaps plus a composed offscreen frame each tick, which keeps the saver responsive in both preview and the installed host.
- The build and preview flow now only depends on the native Swift sources listed above; there is no bundled web terminal or external `cxxmatrix` runtime in the repo anymore.
