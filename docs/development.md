# Developer notes

See the [project roadmap](plans/2026-11-10-1812-project-roadmap-plan.md) for planned work, including GPU-accelerated 3D scenes.

## Current state

- Native Swift/AppKit screen saver bundle
- Edge-to-edge full-screen saver output, with terminal-style chrome kept in the preview host
- In-process renderer for `rain-forever` with an optional upstream `number` intro
- Native **Options…** sheet for Number scene, Twinkle, Diffuse, Character size, Rain density, Frame rate, Error rate, Characters, Fonts, Neo message scene/speed/lines, custom shell commands/playback, and Scan lines
- Preview app for fast iteration without reinstalling

## Repository layout

- `Sources/MatrixScreenSaver/MatrixScreenSaverView.swift` - screen saver view, layout, drawing, and option wiring
- `Sources/MatrixScreenSaver/NativeMatrixRenderer.swift` - native Matrix scene renderer
- `Sources/MatrixScreenSaver/CmdCaptureScene.swift` - streams command output into scrolling terminal rows before the full trace program
- `Sources/MatrixScreenSaver/MatrixScreenSaverOptions.swift` - options model and native configure sheet
- `Sources/MatrixScreenSaver/TerminalSupport.swift` - small shared terminal types used by the active renderer
- `Scripts/product-lifecycle.sh` - shared pair installation, rollback, and removal lifecycle
- `Tools/PreviewHost.swift` - local preview host used by `./preview.sh`
- `Resources/Info.plist` - bundle metadata

## Requirements

- macOS
- Xcode Command Line Tools with `swiftc`

Full Xcode is not required.

## Build

```bash
./build.sh
./build-wallpaper.sh
```

These create the screen saver bundle and wallpaper app:

```text
build/MatrixScreenSaver.saver
build/Matrix Wallpaper.app
```

Both build scripts read the current version from `./VERSION` and write it into their bundle metadata.

Local builds and ordinary CI use ad-hoc signing and do not need Apple credentials.
Only the GitHub release publish job uses Developer ID signing and Apple notarization.

`./build-wallpaper.sh` builds a fresh saver and embeds its recovery archive, lifecycle script, and native installer helper in the app. After explicitly building the saver, use `./build-wallpaper.sh --saver build/MatrixScreenSaver.saver` to reuse those verified bytes. The supplied saver must match `VERSION` in both bundle version fields.

Releases sign, notarize, and staple the saver before assembling the recovery archive. The workflow then signs the installer helper and wallpaper app, notarizes/staples the app, and packages both top-level bundles. This keeps recovery independent of the original download and allows the embedded saver to retain its ticket.

## Test

```bash
./tests.sh
```

Compiles and runs the test suite using `swiftc`. No Xcode required — Command Line Tools are sufficient.

For wallpaper checks, build the app first and run from a logged-in graphical macOS session:

```bash
./wallpaper-tests.sh
./wallpaper-install-tests.sh
```

The UI tests briefly create desktop windows and open Options. Installer tests use a
temporary home directory; neither suite changes your real login items.

## Preview without installing

```bash
./preview.sh
```

This rebuilds the bundle, compiles the preview host, and opens the saver in a normal macOS window for quick iteration.

To launch the built wallpaper app without installing:

```bash
open "build/Matrix Wallpaper.app"
```

## Install

```bash
./install.sh
```

`install.sh`:

1. rebuilds and validates matching wallpaper and saver bundles
2. stages both copies, verifies signatures and executable bytes, and retains rollback backups
3. installs the app in `~/Applications` and the saver in `~/Library/Screen Savers`
4. registers a per-user cleanup LaunchAgent, then commits both replacements
5. stops your saver hosts so macOS reloads the updated bundle

After installing:

1. open **System Settings > Wallpaper > Screen saver...**
2. select **MatrixScreenSaver**

To relaunch the screen saver host manually:

```bash
open -a ScreenSaverEngine
```

The compatibility entrypoint also installs both components:

```bash
./install-wallpaper.sh
open "$HOME/Applications/Matrix Wallpaper.app"
```

### Installation lifecycle checks

Run `python3 Tests/Installation/lifecycle_test.py` for isolated failure, cleanup, and grace-period tests. Run `./wallpaper-install-tests.sh` after building both bundles for real-signature and migration coverage. System commands that could affect your desktop or launch services are mocked.

`./uninstall.sh` removes a local pair. Homebrew owns its native artifacts and invokes the same lifecycle script only for validation, registration, and cleanup state. The cleanup record contains exact destinations and ownership; options are never deleted. A shared lock protects local operations, and a PID lock held by the outer Homebrew process protects native artifact replacement. Native upgrade rollback reruns the previous registration hook.

Release bundles must have identical `CFBundleShortVersionString` and `CFBundleVersion`. There are no runtime companion-version warnings or playback restrictions. Shared-frame validation still rejects incompatible or malformed frames.

## Origin

This project started as an attempt to wrap `cxxmatrix` inside a macOS screen saver.

The current implementation is based on the upstream [`akinomyoga/cxxmatrix`](https://github.com/akinomyoga/cxxmatrix) project and keeps its look and scene behavior, but it no longer launches an external terminal process at runtime. The active saver is a native in-process Swift/AppKit renderer because `ScreenSaverEngine` did not reliably render the external terminal stream.

The active renderer currently ports `rain-forever` and can optionally start with the upstream `number` intro.

## Fonts and glyph sets

The **Glyph set** radio buttons in **Rain** select **Default**, **Classic**, or **Resurrections**. Classic and Resurrections use their original bundled fonts and glyph artwork. Default keeps the existing configurable rain. Switching presets preserves your custom font and character settings; these controls are editable when Default is selected.

The **Font** option selects one installed font family, including hidden fonts discovered in the standard system and user font folders. Choosing another font replaces the selection; Reset restores the system font. Existing multi-font settings retain only the first font. Default and custom characters missing from the selected font use macOS font fallback when glyph images are cached, with no extra font lookup during playback. Install any additional fonts yourself.

The bundled [Matrix Code](https://github.com/Rezmason/matrix/raw/master/assets/Matrix-Code.ttf) and [Matrix Resurrected](https://github.com/Rezmason/matrix/raw/master/assets/Matrix-Resurrected.ttf) fonts are published in [Rezmason/matrix](https://github.com/Rezmason/matrix) (MIT, © Rezmason 2018), which recreate the glyphs from the films. Thanks to Rezmason for making them available. See [font provenance](../Resources/Fonts/README.md) and the [included license](../Resources/Fonts/LICENSE.txt).

## Wallpaper installer

The installer builds and verifies the app, gracefully quits running copies before
replacement, and retains preferences. It does not launch the app or enable login startup.
It migrates a signed `MatrixWallpaper.app` with the matching bundle ID to
`Matrix Wallpaper.app`, restoring the previous installation if replacement fails.
Unrelated bundles and symlinks at the old path are left alone. The executable remains
`MatrixWallpaper` and the bundle ID remains `dev.patsch.MatrixWallpaper`.

## Screen saver synchronization

When MatrixScreenSaver is installed in `~/Library/Screen Savers` or `/Library/Screen Savers`,
the wallpaper menu shows **Sync with Screen Saver**. It is checked by default: the saver
shares the wallpaper's animation. Uncheck it to let the saver animate independently.
The choice survives app restarts and saver reinstallation; opening the menu refreshes
installation detection. This does not change visual options or synchronization between monitors.

When the saver is absent, that menu item becomes **Install Screen Saver**, and the wallpaper settings show the same action in a compact banner. `ScreenSaverInstallationController` refreshes both surfaces on menu opening, settings focus, app activation, and transaction completion without resetting pending options edits. The actual screen saver host has no installation controls.

Recovery runs the app's bundled `product-lifecycle.sh install-saver APP` off the main thread. It uses the existing installation lock and recorded destination/owner, validates and stages only the saver, and leaves the app and preferences untouched. A small native helper validates archive entries and promotes with an exclusive rename so another process's destination is never overwritten. Failures preserve retry state and roll back only transaction-owned changes.

A sibling `.installing` marker records the promoted bundle's device/inode until the transaction commits. If rollback cannot remove that bundle, discovery keeps the install action available and a retry can finish registration. A separately installed replacement has a different identity and remains discoverable.

Run `./wallpaper-tests.sh --installation-tests` for isolated discovery, menu, and banner checks, and `python3 Tests/Installation/lifecycle_test.py` for recovery/rollback in a temporary home. Developer ID and offline Gatekeeper behavior must also be checked with an authorized signed release artifact; stubbed signing tests do not establish that result.

## Component version checks

If Matrix Wallpaper and Matrix Screen Saver have different release versions, an error
appears above the options tabs, on the menu-bar icon, and at the top of its menu.
The wallpaper also shows an alert once per launch. Matrix playback is blocked in both
components: a yellow warning triangle moves slowly over a black screen instead. With Reduce
Motion enabled, the symbol stays still. Settings remain editable. Choose **View Releases…**
and install matching versions to resume playback.
Checks refresh when opening settings or the menu, and approximately once a minute during
playback. A missing companion is not a mismatch; unreadable version information
is explained in settings. Checks compare the loaded host with installed companion bundles,
so another process may still need restarting after an update. Older releases do not gain
these warnings until they are updated.

## Desktop wallpaper lifecycle

While Matrix Wallpaper runs, it saves each display's desktop image and display options,
then sets the underlying wallpaper to plain black. The menu starts with **Pause Animation**
and **Stop Wallpaper**. **Pause Animation** freezes the visible frame; **Resume Animation** continues the scene.
Pausing is session-only and does not persist across launches. With **Sync with Screen Saver**
enabled, the saver temporarily advances the shared scene even while the wallpaper is paused.
When the saver exits, the wallpaper pauses again at the updated scene. **Stop Wallpaper** and
**Quit Matrix Wallpaper** restore the original wallpaper settings. Temporary pauses
and animation restarts keep the original backup.
If you choose a different wallpaper while Matrix runs, that newer choice is preserved.

Backups are stored in `~/Library/Application Support/MatrixWallpaper/DesktopWallpaper/`.
After a crash or force-quit, reopen Matrix Wallpaper and choose **Stop Wallpaper** to restore the desktop.
Disconnected displays and failed restores keep their backups for a later retry.
Exact restoration is supported for static images; macOS's public API cannot preserve every
dynamic/aerial wallpaper, rotating collection, or separate Space configuration.
