import Foundation

/// The drawing state snapshot the view uses to render the current Neo message frame.
struct NeoMessageRenderState {
    /// The current line text, or nil when the screen is intentionally blank.
    let currentLine: String?
    /// Number of characters of `currentLine` to display.
    let visibleCharCount: Int
    /// Whether the blinking cursor should be drawn after the last visible character.
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

    static let lines: [String] = [
        "Wake up, Neo...",
        "The Matrix has you.",
        "Follow the white rabbit.",
        "Knock, knock, Neo.",
    ]

    static let charsPerSecond: Double = 10.0
    static let pauseAfterLineDuration: TimeInterval = 2.0
    static let blankBetweenLinesDuration: TimeInterval = 1.0
    static let cursorBlinkInterval: TimeInterval = 0.5

    private(set) var phase: Phase = .typing
    private(set) var lineIndex: Int = 0
    private(set) var charIndex: Int = 0
    private(set) var cursorVisible: Bool = true
    private var phaseStartTime: TimeInterval = 0
    private var lastCursorToggle: TimeInterval = 0

    mutating func reset(startTime: TimeInterval) {
        phase = .typing
        lineIndex = 0
        charIndex = 0
        cursorVisible = true
        phaseStartTime = startTime
        lastCursorToggle = startTime
    }

    mutating func advance(now: TimeInterval) {
        guard phase != .done else { return }

        if now - lastCursorToggle >= Self.cursorBlinkInterval {
            cursorVisible.toggle()
            lastCursorToggle = now
        }

        switch phase {
        case .typing:
            let elapsed = now - phaseStartTime
            let targetCharIndex = Int(elapsed * Self.charsPerSecond)
            let lineLength = Self.lines[lineIndex].count
            charIndex = min(targetCharIndex, lineLength)
            if charIndex >= lineLength {
                phase = .pauseAfterLine
                phaseStartTime = now
            }
        case .pauseAfterLine:
            if now - phaseStartTime >= Self.pauseAfterLineDuration {
                if lineIndex == Self.lines.count - 1 {
                    phase = .done
                } else {
                    phase = .blankBetweenLines
                    phaseStartTime = now
                }
            }
        case .blankBetweenLines:
            if now - phaseStartTime >= Self.blankBetweenLinesDuration {
                lineIndex += 1
                charIndex = 0
                phase = .typing
                phaseStartTime = now
            }
        case .done:
            break
        }
    }

    var renderState: NeoMessageRenderState {
        switch phase {
        case .blankBetweenLines, .done:
            return NeoMessageRenderState(currentLine: nil, visibleCharCount: 0, cursorVisible: false)
        case .typing, .pauseAfterLine:
            return NeoMessageRenderState(
                currentLine: Self.lines[lineIndex],
                visibleCharCount: charIndex,
                cursorVisible: cursorVisible
            )
        }
    }
}
