import Foundation

/// Tests for ScreenSyncCoordinator restart barrier resolution logic.
func screenSyncCoordinatorTests() {
    do {
        let coordinator = ScreenSyncCoordinator.shared
        coordinator._resetForTesting()
        let first = NSObject(), second = NSObject()
        let firstID = ObjectIdentifier(first), secondID = ObjectIdentifier(second)
        coordinator.register(firstID, expectedCount: 2, startupDelay: 0)
        ok(coordinator.resolvedStartTime() == nil, "ScreenSyncCoordinator: fast startup still waits for every display")
        let before = Date.timeIntervalSinceReferenceDate
        coordinator.register(secondID, expectedCount: 2, startupDelay: 0)
        let start = coordinator.resolvedStartTime()!
        ok(start >= before && start <= Date.timeIntervalSinceReferenceDate && coordinator.startContentTime == start &&
           coordinator.resolvedStartTime() == start,
           "ScreenSyncCoordinator: fast startup shares one immediate playback and content anchor")
        coordinator.requestRestart(firstID)
        coordinator.requestRestart(secondID)
        ok(coordinator.resolvedRestartTime()! > Date.timeIntervalSinceReferenceDate + 0.9,
           "ScreenSyncCoordinator: fast initial startup preserves the rain restart delay")
        coordinator.unregister(firstID)
        coordinator.unregister(secondID)
        coordinator.register(firstID, expectedCount: 1)
        ok(coordinator.resolvedStartTime()! > Date.timeIntervalSinceReferenceDate + 0.9,
           "ScreenSyncCoordinator: a new default session retains its one-second startup delay")
        coordinator._resetForTesting()
        coordinator.register(firstID, expectedCount: 2, startupDelay: 0)
        // Shift the existing clock rather than waiting 20 seconds for the timeout fallback.
        coordinator.shiftTimeline(by: -ScreenSyncCoordinator.registrationTimeout - 1)
        let timeoutBefore = Date.timeIntervalSinceReferenceDate
        let timeoutStart = coordinator.resolvedStartTime()!
        ok(timeoutStart >= timeoutBefore && timeoutStart <= Date.timeIntervalSinceReferenceDate,
           "ScreenSyncCoordinator: registration timeout uses the session's fast startup delay")
        coordinator._resetForTesting()
        coordinator.register(firstID, expectedCount: 1)
        ok(coordinator.resolvedStartTime()! > Date.timeIntervalSinceReferenceDate + 0.9,
           "ScreenSyncCoordinator: testing reset restores the default startup delay")
        coordinator.unregister(firstID)
    }
    do {
        let coordinator = ScreenSyncCoordinator.shared
        coordinator._resetForTesting()
        let native = NSObject(), shared = NSObject()
        coordinator.register(ObjectIdentifier(native), expectedCount: 2)
        coordinator.excludeFromSynchronization(ObjectIdentifier(shared))
        ok(coordinator.registeredCount == 1 && coordinator.resolvedStartTime() != nil,
           "ScreenSyncCoordinator: shared consumers do not delay a remaining native display")
        coordinator.unregister(ObjectIdentifier(native))
        coordinator.register(ObjectIdentifier(native), expectedCount: 2)
        ok(coordinator.resolvedStartTime() != nil,
           "ScreenSyncCoordinator: known shared consumers remain excluded when native startup begins later")
        coordinator.unregister(ObjectIdentifier(native))
        coordinator.unregister(ObjectIdentifier(shared))
        coordinator.register(ObjectIdentifier(native), expectedCount: 2)
        ok(coordinator.resolvedStartTime() == nil,
           "ScreenSyncCoordinator: stopped shared consumers do not leak into the next session")
        coordinator.unregister(ObjectIdentifier(native))
    }
    do {
        let coordinator = ScreenSyncCoordinator.shared
        coordinator._resetForTesting()
        let participant = NSObject()
        let id = ObjectIdentifier(participant)
        coordinator.register(id, expectedCount: 1)
        coordinator.requestRestart(id)
        coordinator.requestPhaseAdvance(id)
        let start = coordinator.resolvedStartTime()!
        let restart = coordinator.resolvedRestartTime()!
        let phase = coordinator.resolvedPhaseAdvanceTime()!
        coordinator.shiftTimeline(by: 3600)
        ok(coordinator.resolvedStartTime() == start + 3600 && coordinator.resolvedRestartTime() == restart + 3600 && coordinator.resolvedPhaseAdvanceTime() == phase + 3600,
           "ScreenSyncCoordinator: suspension shifts all shared anchors without losing participants")
        ok(coordinator.registeredCount == 1, "ScreenSyncCoordinator: suspension preserves barrier membership")
        ok(coordinator.startContentTime == start && coordinator.restartContentTime == restart,
           "ScreenSyncCoordinator: pause leaves session content timestamps immutable")
        coordinator.unregister(id)
    }
    // Test 1: All displays requesting → immediate resolution
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject(), obj3 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)
        let id3 = ObjectIdentifier(obj3)

        coordinator.register(id1, expectedCount: 3)
        coordinator.register(id2, expectedCount: 3)
        coordinator.register(id3, expectedCount: 3)

        coordinator.requestRestart(id1)
        coordinator.requestRestart(id2)
        var resolved = coordinator.resolvedRestartTime()
        ok(resolved == nil, "ScreenSyncCoordinator: restart not resolved with 2/3 requesting")

        coordinator.requestRestart(id3)
        resolved = coordinator.resolvedRestartTime()
        ok(resolved != nil, "ScreenSyncCoordinator: restart resolved when all 3 request")

        let now = Date.timeIntervalSinceReferenceDate
        ok(resolved! > now && resolved! <= now + 2.0, "ScreenSyncCoordinator: startDelay applied to restart")
    }

    // Test 2: Straggler unregister → remaining displays resolve
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject(), obj3 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)
        let id3 = ObjectIdentifier(obj3)

        coordinator.register(id1, expectedCount: 3)
        coordinator.register(id2, expectedCount: 3)
        coordinator.register(id3, expectedCount: 3)

        coordinator.requestRestart(id1)
        coordinator.requestRestart(id2)
        var resolved = coordinator.resolvedRestartTime()
        ok(resolved == nil, "ScreenSyncCoordinator: waiting for id3 before unregister")

        coordinator.unregister(id3)
        resolved = coordinator.resolvedRestartTime()
        ok(resolved != nil, "ScreenSyncCoordinator: resolves immediately after straggler unregisters")
        ok(coordinator.registeredCount == 2, "ScreenSyncCoordinator: registered count dropped to 2")
    }

    // Test 3: finishRestart re-arms the barrier
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)

        coordinator.register(id1, expectedCount: 2)
        coordinator.register(id2, expectedCount: 2)

        coordinator.requestRestart(id1)
        coordinator.requestRestart(id2)
        var resolved = coordinator.resolvedRestartTime()
        ok(resolved != nil, "ScreenSyncCoordinator: first cycle resolves")

        coordinator.finishRestart(id1)
        coordinator.finishRestart(id2)

        coordinator.requestRestart(id1)
        coordinator.requestRestart(id2)
        resolved = coordinator.resolvedRestartTime()
        ok(resolved != nil, "ScreenSyncCoordinator: second cycle resolves (barrier re-armed)")
    }

    // Test 4: Partial finish behavior
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)

        coordinator.register(id1, expectedCount: 2)
        coordinator.register(id2, expectedCount: 2)

        coordinator.requestRestart(id1)
        coordinator.requestRestart(id2)
        var resolved = coordinator.resolvedRestartTime()
        ok(resolved != nil, "ScreenSyncCoordinator: resolved with both requesting")

        coordinator.finishRestart(id1)
        resolved = coordinator.resolvedRestartTime()
        ok(resolved != nil, "ScreenSyncCoordinator: still resolved while id2 unfinished")

        coordinator.finishRestart(id2)
        resolved = coordinator.resolvedRestartTime()
        ok(resolved == nil, "ScreenSyncCoordinator: clears after all finish")
    }

    // Test 5: Unregister during pending restart
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)

        coordinator.register(id1, expectedCount: 2)
        coordinator.register(id2, expectedCount: 2)

        coordinator.requestRestart(id1)
        var resolved = coordinator.resolvedRestartTime()
        ok(resolved == nil, "ScreenSyncCoordinator: waiting for id2")

        coordinator.unregister(id2)
        resolved = coordinator.resolvedRestartTime()
        ok(resolved != nil, "ScreenSyncCoordinator: unregister of sole pending requester allows resolution")
    }

    // Test 6: Startup barrier fix — delayed registration with higher expected count
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject(), obj3 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)
        let id3 = ObjectIdentifier(obj3)

        // First screen registers with low count (OS hasn't discovered all displays yet)
        coordinator.register(id1, expectedCount: 2)
        var startTime = coordinator.resolvedStartTime()
        ok(startTime == nil, "ScreenSyncCoordinator: startup not resolved with only 1/2 registered")

        // Second screen registers with higher count (OS discovers more displays)
        coordinator.register(id2, expectedCount: 3)
        startTime = coordinator.resolvedStartTime()
        ok(startTime == nil, "ScreenSyncCoordinator: startup not resolved with 2/3 registered even though maxExpected=3")

        // Third screen completes the registration
        coordinator.register(id3, expectedCount: 3)
        startTime = coordinator.resolvedStartTime()
        ok(startTime != nil, "ScreenSyncCoordinator: startup resolves when maxExpected count is reached")
    }

    // Test 7: Startup barrier fix — uses maxExpectedCount not first registration count
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject(), obj3 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)
        let id3 = ObjectIdentifier(obj3)

        // First screen sees 2 displays, but actually there are 3 (delayed discovery)
        coordinator.register(id1, expectedCount: 2)
        var startTime = coordinator.resolvedStartTime()
        ok(startTime == nil, "ScreenSyncCoordinator: startup waiting (1 < 2)")

        // Second screen discovers all 3 displays
        coordinator.register(id2, expectedCount: 3)
        startTime = coordinator.resolvedStartTime()
        ok(startTime == nil, "ScreenSyncCoordinator: startup waits for maxExpected (2 < 3 after second registration)")

        // Third screen confirms 3 displays
        coordinator.register(id3, expectedCount: 3)
        startTime = coordinator.resolvedStartTime()
        ok(startTime != nil, "ScreenSyncCoordinator: startup resolves when all maxExpected registers (3 >= 3)")
    }

    // Test 8: Phase advance barrier — all displays requesting → immediate resolution
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject(), obj3 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)
        let id3 = ObjectIdentifier(obj3)

        coordinator.register(id1, expectedCount: 3)
        coordinator.register(id2, expectedCount: 3)
        coordinator.register(id3, expectedCount: 3)

        coordinator.requestPhaseAdvance(id1)
        coordinator.requestPhaseAdvance(id2)
        var resolved = coordinator.resolvedPhaseAdvanceTime()
        ok(resolved == nil, "ScreenSyncCoordinator: phase advance not resolved with 2/3 requesting")

        coordinator.requestPhaseAdvance(id3)
        resolved = coordinator.resolvedPhaseAdvanceTime()
        ok(resolved != nil, "ScreenSyncCoordinator: phase advance resolved when all 3 request")

        let now = Date.timeIntervalSinceReferenceDate
        ok(resolved! >= now - 0.1 && resolved! <= now + 0.1, "ScreenSyncCoordinator: phaseAdvanceDelay=0 applied (within 0.1s)")
    }

    // Test 9: Phase advance barrier — straggler unregister → remaining displays resolve
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject(), obj3 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)
        let id3 = ObjectIdentifier(obj3)

        coordinator.register(id1, expectedCount: 3)
        coordinator.register(id2, expectedCount: 3)
        coordinator.register(id3, expectedCount: 3)

        coordinator.requestPhaseAdvance(id1)
        coordinator.requestPhaseAdvance(id2)
        var resolved = coordinator.resolvedPhaseAdvanceTime()
        ok(resolved == nil, "ScreenSyncCoordinator: waiting for id3 before unregister")

        coordinator.unregister(id3)
        resolved = coordinator.resolvedPhaseAdvanceTime()
        ok(resolved != nil, "ScreenSyncCoordinator: phase advance resolves immediately after straggler unregisters")
        ok(coordinator.registeredCount == 2, "ScreenSyncCoordinator: registered count dropped to 2")
    }

    // Test 10: Phase advance barrier — finishPhaseAdvance re-arms the barrier
    do {
        ScreenSyncCoordinator.shared._resetForTesting()
        let coordinator = ScreenSyncCoordinator.shared
        let obj1 = NSObject(), obj2 = NSObject()
        let id1 = ObjectIdentifier(obj1)
        let id2 = ObjectIdentifier(obj2)

        coordinator.register(id1, expectedCount: 2)
        coordinator.register(id2, expectedCount: 2)

        coordinator.requestPhaseAdvance(id1)
        coordinator.requestPhaseAdvance(id2)
        var resolved = coordinator.resolvedPhaseAdvanceTime()
        ok(resolved != nil, "ScreenSyncCoordinator: first phase advance cycle resolves")

        coordinator.finishPhaseAdvance(id1)
        coordinator.finishPhaseAdvance(id2)

        coordinator.requestPhaseAdvance(id1)
        coordinator.requestPhaseAdvance(id2)
        resolved = coordinator.resolvedPhaseAdvanceTime()
        ok(resolved != nil, "ScreenSyncCoordinator: second phase advance cycle resolves (barrier re-armed)")
    }
}
