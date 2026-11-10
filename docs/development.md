# Developer notes

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
