import AppKit
import ScreenSaver

/// A passive desktop surface that leaves input and desktop management to macOS.
final class DesktopWindow: NSWindow {
    /// Prevents wallpaper windows from receiving keyboard focus.
    override var canBecomeKey: Bool { false }

    /// Excludes wallpaper windows from the application's main-window role.
    override var canBecomeMain: Bool { false }

    /// Hosts a full-quality saver at the display's full desktop frame.
    ///
    /// - Parameters:
    ///   - screen: Display whose desktop this window covers.
    ///   - saverView: Native saver view, created with preview mode disabled.
    init(screen: NSScreen, saverView: ScreenSaverView) {
        super.init(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        // Explicit global coordinates also cover displays left of or above the primary display.
        setFrame(screen.frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        saverView.autoresizingMask = [.width, .height]
        contentView = saverView
    }
}
