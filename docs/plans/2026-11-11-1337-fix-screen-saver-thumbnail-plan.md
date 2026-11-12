---
title: Screen Saver Thumbnail - Plan
type: fix
date: 2026-11-11
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Screen Saver Thumbnail - Plan

## Goal Capsule

Make the MatrixScreenSaver tile in System Settings show the supplied Matrix screenshot instead of the generic blue image.
Prepare static thumbnail assets and package them in the existing native `.saver` bundle.
Deliver the change in one small PR, following the repository's branch and approval rules.
This plan authorizes no image changes, installation, cache removal, or Git publication by itself.

## Product Contract

### Summary

Use the supplied Matrix rain screenshot as the gallery thumbnail for MatrixScreenSaver under **Other** in the macOS screen saver picker.
The screenshot of System Settings identifies the target tile; it is not the source artwork.

### Problem Frame

The user's System Settings screenshot shows a generic blue image for MatrixScreenSaver, making the tile visually unrelated to the effect it provides.
The repository already contains Matrix preview images, but their filenames differ from the thumbnail resources in Apple's installed Random saver.
That mismatch is a likely cause, not yet a proven explanation of the picker behavior.

### Requirements

- R1. The gallery tile uses the screenshot supplied at `2026-11-11 at 11.47.04`, preserving its green-on-black appearance without labels, borders, or generated artwork.
- R2. The image fills the tile without stretching; standard and Retina variants use the same crop.
- R3. Both the standalone saver and the wallpaper app's embedded recovery saver contain the thumbnail resources.
- R4. Verify the installed tile in System Settings on the user's macOS version before declaring the fix complete.

### Scope Boundaries

This changes static gallery artwork only.
The black live preview above the controls in the System Settings screenshot, renderer behavior, app icon, preferences, and playback are separate concerns.

## Planning Contract

### Repository and Platform Evidence

- `Resources/Preview.png` is 400×250 and `Resources/Preview@2x.png` is 800×500; both already depict Matrix rain.
- `build.sh` copies those files into the saver resources, silently skipping missing files.
- A repository search found their filenames only in `build.sh` and the resource inventory in `AGENTS.md`.
- `Resources/Info.plist` has no thumbnail-specific key.
- On the inspected macOS 27.2 installation, Apple's `Random.saver` contains lowercase `thumbnail.png` at 90×58 and `thumbnail@2x.png` at 180×116 in `Contents/Resources`; its plist has no thumbnail-specific key either.
- `build-wallpaper.sh` embeds the prepared saver archive, so fixing the saver resources before app assembly reaches recovery installations without a new installer path.

The installed Apple bundle is primary evidence for the filename convention, not a published compatibility guarantee.
Apple documents preview-mode views separately in [ScreenSaverView](https://developer.apple.com/documentation/screensaver/screensaverview), supporting the distinction between gallery artwork and live rendering.

### Key Technical Decisions

- KTD1. Use lowercase `thumbnail.png` and `thumbnail@2x.png` in `Contents/Resources`, matching the observed native bundle. Do not add an undocumented plist key or change the bundle identifier.
- KTD2. Produce 90×58 and 180×116 opaque PNGs from one centered 45:29 crop of the supplied 2493×1406 image. Crop the sides rather than distort the glyphs or add letterboxing; review the result at actual tile size.
- KTD3. Retain the unmodified source as `Resources/ThumbnailSource.png` for reproducibility, but package only the two generated thumbnails. Use deterministic image resizing and record the crop/export recipe in developer documentation.
- KTD4. Replace the unused `Preview` assets and copy loop rather than shipping duplicate aliases. Make the two required resource copies fail the build if either is absent.
- KTD5. Treat a stale tile as a separate verification issue: reopen System Settings and reselect the saver first; if necessary, verify on a fresh macOS user or VM before investigating a specifically identified cache. Do not delete broad system caches or reset preferences.

### Local Source Inputs

The artwork is the user-provided, machine-local file `/Users/patrickschaper/Desktop/Screenshot 2026-11-11 at 11.47.04.png` (2493×1406, 932179 bytes).
The target reference is `/Users/patrickschaper/Desktop/Screenshot 2026-11-11 at 13.25.15.png`.
Copy the artwork into the repository during implementation so future builds do not depend on a Desktop path.
If the local file is unavailable, obtain the original attachment before generating assets; do not substitute the existing preview image.

## Implementation Units

### U1. Prepare and package the supplied artwork

**Covers:** R1–R3; KTD1–KTD4.

**Files:** new `Resources/ThumbnailSource.png`, `Resources/thumbnail.png`, `Resources/thumbnail@2x.png`; remove `Resources/Preview.png` and `Resources/Preview@2x.png`; update `build.sh`, the resource inventory in `AGENTS.md`, and `docs/development.md`.

Create the two assets from the preserved source using the same crop and normal downsampling.
Inspect them at 1× and 2× for visible Matrix columns, correct aspect ratio, and a solid black background.
Keep asset generation out of routine builds: checked-in exports are the build inputs.
Update the copy step and document the source/export recipe; no renderer or plist changes are expected.

**Verification:** `sips` reports the intended pixel sizes; both images decode; the source remains byte-identical to the attachment; `./build.sh` packages the two exact names and passes its existing signing step.
No image-processing test framework is needed for this asset edit.

### U2. Check distribution and recovery packaging

**Depends on:** U1. **Covers:** R3.

**Files:** `wallpaper-install-tests.sh`; change `build-wallpaper.sh` only if inspection exposes a packaging gap.

Extend the existing packaging smoke test with assertions that both required image files survive in the standalone saver and the saver extracted from the wallpaper app's recovery archive.
Compare each packaged image with its checked-in export so a valid but stale image cannot pass.
Reuse the harness's temporary directories and archive tools; do not install into the developer's real account for automated checks.

**Test scenarios:** a fresh build contains both assets; the embedded archive has the same image bytes; removing either required input makes the saver build fail rather than silently ship generic artwork.

### U3. Verify the actual System Settings tile

**Depends on:** U1–U2. **Covers:** R4; KTD5.

**Files:** none expected; record the macOS version and verification result in the PR.

After implementation and installation are authorized, install the matching saver/app pair through the existing project installer.
Open the screen saver picker, locate MatrixScreenSaver under **Other**, and verify the supplied rain image appears with the correct crop and no generic blue fallback.
Check the tile selected and unselected, and confirm the Options button and actual saver still work.
If the tile remains stale, follow KTD5 before changing packaging again.
Do not interpret the separate black live preview as failure of the static thumbnail change.

## Verification Contract

- Inspect exports with `sips` and an image viewer; no generated imagery or renderer changes.
- Run `./build.sh`, then `./build-wallpaper.sh --saver build/MatrixScreenSaver.saver`.
- Run `./wallpaper-install-tests.sh` with the added packaging assertions.
- Verify strict code signatures on the built saver and wallpaper app after packaging.
- Complete U3 on macOS 27.2 and record the result; check macOS 15 compatibility in an available test environment before claiming it.

Broad animation tests are unnecessary unless implementation unexpectedly changes Swift code.
No tests or installations were performed for this thumbnail plan.

## Definition Done

- The installed gallery tile shows the supplied Matrix screenshot.
- Both thumbnail resolutions derive from the same undistorted crop.
- Standalone and embedded recovery savers contain the correct image bytes.
- Signing remains valid, and the existing installation/recovery flow remains compatible.
- Obsolete preview aliases and experimental cache workarounds are absent from the final change.
