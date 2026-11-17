---
title: Matrix desktop and lock-screen images
type: feat
date: 2026-11-17
---

# Matrix desktop and lock-screen images

## Goal

Use the current Matrix frame as the native macOS wallpaper so the desktop, menu-bar treatment, and lock screen fit the animation.

## Settled behavior

- Enable image updates by default. Preserve saved choices, including an explicit opt-out.
- Share one persisted preference between **Use Matrix Image on Lock Screen**, directly below **Sync with Screen Saver**, and the General options checkbox.
- Describe it as: “Uses the current Matrix frame for your desktop and lock screen.”
- Capture any visible scene: intro messages, command output, trace program, or rain. Skip empty frames.
- Capture once after startup or explicit Start, and once per observed lock transition. Enabling the preference also schedules one capture.
- Do not refresh continuously, restore previous wallpapers, or delete images after Stop, Quit, or disabling the preference.
- No separate manual capture command.

These are the user's final decisions; they replace the earlier manual-only, rain-only, and default-off proposals.

## Implementation

### Capture

Reuse the renderer's existing drawing path at each display's backing resolution. Capture only Matrix content, without advancing the scene, changing pause state, enabling screen-saver sync, or requiring screen recording.

Require valid views for all connected displays before capture. A read-only visible-content check works across scenes. Lock capture may use retained views already hidden by the screen saver.

### Storage and native wallpaper updates

Prepare all PNGs before calling the native desktop setter. Use unique directories under the existing application-support image directory. Retain earlier images because inactive Spaces may reference them.

Report preparation failures without changing wallpapers. Report per-display setter failures honestly; successful changes are not rolled back. Automatic errors must not open a modal alert during locking or cause a retry loop.

### Shared controls

Use `UseMatrixImageForLockScreen` in the shared options model. Register a true default and preserve false through loading, sanitization, and saving.

The menu uses the native checkmark. A menu change updates an open General checkbox without discarding other edits. Saving General updates the menu. Preference-only changes do not restart the renderer.

### Scheduling

Reuse the existing maintenance timer for the pending startup capture. Clear pending state after an eligible attempt, including a failed attempt. Do not rearm on ordinary wake, display changes, or renderer restarts.

Deduplicate lock notifications until unlock. Never start stopped playback merely to capture an image.

## Limits

- macOS may prepare the lock screen before the notification arrives. Refresh is best-effort.
- Visible messages and command output become part of the saved image.
- The native API changes the desktop wallpaper too, not only the lock screen.
- Turning the option off retains the selected image; choose another wallpaper in System Settings to replace it.
- Captures accumulate on disk. Cleanup is deferred because other Spaces may reference old files.
- No guarantee covers every Space or the pre-login/FileVault screen.

## Verification

Use isolated preference stores and fake desktop setters; tests must not change the user's wallpapers.

- `./wallpaper-tests.sh --still-tests`: native-resolution capture, PNG preparation, partial failures, shared controls, defaults, saved opt-outs, all scenes, paused frames, startup/lock timing, and duplicate notifications.
- `./wallpaper-tests.sh`: host and consumer integration.
- `./tests.sh`: renderer regressions.
- `./build.sh` and `./build-wallpaper.sh --saver build/MatrixScreenSaver.saver`: matching bundles.
- Targeted strict Swift formatting, signature validation, and `git diff --check`.

Run graphical checks sequentially, without another wallpaper producer competing for shared-frame notifications. Observe actual lock-screen freshness manually; notification timing is not guaranteed by tests.
