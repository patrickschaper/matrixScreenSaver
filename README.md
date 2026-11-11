# macOS Matrix Screen Saver

The iconic Matrix digital rain for your Mac.

![macOS Matrix Screen Saver demo](docs/matrix-screensaver.gif)

## Features

- Digital rain, “Wake up, Neo” messages, trace program, and custom command scenes.
- Highly customizable: change the font, characters, speed, density, glow, and scan lines.
- Classic and Resurrections glyph styles, plus personalized intro messages.

Only use trusted custom commands: they run with the app's permissions, and their text and output are visible even on the lock screen.

## Including animated Wallpaper

Run the animation on your desktop with the included **Matrix Wallpaper** app. Use its menu bar icon to pause, stop, or open **Settings…**.

## Quick install

```bash
brew trust --cask patrickschaper/tap/matrix-screen-saver
brew install --cask patrickschaper/tap/matrix-screen-saver && open "/Applications/Matrix Wallpaper.app"
```

- **Wallpaper:** open **Matrix Wallpaper** in Applications.
- **Screen saver options:** **System Settings → Wallpaper → Screen Saver → MatrixScreenSaver → Options…**.

## Install from a download

Download the release archive, extract it, and open **Install.command**. This installs both components for your user account. Both installers install and upgrade the app and screen saver together; separate installation is not supported.

## Uninstall

For Homebrew installations:

```bash
brew uninstall --cask matrix-screen-saver
```

For installations made with **Install.command** or the local scripts:

```bash
/bin/bash "$HOME/Library/Application Support/MatrixWallpaper/Installation/product-lifecycle.sh" uninstall
```

Both commands remove the app and screen saver while keeping your preferences. Moving the app to Trash, or away from its installed location, also removes the screen saver after about five to six minutes while you are logged in. A short macOS background job checks once a minute and removes itself after cleanup; it does not run continuously. Disabling that job prevents automatic cleanup. Restoring the app before cleanup cancels removal.

After manually removing a Homebrew installation, run the Homebrew uninstall command to clear its installation receipt.

## Buy me a coffee

There is no spoon. There is coffee. Donations help cover the Apple Developer membership and ongoing development.

<a href="https://www.buymeacoffee.com/yesman82"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" width="150"></a><br>
<img src="docs/bmc_qr.png" alt="Buy Me a Coffee QR code" width="150">

## Requirements

- Mac with Apple silicon (M1 or later).
- macOS 15 Sequoia or later.
- Homebrew for the quick install above.

## Development

Want to build or contribute? See the [developer documentation](docs/development.md) for setup, testing, and project details.
