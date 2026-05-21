import Foundation

/// The drawing state snapshot the view uses to render the current Neo message frame.
struct NeoMessageRenderState {
    let currentLine: String?
    let visibleCharCount: Int
    let cursorVisible: Bool
}

/// Time-driven state machine for the Neo message intro scene.
struct NeoMessageScene {
    enum Phase: Equatable {
        case typing
        case pauseAfterLine
        case blankBetweenLines
        case done
    }

    static let defaultLines: [String] = [
        "Wake up, Neo...",
        "The Matrix has you.",
        "Follow the white rabbit.",
        "Knock, knock, Neo.",
    ]

    static let charsPerSecond: Double = 40.0
    static let cursorBlinkInterval: TimeInterval = 0.5

    private struct LineSchedule {
        let charTimings: [TimeInterval]
        let lineStart: TimeInterval
        let typingEnd: TimeInterval
        let pauseEnd: TimeInterval
        let blankEnd: TimeInterval
    }

    private(set) var phase: Phase = .done
    private(set) var lineIndex: Int = 0
    private(set) var charIndex: Int = 0
    private(set) var cursorVisible: Bool = true
    private var startTime: TimeInterval = 0
    private var schedule: [LineSchedule] = []
    private var lines: [String] = Self.defaultLines

    /// Actual wall-clock duration of the scene in seconds (time when last pause ends).
    /// Shorter when `speedFactor > 1` because the typing intervals are pre-scaled.
    /// The number scene anchors its start after this duration.
    private(set) var scheduledDuration: TimeInterval = 60.0

    mutating func reset(startTime: TimeInterval, seed: UInt64, lines: [String] = Self.defaultLines, speedFactor: Double = 1.0) {
        self.startTime = startTime
        self.lines = lines.isEmpty ? Self.defaultLines : lines
        var rng = Xorshift64(seed: seed)
        schedule = []

        let typingInterval = 1.0 / Self.charsPerSecond / max(speedFactor, 1e-6)
        var t: TimeInterval = 0
        for (index, line) in self.lines.enumerated() {
            let isLast = index == self.lines.count - 1
            let chars = NativeMatrixRenderer.naturalTypingTimings(
                for: line,
                baseInterval: typingInterval,
                rng: &rng
            )
            let lineStart = t
            let typingEnd = t + (chars.last ?? 0)
            // pauseDuration min (2 s) > blankDuration max (1.5 s) — guaranteed by range choice.
            let pauseDuration = isLast
                ? Double.random(in: 3...5, using: &rng)
                : Double.random(in: 2...4, using: &rng)
            let blankDuration = isLast ? 0.0 : Double.random(in: 0.5...1.5, using: &rng)
            let pauseEnd = typingEnd + pauseDuration
            let blankEnd = pauseEnd + blankDuration
            schedule.append(LineSchedule(
                charTimings: chars,
                lineStart: lineStart,
                typingEnd: typingEnd,
                pauseEnd: pauseEnd,
                blankEnd: blankEnd
            ))
            t = blankEnd
        }

        scheduledDuration = schedule.last?.pauseEnd ?? 60.0
        phase = .typing
        lineIndex = 0
        charIndex = 0
        cursorVisible = true
    }

    mutating func advance(now: TimeInterval) {
        guard !schedule.isEmpty else { return }

        let sceneTime = now - startTime
        cursorVisible = Int(sceneTime / Self.cursorBlinkInterval) % 2 == 0
        updateState(sceneTime: sceneTime)
    }

    private mutating func updateState(sceneTime: TimeInterval) {
        // Before the scene begins: show a blinking cursor at the start position.
        guard sceneTime >= 0 else {
            phase = .typing
            lineIndex = 0
            charIndex = 0
            return
        }

        for (index, timing) in schedule.enumerated() {
            let isLast = index == schedule.count - 1
            if sceneTime < timing.typingEnd {
                let lineElapsed = sceneTime - timing.lineStart
                lineIndex = index
                charIndex = timing.charTimings.prefix(while: { $0 <= lineElapsed }).count
                phase = .typing
                return
            } else if sceneTime < timing.pauseEnd {
                lineIndex = index
                charIndex = timing.charTimings.count
                phase = .pauseAfterLine
                return
            } else if !isLast && sceneTime < timing.blankEnd {
                lineIndex = index
                phase = .blankBetweenLines
                // Blink relative to the blank start so the cursor is always visible
                // at the beginning of each blank period (avoids the cursor starting
                // in its hidden half-cycle).
                let blankElapsed = sceneTime - timing.pauseEnd
                cursorVisible = Int(blankElapsed / Self.cursorBlinkInterval) % 2 == 0
                return
            } else if isLast {
                phase = .done
                return
            }
        }
        phase = .done
    }

    var renderState: NeoMessageRenderState {
        switch phase {
        case .blankBetweenLines:
            return NeoMessageRenderState(currentLine: nil, visibleCharCount: 0, cursorVisible: cursorVisible)
        case .done:
            return NeoMessageRenderState(currentLine: nil, visibleCharCount: 0, cursorVisible: false)
        case .typing, .pauseAfterLine:
            return NeoMessageRenderState(
                currentLine: lines[lineIndex],
                visibleCharCount: charIndex,
                cursorVisible: cursorVisible
            )
        }
    }

}
