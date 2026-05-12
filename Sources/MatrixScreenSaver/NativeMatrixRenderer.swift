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
                errorRate: max(errorRate, MatrixScreenSaverOptions.minimumErrorRate)
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
    private static let numberIntroStripePeriods = [0, 32, 16, 8, 4, 2, 2, 2]
    private static let numberIntroFramesPerStripe = 20
    private static let numberIntroFillFrames = 40
    private static let maxBufferedSimulationSteps = 2.0
    private static let maxSimulationStepsPerTick = 2
    private static let disableBoldFlag: UInt32 = 0x1
    private static let blankRenderCell = RenderCell()
    private static let glyphPool: [UnicodeScalar] = {
        var glyphs = Array("0123456789".unicodeScalars)
        glyphs.append(contentsOf: (0..<46).compactMap { UnicodeScalar(0xFF70 + $0) })
        glyphs.append(contentsOf: "<>*+.:=_|".unicodeScalars)
        return glyphs
    }()
    private static let palette = makePalette()

    static var supportedScalars: [UnicodeScalar] {
        glyphPool
    }

    private(set) var columns = 0
    private(set) var rows = 0
    private(set) var levelColors = NativeMatrixRenderer.palette

    private var configuration = Configuration()
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
    private var sceneFrameIndex = 0
    private var sceneStartTime: TimeInterval = 0
    private var isInNumberFillPhase = false
    private var numberIntroShuffledIndices: [Int] = []
    private var numberIntroRevealIndex = 0

    /// Whether the Neo message intro scene is currently active.
    var isInNeoMessageScene: Bool {
        activeScene == .neoMessage
    }

    /// The Neo message render state for the current frame, or nil when not in that scene.
    var neoMessageRenderState: NeoMessageRenderState? {
        guard activeScene == .neoMessage else { return nil }
        return neoScene.renderState
    }

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

        let shouldResetSceneSequence =
            columns > 0 &&
            rows > 0 &&
            (previousConfiguration.neoMessageSceneEnabled != sanitizedConfiguration.neoMessageSceneEnabled ||
             previousConfiguration.numberSceneEnabled != sanitizedConfiguration.numberSceneEnabled)

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
            if isInNumberFillPhase {
                stepNumberFillFrame()
            } else {
                stepNumberIntroFrame()
            }
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

    /// Advances the startup number scene by one simulation step.
    private func stepNumberIntroFrame() {
        populateNumberIntroFrame(stripe: currentNumberIntroStripe)
        now += 1
        sceneFrameIndex += 1
        if sceneFrameIndex >= Self.totalNumberIntroFrames {
            activeScene = .rainForever
        }
    }

    /// Advances the random-fill phase of the number intro scene.
    private func stepNumberFillFrame() {
        let total = columns * rows
        guard total > 0 else {
            isInNumberFillPhase = false
            return
        }
        let levelCount = max(levelColors.count, 1)
        let decay = self.decay
        let perFrame = max(1, total / Self.numberIntroFillFrames)
        let newRevealIndex = min(numberIntroRevealIndex + perFrame, total)

        // Reveal newly added cells
        for i in numberIntroRevealIndex..<newRevealIndex {
            let cellIndex = numberIntroShuffledIndices[i]
            let scalar = randomNumberGlyph()
            layers[1].content[cellIndex] = LayerCell(
                scalar: scalar,
                birth: now - Int((Double(decay) * (0.5 + 0.1 * Double.random(in: 0...1))).rounded()),
                power: 1.0,
                decay: decay,
                flags: Self.disableBoldFlag,
                stage: 0.0,
                currentPower: 0.0
            )
        }
        numberIntroRevealIndex = newRevealIndex

        // Refresh all revealed cells with new random glyphs each frame
        for i in 0..<numberIntroRevealIndex {
            let cellIndex = numberIntroShuffledIndices[i]
            let scalar = randomNumberGlyph()
            let level = min(levelCount - 1, Int(Double(levelCount - 1) * (0.5 + 0.3 * Double.random(in: 0...1))))
            renderCells[cellIndex] = RenderCell(scalar: scalar, foregroundLevel: level, backgroundLevel: 0, bold: false)
            let row = cellIndex / columns
            visibleCountByRow[row] = min(visibleCountByRow[row] + 1, columns)
        }
        markAllRowsDirty()
        now += 1

        if numberIntroRevealIndex >= total {
            isInNumberFillPhase = false
            sceneFrameIndex = 0
        }
    }

    /// Initialises the random-fill phase for the number intro scene.
    private func initNumberFillPhase() {
        let total = columns * rows
        numberIntroShuffledIndices = Array(0..<total).shuffled()
        numberIntroRevealIndex = 0
        isInNumberFillPhase = true
        // Clear render cells so we start from a blank screen
        for i in renderCells.indices { renderCells[i] = Self.blankRenderCell }
        for i in visibleCountByRow.indices { visibleCountByRow[i] = 0 }
        markAllRowsDirty()
    }

    /// Advances the Neo message intro scene by one simulation step.
    private func stepNeoMessageFrame() {
        neoScene.advance(now: Date.timeIntervalSinceReferenceDate, speedFactor: configuration.neoMessageSpeedFactor)
        markAllRowsDirty()
        if neoScene.phase == .done {
            transitionFromNeoMessage()
        }
    }

    /// Moves from the Neo message scene to the next scene in the sequence.
    private func transitionFromNeoMessage() {
        sceneStartTime = Date.timeIntervalSinceReferenceDate
        if configuration.numberSceneEnabled {
            activeScene = .numberIntro
            initNumberFillPhase()
        } else {
            activeScene = .rainForever
            stepRainFrame()
        }
    }

    private var currentNumberIntroStripe: Int {
        let stripeIndex = min(sceneFrameIndex / Self.numberIntroFramesPerStripe, Self.numberIntroStripePeriods.count - 1)
        return Self.numberIntroStripePeriods[stripeIndex]
    }

    private static var totalNumberIntroFrames: Int {
        numberIntroStripePeriods.count * numberIntroFramesPerStripe
    }

    /// Chooses and initializes the first scene for the current session.
    private func beginSceneSequence() {
        sceneFrameIndex = 0
        now = 100
        frameIndex = 0
        sceneStartTime = Date.timeIntervalSinceReferenceDate

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
            neoScene.reset(startTime: Date.timeIntervalSinceReferenceDate)
        } else if configuration.numberSceneEnabled {
            activeScene = .numberIntro
            initNumberFillPhase()
        } else {
            activeScene = .rainForever
            stepRainFrame()
        }
    }

    /// Clears all render layers back to a blank state.
    private func resetLayers() {
        for index in layers.indices {
            layers[index].clear()
        }
    }

    /// Generates the current startup number-scene frame directly into the render grid.
    private func populateNumberIntroFrame(stripe: Int) {
        guard columns > 0, rows > 0 else {
            return
        }

        let rowCount = rows
        let columnCount = columns
        let decay = self.decay
        let levelCount = max(levelColors.count, 1)
        let layerIndex = 1

        var row = 0
        while row < rowCount {
            let rowOffset = row * columnCount
            var visibleCount = 0
            var column = 0
            while column < columnCount {
                let index = rowOffset + column
                if stripe != 0, column % stripe == 0 {
                    layers[layerIndex].content[index] = LayerCell()
                    renderCells[index] = Self.blankRenderCell
                    column += 1
                    continue
                }

                let scalar = randomNumberGlyph()
                layers[layerIndex].content[index] = LayerCell(
                    scalar: scalar,
                    birth: now - Int((Double(decay) * (0.5 + 0.1 * Double.random(in: 0...1))).rounded()),
                    power: 1.0,
                    decay: decay,
                    flags: Self.disableBoldFlag,
                    stage: 0.0,
                    currentPower: 0.0
                )

                let level = min(levelCount - 1, Int(Double(levelCount - 1) * (0.5 + 0.3 * Double.random(in: 0...1))))
                renderCells[index] = RenderCell(
                    scalar: scalar,
                    foregroundLevel: level,
                    backgroundLevel: 0,
                    bold: false
                )
                visibleCount += 1
                column += 1
            }
            visibleCountByRow[row] = visibleCount
            row += 1
        }
        markAllRowsDirty()
    }

    private var spawnModulo: Int {
        let density = max(configuration.rainDensity, MatrixScreenSaverOptions.minimumRainDensity)
        let baseSpawnModulo = (150.0 / density) / Double(max(columns, 1))
        return max(1, Int(ceil(baseSpawnModulo * frameRateScale)))
    }

    /// Spawns a new falling thread on one of the renderer layers.
    private func addRandomThread() {
        let baseSpeed = Self.baseSpeedTable.randomElement() ?? 6
        let stepInterval = max(1, Int((Double(baseSpeed) * frameRateScale).rounded()))
        let thread = RainThread(
            x: Int.random(in: 0..<columns),
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
        Self.glyphPool.randomElement() ?? UnicodeScalar("0")
    }

    /// Returns a random ASCII numeral for the startup number scene.
    private func randomNumberGlyph() -> UnicodeScalar {
        UnicodeScalar(48 + Int.random(in: 0..<10)) ?? UnicodeScalar("0")
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
