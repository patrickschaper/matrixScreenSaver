import Foundation

/// Keeps explicit playback intent separate from overlapping temporary system conditions.
struct WallpaperPlaybackState {
    /// Independent reasons why rendering must remain suspended.
    enum Suspension: Hashable {
        /// The computer is sleeping.
        case sleeping
        /// The displays are asleep independently of computer sleep.
        case displaysSleeping
        /// Another login session is active.
        case sessionInactive
        /// The screen is locked.
        case locked
        /// The real screen saver is active.
        case screenSaver
    }

    /// Whether the user wants wallpaper playback, even if it cannot run right now.
    var isRequested = true

    /// Manual pause freezes the scene while leaving its desktop surfaces visible.
    var isPaused = false

    /// A recent matching saver request lets the wallpaper own animation while its desktop is hidden.
    var isServingScreenSaver = false

    /// Conditions that have not yet received a matching resume notification.
    private var suspensions: Set<Suspension> = []

    /// Whether animation may run after combining user intent and system state.
    var shouldRun: Bool {
        isRequested && !isPaused && suspensions.allSatisfy { isServingScreenSaver && ($0 == .screenSaver || $0 == .locked) }
    }

    /// Desktop visibility remains separate from rendering for the lock-screen consumer.
    var shouldShowDesktop: Bool { isRequested && suspensions.isEmpty }

    /// Updates one condition idempotently without clearing unrelated conditions.
    ///
    /// - Parameters:
    ///   - reason: System condition reported by the host.
    ///   - suspended: Whether that condition is currently active.
    mutating func setSuspended(_ reason: Suspension, _ suspended: Bool) {
        if suspended { suspensions.insert(reason) } else { suspensions.remove(reason) }
    }
}
