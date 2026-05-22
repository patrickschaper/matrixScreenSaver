import Foundation

/// Coordinates multi-screen startup so every screen saver instance begins
/// its scene sequence at the exact same moment.
///
/// `ScreenSaverEngine` creates one `MatrixScreenSaverView` per attached
/// display. Without coordination, instances that start at different moments
/// may compute different scene start times, producing misaligned scenes.
///
/// Each view calls ``register(_:expectedCount:)`` during `startAnimation()`
/// and polls ``resolvedStartTime()`` each frame. Once all expected instances
/// have registered — or the ``registrationTimeout`` elapses — every instance
/// receives the same start time and begins simultaneously.
final class ScreenSyncCoordinator {
    static let shared = ScreenSyncCoordinator()

    /// Maximum seconds to wait for all instances before starting anyway.
    static let registrationTimeout: TimeInterval = 20.0

    /// Seconds after all instances register (or timeout) before scenes begin.
    static let startDelay: TimeInterval = 1.0

    private var expectedCount = 0
    private var registeredIDs: Set<ObjectIdentifier> = []
    private var firstRegistrationTime: TimeInterval = 0
    private var resolvedTime: TimeInterval?

    /// The number of currently registered instances.
    var registeredCount: Int { registeredIDs.count }

    /// The number of expected instances (set on first registration).
    var expected: Int { expectedCount }

    /// Registers a screen saver instance and records the expected display count.
    ///
    /// Call once per instance from `startAnimation()`. On the first call of a
    /// session the coordinator snapshots `expectedCount` and starts the timeout
    /// clock. Subsequent calls add to the registered set.
    ///
    /// - Parameters:
    ///   - id: Unique identity of the registering view (use `ObjectIdentifier`).
    ///   - expectedCount: Total number of displays (typically `NSScreen.screens.count`).
    func register(_ id: ObjectIdentifier, expectedCount: Int) {
        if registeredIDs.isEmpty {
            self.expectedCount = max(expectedCount, 1)
            firstRegistrationTime = Date.timeIntervalSinceReferenceDate
            resolvedTime = nil
        }
        registeredIDs.insert(id)

        if registeredIDs.count >= self.expectedCount && resolvedTime == nil {
            resolvedTime = Date.timeIntervalSinceReferenceDate + Self.startDelay
        }
    }

    /// Removes an instance from the coordinator.
    ///
    /// When the last instance unregisters the coordinator resets, ready for
    /// the next screen saver activation.
    ///
    /// - Parameter id: Unique identity of the unregistering view.
    func unregister(_ id: ObjectIdentifier) {
        registeredIDs.remove(id)
        if registeredIDs.isEmpty {
            resolvedTime = nil
            expectedCount = 0
        }
    }

    /// Returns the shared scene start time once all instances are ready, or
    /// after ``registrationTimeout`` elapses. Returns `nil` while still
    /// waiting for instances.
    func resolvedStartTime() -> TimeInterval? {
        if let time = resolvedTime {
            return time
        }
        guard !registeredIDs.isEmpty else { return nil }

        let elapsed = Date.timeIntervalSinceReferenceDate - firstRegistrationTime
        if elapsed >= Self.registrationTimeout {
            let time = Date.timeIntervalSinceReferenceDate + Self.startDelay
            resolvedTime = time
            return time
        }
        return nil
    }
}
