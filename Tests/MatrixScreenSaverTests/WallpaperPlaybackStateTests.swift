import Foundation

/// Verifies user intent remains independent of overlapping system suspension reasons.
func wallpaperPlaybackStateTests() {
    var state = WallpaperPlaybackState()
    ok(state.shouldRun, "WallpaperPlaybackState: launches with playback requested")
    state.isPaused = true
    ok(!state.shouldRun && state.shouldShowDesktop, "WallpaperPlaybackState: manual pause keeps the desktop visible")
    state.setSuspended(.sleeping, true)
    ok(!state.shouldRun && !state.shouldShowDesktop, "WallpaperPlaybackState: sleep hides a paused desktop")
    state.setSuspended(.sleeping, false)
    ok(!state.shouldRun && state.shouldShowDesktop, "WallpaperPlaybackState: wake preserves manual pause")
    state.isServingScreenSaver = true
    state.setSuspended(.locked, true)
    ok(!state.shouldRun && !state.shouldShowDesktop, "WallpaperPlaybackState: saver sharing cannot override manual pause")
    state.isServingScreenSaver = false
    state.isPaused = false
    ok(!state.shouldRun, "WallpaperPlaybackState: manual resume cannot override lock")
    state.setSuspended(.locked, false)
    ok(state.shouldRun && state.shouldShowDesktop, "WallpaperPlaybackState: resume runs after system suspension clears")
    state.setSuspended(.locked, true)
    state.setSuspended(.locked, true)
    state.setSuspended(.sleeping, true)
    ok(!state.shouldRun, "WallpaperPlaybackState: duplicate and overlapping suspension is idempotent")
    state.setSuspended(.sleeping, false)
    ok(!state.shouldRun, "WallpaperPlaybackState: waking does not override lock")
    state.isRequested = false
    state.setSuspended(.locked, false)
    ok(!state.shouldRun, "WallpaperPlaybackState: Stop while suspended survives unlocking")
    state.setSuspended(.screenSaver, true)
    state.isRequested = true
    ok(!state.shouldRun, "WallpaperPlaybackState: Start does not override an active screen saver")
    state.setSuspended(.screenSaver, false)
    ok(state.shouldRun, "WallpaperPlaybackState: resumes after the last suspension clears")
    for reason in [WallpaperPlaybackState.Suspension.sessionInactive, .displaysSleeping] {
        state.setSuspended(reason, true)
    }
    state.setSuspended(.sessionInactive, false)
    ok(!state.shouldRun, "WallpaperPlaybackState: session activation does not override display sleep")
    state.setSuspended(.displaysSleeping, false)
    state.setSuspended(.displaysSleeping, false)
    ok(state.shouldRun, "WallpaperPlaybackState: duplicate resume notifications are harmless")
    state.setSuspended(.screenSaver, true)
    state.setSuspended(.locked, true)
    state.isServingScreenSaver = true
    ok(state.shouldRun && !state.shouldShowDesktop, "WallpaperPlaybackState: shared saver keeps rendering behind the lock screen")
    state.setSuspended(.displaysSleeping, true)
    ok(!state.shouldRun, "WallpaperPlaybackState: sharing never overrides display sleep")
    state.setSuspended(.displaysSleeping, false)
    state.setSuspended(.sessionInactive, true)
    ok(!state.shouldRun, "WallpaperPlaybackState: sharing never overrides an inactive login session")
    state.setSuspended(.sessionInactive, false)
    state.isServingScreenSaver = false
    ok(!state.shouldRun, "WallpaperPlaybackState: expired consumers restore ordinary lock and saver suspension")
}
