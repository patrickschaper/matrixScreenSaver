import Foundation

final class NativeMatrixRenderer {
    struct Configuration: Equatable {
        var numberSceneEnabled = true
        var twinkleEnabled = true
        var diffuseEnabled = true
        var rainDensity = 1.0
        var frameRate = 25.0
        var errorRate = 1.0

        func sanitized() -> Configuration {
            Configuration(
                numberSceneEnabled: numberSceneEnabled,
                twinkleEnabled: twinkleEnabled,
                diffuseEnabled: diffuseEnabled,
                rainDensity: max(rainDensity, MatrixScreenSaverOptions.minimumRainDensity),
                frameRate: min(max(frameRate, MatrixScreenSaverOptions.minimumFrameRate), MatrixScreenSaverOptions.maximumFrameRate),
                errorRate: max(errorRate, MatrixScreenSaverOptions.minimumErrorRate)
            )
        }
    }

    struct RenderCell {
        var scalar: UnicodeScalar = Self.blankScalar
        var foregroundLevel: Int = 0
        var backgroundLevel: Int = 0
        var bold = false

        static let blankScalar = UnicodeScalar(" ")

        var isVisible: Bool {
            scalar != Self.blankScalar && foregroundLevel > 0
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
        case numberIntro
        case rainForever
    }

    private struct Layer {
        var columns = 0
        var rows = 0
        var content: [LayerCell] = []
        var threads: [RainThread] = []

        mutating func resize(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
            content = Array(repeating: LayerCell(), count: columns * rows)
            threads.removeAll(keepingCapacity: false)
        }

        mutating func clear() {
            content = Array(repeating: LayerCell(), count: columns * rows)
            threads.removeAll(keepingCapacity: false)
        }

        subscript(row: Int, column: Int) -> LayerCell {
            get { content[(row * columns) + column] }
            set { content[(row * columns) + column] = newValue }
        }

        mutating func addThread(_ thread: RainThread) {
            threads.append(thread)
        }

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
    private var layers = [Layer(), Layer(), Layer()]
    private var renderCells: [RenderCell] = []
    private var visibleCountByRow: [Int] = []
    private var lastUpdateTime = Date.timeIntervalSinceReferenceDate
    private var pendingSimulationSteps = 0.0
    private var running = false
    private var now = 100
    private var frameIndex = 0
    private var activeScene: Scene = .numberIntro
    private var sceneFrameIndex = 0

    subscript(row: Int, column: Int) -> RenderCell {
        renderCells[(row * columns) + column]
    }

    func visibleCount(in row: Int) -> Int {
        guard row >= 0, row < visibleCountByRow.count else {
            return 0
        }
        return visibleCountByRow[row]
    }

    var preferredAnimationTimeInterval: TimeInterval {
        1.0 / max(configuration.frameRate, MatrixScreenSaverOptions.minimumFrameRate)
    }

    func start() {
        running = true
        lastUpdateTime = Date.timeIntervalSinceReferenceDate
        pendingSimulationSteps = 0.0
        if columns > 0, rows > 0 {
            resetLayers()
            beginSceneSequence()
        }
    }

    func stop() {
        running = false
    }

    func resize(to size: TerminalSize) {
        columns = max(size.columns, 1)
        rows = max(size.rows, 1)

        renderCells = Array(repeating: RenderCell(), count: columns * rows)
        visibleCountByRow = Array(repeating: 0, count: rows)
        for index in layers.indices {
            layers[index].resize(columns: columns, rows: rows)
        }

        lastUpdateTime = Date.timeIntervalSinceReferenceDate
        pendingSimulationSteps = 0.0
        beginSceneSequence()
    }

    func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration.sanitized()
        lastUpdateTime = Date.timeIntervalSinceReferenceDate
        pendingSimulationSteps = 0.0
        if !running, columns > 0, rows > 0 {
            resetLayers()
            beginSceneSequence()
        } else if columns > 0, rows > 0, activeScene == .rainForever {
            constructRenderContent()
        }
    }

    func advance() {
        guard running, columns > 0, rows > 0 else {
            return
        }

        let nowTime = Date.timeIntervalSinceReferenceDate
        let elapsed = nowTime - lastUpdateTime
        lastUpdateTime = nowTime

        pendingSimulationSteps += elapsed * configuration.frameRate
        let availableSteps = Int(pendingSimulationSteps.rounded(.down))
        guard availableSteps > 0 else {
            return
        }

        let steps = min(availableSteps, 5)
        pendingSimulationSteps -= Double(steps)

        for _ in 0..<steps {
            stepFrame()
        }
    }

    private func stepFrame() {
        switch activeScene {
        case .numberIntro:
            stepNumberIntroFrame()
        case .rainForever:
            stepRainFrame()
        }
    }

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

    private func stepNumberIntroFrame() {
        populateNumberIntroFrame(stripe: currentNumberIntroStripe)
        now += 1
        sceneFrameIndex += 1
        if sceneFrameIndex >= Self.totalNumberIntroFrames {
            activeScene = .rainForever
        }
    }

    private var currentNumberIntroStripe: Int {
        let stripeIndex = min(sceneFrameIndex / Self.numberIntroFramesPerStripe, Self.numberIntroStripePeriods.count - 1)
        return Self.numberIntroStripePeriods[stripeIndex]
    }

    private static var totalNumberIntroFrames: Int {
        numberIntroStripePeriods.count * numberIntroFramesPerStripe
    }

    private func beginSceneSequence() {
        sceneFrameIndex = 0
        now = 100
        frameIndex = 0

        guard columns > 0, rows > 0 else {
            activeScene = configuration.numberSceneEnabled ? .numberIntro : .rainForever
            return
        }

        if configuration.numberSceneEnabled {
            activeScene = .numberIntro
            populateNumberIntroFrame(stripe: currentNumberIntroStripe)
            sceneFrameIndex = min(1, Self.totalNumberIntroFrames)
        } else {
            activeScene = .rainForever
            stepRainFrame()
        }
    }

    private func resetLayers() {
        for index in layers.indices {
            layers[index].clear()
        }
    }

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
    }

    private var spawnModulo: Int {
        let density = max(configuration.rainDensity, MatrixScreenSaverOptions.minimumRainDensity)
        let baseSpawnModulo = (150.0 / density) / Double(max(columns, 1))
        return max(1, Int(ceil(baseSpawnModulo * frameRateScale)))
    }

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

    private func constructRenderContent() {
        if renderCells.count != columns * rows {
            renderCells = Array(repeating: Self.blankRenderCell, count: columns * rows)
        }
        if visibleCountByRow.count != rows {
            visibleCountByRow = Array(repeating: 0, count: rows)
        }

        let layer0 = layers[0].content
        let layer1 = layers[1].content
        let layer2 = layers[2].content
        let levelCount = levelColors.count

        var row = 0
        while row < rows {
            let rowOffset = row * columns
            var visibleCount = 0
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
                    renderCells[index] = Self.blankRenderCell
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
                var level = Int(floor(fractionalLevel))
                if Double.random(in: 0...1) > fractionalLevel - Double(level) {
                    level += 1
                }
                level = min(level, levelCount - 1)

                guard level > 0 else {
                    renderCells[index] = Self.blankRenderCell
                    column += 1
                    continue
                }

                let backgroundLevel: Int
                if configuration.diffuseEnabled, level > 1 {
                    backgroundLevel = max(1, Int((Double(level) * 0.35).rounded()))
                } else {
                    backgroundLevel = 0
                }

                renderCells[index] = RenderCell(
                    scalar: sourceCell.scalar,
                    foregroundLevel: level,
                    backgroundLevel: min(backgroundLevel, levelCount - 1),
                    bold: (sourceCell.flags & Self.disableBoldFlag) == 0 && sourceCell.stage > 0.5
                )
                visibleCount += 1
                column += 1
            }
            visibleCountByRow[row] = visibleCount
            row += 1
        }
    }

    private func randomGlyph() -> UnicodeScalar {
        Self.glyphPool.randomElement() ?? UnicodeScalar("0")
    }

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

    private func interpolate(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * value
    }

    private static func color2index(_ red: Double, _ green: Double, _ blue: Double, levels: Int) -> Int {
        let r = Int(round(red * Double(levels - 1)))
        let g = Int(round(green * Double(levels - 1)))
        let b = Int(round(blue * Double(levels - 1)))
        return 16 + (r * levels + g) * levels + b
    }

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
