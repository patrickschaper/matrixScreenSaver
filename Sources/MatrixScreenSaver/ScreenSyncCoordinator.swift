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

    /// Maximum seconds to wait for a stuck/hidden display during restart before resolving anyway.
    static let restartSafetyTimeout: TimeInterval = 60.0

    private var expectedCount = 0
    private var maxExpectedCount = 0
    private var registeredIDs: Set<ObjectIdentifier> = []
    private var firstRegistrationTime: TimeInterval = 0
    private var resolvedTime: TimeInterval?

    /// Instances that have requested a rain restart.
    private var restartRequestedIDs: Set<ObjectIdentifier> = []
    /// Resolved time for the next coordinated restart, once all displays are ready.
    private var restartResolvedTime: TimeInterval?
    /// Snapshot of when the first restart request arrived (for timeout fallback).
    private var firstRestartRequestTime: TimeInterval = 0

    /// Instances that have requested a phase advance (scene transition).
    private var phaseAdvanceRequestedIDs: Set<ObjectIdentifier> = []
    /// Resolved time for the phase advance barrier.
    private var phaseAdvanceResolvedTime: TimeInterval?
    /// Snapshot of when the first phase advance request arrived (for timeout).
    private var firstPhaseAdvanceRequestTime: TimeInterval = 0

    /// Maximum seconds to wait for all displays during a phase advance before resolving anyway.
    static let phaseAdvanceTimeout: TimeInterval = 20.0

    /// Delay before phase advance proceeds (0s since timing is pre-computed from shared seed).
    static let phaseAdvanceDelay: TimeInterval = 0.0

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
            self.maxExpectedCount = max(expectedCount, 1)
            firstRegistrationTime = Date.timeIntervalSinceReferenceDate
            resolvedTime = nil
        } else {
            // Update maxExpectedCount if a larger count is seen (handles delayed OS discovery).
            maxExpectedCount = max(maxExpectedCount, expectedCount)
        }
        registeredIDs.insert(id)

        // Try to resolve startup using live registered count vs max expected.
        tryResolveStart()
    }

    /// Removes an instance from the coordinator.
    ///
    /// When the last instance unregisters the coordinator resets, ready for
    /// the next screen saver activation.
    ///
    /// - Parameter id: Unique identity of the unregistering view.
    func unregister(_ id: ObjectIdentifier) {
        registeredIDs.remove(id)
        restartRequestedIDs.remove(id)
        phaseAdvanceRequestedIDs.remove(id)
        if registeredIDs.isEmpty {
            resolvedTime = nil
            restartResolvedTime = nil
            phaseAdvanceResolvedTime = nil
            expectedCount = 0
            maxExpectedCount = 0
        } else {
            // If a straggler detaches during startup, remaining displays must be able to resolve
            // their startup without waiting for it. Check against max expected.
            tryResolveStart()
            // If a straggler detaches during restart, remaining displays must be able to resolve.
            tryResolveRestart()
            // If a straggler detaches during phase advance, remaining displays must be able to resolve.
            tryResolvePhaseAdvance()
        }
    }

    /// Attempts to resolve startup time if all currently-registered displays
    /// have registered.
    ///
    /// Called after each registration and when an instance unregisters,
    /// so the coordinator can resolve as soon as all live displays have registered.
    private func tryResolveStart() {
        guard resolvedTime == nil, !registeredIDs.isEmpty else { return }
        if registeredIDs.count >= maxExpectedCount {
            resolvedTime = Date.timeIntervalSinceReferenceDate + Self.startDelay
        }
    }

    /// Attempts to resolve a restart time if all currently-registered displays
    /// have requested a restart.
    ///
    /// This method is called after each restart request and when an instance unregisters,
    /// so the coordinator can resolve as soon as all live displays have drained.
    private func tryResolveRestart() {
        guard restartResolvedTime == nil, !restartRequestedIDs.isEmpty else { return }
        if restartRequestedIDs.count >= registeredIDs.count {
            restartResolvedTime = Date.timeIntervalSinceReferenceDate + Self.startDelay
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

    /// Requests a coordinated restart for the given instance.
    ///
    /// Call when the renderer's rain has fully drained and needs to cycle.
    /// The coordinator accumulates restart requests from all displays, then
    /// resolves a shared restart time once all have requested or timeout elapses.
    /// Use ``resolvedRestartTime()`` to poll for the resolved time each frame,
    /// and ``finishRestart(_:)`` once the instance has restarted.
    ///
    /// - Parameter id: Unique identity of the instance requesting restart.
    func requestRestart(_ id: ObjectIdentifier) {
        if restartRequestedIDs.isEmpty {
            firstRestartRequestTime = Date.timeIntervalSinceReferenceDate
            restartResolvedTime = nil
        }
        restartRequestedIDs.insert(id)

        // Check if all currently-registered displays have now requested a restart.
        tryResolveRestart()
    }

    /// Returns the shared restart time once all instances have requested
    /// a restart, or after ``restartSafetyTimeout`` elapses. Returns `nil`
    /// while still waiting.
    func resolvedRestartTime() -> TimeInterval? {
        if let time = restartResolvedTime {
            return time
        }
        guard !restartRequestedIDs.isEmpty else { return nil }

        let elapsed = Date.timeIntervalSinceReferenceDate - firstRestartRequestTime
        if elapsed >= Self.restartSafetyTimeout {
            let time = Date.timeIntervalSinceReferenceDate + Self.startDelay
            restartResolvedTime = time
            return time
        }
        return nil
    }

    /// Marks the given instance as having completed its restart.
    ///
    /// Call after the instance has restarted its rain sequence. When the last
    /// instance calls this, the restart barrier clears and is ready for the
    /// next rain cycle.
    ///
    /// - Parameter id: Unique identity of the instance that restarted.
    func finishRestart(_ id: ObjectIdentifier) {
        restartRequestedIDs.remove(id)
        if restartRequestedIDs.isEmpty {
            restartResolvedTime = nil
        }
    }

    /// Requests a coordinated phase advance (scene transition) for the given instance.
    ///
    /// Call when a scene completes and needs to transition to the next scene.
    /// The coordinator accumulates requests from all displays, then resolves a shared
    /// time once all have requested or timeout elapses.
    /// Use ``resolvedPhaseAdvanceTime()`` to poll for the resolved time each frame,
    /// and ``finishPhaseAdvance(_:)`` once the instance has advanced.
    ///
    /// - Parameter id: Unique identity of the instance requesting phase advance.
    func requestPhaseAdvance(_ id: ObjectIdentifier) {
        if phaseAdvanceRequestedIDs.isEmpty {
            firstPhaseAdvanceRequestTime = Date.timeIntervalSinceReferenceDate
            phaseAdvanceResolvedTime = nil
        }
        phaseAdvanceRequestedIDs.insert(id)

        // Check if all currently-registered displays have now requested a phase advance.
        tryResolvePhaseAdvance()
    }

    /// Attempts to resolve phase advance time if all currently-registered displays
    /// have requested a phase advance.
    ///
    /// Called after each phase advance request and when an instance unregisters.
    private func tryResolvePhaseAdvance() {
        guard phaseAdvanceResolvedTime == nil, !phaseAdvanceRequestedIDs.isEmpty else { return }
        if phaseAdvanceRequestedIDs.count >= registeredIDs.count {
            phaseAdvanceResolvedTime = Date.timeIntervalSinceReferenceDate + Self.phaseAdvanceDelay
        }
    }

    /// Returns the shared phase advance time once all instances have requested
    /// a phase advance, or after ``phaseAdvanceTimeout`` elapses. Returns `nil`
    /// while still waiting.
    func resolvedPhaseAdvanceTime() -> TimeInterval? {
        if let time = phaseAdvanceResolvedTime {
            return time
        }
        guard !phaseAdvanceRequestedIDs.isEmpty else { return nil }

        let elapsed = Date.timeIntervalSinceReferenceDate - firstPhaseAdvanceRequestTime
        if elapsed >= Self.phaseAdvanceTimeout {
            let time = Date.timeIntervalSinceReferenceDate + Self.phaseAdvanceDelay
            phaseAdvanceResolvedTime = time
            return time
        }
        return nil
    }

    /// Marks the given instance as having completed its phase advance.
    ///
    /// Call after the instance has transitioned to the next scene. When the last
    /// instance calls this, the phase advance barrier clears and is ready for the
    /// next scene transition.
    ///
    /// - Parameter id: Unique identity of the instance that advanced.
    func finishPhaseAdvance(_ id: ObjectIdentifier) {
        phaseAdvanceRequestedIDs.remove(id)
        if phaseAdvanceRequestedIDs.isEmpty {
            phaseAdvanceResolvedTime = nil
        }
    }

    /// Resets the coordinator to a clean state (for testing only).
    func _resetForTesting() {
        expectedCount = 0
        maxExpectedCount = 0
        registeredIDs = []
        firstRegistrationTime = 0
        resolvedTime = nil
        restartRequestedIDs = []
        restartResolvedTime = nil
        firstRestartRequestTime = 0
        phaseAdvanceRequestedIDs = []
        phaseAdvanceResolvedTime = nil
        firstPhaseAdvanceRequestTime = 0
    }
}
