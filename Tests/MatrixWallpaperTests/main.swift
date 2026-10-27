import AppKit
import ScreenSaver

/// Counts failed AppKit checks without requiring XCTest or Xcode.
var failures = 0

/// Reports one self-check result and records failures.
func check(_ condition: Bool, _ description: String) {
    print("\(condition ? "ok" : "not ok") - \(description)")
    if !condition { failures += 1 }
}

/// Captures the actual native view output, without advancing it from the test.
func pixels(of view: NSView) -> Data? {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let bytes = bitmap.bitmapData else { return nil }
    return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
}

/// Pumps AppKit's run loop so only the framework's animation scheduling drives frames.
func wait(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
if CommandLine.arguments.contains("--consumer-host") {
    consumerHostTests()
    exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
}
if CommandLine.arguments.contains("--composition-benchmark") {
    compositionBenchmark()
    exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
}
if CommandLine.arguments.contains("--composition-tests") {
    sharedCompositionTests()
    exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
}
if CommandLine.arguments.contains("--gpu-composition-tests") {
    gpuCompositionFeasibilityTests()
    exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
}
if CommandLine.arguments.contains("--gpu-composition-benchmark") {
    gpuCompositionFeasibilityTests(benchmark: true)
    exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
}
guard let screen = NSScreen.main,
      let saver = MatrixScreenSaverView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), isPreview: false) else {
    fatalError("Wallpaper self-check requires a logged-in graphical macOS session")
}
let window = DesktopWindow(screen: screen, saverView: saver)
check(window.frame == screen.frame, "window fills the entire display")
check(window.level.rawValue == Int(CGWindowLevelForKey(.desktopWindow)), "window uses the desktop level")
check(window.ignoresMouseEvents && !window.canBecomeKey && !window.canBecomeMain,
      "desktop window rejects mouse and keyboard focus")
check(window.collectionBehavior.contains([.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]),
      "window joins desktop Spaces without joining fullscreen apps or window cycling")
check(!saver.isPreview, "host uses the full-quality saver mode")
let previousApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
window.orderBack(nil)
saver.startAnimation()
wait(0.5)
check(window.isVisible && !window.isKeyWindow && !window.isMainWindow, "wallpaper is visible without focus")
check(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp, "showing wallpaper does not activate its app")
let initial = pixels(of: saver)
wait(2)
let advanced = pixels(of: saver)
check(initial != nil && advanced != nil && initial != advanced, "native animation advances without a second timer")
saver.stopAnimation()
let stopped = pixels(of: saver)
wait(0.3)
check(stopped != nil && pixels(of: saver) == stopped, "native animation stays stopped")
window.close()
check(!window.isVisible, "closing removes the desktop window")
sharedSaverTests()
sharedCompositionTests()
wallpaperAppTests()
desktopWallpaperTests()
loginItemTests()
exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
