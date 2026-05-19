import Foundation

final class NativeMatrixRenderer {
    struct Configuration: Equatable {
        var neoMessageSceneEnabled = true
        var neoMessageSpeedFactor = 1.0
        var numberSceneEnabled = true
        var twinkleEnabled = true
        var diffuseEnabled = true
        var rainDensity = 1.0
        var frameRate = 25.0
        var errorRate = 1.0
        var characters = ""
        var neoMessageLines: [String] = NeoMessageScene.defaultLines
        /// When true the 10-second multi-screen sync delay is skipped so scenes
        /// start within one second of launch. Set for preview contexts where
        /// cross-display alignment is unnecessary.
        var skipSyncDelay = false

        /// Clamps runtime configuration values to the supported renderer ranges.
        func sanitized() -> Configuration {
            Configuration(
                neoMessageSceneEnabled: neoMessageSceneEnabled,
                neoMessageSpeedFactor: max(neoMessageSpeedFactor, MatrixScreenSaverOptions.minimumNeoMessageSpeedFactor),
                numberSceneEnabled: numberSceneEnabled,
                twinkleEnabled: twinkleEnabled,
                diffuseEnabled: diffuseEnabled,
                rainDensity: max(rainDensity, MatrixScreenSaverOptions.minimumRainDensity),
                frameRate: min(max(frameRate, MatrixScreenSaverOptions.minimumFrameRate), MatrixScreenSaverOptions.maximumFrameRate),
                errorRate: max(errorRate, MatrixScreenSaverOptions.minimumErrorRate),
                characters: characters,
                neoMessageLines: neoMessageLines.isEmpty ? NeoMessageScene.defaultLines : neoMessageLines,
                skipSyncDelay: skipSyncDelay
            )
        }
    }

    struct RenderCell: Equatable {
        var scalar: UnicodeScalar = Self.blankScalar
        var foregroundLevel: Int = 0
        var backgroundLevel: Int = 0
        var bold = false

        static let blankScalar = UnicodeScalar(" ")

        var hasForeground: Bool {
            scalar != Self.blankScalar && foregroundLevel > 0
        }

        var hasBackground: Bool {
            backgroundLevel > 0
        }

        var isVisible: Bool {
            hasForeground
        }

        var isRenderable: Bool {
            hasForeground || hasBackground
        }
    }

    private struct LayerCell {
        var scalar: UnicodeScalar = RenderCell.blankScalar
        var birth = 0
        var power = 0.0
        var decay = NativeMatrixRenderer.baseDecay
        var flags: UInt32 = 0
        var stage = 0.0
        var currentPower = 0.0

        var isBlank: Bool {
            scalar == RenderCell.blankScalar
        }
    }

    private struct RainThread {
        var x: Int
        var y: Int
        var age: Int
        var speed: Int
        var power: Double
        var decay: Int
    }

    private enum Scene {
        case neoMessage
        case numberIntro
        case rainForever
    }

    private struct Layer {
        var columns = 0
        var rows = 0
        var content: [LayerCell] = []
        var threads: [RainThread] = []

        /// Resizes the layer storage to the active terminal grid.
        mutating func resize(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
            content = Array(repeating: LayerCell(), count: columns * rows)
            threads.removeAll(keepingCapacity: false)
        }

        /// Clears all layer content and active rain threads.
        mutating func clear() {
            content = Array(repeating: LayerCell(), count: columns * rows)
            threads.removeAll(keepingCapacity: false)
        }

        subscript(row: Int, column: Int) -> LayerCell {
            get { content[(row * columns) + column] }
            set { content[(row * columns) + column] = newValue }
        }

        /// Adds a newly spawned rain thread to the layer.
        mutating func addThread(_ thread: RainThread) {
            threads.append(thread)
        }

        /// Advances each rain thread and stamps newly spawned glyphs into the layer.
        mutating func stepThreads(now: Int, glyphProvider: () -> UnicodeScalar) {
            var writeIndex = 0
            var readIndex = 0
            while readIndex < threads.count {
                let thread = threads[readIndex]
                if thread.y >= 0 && thread.y < rows {
                    threads[writeIndex] = thread
                    writeIndex += 1
                }
                readIndex += 1
            }
            if writeIndex < threads.count {
                threads.removeLast(threads.count - writeIndex)
            }

            var index = 0
            while index < threads.count {
                if threads[index].age % threads[index].speed == 0 {
                    let x = threads[index].x % columns
                    let y = threads[index].y % rows
                    var cell = self[y, x]
                    cell.birth = now
                    cell.power = threads[index].power
                    cell.decay = threads[index].decay
                    cell.flags = 0
                    cell.scalar = glyphProvider()
                    self[y, x] = cell
                    threads[index].y += 1
                }
                threads[index].age += 1
                index += 1
            }
        }

        /// Updates per-cell decay state and optional glyph corruption for the frame.
        mutating func resolveLevels(now: Int, errorRateModulo: Int, glyphProvider: () -> UnicodeScalar) {
            guard columns > 0, rows > 0 else {
                return
            }

            var index = 0
            while index < content.count {
                guard !content[index].isBlank else {
                    index += 1
                    continue
                }

                let age = now - content[index].birth
                content[index].stage = 1.0 - (Double(age) / Double(content[index].decay))
                if content[index].stage < 0.0 {
                    content[index].scalar = RenderCell.blankScalar
                    index += 1
                    continue
                }

                content[index].currentPower = content[index].power * content[index].stage
                if errorRateModulo > 0 && Int.random(in: 0..<errorRateModulo) == 0 {
                    content[index].scalar = glyphProvider()
                }
                index += 1
            }
        }
    }

    private static let referenceFrameRate = 25.0
    private static let baseDecay = 100
    private static let defaultTwinkle = 0.2
    private static let baseSpeedTable = [2, 2, 2, 2, 3, 3, 6, 6, 6, 7, 7, 8, 8, 8]
    private static let baseErrorRateModulo = 20.0
    private static let numberIntroCursorBlinkPeriod: TimeInterval = 0.5   // matches NeoMessageScene
    private static let numberIntroCursorBlinkCount = 2                    // 4 half-periods × 0.5 s ≈ 2 s
    private static let numberIntroTypingInterval: TimeInterval = 0.036
    private static let rainDuration: TimeInterval = 90.0   // how long rain runs before restarting
    private static let numberIntroRainFrames = 160
    private static let numberIntroBlackoutInterval: TimeInterval = 1.0
    private static let numberIntroBlackoutRounds = 10
    private static let numberIntroMargin = 2
    private static let maxBufferedSimulationSteps = 2.0
    private static let maxSimulationStepsPerTick = 2
    private static let disableBoldFlag: UInt32 = 0x1
    private static let blankRenderCell = RenderCell()
    private static let defaultGlyphPool: [UnicodeScalar] = {
        var glyphs = Array("0123456789".unicodeScalars)
        glyphs.append(contentsOf: (0..<46).compactMap { UnicodeScalar(0xFF70 + $0) })
        glyphs.append(contentsOf: "<>*+.:=_|".unicodeScalars)
        // Printable ASCII for terminal text lines
        glyphs.append(contentsOf: (0x20..<0x7F).compactMap { UnicodeScalar($0) })
        // Block cursor used in number intro
        glyphs.append(UnicodeScalar(0x2588)!)
        return glyphs
    }()
    private static let palette = makePalette()

    /// Returns the glyph pool for the given characters string, deduplicating and falling back to the default pool when empty.
    private static func resolveGlyphPool(characters: String) -> [UnicodeScalar] {
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultGlyphPool
        }
        var seen = Set<UnicodeScalar>()
        var pool = [UnicodeScalar]()
        for scalar in trimmed.unicodeScalars {
            guard !scalar.properties.isDiacritic,
                  !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  !CharacterSet.controlCharacters.contains(scalar) else { continue }
            if seen.insert(scalar).inserted {
                pool.append(scalar)
            }
        }
        return pool.isEmpty ? defaultGlyphPool : pool
    }

    /// The content margin (in cells) used for the text row and columns in number/neo scenes.
    static var contentMargin: Int { numberIntroMargin }

    private(set) var columns = 0
    private(set) var rows = 0
    private(set) var levelColors = NativeMatrixRenderer.palette

    private var configuration = Configuration()
    private var activeGlyphPool: [UnicodeScalar] = NativeMatrixRenderer.defaultGlyphPool

    var supportedScalars: [UnicodeScalar] {
        let defaultSet = Set(Self.defaultGlyphPool)
        let extra = activeGlyphPool.filter { !defaultSet.contains($0) }
        return extra.isEmpty ? Self.defaultGlyphPool : Self.defaultGlyphPool + extra
    }

    private var neoScene = NeoMessageScene()
    private var layers = [Layer(), Layer(), Layer()]
    private var renderCells: [RenderCell] = []
    private var stagingRenderCells: [RenderCell] = []
    private var diffuseLevels: [Double] = []
    private var visibleCountByRow: [Int] = []
    private var dirtyRows: [Bool] = []
    private var dirtyRowCount = 0
    private var lastUpdateTime = Date.timeIntervalSinceReferenceDate
    private var pendingSimulationSteps = 0.0
    private var running = false
    private var now = 100
    private var frameIndex = 0
    private var activeScene: Scene = .numberIntro
    private enum NumberIntroPhase {
        case cursorBlink, typingFirstLine, pauseAfterFirst, secondLine, pauseAfterSecond, rain
    }

    private struct NumberIntroSchedule {
        var typingText: String = ""
        var cursorBlinkEnd: TimeInterval = 1.8
        var charTimings: [TimeInterval] = []
        var typingEnd: TimeInterval = 3.8
        var pause1Duration: TimeInterval = 2.0
        var pause1End: TimeInterval = 5.8
        var pause2Duration: TimeInterval = 2.0
        var rainStart: TimeInterval = 7.8
        var blackoutRounds: [[Int]] = []
    }

    private var numberIntroPhase: NumberIntroPhase = .cursorBlink
    private var numberIntroPhaseStart: TimeInterval = 0
    private var numberIntroTypingText = ""
    private var numberIntroTypedCount = 0
    private var numberIntroCharTimings: [TimeInterval] = []
    private var numberIntroCursorVisible = false
    private var numberIntroRainFrame = 0
    private var sceneStartTime: TimeInterval = 0   // 5-second-quantised anchor — shared across displays
    private var sceneSeed: UInt64 = 0             // seed derived from sceneStartTime
    private var numberSceneRNG: Xorshift64 = Xorshift64(seed: 1)
    private var rainRNG: Xorshift64 = Xorshift64(seed: 1)
    private var numberIntroAnchor: TimeInterval = 0
    private var numberIntroSchedule = NumberIntroSchedule()
    private var numberIntroBlackoutCount = 0
    private var numberIntroBlackedColumns = Set<Int>()
    private var rainStartTime: TimeInterval = 0   // unused; kept for future use

    /// Returns the rendered cell content at the requested grid position.
    subscript(row: Int, column: Int) -> RenderCell {
        renderCells[(row * columns) + column]
    }

    /// Returns the number of visible cells currently present in a row.
    func visibleCount(in row: Int) -> Int {
        guard row >= 0, row < visibleCountByRow.count else {
            return 0
        }
        return visibleCountByRow[row]
    }

    /// Indicates whether a row changed in the most recent render pass.
    func isRowDirty(_ row: Int) -> Bool {
        guard row >= 0, row < dirtyRows.count else {
            return false
        }
        return dirtyRows[row]
    }

    /// Clears the dirty-row flags after the view has presented the current frame.
    func clearDirtyRows() {
        guard dirtyRowCount > 0 else {
            return
        }
        if let baseAddress = dirtyRows.withUnsafeMutableBufferPointer({ $0.baseAddress }) {
            baseAddress.update(repeating: false, count: dirtyRows.count)
        }
        dirtyRowCount = 0
    }

    /// When in the Neo message blank-between-lines phase, returns cursor visibility;
    /// otherwise `nil`. The view uses this to draw the cursor directly on-screen
    /// (bypassing the frame buffer) so it is guaranteed to appear.
    /// Covers all Neo scene phases: startup delay, typing, pause, and blank.
    var neoSceneCursor: (column: Int, visible: Bool)? {
        guard activeScene == .neoMessage, neoScene.phase != .done else { return nil }
        let state = neoScene.renderState
        let m = Self.numberIntroMargin
        let textCount = state.currentLine.map { min(state.visibleCharCount, $0.unicodeScalars.count) } ?? 0
        return (column: m + textCount, visible: state.cursorVisible)
    }

    var preferredAnimationTimeInterval: TimeInterval {
        1.0 / max(configuration.frameRate, MatrixScreenSaverOptions.minimumFrameRate)
    }

    /// Starts the renderer state for a new saver session.
    func start() {
        running = true
        lastUpdateTime = Date.timeIntervalSinceReferenceDate
        pendingSimulationSteps = 0.0
        if columns > 0, rows > 0 {
            resetLayers()
            beginSceneSequence()
        }
    }

    /// Stops the renderer so no more simulation work is produced.
    func stop() {
        running = false
    }

    /// Resizes the terminal grid and resets scene state to match it.
    func resize(to size: TerminalSize) {
        columns = max(size.columns, 1)
        rows = max(size.rows, 1)

        renderCells = Array(repeating: RenderCell(), count: columns * rows)
        stagingRenderCells = Array(repeating: RenderCell(), count: columns * rows)
        diffuseLevels = Array(repeating: 0.0, count: columns * rows)
        visibleCountByRow = Array(repeating: 0, count: rows)
        dirtyRows = Array(repeating: true, count: rows)
        dirtyRowCount = rows
        for index in layers.indices {
            layers[index].resize(columns: columns, rows: rows)
        }

        lastUpdateTime = Date.timeIntervalSinceReferenceDate
        pendingSimulationSteps = 0.0
        beginSceneSequence()
    }

    /// Applies an updated renderer configuration while preserving intent where possible.
    func updateConfiguration(_ configuration: Configuration) {
        let previousConfiguration = self.configuration
        let sanitizedConfiguration = configuration.sanitized()
        self.configuration = sanitizedConfiguration
        lastUpdateTime = Date.timeIntervalSinceReferenceDate
        pendingSimulationSteps = 0.0

        activeGlyphPool = Self.resolveGlyphPool(characters: sanitizedConfiguration.characters)

        let shouldResetSceneSequence =
            columns > 0 &&
            rows > 0 &&
            (previousConfiguration.neoMessageSceneEnabled != sanitizedConfiguration.neoMessageSceneEnabled ||
             previousConfiguration.numberSceneEnabled != sanitizedConfiguration.numberSceneEnabled ||
             previousConfiguration.neoMessageLines != sanitizedConfiguration.neoMessageLines)

        if shouldResetSceneSequence || (!running && columns > 0 && rows > 0) {
            resetLayers()
            beginSceneSequence()
        } else if columns > 0, rows > 0, activeScene == .rainForever {
            constructRenderContent()
        }
    }

    /// Advances the renderer by the elapsed time and reports whether output changed.
    @discardableResult
    func advance() -> Bool {
        guard running, columns > 0, rows > 0 else {
            return false
        }

        let nowTime = Date.timeIntervalSinceReferenceDate
        let elapsed = nowTime - lastUpdateTime
        lastUpdateTime = nowTime

        pendingSimulationSteps += elapsed * configuration.frameRate
        pendingSimulationSteps = min(pendingSimulationSteps, Self.maxBufferedSimulationSteps)
        let availableSteps = Int(pendingSimulationSteps.rounded(.down))
        guard availableSteps > 0 else {
            return false
        }

        let steps = min(availableSteps, Self.maxSimulationStepsPerTick)
        pendingSimulationSteps -= Double(steps)

        for _ in 0..<steps {
            stepFrame()
        }
        return dirtyRowCount > 0
    }

    /// Dispatches the current frame tick to the active scene implementation.
    private func stepFrame() {
        switch activeScene {
        case .neoMessage:
            stepNeoMessageFrame()
        case .numberIntro:
            stepNumberIntroScene()
        case .rainForever:
            stepRainFrame()
        }
    }

    /// Advances the continuous rain scene by one simulation step.
    private func stepRainFrame() {
        if frameIndex % spawnModulo == 0 {
            addRandomThread()
        }
        frameIndex += 1
        now += 1

        layers[0].stepThreads(now: now, glyphProvider: randomGlyph)
        layers[0].resolveLevels(now: now, errorRateModulo: errorRateModulo, glyphProvider: randomGlyph)
        layers[1].stepThreads(now: now, glyphProvider: randomGlyph)
        layers[1].resolveLevels(now: now, errorRateModulo: errorRateModulo, glyphProvider: randomGlyph)
        layers[2].stepThreads(now: now, glyphProvider: randomGlyph)
        layers[2].resolveLevels(now: now, errorRateModulo: errorRateModulo, glyphProvider: randomGlyph)

        constructRenderContent()
    }

    // MARK: - Number intro scene

    private func initNumberIntroScene() {
        numberSceneRNG = Xorshift64(seed: sceneSeed &+ 2)

        // Anchor: sceneStartTime + however long the Neo scene takes at 1× speed.
        // All displays use the same sceneStartTime and same seed → same anchor.
        let neoWallDuration: TimeInterval = configuration.neoMessageSceneEnabled
            ? neoScene.scheduledDuration / configuration.neoMessageSpeedFactor
            : 0
        numberIntroAnchor = sceneStartTime + neoWallDuration

        let cursorBlinkEnd = Double(Self.numberIntroCursorBlinkCount * 2) * Self.numberIntroCursorBlinkPeriod

        let blinkEndDate = Date(timeIntervalSinceReferenceDate: numberIntroAnchor + cursorBlinkEnd)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        let dateString = formatter.string(from: blinkEndDate)
        formatter.dateFormat = "H:mm:ss"
        let timeString = formatter.string(from: blinkEndDate)
        let typingText = "Call trans opt: received. \(dateString) \(timeString) REC:Log>"

        let charTimings = Self.naturalTypingTimings(for: typingText,
                                                    baseInterval: Self.numberIntroTypingInterval,
                                                    rng: &numberSceneRNG)
        let typingEnd = cursorBlinkEnd + (charTimings.last ?? 0)

        let pause1Duration = Double.random(in: 1...3, using: &numberSceneRNG)
        let pause1End = typingEnd + pause1Duration

        let pause2Duration = Double.random(in: 1...3, using: &numberSceneRNG)
        let rainStart = pause1End + pause2Duration

        let margin = Self.numberIntroMargin
        let colStart = margin
        let colEnd = max(margin + 1, columns - margin)
        let contentColumns = colEnd - colStart
        // Divide columns into exactly numberIntroBlackoutRounds groups so all
        // screens — regardless of width — finish the blackout in the same time.
        let numRounds = Self.numberIntroBlackoutRounds
        let columnsPerRound = contentColumns > 0
            ? max(1, Int(ceil(Double(contentColumns) / Double(numRounds))))
            : 1
        var available = Array(colStart..<colEnd)
        var blackoutRounds: [[Int]] = []
        for _ in 0..<numRounds {
            let count = min(columnsPerRound, available.count)
            let chosen = count > 0 ? Array(available.shuffled(using: &numberSceneRNG).prefix(count)) : []
            blackoutRounds.append(chosen)
            let chosenSet = Set(chosen)
            available.removeAll { chosenSet.contains($0) }
        }

        numberIntroSchedule = NumberIntroSchedule(
            typingText: typingText,
            cursorBlinkEnd: cursorBlinkEnd,
            charTimings: charTimings,
            typingEnd: typingEnd,
            pause1Duration: pause1Duration,
            pause1End: pause1End,
            pause2Duration: pause2Duration,
            rainStart: rainStart,
            blackoutRounds: blackoutRounds
        )

        numberIntroPhase = .cursorBlink
        numberIntroPhaseStart = numberIntroAnchor
        numberIntroCursorVisible = true
        numberIntroRainFrame = 0
        numberIntroBlackoutCount = 0
        numberIntroBlackedColumns = []
        numberIntroTypedCount = 0
        numberIntroTypingText = typingText
        numberIntroCharTimings = charTimings

        for i in renderCells.indices { renderCells[i] = Self.blankRenderCell }
        for i in visibleCountByRow.indices { visibleCountByRow[i] = 0 }
        setRow0(text: "", typedCount: 0, showCursor: true)
        markAllRowsDirty()
    }

    private func stepNumberIntroScene() {
        for _ in 0..<20 {
            guard activeScene == .numberIntro else { break }
            let previousPhase = numberIntroPhase
            let t = Date.timeIntervalSinceReferenceDate
            switch numberIntroPhase {
            case .cursorBlink:      stepCursorBlink(t: t)
            case .typingFirstLine:  stepTypingFirstLine(t: t)
            case .pauseAfterFirst:  stepPauseAfterFirst(t: t)
            case .secondLine:       commitSecondLine(t: t)
            case .pauseAfterSecond: stepPauseAfterSecond(t: t)
            case .rain:             stepNumberRain(t: t)
            }
            if numberIntroPhase == previousPhase { break }
        }
        markAllRowsDirty()
    }

    private func stepCursorBlink(t: TimeInterval) {
        let elapsed = t - numberIntroPhaseStart
        let halfPeriod = Int(elapsed / Self.numberIntroCursorBlinkPeriod)
        if halfPeriod >= Self.numberIntroCursorBlinkCount * 2 {
            numberIntroPhase = .typingFirstLine
            numberIntroPhaseStart = numberIntroAnchor + numberIntroSchedule.cursorBlinkEnd
            setRow0(text: "", typedCount: 0, showCursor: false)
            return
        }
        let visible = (halfPeriod % 2 == 0)
        if visible != numberIntroCursorVisible {
            numberIntroCursorVisible = visible
            setRow0(text: "", typedCount: 0, showCursor: visible)
        }
    }

    private func stepTypingFirstLine(t: TimeInterval) {
        let totalChars = numberIntroSchedule.charTimings.count
        let elapsed = t - numberIntroPhaseStart
        let count = numberIntroSchedule.charTimings.prefix(while: { $0 <= elapsed }).count
        numberIntroTypedCount = count
        if count >= totalChars {
            numberIntroCursorVisible = true
            setRow0(text: numberIntroSchedule.typingText, typedCount: totalChars, showCursor: true)
            numberIntroPhase = .pauseAfterFirst
            numberIntroPhaseStart = numberIntroAnchor + numberIntroSchedule.typingEnd
            return
        }
        let halfPeriod = Int(elapsed / Self.numberIntroCursorBlinkPeriod)
        setRow0(text: numberIntroSchedule.typingText, typedCount: count,
                showCursor: halfPeriod % 2 == 0)
    }

    private func stepPauseAfterFirst(t: TimeInterval) {
        let elapsed = t - numberIntroPhaseStart
        let halfPeriod = Int(elapsed / Self.numberIntroCursorBlinkPeriod)
        let visible = halfPeriod % 2 == 0
        if visible != numberIntroCursorVisible {
            numberIntroCursorVisible = visible
            setRow0(text: numberIntroSchedule.typingText,
                    typedCount: numberIntroSchedule.charTimings.count,
                    showCursor: visible)
        }
        if elapsed >= numberIntroSchedule.pause1Duration {
            numberIntroPhase = .secondLine
        }
    }

    private func commitSecondLine(t: TimeInterval) {
        let text = "Trace program: running"
        setRow0(text: text, typedCount: text.unicodeScalars.count, showCursor: false)
        numberIntroPhase = .pauseAfterSecond
        numberIntroPhaseStart = numberIntroAnchor + numberIntroSchedule.pause1End
    }

    private func stepPauseAfterSecond(t: TimeInterval) {
        if t - numberIntroPhaseStart >= numberIntroSchedule.pause2Duration {
            fillNumberRain()
            numberIntroPhase = .rain
            numberIntroRainFrame = 0
        }
    }

    private func stepNumberRain(t: TimeInterval) {
        while activeScene == .numberIntro {
            let expectedTime = numberIntroAnchor + numberIntroSchedule.rainStart
                + Double(numberIntroBlackoutCount) * Self.numberIntroBlackoutInterval
            if t >= expectedTime {
                blackoutColumns()
            } else {
                break
            }
        }
        guard activeScene == .numberIntro else { return }
        scrollNumberRain()
        self.now += 1
    }

    /// Writes cursor / typed text into row 0 of the render grid.
    /// Writes cursor / typed text into the content area top-left (row m, col m).
    private func setRow0(text: String, typedCount: Int, showCursor: Bool) {
        let m = Self.numberIntroMargin
        guard rows > m, columns > m else { return }
        let baseGreenLevel = max(levelColors.count / 2, 1)
        let scalars = Array(text.unicodeScalars)
        let offset = m * columns
        let colStart = m
        let colEnd = columns - m
        for col in colStart..<colEnd { renderCells[offset + col] = Self.blankRenderCell }
        var col = colStart
        for i in 0..<min(typedCount, scalars.count) {
            guard col < colEnd else { break }
            renderCells[offset + col] = RenderCell(scalar: scalars[i], foregroundLevel: baseGreenLevel,
                                          backgroundLevel: 0, bold: false)
            col += 1
        }
        if showCursor, col < colEnd {
            renderCells[offset + col] = RenderCell(scalar: UnicodeScalar(0x2588)!, foregroundLevel: baseGreenLevel,
                                          backgroundLevel: 0, bold: false)
            col += 1
        }
        visibleCountByRow[m] = col - colStart
    }

    /// Instantly fills rows m+1..rows-m-1 with random numbers; row m stays empty.
    private func fillNumberRain() {
        let m = Self.numberIntroMargin
        guard rows > m * 2 + 1, columns > m * 2 else { return }
        let levelCount = max(levelColors.count, 1)
        let rowStart = m + 1; let rowEnd = rows - m
        let colStart = m;     let colEnd = columns - m
        // ensure text row is blank
        let textOffset = m * columns
        for col in colStart..<colEnd { renderCells[textOffset + col] = Self.blankRenderCell }
        visibleCountByRow[m] = 0
        for row in rowStart..<rowEnd {
            let rowOffset = row * columns
            for col in colStart..<colEnd {
                renderCells[rowOffset + col] = RenderCell(
                    scalar: randomNumberGlyph(),
                    foregroundLevel: numberRainLevel(levelCount: levelCount),
                    backgroundLevel: 0, bold: false)
            }
            visibleCountByRow[row] = colEnd - colStart
        }
        markAllRowsDirty()
    }

    /// Shifts rows m+1..rows-m-1 down by one, fills the new row m+1; row m untouched.
    private func scrollNumberRain() {
        let m = Self.numberIntroMargin
        guard rows > m * 2 + 1, columns > m * 2 else { return }
        let levelCount = max(levelColors.count, 1)
        let rowStart = m + 1; let rowEnd = rows - m
        let colStart = m;     let colEnd = columns - m
        for row in stride(from: rowEnd - 1, through: rowStart + 1, by: -1) {
            let dst = row * columns
            let src = (row - 1) * columns
            for col in colStart..<colEnd { renderCells[dst + col] = renderCells[src + col] }
            visibleCountByRow[row] = visibleCountByRow[row - 1]
        }
        let newTopOffset = rowStart * columns
        for col in colStart..<colEnd {
            guard !numberIntroBlackedColumns.contains(col) else {
                renderCells[newTopOffset + col] = Self.blankRenderCell
                continue
            }
            renderCells[newTopOffset + col] = RenderCell(
                scalar: randomNumberGlyph(),
                foregroundLevel: numberRainLevel(levelCount: levelCount),
                backgroundLevel: 0, bold: false)
        }
        visibleCountByRow[rowStart] = colEnd - colStart
    }

    /// Blacks out ~10 % of content columns: clears rows m+1..rowEnd, shows indicator at row m.
    private func blackoutColumns() {
        let m = Self.numberIntroMargin
        guard rows > m * 2 + 1, columns > m * 2 else { return }
        guard numberIntroBlackoutCount < numberIntroSchedule.blackoutRounds.count else { return }
        let chosen = numberIntroSchedule.blackoutRounds[numberIntroBlackoutCount]
        let colStart = m; let colEnd = columns - m
        let rowStart = m + 1; let rowEnd = rows - m
        for col in chosen {
            for row in rowStart..<rowEnd { renderCells[row * columns + col] = Self.blankRenderCell }
            renderCells[m * columns + col] = RenderCell(
                scalar: randomNumberGlyph(),
                foregroundLevel: max(levelColors.count / 2, 1),
                backgroundLevel: 0, bold: false)
            numberIntroBlackedColumns.insert(col)
        }
        visibleCountByRow[m] = (colStart..<colEnd).filter { numberIntroBlackedColumns.contains($0) }.count
        numberIntroBlackoutCount += 1
        if numberIntroBlackoutCount >= numberIntroSchedule.blackoutRounds.count {
            activeScene = .rainForever
            rainStartTime = Date.timeIntervalSinceReferenceDate
        }
    }

    /// Returns a random palette level with power clamped to 0.2–0.6.
    private func numberRainLevel(levelCount: Int) -> Int {
        if Double.random(in: 0...1, using: &rainRNG) < 0.001 { return levelCount - 1 }
        let power = Double.random(in: 0.2...0.6, using: &rainRNG)
        let fractional = interpolate(power, 0.6, Double(levelCount))
        return max(1, quantizedLevel(for: fractional, upperBound: levelCount - 1))
    }

    /// Returns cumulative character-appear times for natural-feeling typing.
    /// Adds random per-character variation, longer pauses at punctuation, and
    /// rare hesitations. All timings are in seconds.
    /// Computes per-character cumulative delays with natural variation for a typing sequence.
    /// Used by both the Neo message scene and the number intro scene.
    static func naturalTypingTimings(for text: String,
                                             baseInterval: TimeInterval,
                                             rng: inout Xorshift64) -> [TimeInterval] {
        var timings: [TimeInterval] = []
        var t: TimeInterval = 0
        for ch in text {
            var delay = baseInterval * Double.random(in: 0.4...2.2, using: &rng)
            if ".,!?:>".contains(ch) { delay += baseInterval * Double.random(in: 1.0...3.5, using: &rng) }
            else if ch == " " { delay += baseInterval * Double.random(in: 0.3...1.2, using: &rng) }
            if Double.random(in: 0...1, using: &rng) < 0.04 { delay += Double.random(in: 0.12...0.35, using: &rng) }
            t += delay
            timings.append(t)
        }
        return timings
    }

    /// Advances the Neo message intro scene by one simulation step.
    private func stepNeoMessageFrame() {
        neoScene.advance(now: Date.timeIntervalSinceReferenceDate, speedFactor: configuration.neoMessageSpeedFactor)
        let state = neoScene.renderState
        // Never write the cursor to the frame buffer — the view draws it directly
        // via neoSceneCursor so it is guaranteed to appear in every phase.
        setRow0(text: state.currentLine ?? "", typedCount: state.visibleCharCount, showCursor: false)
        markAllRowsDirty()
        if neoScene.phase == .done {
            transitionFromNeoMessage()
        }
    }

    /// Moves from the Neo message scene to the next scene in the sequence.
    private func transitionFromNeoMessage() {
        if configuration.numberSceneEnabled {
            activeScene = .numberIntro
            initNumberIntroScene()
        } else {
            activeScene = .rainForever
            rainStartTime = Date.timeIntervalSinceReferenceDate
            stepRainFrame()
        }
    }

    /// Chooses and initializes the first scene for the current session.
    private func beginSceneSequence() {
        now = 100
        frameIndex = 0

        // In preview contexts (System Settings thumbnail, preview host) skip the
        // multi-screen sync delay so scenes begin within one second of launch.
        // In the screensaver engine the 10-second boundary ensures all displays
        // sharing the same activation window use an identical startTime and seed.
        let nowTime = Date.timeIntervalSinceReferenceDate
        if configuration.skipSyncDelay {
            sceneStartTime = nowTime + 1.0
        } else {
            let syncWindow: TimeInterval = 10.0
            sceneStartTime = floor(nowTime / syncWindow) * syncWindow + syncWindow
        }
        sceneSeed = UInt64(bitPattern: Int64(sceneStartTime))
        rainRNG = Xorshift64(seed: sceneSeed &+ 3)

        guard columns > 0, rows > 0 else {
            if configuration.neoMessageSceneEnabled {
                activeScene = .neoMessage
            } else if configuration.numberSceneEnabled {
                activeScene = .numberIntro
            } else {
                activeScene = .rainForever
            }
            return
        }

        if configuration.neoMessageSceneEnabled {
            activeScene = .neoMessage
            neoScene.reset(startTime: sceneStartTime, seed: sceneSeed &+ 1, lines: configuration.neoMessageLines)
            for i in renderCells.indices { renderCells[i] = Self.blankRenderCell }
            for i in visibleCountByRow.indices { visibleCountByRow[i] = 0 }
            markAllRowsDirty()
        } else if configuration.numberSceneEnabled {
            activeScene = .numberIntro
            initNumberIntroScene()
        } else {
            activeScene = .rainForever
            rainStartTime = nowTime
            stepRainFrame()
        }
    }

    /// Clears all render layers back to a blank state.
    private func resetLayers() {
        for index in layers.indices {
            layers[index].clear()
        }
    }

    private var spawnModulo: Int {
        let density = max(configuration.rainDensity, MatrixScreenSaverOptions.minimumRainDensity)
        let baseSpawnModulo = (150.0 / density) / Double(max(columns, 1))
        return max(1, Int(ceil(baseSpawnModulo * frameRateScale)))
    }

    /// Spawns a new falling thread on one of the renderer layers.
    private func addRandomThread() {
        let baseSpeed = Self.baseSpeedTable.randomElement(using: &rainRNG) ?? 6
        let stepInterval = max(1, Int((Double(baseSpeed) * frameRateScale).rounded()))
        let thread = RainThread(
            x: Int.random(in: 0..<columns, using: &rainRNG),
            y: 0,
            age: 0,
            speed: stepInterval,
            power: 2.0 / Double(baseSpeed),
            decay: decay
        )
        let layerIndex = baseSpeed < 3 ? 0 : baseSpeed < 5 ? 1 : 2
        layers[layerIndex].addThread(thread)
    }

    /// Rebuilds the composed render grid from the three simulation layers.
    private func constructRenderContent() {
        let cellCount = columns * rows
        if renderCells.count != cellCount {
            renderCells = Array(repeating: Self.blankRenderCell, count: cellCount)
        }
        if stagingRenderCells.count != cellCount {
            stagingRenderCells = Array(repeating: Self.blankRenderCell, count: cellCount)
        }
        if diffuseLevels.count != cellCount {
            diffuseLevels = Array(repeating: 0.0, count: cellCount)
        }
        if visibleCountByRow.count != rows {
            visibleCountByRow = Array(repeating: 0, count: rows)
        }
        prepareDirtyRows()

        let layer0 = layers[0].content
        let layer1 = layers[1].content
        let layer2 = layers[2].content
        let levelCount = levelColors.count
        let diffuseEnabled = configuration.diffuseEnabled
        if diffuseEnabled, let baseAddress = diffuseLevels.withUnsafeMutableBufferPointer({ $0.baseAddress }) {
            baseAddress.update(repeating: 0.0, count: diffuseLevels.count)
        }

        var row = 0
        while row < rows {
            let rowOffset = row * columns
            var renderableCount = 0
            var column = 0
            while column < columns {
                let index = rowOffset + column
                var sourceCell: LayerCell?
                var currentPower = 0.0

                let cell0 = layer0[index]
                if !cell0.isBlank {
                    sourceCell = cell0
                    currentPower = cell0.currentPower
                }

                let cell1 = layer1[index]
                if !cell1.isBlank {
                    if sourceCell == nil {
                        sourceCell = cell1
                    }
                    if cell1.currentPower > currentPower {
                        currentPower = cell1.currentPower
                    }
                }

                let cell2 = layer2[index]
                if !cell2.isBlank {
                    if sourceCell == nil {
                        sourceCell = cell2
                    }
                    if cell2.currentPower > currentPower {
                        currentPower = cell2.currentPower
                    }
                }

                guard let sourceCell else {
                    stagingRenderCells[index] = Self.blankRenderCell
                    column += 1
                    continue
                }

                var adjustedPower = currentPower
                if twinkleAmount > 0 {
                    adjustedPower -= hypot(adjustedPower * twinkleAmount, 0.1) * Double.random(in: 0...1)
                }
                if adjustedPower < 0 {
                    adjustedPower = 0
                }

                let fractionalLevel = interpolate(adjustedPower, 0.6, Double(levelCount))
                let level = quantizedLevel(for: fractionalLevel, upperBound: levelCount - 1)

                guard level > 0 else {
                    stagingRenderCells[index] = Self.blankRenderCell
                    column += 1
                    continue
                }

                stagingRenderCells[index] = RenderCell(
                    scalar: sourceCell.scalar,
                    foregroundLevel: level,
                    backgroundLevel: 0,
                    bold: (sourceCell.flags & Self.disableBoldFlag) == 0 && sourceCell.stage > 0.5
                )
                renderableCount += 1

                if diffuseEnabled {
                    accumulateDiffuse(into: &diffuseLevels, row: row, column: column, level: level, levelCount: levelCount)
                }
                column += 1
            }
            visibleCountByRow[row] = renderableCount
            row += 1
        }

        if diffuseEnabled {
            applyDiffuseLevels(into: &stagingRenderCells, levelCount: levelCount)
        }

        row = 0
        while row < rows {
            let rowOffset = row * columns
            var rowDirty = false
            var column = 0
            while column < columns {
                let index = rowOffset + column
                let nextCell = stagingRenderCells[index]
                if renderCells[index] != nextCell {
                    renderCells[index] = nextCell
                    rowDirty = true
                }
                column += 1
            }
            if rowDirty {
                markRowDirty(row)
            }
            row += 1
        }
    }

    /// Returns a random glyph from the supported rain character pool.
    private func randomGlyph() -> UnicodeScalar {
        activeGlyphPool.randomElement(using: &rainRNG) ?? UnicodeScalar("0")
    }

    /// Returns a random ASCII numeral for the startup number scene.
    private func randomNumberGlyph() -> UnicodeScalar {
        UnicodeScalar(48 + Int.random(in: 0..<10, using: &rainRNG)) ?? UnicodeScalar("0")
    }

    private var frameRateScale: Double {
        configuration.frameRate / Self.referenceFrameRate
    }

    private var decay: Int {
        max(1, Int((Double(Self.baseDecay) * frameRateScale).rounded()))
    }

    private var errorRateModulo: Int {
        guard configuration.errorRate > 0 else {
            return 0
        }
        return max(1, Int((Self.baseErrorRateModulo * frameRateScale / configuration.errorRate).rounded()))
    }

    private var twinkleAmount: Double {
        configuration.twinkleEnabled ? Self.defaultTwinkle : 0.0
    }

    /// Accumulates diffuse glow contributions around a rendered foreground cell.
    private func accumulateDiffuse(into diffuseLevels: inout [Double], row: Int, column: Int, level: Int, levelCount: Int) {
        guard levelCount > 1 else {
            return
        }

        let twinklePower = Double(level) / Double(levelCount - 1)
        let p0 = (1.0 / 0.22) * twinklePower
        let p1 = (1.0 / 0.25) * (twinklePower - 0.2)
        let p2 = (1.0 / 0.35) * (twinklePower - 0.45)

        addDiffuse(into: &diffuseLevels, row: row, column: column, value: p0)
        addDiffuse(into: &diffuseLevels, row: row, column: column - 1, value: p1)
        addDiffuse(into: &diffuseLevels, row: row, column: column + 1, value: p1)
        addDiffuse(into: &diffuseLevels, row: row - 1, column: column, value: p1)
        addDiffuse(into: &diffuseLevels, row: row + 1, column: column, value: p1)
        addDiffuse(into: &diffuseLevels, row: row - 1, column: column - 1, value: p2)
        addDiffuse(into: &diffuseLevels, row: row - 1, column: column + 1, value: p2)
        addDiffuse(into: &diffuseLevels, row: row + 1, column: column - 1, value: p2)
        addDiffuse(into: &diffuseLevels, row: row + 1, column: column + 1, value: p2)
    }

    /// Adds a single diffuse contribution to a valid neighboring cell.
    private func addDiffuse(into diffuseLevels: inout [Double], row: Int, column: Int, value: Double) {
        guard row >= 0, row < rows, column >= 0, column < columns, value > 0 else {
            return
        }
        diffuseLevels[(row * columns) + column] += value
    }

    /// Converts accumulated diffuse values into background color levels.
    private func applyDiffuseLevels(into renderCells: inout [RenderCell], levelCount: Int) {
        guard levelCount > 1 else {
            return
        }

        let upperBound = levelCount - 1
        var index = 0
        while index < diffuseLevels.count {
            let diffuse = min(0.08 * diffuseLevels[index], 0.55)
            let backgroundLevel = min(max(Int(floor(Double(upperBound) * diffuse)), 0), upperBound)
            if backgroundLevel > 0, !renderCells[index].hasForeground {
                visibleCountByRow[index / columns] += 1
            }
            renderCells[index].backgroundLevel = backgroundLevel
            index += 1
        }
    }

    /// Resets all dirty-row bookkeeping before a new render pass.
    private func prepareDirtyRows() {
        if dirtyRows.count != rows {
            dirtyRows = Array(repeating: false, count: rows)
        } else if let baseAddress = dirtyRows.withUnsafeMutableBufferPointer({ $0.baseAddress }) {
            baseAddress.update(repeating: false, count: dirtyRows.count)
        }
        dirtyRowCount = 0
    }

    /// Marks a row as dirty if it changed during rendering.
    private func markRowDirty(_ row: Int) {
        guard row >= 0, row < rows, !dirtyRows[row] else {
            return
        }
        dirtyRows[row] = true
        dirtyRowCount += 1
    }

    /// Marks the entire grid dirty, usually after a full scene reset.
    private func markAllRowsDirty() {
        if dirtyRows.count != rows {
            dirtyRows = Array(repeating: true, count: rows)
        } else if let baseAddress = dirtyRows.withUnsafeMutableBufferPointer({ $0.baseAddress }) {
            baseAddress.update(repeating: true, count: dirtyRows.count)
        }
        dirtyRowCount = rows
    }

    /// Quantizes a fractional brightness value into a palette level.
    private func quantizedLevel(for fractionalLevel: Double, upperBound: Int) -> Int {
        let clampedLevel = max(0.0, fractionalLevel)
        let quantizedLevel: Int

        if configuration.twinkleEnabled {
            var level = Int(floor(clampedLevel))
            if Double.random(in: 0...1) < clampedLevel - Double(level) {
                level += 1
            }
            quantizedLevel = level
        } else {
            // Match upstream cxxmatrix: twinkle-off uses stable floor quantization.
            quantizedLevel = Int(floor(clampedLevel))
        }

        return min(max(quantizedLevel, 0), upperBound)
    }

    /// Linearly interpolates a value into the supplied output range.
    private func interpolate(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * value
    }

    /// Converts normalized RGB values into an xterm-256 palette index.
    private static func color2index(_ red: Double, _ green: Double, _ blue: Double, levels: Int) -> Int {
        let r = Int(round(red * Double(levels - 1)))
        let g = Int(round(green * Double(levels - 1)))
        let b = Int(round(blue * Double(levels - 1)))
        return 16 + (r * levels + g) * levels + b
    }

    /// Converts an xterm-256 palette index back into an RGB color.
    private static func index2color(_ index: Int) -> TerminalColor {
        let r: Int
        let g: Int
        let b: Int

        if index < 16 {
            let maxValue = index < 8 ? 0x80 : 0xFF
            r = maxValue * (index & 1)
            g = maxValue * ((index / 2) & 1)
            b = maxValue * ((index / 4) & 1)
        } else if index < 232 {
            let adjusted = index - 16
            var rr = adjusted / 36
            var gg = (adjusted / 6) % 6
            var bb = adjusted % 6
            if rr != 0 { rr = rr * 40 + 55 }
            if gg != 0 { gg = gg * 40 + 55 }
            if bb != 0 { bb = bb * 40 + 55 }
            r = rr
            g = gg
            b = bb
        } else {
            let gray = 8 + 10 * (index - 232)
            r = gray
            g = gray
            b = gray
        }

        return TerminalColor(red: UInt8(r), green: UInt8(g), blue: UInt8(b))
    }

    /// Builds the green palette used for foreground and diffuse rendering levels.
    private static func makePalette() -> [TerminalColor] {
        let base = index2color(47)

        let offset = 35
        let modulo = 40
        let levels = 6
        let colorCount = 256
        let edge = Double(levels - 1)

        let red = (Int(base.red) - offset) / modulo
        let green = (Int(base.green) - offset) / modulo
        let blue = (Int(base.blue) - offset) / modulo
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)

        var indices: [Int] = []
        if maximum != minimum {
            for level in 0..<levels {
                let fraction = Double(level) / edge
                let r = (Double(red) / edge) * fraction
                let g = (Double(green) / edge) * fraction
                let b = (Double(blue) / edge) * fraction
                indices.append(color2index(r, g, b, levels: levels))
            }

            if minimum + 1 < levels {
                for level in (minimum + 1)..<levels {
                    let remaining = Double(levels - 1 - level)
                    let denominator = Double(levels - 1 - minimum)
                    let r = 1.0 - (1.0 - Double(red) / edge) * (remaining / denominator)
                    let g = 1.0 - (1.0 - Double(green) / edge) * (remaining / denominator)
                    let b = 1.0 - (1.0 - Double(blue) / edge) * (remaining / denominator)
                    indices.append(color2index(r, g, b, levels: levels))
                }
            }
        } else {
            let grayStart = 16 + levels * levels * levels
            indices.append(16)
            for level in grayStart..<colorCount {
                indices.append(level)
            }
            indices.append(grayStart - 1)
        }

        return indices.map(index2color)
    }
}
