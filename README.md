# macOS Matrix Screen Saver and Animated Wallpaper

The iconic Matrix digital rain for your Mac.

![macOS Matrix Screen Saver demo](docs/matrix-screensaver.gif)

## Features

- Digital rain, “Wake up, Neo” messages, trace program, and custom command scenes.
- Customize the font, characters, speed, density, glow, and scan lines.
- Classic and Resurrections glyph styles, plus personalized intro messages.

Only use trusted custom commands. They run with the app's permissions. Their text and output are visible on the lock screen.

## Animated wallpaper

Run the animation on your desktop with the included **Matrix Wallpaper** app. Use its menu bar icon to pause, stop, or open **Settings…**.

## Quick install

```bash
brew trust --cask patrickschaper/tap/matrix-screen-saver
brew install --cask patrickschaper/tap/matrix-screen-saver && open "/Applications/Matrix Wallpaper.app"
```

- **Wallpaper:** open **Matrix Wallpaper** in Applications.
- **Screen saver options:** **System Settings → Wallpaper → Screen Saver → MatrixScreenSaver → Options…**.

## Buy me a coffee

There is no spoon. There is coffee. Donations help fund the Apple Developer membership and development.

<a href="https://www.buymeacoffee.com/yesman82"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" width="150"></a><br>
<img src="docs/bmc_qr.png" alt="Buy Me a Coffee QR code" width="150">

## Install from a download

Download and extract the release archive. Open **Install.command** to install for your user account. Both installation methods install and update the app and screen saver together.

To restore a deleted screen saver, choose **Install Screen Saver** in the app menu or **Settings…**. Your settings and wallpaper stay unchanged. Select the restored saver in System Settings.

## Uninstall

Homebrew:

```bash
brew uninstall --cask matrix-screen-saver
```

**Install.command** or local scripts:

```bash
/bin/bash "$HOME/Library/Application Support/MatrixWallpaper/Installation/product-lifecycle.sh" uninstall
```

Preferences are kept.

Moving or deleting the app also removes the screen saver. Allow 5–6 minutes while logged in. Restoring the app before cleanup cancels removal.

For Homebrew installs, run its uninstall command after manual removal.

## Requirements

- Mac with Apple silicon (M1 or later).
- macOS 15 Sequoia or later.
- Homebrew for the quick install above.

## Development

See the [developer documentation](docs/development.md) for setup and testing.
