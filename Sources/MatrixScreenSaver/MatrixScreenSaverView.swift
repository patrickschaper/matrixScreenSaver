import AppKit
import ScreenSaver

@objc(MatrixScreenSaverView)
final class MatrixScreenSaverView: ScreenSaverView {
    private static let terminalTitle = "cxxmatrix"
    private static let nativeRenderer = NativeMatrixRenderer()
    private static let defaults: ScreenSaverDefaults = {
        let moduleName = Bundle(for: MatrixScreenSaverView.self).bundleIdentifier ?? "MatrixScreenSaver"
        guard let defaults = ScreenSaverDefaults(forModuleWithName: moduleName) else {
            fatalError("Unable to create ScreenSaverDefaults for \(moduleName)")
        }
        MatrixScreenSaverOptions.registerDefaults(in: defaults)
        return defaults
    }()
    private static let fallbackReferenceSize = NSSize(width: 1280, height: 832)
    private static let referenceTerminalFontSize: CGFloat = 11
    private static let titlebarHeight: CGFloat = 44
    private static let contentPadding: CGFloat = 18
    private static let windowCornerRadius: CGFloat = 18
    private static let terminalCornerRadius: CGFloat = 10

    private static let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.02, alpha: 1.0),
        NSColor(calibratedRed: 0.01, green: 0.01, blue: 0.01, alpha: 1.0),
    ])

    private static let titlebarGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.16, alpha: 0.98),
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 0.98),
    ])

    private var animationActive = false
    private var terminalSize: TerminalSize?
    private var hasLoggedFirstDraw = false
    private var geometrySyncInProgress = false

    private var windowRect = NSRect.zero
    private var titlebarRect = NSRect.zero
    private var terminalRect = NSRect.zero
    private var cellWidth: CGFloat = 10
    private var lineHeight: CGFloat = 22
    private var regularFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
    private var titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private var textInsetY: CGFloat = 2
    private var colorCache: [TerminalColor: NSColor] = [:]
    private var nativeRegularGlyphsByLevel: [[UnicodeScalar: CGImage]] = []
    private var nativeBoldGlyphsByLevel: [[UnicodeScalar: CGImage]] = []
    private var nativeDiffuseColorsByLevel: [CGColor] = []
    private var nativeFrameContext: CGContext?
    private var nativeFrameSize = CGSize.zero
    private var saverOptions = MatrixScreenSaverOptions()
    private lazy var optionsSheetController = MatrixScreenSaverOptionsSheetController(owner: self)
    private let debugIdentifier = String(UUID().uuidString.prefix(8))

    override var isOpaque: Bool {
        true
    }

    override var hasConfigureSheet: Bool {
        true
    }

    override var configureSheet: NSWindow? {
        optionsSheetController.prepare(using: saverOptions)
        return optionsSheetController.configureSheet()
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayout()
    }

    override var frame: NSRect {
        didSet {
            guard !geometrySyncInProgress else {
                return
            }
            updateLayout()
        }
    }

    override func layout() {
        super.layout()
        updateLayout()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        adoptContainerBoundsIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        adoptContainerBoundsIfNeeded()
    }

    override func startAnimation() {
        super.startAnimation()
        animationActive = true
        NSLog("MatrixScreenSaver startAnimation bounds=%@", NSStringFromRect(bounds))
        appendDebugLog("[\(debugIdentifier)] startAnimation bounds=\(NSStringFromRect(bounds))")
        updateLayout()
        Self.nativeRenderer.start()
    }

    override func stopAnimation() {
        super.stopAnimation()
        animationActive = false
        NSLog("MatrixScreenSaver stopAnimation")
        Self.nativeRenderer.stop()
    }

    override func animateOneFrame() {
        super.animateOneFrame()
        Self.nativeRenderer.advance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if !hasLoggedFirstDraw {
            hasLoggedFirstDraw = true
            NSLog("MatrixScreenSaver draw bounds=%@", NSStringFromRect(bounds))
        }
        drawBackground()
        drawWindow()
        drawTitlebar()
        drawTerminal()
    }

    private func commonInit() {
        autoresizingMask = [.width, .height]
        translatesAutoresizingMaskIntoConstraints = true
        NSLog("MatrixScreenSaver init frame=%@ preview=%d", NSStringFromRect(frame), isPreview)
        appendDebugLog("[\(debugIdentifier)] init frame=\(NSStringFromRect(frame)) preview=\(isPreview)")
        saverOptions = Self.loadSaverOptions()
        applySaverOptions(saverOptions, persist: false, restartAnimation: false)
        updateLayout()
        needsDisplay = true
    }

    private func adoptContainerBoundsIfNeeded() {
        normalizeHostGeometryIfNeeded()
    }

    private func updateLayout() {
        normalizeHostGeometryIfNeeded()

        let canvasBounds = NSRect(origin: .zero, size: bounds.size)
        guard canvasBounds.width > 20, canvasBounds.height > 20 else {
            return
        }
        let renderBaseSize = preferredRenderBaseSize(for: canvasBounds.size)

        terminalRect = canvasBounds.integral

        var expandedWindowRect = terminalRect.insetBy(dx: -Self.contentPadding, dy: -Self.contentPadding)
        expandedWindowRect.size.height += Self.titlebarHeight
        windowRect = expandedWindowRect.integral

        titlebarRect = NSRect(
            x: windowRect.minX,
            y: windowRect.maxY - Self.titlebarHeight,
            width: windowRect.width,
            height: Self.titlebarHeight
        ).integral

        let fontSize = preferredTerminalFontSize(for: renderBaseSize)
        regularFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

        lineHeight = max(12, round(fontSize * 1.35))
        let characterWidth = ceil(("W" as NSString).size(withAttributes: [.font: regularFont]).width + 1)
        cellWidth = max(7, characterWidth)
        textInsetY = max(0, floor((lineHeight - regularFont.pointSize) / 2) - 1)
        rebuildNativeGlyphCache()
        rebuildNativeDiffuseColors()

        let nextSize = TerminalSize(
            columns: max(24, Int(floor(renderBaseSize.width / cellWidth))),
            rows: max(12, Int(floor(renderBaseSize.height / lineHeight)))
        )
        rebuildNativeFrameContext(for: nextSize)

        if nextSize != terminalSize {
            terminalSize = nextSize
            NSLog("MatrixScreenSaver layout columns=%d rows=%d bounds=%@", nextSize.columns, nextSize.rows, NSStringFromRect(bounds))
            appendDebugLog("[\(debugIdentifier)] layout columns=\(nextSize.columns) rows=\(nextSize.rows) bounds=\(NSStringFromRect(bounds)) terminalRect=\(NSStringFromRect(terminalRect))")
            Self.nativeRenderer.resize(to: nextSize)
        }

        markDisplayDirty()
    }

    private func markDisplayDirty() {
        needsDisplay = true
    }

    private func drawBackground() {
        let canvasBounds = NSRect(origin: .zero, size: bounds.size)

        if let gradient = Self.backgroundGradient {
            gradient.draw(in: canvasBounds, angle: 90)
        } else {
            NSColor.black.setFill()
            canvasBounds.fill()
        }

        let glowRect = NSRect(
            x: canvasBounds.midX - canvasBounds.width * 0.22,
            y: canvasBounds.maxY - canvasBounds.height * 0.28,
            width: canvasBounds.width * 0.44,
            height: canvasBounds.height * 0.25
        )
        let glowPath = NSBezierPath(ovalIn: glowRect)
        NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.38, alpha: 0.08).setFill()
        glowPath.fill()
    }

    private func drawWindow() {
        let path = NSBezierPath(
            roundedRect: windowRect,
            xRadius: Self.windowCornerRadius,
            yRadius: Self.windowCornerRadius
        )

        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.04, alpha: 0.96).setFill()
        path.fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTitlebar() {
        let clipPath = NSBezierPath(
            roundedRect: titlebarRect,
            xRadius: Self.windowCornerRadius,
            yRadius: Self.windowCornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        if let gradient = Self.titlebarGradient {
            gradient.draw(in: titlebarRect, angle: 90)
        } else {
            NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.14, alpha: 1.0).setFill()
            titlebarRect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
        NSRect(x: titlebarRect.minX, y: titlebarRect.minY, width: titlebarRect.width, height: 1).fill()

        let lightColors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1.0),
            NSColor(calibratedRed: 0.996, green: 0.737, blue: 0.18, alpha: 1.0),
            NSColor(calibratedRed: 0.157, green: 0.784, blue: 0.251, alpha: 1.0),
        ]

        for (index, color) in lightColors.enumerated() {
            let rect = NSRect(
                x: titlebarRect.minX + 16 + CGFloat(index * 20),
                y: titlebarRect.midY - 6,
                width: 12,
                height: 12
            )
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 0.9),
            .paragraphStyle: paragraph,
        ]
        let titleRect = NSRect(
            x: titlebarRect.minX + 80,
            y: titlebarRect.minY + 13,
            width: titlebarRect.width - 160,
            height: 18
        )
        (Self.terminalTitle as NSString).draw(in: titleRect, withAttributes: attributes)
    }

    private func drawTerminal() {
        let terminalPath = NSBezierPath(
            roundedRect: terminalRect,
            xRadius: Self.terminalCornerRadius,
            yRadius: Self.terminalCornerRadius
        )

        NSColor.black.setFill()
        terminalPath.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.03).setStroke()
        terminalPath.lineWidth = 1
        terminalPath.stroke()

        guard let localTerminalSize = terminalSize else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        terminalPath.addClip()
        drawNativeTerminal(localTerminalSize)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawNativeTerminal(_ localTerminalSize: TerminalSize) {
        let visibleRows = min(localTerminalSize.rows, Self.nativeRenderer.rows)
        let visibleColumns = min(localTerminalSize.columns, Self.nativeRenderer.columns)
        guard visibleRows > 0, visibleColumns > 0 else {
            return
        }
        guard
            let context = NSGraphicsContext.current?.cgContext,
            let frameContext = nativeFrameContext
        else {
            return
        }

        let frameBounds = CGRect(origin: .zero, size: nativeFrameSize)
        frameContext.clear(frameBounds)

        var row = 0
        while row < visibleRows {
            guard Self.nativeRenderer.visibleCount(in: row) > 0 else {
                row += 1
                continue
            }

            let baseY = nativeFrameSize.height - (CGFloat(row + 1) * lineHeight)
            var column = 0
            while column < visibleColumns {
                let cell = Self.nativeRenderer[row, column]
                guard cell.isVisible else {
                    column += 1
                    continue
                }

                let x = CGFloat(column) * cellWidth
                let cellRect = CGRect(x: x, y: baseY, width: cellWidth, height: lineHeight)
                if cell.backgroundLevel > 0, cell.backgroundLevel < nativeDiffuseColorsByLevel.count {
                    frameContext.setFillColor(nativeDiffuseColorsByLevel[cell.backgroundLevel])
                    frameContext.fill(cellRect)
                }
                guard let glyph = nativeGlyphImage(for: cell) else {
                    column += 1
                    continue
                }
                frameContext.draw(glyph, in: cellRect)
                column += 1
            }
            row += 1
        }

        guard let image = frameContext.makeImage() else {
            return
        }

        let drawRect = CGRect(
            x: terminalRect.minX,
            y: terminalRect.minY,
            width: terminalRect.width,
            height: terminalRect.height
        )
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(image, in: drawRect)
        context.restoreGState()
    }

    private func rebuildNativeGlyphCache() {
        let palette = Self.nativeRenderer.levelColors
        nativeRegularGlyphsByLevel = makeNativeGlyphCaches(palette: palette, font: regularFont)
        nativeBoldGlyphsByLevel = makeNativeGlyphCaches(palette: palette, font: boldFont)
    }

    private func rebuildNativeDiffuseColors() {
        let palette = Self.nativeRenderer.levelColors
        let denominator = max(CGFloat(palette.count - 1), 1)
        nativeDiffuseColorsByLevel = palette.enumerated().map { index, terminalColor in
            let intensity = CGFloat(index) / denominator
            let alpha = 0.03 + (intensity * 0.14)
            return color(for: terminalColor).withAlphaComponent(alpha).cgColor
        }
    }

    private func makeNativeGlyphCaches(
        palette: [TerminalColor],
        font: NSFont
    ) -> [[UnicodeScalar: CGImage]] {
        var caches: [[UnicodeScalar: CGImage]] = Array(repeating: [:], count: palette.count)
        for level in palette.indices {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color(for: palette[level]),
            ]
            caches[level].reserveCapacity(NativeMatrixRenderer.supportedScalars.count)
            for scalar in NativeMatrixRenderer.supportedScalars {
                guard let image = makeNativeGlyphImage(for: scalar, attributes: attributes) else {
                    continue
                }
                caches[level][scalar] = image
            }
        }
        return caches
    }

    private func makeNativeGlyphImage(
        for scalar: UnicodeScalar,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGImage? {
        let pixelWidth = max(Int(ceil(cellWidth)), 1)
        let pixelHeight = max(Int(ceil(lineHeight)), 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = NSSize(width: cellWidth, height: lineHeight)
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        let text = String(scalar)
        let textSize = (text as NSString).size(withAttributes: attributes)
        let point = NSPoint(
            x: max(0, floor((cellWidth - textSize.width) / 2)),
            y: textInsetY
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.clear(CGRect(origin: .zero, size: CGSize(width: cellWidth, height: lineHeight)))
        (text as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.cgImage
    }

    private func nativeGlyphImage(for cell: NativeMatrixRenderer.RenderCell) -> CGImage? {
        let caches = cell.bold ? nativeBoldGlyphsByLevel : nativeRegularGlyphsByLevel
        guard !caches.isEmpty else {
            return nil
        }

        let level = min(max(cell.foregroundLevel, 0), caches.count - 1)
        return caches[level][cell.scalar]
    }

    private func rebuildNativeFrameContext(for size: TerminalSize) {
        let frameWidth = max(1, Int(ceil(CGFloat(size.columns) * cellWidth)))
        let frameHeight = max(1, Int(ceil(CGFloat(size.rows) * lineHeight)))
        let frameSize = CGSize(width: frameWidth, height: frameHeight)
        guard frameSize != nativeFrameSize || nativeFrameContext == nil else {
            return
        }

        guard let frameContext = CGContext(
            data: nil,
            width: frameWidth,
            height: frameHeight,
            bitsPerComponent: 8,
            bytesPerRow: frameWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            nativeFrameContext = nil
            nativeFrameSize = .zero
            return
        }

        frameContext.interpolationQuality = .none
        nativeFrameContext = frameContext
        nativeFrameSize = frameSize
    }

    private func color(for terminalColor: TerminalColor) -> NSColor {
        if let cached = colorCache[terminalColor] {
            return cached
        }

        let color = NSColor(
            calibratedRed: CGFloat(terminalColor.red) / 255,
            green: CGFloat(terminalColor.green) / 255,
            blue: CGFloat(terminalColor.blue) / 255,
            alpha: 1.0
        )
        colorCache[terminalColor] = color
        return color
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(upper, max(lower, value))
    }

    private func preferredTerminalFontSize(for hostSize: NSSize) -> CGFloat {
        let referenceSize = Self.largestScreenReferenceSize()
        let referenceArea = max(referenceSize.width * referenceSize.height, 1)
        let hostArea = max(hostSize.width * hostSize.height, 1)
        let areaRatio = Double(max(hostArea / referenceArea, 0.01))
        let fontScale = CGFloat(pow(areaRatio, 0.25))

        return clamp(Self.referenceTerminalFontSize * fontScale, lower: 9, upper: 18)
    }

    private func preferredRenderBaseSize(for hostSize: NSSize) -> NSSize {
        let referenceSize = Self.largestScreenReferenceSize()
        return NSSize(
            width: max(hostSize.width, referenceSize.width),
            height: max(hostSize.height, referenceSize.height)
        )
    }

    private static func largestScreenReferenceSize() -> NSSize {
        let screenSizes = NSScreen.screens.map(\.frame.size).filter { $0.width > 20 && $0.height > 20 }
        guard !screenSizes.isEmpty else {
            return fallbackReferenceSize
        }

        let width = screenSizes.reduce(fallbackReferenceSize.width) { max($0, $1.width) }
        let height = screenSizes.reduce(fallbackReferenceSize.height) { max($0, $1.height) }
        return NSSize(width: width, height: height)
    }

    func applySaverOptionsFromSheet(_ options: MatrixScreenSaverOptions) {
        applySaverOptions(options, persist: true, restartAnimation: animationActive)
    }

    private func applySaverOptions(_ options: MatrixScreenSaverOptions, persist: Bool, restartAnimation: Bool) {
        let sanitizedOptions = options.sanitized()
        saverOptions = sanitizedOptions

        if persist {
            sanitizedOptions.save(to: Self.defaults)
        }

        if restartAnimation {
            stopAnimation()
        }

        Self.nativeRenderer.updateConfiguration(sanitizedOptions.rendererConfiguration())
        animationTimeInterval = Self.nativeRenderer.preferredAnimationTimeInterval

        updateLayout()

        if restartAnimation {
            startAnimation()
        } else {
            markDisplayDirty()
        }
    }

    private static func loadSaverOptions() -> MatrixScreenSaverOptions {
        MatrixScreenSaverOptions.load(from: defaults)
    }

    private func normalizeHostGeometryIfNeeded() {
        guard !geometrySyncInProgress else {
            return
        }

        let targetSize = preferredHostSize()

        geometrySyncInProgress = true
        defer { geometrySyncInProgress = false }

        if bounds.origin != .zero {
            NSLog("MatrixScreenSaver normalizing bounds origin=%@", NSStringFromPoint(bounds.origin))
            setBoundsOrigin(.zero)
        }

        if shouldSyncBoundsSize(to: targetSize) {
            NSLog("MatrixScreenSaver syncing bounds size=%@", NSStringFromSize(targetSize))
            setBoundsSize(targetSize)
        }

        let targetFrame = NSRect(origin: .zero, size: targetSize)
        if frame.origin != targetFrame.origin || frame.size != targetFrame.size {
            NSLog("MatrixScreenSaver syncing frame=%@", NSStringFromRect(targetFrame))
            frame = targetFrame
        }
    }

    private func preferredHostSize() -> NSSize {
        let externalContentViewSize: NSSize?
        if let contentView = window?.contentView, contentView !== self {
            externalContentViewSize = contentView.bounds.size
        } else {
            externalContentViewSize = nil
        }

        let candidates: [NSSize?] = [
            externalContentViewSize,
            superview?.bounds.size,
            bounds.size,
            frame.size,
            window.map { $0.contentRect(forFrameRect: $0.frame).size },
            window?.screen?.frame.size,
        ]

        for candidate in candidates {
            guard let candidate, candidate.width > 20, candidate.height > 20 else {
                continue
            }
            return candidate
        }

        return frame.size
    }

    private func shouldSyncBoundsSize(to targetSize: NSSize) -> Bool {
        guard bounds.width > 20, bounds.height > 20 else {
            return true
        }

        let widthDelta = abs(bounds.width - targetSize.width)
        let heightDelta = abs(bounds.height - targetSize.height)

        return (widthDelta / max(targetSize.width, 1)) > 0.05 ||
            (heightDelta / max(targetSize.height, 1)) > 0.05
    }
}

private let debugLogQueue = DispatchQueue(label: "MatrixScreenSaver.debug.log")

func appendDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) \(message)\n"
    let logURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/MatrixScreenSaver-debug.log")

    debugLogQueue.async {
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: logURL.path) {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
                return
            }

            guard let handle = FileHandle(forWritingAtPath: logURL.path) else {
                NSLog("MatrixScreenSaver debug log open failed at %@", logURL.path)
                return
            }

            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } catch {
            NSLog("MatrixScreenSaver debug log write failed: %@", error.localizedDescription)
        }
    }
}
