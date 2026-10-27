import AppKit
import ScreenSaver

@objc(MatrixScreenSaverView)
final class MatrixScreenSaverView: ScreenSaverView {
    private static let terminalTitle = "cxxmatrix"
    private static let screenSaverWillStopNotification = Notification.Name("com.apple.screensaver.willstop")
    private static let screenSaverDidStopNotification = Notification.Name("com.apple.screensaver.didstop")
    /// Keeps saver preferences shared even when this view is compiled into a different host.
    static let defaults: ScreenSaverDefaults = {
        let moduleName = "dev.patsch.MatrixScreenSaver"
        guard let defaults = ScreenSaverDefaults(forModuleWithName: moduleName) else {
            fatalError("Unable to create ScreenSaverDefaults for \(moduleName)")
        }
        MatrixScreenSaverOptions.registerDefaults(in: defaults)
        return defaults
    }()
    private static let titlebarHeight: CGFloat = 44
    private static let contentPadding: CGFloat = 18
    private static let windowCornerRadius: CGFloat = 18
    private static let terminalCornerRadius: CGFloat = 10
    private static let nativeColorSpace = CGColorSpaceCreateDeviceRGB()
    private static let nativeBitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )

    private static let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.02, alpha: 1.0),
        NSColor(calibratedRed: 0.01, green: 0.01, blue: 0.01, alpha: 1.0),
    ])

    private static let titlebarGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.16, alpha: 0.98),
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 0.98),
    ])

    private var animationActive = false
    /// Whether the wallpaper host has suspended the framework timer while preserving renderer state.
    private var wallpaperAnimationPaused = false

    /// Enables coordinated scenes while the wallpaper app owns system suspension handling.
    /// Set before starting animation; ordinary saver and preview hosts keep the default.
    var isWallpaperHost = false

    /// Lets the wallpaper's sole animation session continue while a saver covers its windows.
    var rendersWallpaperWhileHidden = false

    private var wallpaperFrameReader: WallpaperFrameReader?
    private var sharedWallpaperImage: CGImage?
    private var sharedFrameBuffer: SharedWallpaperFrame?
    private var publishedWallpaperImage: CGImage?
    /// Full-resolution scene base, reused while only terminal content changes.
    private var wallpaperSceneBase: CGImage?
    /// Backing-resolution scanlines avoid repainting hundreds of tall stripes each frame.
    private var wallpaperScanLines: CGImage?
    /// GPU resources are display-local and discarded with the cached visual layers.
    private var wallpaperCompositor: SharedWallpaperCompositor?
    /// Retains an unchanged cursor raster within the current layout and backing-scale epoch.
    private var wallpaperCursor: (column: Int, color: TerminalColor, image: CGImage)?
    /// Avoids retrying an unavailable or failed GPU until visual resources are rebuilt.
    private var wallpaperGPUAttempted = false
    /// Visual edits must publish even when the next simulation tick changes no cells.
    private var wallpaperFrameNeedsRedraw = true
    /// Keeps independent producer-loss playback independent across later option edits.
    private var nativePlaybackSynchronized = false
    /// Brief discovery precedes standalone startup so a warm wallpaper does not replay the intro.
    private var awaitingWallpaperUntil: TimeInterval?
    private var terminalSize: TerminalSize?
    private var hasLoggedFirstDraw = false
    private var geometrySyncInProgress = false
    private var firstHiddenFrameTime: TimeInterval = 0
    private static let hiddenFrameToleranceSeconds: TimeInterval = 5.0

    /// When `true`, the renderer start is deferred until the
    /// ``ScreenSyncCoordinator`` resolves a shared scene start time.
    private var pendingSync = false

    /// When `true`, a rain restart is deferred until the ``ScreenSyncCoordinator``
    /// resolves a shared restart time across all displays.
    private var pendingRestart = false

    /// When `true`, a scene transition is deferred until the ``ScreenSyncCoordinator``
    /// resolves a shared phase advance time across all displays.
    private var pendingSceneAdvance = false

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
    /// Glyph pixels depend on cell-derived font metrics and renderer content, not canvas size.
    private struct GlyphCacheKey: Equatable {
        let cellSize: CGSize
        let regularFont: NSFont
        let boldFont: NSFont
        let textInsetY: CGFloat
        let palette: [TerminalColor]
        let scalars: [UnicodeScalar]
    }
    /// Inputs used by the current regular and bold rasters.
    private var nativeGlyphCacheKey: GlyphCacheKey?
    private var nativeDiffuseColorsByLevel: [CGColor] = []
    private var nativeFrameBuffer: UnsafeMutableRawPointer?
    private var nativeFrameContext: CGContext?
    private var nativeFrameImage: CGImage?
    private var nativeFrameSize = CGSize.zero
    private let nativeRenderer = NativeMatrixRenderer()
    private var saverOptions = MatrixScreenSaverOptions()
    private var shouldReloadOptionsOnStart = true
    private var optionsSheetController: MatrixScreenSaverOptionsSheetController?
    private var hostWindowObservers: [NSObjectProtocol] = []
    private var screenSaverLifecycleObservers: [NSObjectProtocol] = []
    private let debugIdentifier = String(UUID().uuidString.prefix(8))
    private var showsWindowChrome: Bool { isPreview }

    /// Multi-screen sync is only needed when running inside ScreenSaverEngine
    /// in full-screen mode. In the preview host or System Settings thumbnail the
    /// 10-second sync window just delays the first scene unnecessarily.
    private static let isRunningInScreenSaverEngine: Bool = {
        let name = ProcessInfo.processInfo.processName
        return name == "ScreenSaverEngine" || name == "legacyScreenSaver"
    }()

    override var isOpaque: Bool {
        true
    }

    /// A stable seed derived from this screen's CGDirectDisplayID.
    /// Different physical displays return different values, giving each
    /// NativeMatrixRenderer instance an independent animation sequence.
    private var displaySeed: UInt64 {
        let id = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? UInt32 ?? 0
        return UInt64(id)
    }

    override var hasConfigureSheet: Bool {
        true
    }

    override var configureSheet: NSWindow? {
        saverOptions = Self.loadSaverOptions()
        let controller = makeOptionsSheetController()
        controller.prepare(using: saverOptions)
        return controller.configureSheet()
    }

    /// Creates the saver view for preview hosts and ScreenSaver.framework.
    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    /// Recreates the saver view from Interface Builder or archived state.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Keeps the cached layout in sync when AppKit changes the frame size.
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

    /// Recomputes the chrome and renderer layout during standard view layout passes.
    override func layout() {
        super.layout()
        updateLayout()
    }

    /// Adopts host geometry once the saver is attached to a container view.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        adoptContainerBoundsIfNeeded()
    }

    /// Stops animation work when the saver is detached from its superview.
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            handleHostDetachment(reason: "superview-detach")
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    /// Refreshes host-window observation after moving to a new window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHostWindowObservation()
        adoptContainerBoundsIfNeeded()
    }

    /// Tears down host-window observation when the saver leaves a window.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            handleHostDetachment(reason: "window-detach")
        }
        if window !== newWindow {
            stopObservingHostWindow()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Starts the renderer and host lifecycle observers for an active saver session.
    override func startAnimation() {
        super.startAnimation()
        animationActive = true
        firstHiddenFrameTime = 0
        if shouldReloadOptionsOnStart {
            saverOptions = Self.loadSaverOptions()
        }
        shouldReloadOptionsOnStart = true
        wallpaperFrameReader = !isWallpaperHost && !isPreview && Self.isRunningInScreenSaverEngine ? WallpaperFrameReader() : nil
        NSLog("MatrixScreenSaver startAnimation bounds=%@", NSStringFromRect(bounds))
        appendDebugLog("[\(debugIdentifier)] startAnimation bounds=\(NSStringFromRect(bounds))")
        updateScreenSaverLifecycleObservation()
        if let wallpaperFrameReader {
            nativeRenderer.stop()
            awaitingWallpaperUntil = ProcessInfo.processInfo.systemUptime + 1
            _ = wallpaperFrameReader.frame(displayID: UInt32(displaySeed), pointSize: bounds.size)
            needsDisplay = true
        } else {
            startNativeRenderer(synchronize: !isPreview && isWallpaperHost)
        }
    }

    /// Starts coordinated standalone playback, or an immediate fallback after a lost producer.
    private func startNativeRenderer(synchronize: Bool) {
        nativePlaybackSynchronized = synchronize
        let skipSyncDelay = !synchronize
        nativeRenderer.overrideSceneStartTime = nil
        nativeRenderer.overrideSceneContentStartTime = nil
        nativeRenderer.updateConfiguration(saverOptions.rendererConfiguration(isPreview: skipSyncDelay))
        animationTimeInterval = nativeRenderer.preferredAnimationTimeInterval
        updateLayout()
        nativeRenderer.seedOffset = displaySeed

        if !skipSyncDelay {
            // Register with the coordinator and defer renderer start until
            // all expected instances are ready (or the timeout elapses).
            let screenCount = NSScreen.screens.count
            // Wallpaper attaches every window before registration, so it needs no extra lead-in.
            ScreenSyncCoordinator.shared.register(ObjectIdentifier(self), expectedCount: screenCount,
                                                   startupDelay: isWallpaperHost ? 0 : ScreenSyncCoordinator.startDelay)
            pendingSync = true
            NSLog("MatrixScreenSaver sync registered (%d/%d)", ScreenSyncCoordinator.shared.registeredCount, screenCount)
        } else {
            pendingSync = false
            nativeRenderer.start()
        }
    }

    /// Stops the renderer and releases temporary rendering resources.
    override func stopAnimation() {
        let wasActive = animationActive
        animationActive = false
        wallpaperAnimationPaused = false
        pendingSync = false
        pendingRestart = false
        pendingSceneAdvance = false
        wallpaperFrameReader = nil
        sharedWallpaperImage = nil
        awaitingWallpaperUntil = nil
        nativeRenderer.stop()
        ScreenSyncCoordinator.shared.unregister(ObjectIdentifier(self))
        releaseRenderingResources()
        if wasActive {
            NSLog("MatrixScreenSaver stopAnimation")
            appendDebugLog("[\(debugIdentifier)] stopAnimation")
        }
        super.stopAnimation()
    }

    /// Advances the simulation and schedules redraws when the frame changed.
    override func animateOneFrame() {
        guard animationActive && !wallpaperAnimationPaused else {
            return
        }
        guard isHostWindowVisibleForAnimation || (isWallpaperHost && rendersWallpaperWhileHidden) else {
            // The wallpaper app owns resumption when desktop visibility changes.
            guard !isWallpaperHost else { return }
            let now = Date.timeIntervalSinceReferenceDate
            if firstHiddenFrameTime == 0 {
                firstHiddenFrameTime = now
            } else if now - firstHiddenFrameTime >= Self.hiddenFrameToleranceSeconds {
                handleHostDetachment(reason: "window-hidden")
            }
            return
        }
        firstHiddenFrameTime = 0

        if let wallpaperFrameReader {
            if let frame = wallpaperFrameReader.frame(displayID: UInt32(displaySeed), pointSize: bounds.size) {
                awaitingWallpaperUntil = nil
                if sharedWallpaperImage == nil {
                    nativeRenderer.stop()
                    ScreenSyncCoordinator.shared.excludeFromSynchronization(ObjectIdentifier(self))
                    pendingSync = false
                    pendingRestart = false
                    pendingSceneAdvance = false
                }
                if sharedWallpaperImage !== frame.image {
                    sharedWallpaperImage = frame.image
                    needsDisplay = true
                }
                return
            } else if sharedWallpaperImage != nil {
                sharedWallpaperImage = nil
                startNativeRenderer(synchronize: false)
            } else if let deadline = awaitingWallpaperUntil {
                guard ProcessInfo.processInfo.systemUptime >= deadline else { return }
                awaitingWallpaperUntil = nil
                startNativeRenderer(synchronize: true)
            }
        }

        // While waiting for multi-screen sync (either initial startup or rain restart),
        // poll the coordinator each frame. Once a shared start time is available,
        // apply it and start the renderer so all displays begin simultaneously.
        if pendingSync {
            let startTime: TimeInterval?
            if pendingRestart {
                startTime = ScreenSyncCoordinator.shared.resolvedRestartTime()
            } else {
                startTime = ScreenSyncCoordinator.shared.resolvedStartTime()
            }
            guard let time = startTime else {
                sharedFrameBuffer?.refresh()
                return
            }
            nativeRenderer.overrideSceneContentStartTime = pendingRestart
                ? ScreenSyncCoordinator.shared.restartContentTime
                : ScreenSyncCoordinator.shared.startContentTime
            pendingSync = false
            if pendingRestart {
                ScreenSyncCoordinator.shared.finishRestart(ObjectIdentifier(self))
                pendingRestart = false
                NSLog("MatrixScreenSaver restart resolved — restarting rain (startTime=%.2f)", time)
            } else {
                NSLog("MatrixScreenSaver sync resolved — starting renderer (startTime=%.2f)", time)
            }
            nativeRenderer.overrideSceneStartTime = time
            nativeRenderer.start()
        }

        // While waiting for a scene advance (Neo→Number, Number→Rain), poll the coordinator
        // each frame. Once all displays are ready, advance to the next scene.
        if pendingSceneAdvance {
            guard let _ = ScreenSyncCoordinator.shared.resolvedPhaseAdvanceTime() else {
                sharedFrameBuffer?.refresh()
                return
            }
            pendingSceneAdvance = false
            ScreenSyncCoordinator.shared.finishPhaseAdvance(ObjectIdentifier(self))
            nativeRenderer.advanceToNextScene()
            NSLog("MatrixScreenSaver phase advance resolved — transitioning to next scene")
        }

        super.animateOneFrame()
        let advanced = nativeRenderer.advance()
        if advanced {
            needsDisplay = true
        }
        publishWallpaperFrame(redraw: advanced)

        // After advance, check if the renderer has requested a restart
        if nativeRenderer.consumeRestartRequest() {
            ScreenSyncCoordinator.shared.requestRestart(ObjectIdentifier(self))
            pendingRestart = true
            pendingSync = true
        }

        // After advance, check if the renderer has completed a scene and needs to transition
        if nativeRenderer.consumeNeoSceneDone() {
            ScreenSyncCoordinator.shared.requestPhaseAdvance(ObjectIdentifier(self))
            pendingSceneAdvance = true
            NSLog("MatrixScreenSaver Neo scene complete — requesting phase advance")
        } else if nativeRenderer.consumeNumberSceneDone() {
            ScreenSyncCoordinator.shared.requestPhaseAdvance(ObjectIdentifier(self))
            pendingSceneAdvance = true
            NSLog("MatrixScreenSaver Number scene complete — requesting phase advance")
        }
    }

    /// Releases renderer resources when the saver view is torn down.
    deinit {
        appendDebugLog("[\(debugIdentifier)] deinit")
        animationActive = false
        nativeRenderer.stop()
        ScreenSyncCoordinator.shared.unregister(ObjectIdentifier(self))
        releaseRenderingResources()
    }

    /// Paints the full terminal-window scene for the current frame.
    override func draw(_ dirtyRect: NSRect) {
        if let image = sharedWallpaperImage ?? publishedWallpaperImage {
            NSGraphicsContext.current?.cgContext.draw(image, in: bounds)
            return
        }
        if awaitingWallpaperUntil != nil {
            NSColor.black.setFill()
            bounds.fill()
            return
        }
        drawScene()
    }

    private func drawScene() {
        if !hasLoggedFirstDraw {
            hasLoggedFirstDraw = true
            NSLog("MatrixScreenSaver draw bounds=%@", NSStringFromRect(bounds))
        }
        drawBackground()
        if showsWindowChrome {
            drawWindow()
        }
        drawTerminal()
        if showsWindowChrome {
            drawTitlebar()
        }
    }

    /// Applies one-time defaults and initial layout state for new instances.
    private func commonInit() {
        autoresizingMask = [.width, .height]
        translatesAutoresizingMaskIntoConstraints = true
        NSLog("MatrixScreenSaver init frame=%@ preview=%d", NSStringFromRect(frame), isPreview)
        appendDebugLog("[\(debugIdentifier)] init frame=\(NSStringFromRect(frame)) preview=\(isPreview)")
        saverOptions = Self.loadSaverOptions()
        applySaverOptions(saverOptions, persist: false, restartAnimation: false)
        shouldReloadOptionsOnStart = true
        needsDisplay = true
    }

    /// Gives the saver a chance to normalize host geometry after attachment.
    private func adoptContainerBoundsIfNeeded() {
        normalizeHostGeometryIfNeeded()
    }

    /// Recomputes geometry, fonts, and renderer resources for the current bounds.
    private func updateLayout() {
        normalizeHostGeometryIfNeeded()

        let canvasBounds = NSRect(origin: .zero, size: bounds.size)
        guard canvasBounds.width > 20, canvasBounds.height > 20 else {
            return
        }
        let hostSize = canvasBounds.size

        terminalRect = canvasBounds.integral
        windowRect = canvasBounds.integral

        titlebarRect = NSRect(
            x: windowRect.minX,
            y: windowRect.maxY - Self.titlebarHeight,
            width: windowRect.width,
            height: Self.titlebarHeight
        ).integral

        cellWidth = CGFloat(max(saverOptions.characterWidth, MatrixScreenSaverOptions.minimumCharacterWidth))
        lineHeight = CGFloat(max(saverOptions.characterHeight, MatrixScreenSaverOptions.minimumCharacterHeight))

        let fontSize = fittedTerminalFontSize(forCellWidth: cellWidth, cellHeight: lineHeight)
        regularFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

        textInsetY = max(0, floor((lineHeight - regularFont.pointSize) / 2) - 1)
        rebuildNativeGlyphCache()
        rebuildNativeDiffuseColors()

        let nextSize = TerminalSize(
            columns: max(24, Int(floor(hostSize.width / cellWidth))),
            rows: max(12, Int(floor(hostSize.height / lineHeight)))
        )
        rebuildNativeFrameContext(for: nextSize)

        if nextSize != terminalSize {
            terminalSize = nextSize
            NSLog("MatrixScreenSaver layout columns=%d rows=%d bounds=%@", nextSize.columns, nextSize.rows, NSStringFromRect(bounds))
            appendDebugLog("[\(debugIdentifier)] layout columns=\(nextSize.columns) rows=\(nextSize.rows) bounds=\(NSStringFromRect(bounds)) terminalRect=\(NSStringFromRect(terminalRect))")
            nativeRenderer.resize(to: nextSize)
        }

        markDisplayDirty()
        if sharedFrameBuffer != nil { _ = shareWallpaperFrames() }
    }

    /// Marks the saver view as needing display on the next run-loop turn.
    private func markDisplayDirty() {
        wallpaperSceneBase = nil
        wallpaperScanLines = nil
        wallpaperCompositor = nil
        wallpaperCursor = nil
        wallpaperGPUAttempted = false
        wallpaperFrameNeedsRedraw = true
        needsDisplay = true
    }

    /// Rebuilds full-resolution publication resources after a display scale change.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        markDisplayDirty()
        if sharedFrameBuffer != nil { _ = shareWallpaperFrames() }
    }

    /// Stops animation and frees resources once the host is no longer visible.
    private func handleHostDetachment(reason: String) {
        appendDebugLog("[\(debugIdentifier)] \(reason)")
        if animationActive {
            stopAnimation()
        } else {
            releaseRenderingResources()
        }
    }

    private var isHostWindowVisibleForAnimation: Bool {
        guard let window else {
            return superview != nil
        }
        return window.isVisible
    }

    /// Starts observing window notifications that indicate the saver left the host.
    private func updateHostWindowObservation() {
        stopObservingHostWindow()
        guard let window else {
            return
        }

        let notificationCenter = NotificationCenter.default
        hostWindowObservers = [
            notificationCenter.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: nil
            ) { [weak self] _ in
                guard let self, self.animationActive else {
                    return
                }
                if !window.isVisible && !self.isWallpaperHost {
                    self.handleHostDetachment(reason: "window-hidden")
                }
            },
            notificationCenter.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: nil
            ) { [weak self] _ in
                self?.handleHostDetachment(reason: "window-close")
            },
            notificationCenter.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: nil
            ) { [weak self] _ in
                self?.handleHostDetachment(reason: "window-miniaturize")
            },
        ]
    }

    /// Removes all host-window observers created for the current host session.
    private func stopObservingHostWindow() {
        guard !hostWindowObservers.isEmpty else {
            return
        }
        let notificationCenter = NotificationCenter.default
        for observer in hostWindowObservers {
            notificationCenter.removeObserver(observer)
        }
        hostWindowObservers.removeAll(keepingCapacity: false)
    }

    /// Starts observing distributed screen saver lifecycle notifications.
    private func updateScreenSaverLifecycleObservation() {
        stopObservingScreenSaverLifecycle()
        guard !isWallpaperHost else { return }

        let center = DistributedNotificationCenter.default()
        screenSaverLifecycleObservers = [
            center.addObserver(
                forName: Self.screenSaverWillStopNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self, self.animationActive else {
                    return
                }
                self.handleHostDetachment(reason: "screensaver-willstop")
            },
            center.addObserver(
                forName: Self.screenSaverDidStopNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self, self.animationActive else {
                    return
                }
                self.handleHostDetachment(reason: "screensaver-didstop")
            },
        ]
    }

    /// Removes the distributed screen saver lifecycle observers.
    private func stopObservingScreenSaverLifecycle() {
        guard !screenSaverLifecycleObservers.isEmpty else {
            return
        }
        let center = DistributedNotificationCenter.default()
        for observer in screenSaverLifecycleObservers {
            center.removeObserver(observer)
        }
        screenSaverLifecycleObservers.removeAll(keepingCapacity: false)
    }

    /// Releases transient rendering caches and host observation state.
    private func releaseRenderingResources() {
        stopSharingWallpaperFrames()
        stopObservingHostWindow()
        stopObservingScreenSaverLifecycle()
        releaseNativeFrameResources()
        terminalSize = nil
        nativeRegularGlyphsByLevel.removeAll(keepingCapacity: false)
        nativeGlyphCacheKey = nil
        nativeBoldGlyphsByLevel.removeAll(keepingCapacity: false)
        nativeDiffuseColorsByLevel.removeAll(keepingCapacity: false)
        colorCache.removeAll(keepingCapacity: false)
        optionsSheetController = nil
        hasLoggedFirstDraw = false
    }

    /// Paints the background outside the faux terminal window.
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

    /// Paints the outer terminal-window frame.
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

    /// Paints the faux titlebar chrome above the terminal content.
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

    /// Paints the clipped terminal surface and its rendered frame buffer.
    private func drawTerminal() {
        drawTerminalSurface()
        drawTerminalContent()
    }

    /// Paints the unchanged black surface and rounded border beneath terminal content.
    private func drawTerminalSurface() {
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
    }

    /// Paints changing cells, cursor, and scanlines in their original compositing order.
    private func drawTerminalContent() {

        guard let localTerminalSize = terminalSize else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let terminalPath = NSBezierPath(roundedRect: terminalRect,
            xRadius: Self.terminalCornerRadius, yRadius: Self.terminalCornerRadius)
        if sharedFrameBuffer == nil { terminalPath.addClip() }
        drawNativeTerminal(localTerminalSize)
        if sharedFrameBuffer != nil { terminalPath.addClip() }

        drawNativeCursor()

        NSGraphicsContext.restoreGraphicsState()

        if saverOptions.scanLinesIntensity > 0 {
            if let wallpaperScanLines {
                NSGraphicsContext.current?.cgContext.draw(wallpaperScanLines, in: bounds)
            } else {
                drawScanLines()
            }
        }
    }

    /// Bypasses the glyph bitmap so the Neo cursor remains visible in every intro phase.
    private func drawNativeCursor() {
        if let cursor = nativeRenderer.neoSceneCursor, cursor.visible {
            let palette = nativeRenderer.levelColors
            let level = min(max(palette.count / 2, 1), palette.count - 1)
            color(for: palette[level]).setFill()
            let x = terminalRect.minX + CGFloat(cursor.column) * cellWidth
            let m = CGFloat(NativeMatrixRenderer.contentMargin)
            let y = terminalRect.maxY - (m + 1) * lineHeight
            NSRect(x: x, y: y, width: cellWidth, height: lineHeight).fill()
        }

    }

    /// Overlays 1 px dark stripes every 2 px for a CRT scanline effect.
    private func drawScanLines() {
        let rect = showsWindowChrome ? terminalRect : bounds
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: saverOptions.scanLinesIntensity))
        if saverOptions.scanLinesVertical {
            var x = rect.minX + 1
            while x < rect.maxX {
                ctx.fill(CGRect(x: floor(x), y: rect.minY, width: 1, height: rect.height))
                x += 2
            }
        } else {
            var y = rect.minY + 1
            while y < rect.maxY {
                ctx.fill(CGRect(x: rect.minX, y: floor(y), width: rect.width, height: 1))
                y += 2
            }
        }
        ctx.restoreGState()
    }

    /// Repaints dirty rows once and snapshots the bitmap for CPU or GPU composition.
    private func nativeTerminalImage(_ localTerminalSize: TerminalSize) -> CGImage? {
        let visibleRows = min(localTerminalSize.rows, nativeRenderer.rows)
        let visibleColumns = min(localTerminalSize.columns, nativeRenderer.columns)
        guard visibleRows > 0, visibleColumns > 0 else {
            return nil
        }
        guard let frameContext = nativeFrameContext else { return nil }

        let hasDiffuseBackground = saverOptions.diffuseEnabled && !nativeDiffuseColorsByLevel.isEmpty

        var row = 0
        while row < visibleRows {
            guard nativeRenderer.isRowDirty(row) else {
                row += 1
                continue
            }

            let baseY = nativeFrameSize.height - (CGFloat(row + 1) * lineHeight)
            frameContext.clear(CGRect(x: 0, y: baseY, width: nativeFrameSize.width, height: lineHeight))

            guard nativeRenderer.visibleCount(in: row) > 0 else {
                row += 1
                continue
            }

            if hasDiffuseBackground {
                var column = 0
                while column < visibleColumns {
                    let backgroundLevel = nativeRenderer[row, column].backgroundLevel
                    guard backgroundLevel > 0, backgroundLevel < nativeDiffuseColorsByLevel.count else {
                        column += 1
                        continue
                    }

                    let runStart = column
                    column += 1
                    while column < visibleColumns, nativeRenderer[row, column].backgroundLevel == backgroundLevel {
                        column += 1
                    }

                    let x = CGFloat(runStart) * cellWidth
                    let width = CGFloat(column - runStart) * cellWidth
                    frameContext.setFillColor(nativeDiffuseColorsByLevel[backgroundLevel])
                    frameContext.fill(CGRect(x: x, y: baseY, width: width, height: lineHeight))
                }
            }

            var column = 0
            while column < visibleColumns {
                let cell = nativeRenderer[row, column]
                guard cell.hasForeground else {
                    column += 1
                    continue
                }

                let x = CGFloat(column) * cellWidth
                let cellRect = CGRect(x: x, y: baseY, width: cellWidth, height: lineHeight)
                guard let glyph = nativeGlyphImage(for: cell) else {
                    column += 1
                    continue
                }
                frameContext.draw(glyph, in: cellRect)
                column += 1
            }
            row += 1
        }

        frameContext.flush()
        nativeRenderer.clearDirtyRows()
        return frameContext.makeImage()
    }

    /// Presents the shared dirty-row raster through the unchanged native CPU reference path.
    private func drawNativeTerminal(_ localTerminalSize: TerminalSize) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = nativeTerminalImage(localTerminalSize) else { return }

        let drawRect = CGRect(
            x: terminalRect.minX,
            y: terminalRect.minY,
            width: terminalRect.width,
            height: terminalRect.height
        )
        context.saveGState()
        context.interpolationQuality = .none
        context.setAlpha(1.0)
        if sharedFrameBuffer != nil {
            // Only the edge bands need the expensive rounded coverage mask.
            let radius = min(Self.terminalCornerRadius, terminalRect.height / 2)
            context.saveGState()
            context.clip(to: terminalRect.insetBy(dx: 0, dy: radius))
            context.draw(image, in: drawRect)
            context.restoreGState()
            context.clip(to: [
                CGRect(x: terminalRect.minX, y: terminalRect.minY, width: terminalRect.width, height: radius),
                CGRect(x: terminalRect.minX, y: terminalRect.maxY - radius, width: terminalRect.width, height: radius),
            ])
            NSBezierPath(roundedRect: terminalRect, xRadius: Self.terminalCornerRadius,
                         yRadius: Self.terminalCornerRadius).addClip()
            context.draw(image, in: drawRect)
        } else {
            context.draw(image, in: drawRect)
        }
        context.restoreGState()
    }

    /// Retains glyph rasters across layout passes until their pixel-producing inputs change.
    private func rebuildNativeGlyphCache() {
        let palette = nativeRenderer.levelColors
        let key = GlyphCacheKey(cellSize: CGSize(width: cellWidth, height: lineHeight),
                                regularFont: regularFont, boldFont: boldFont, textInsetY: textInsetY,
                                palette: palette, scalars: nativeRenderer.supportedScalars)
        guard nativeGlyphCacheKey != key else { return }
        nativeRegularGlyphsByLevel = makeNativeGlyphCaches(palette: palette, font: regularFont)
        nativeBoldGlyphsByLevel = makeNativeGlyphCaches(palette: palette, font: boldFont)
        nativeGlyphCacheKey = key
    }

    /// Rebuilds the diffuse background fill palette used by the renderer.
    private func rebuildNativeDiffuseColors() {
        let palette = nativeRenderer.levelColors
        let denominator = max(CGFloat(palette.count - 1), 1)
        nativeDiffuseColorsByLevel = palette.enumerated().map { index, terminalColor in
            let intensity = CGFloat(index) / denominator
            let alpha = 0.06 + (intensity * 0.21)
            return color(for: terminalColor).withAlphaComponent(alpha).cgColor
        }
    }

    /// Builds per-level glyph images for all supported scalar values.
    private func makeNativeGlyphCaches(
        palette: [TerminalColor],
        font: NSFont
    ) -> [[UnicodeScalar: CGImage]] {
        var caches: [[UnicodeScalar: CGImage]] = Array(repeating: [:], count: palette.count)
        let scalars = nativeRenderer.supportedScalars
        for level in palette.indices {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color(for: palette[level]),
            ]
            caches[level].reserveCapacity(scalars.count)
            for scalar in scalars {
                guard let image = makeNativeGlyphImage(for: scalar, attributes: attributes) else {
                    continue
                }
                caches[level][scalar] = image
            }
        }
        return caches
    }

    /// Rasterizes a single glyph into a native Core Graphics image.
    private func makeNativeGlyphImage(
        for scalar: UnicodeScalar,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGImage? {
        let pixelWidth = max(Int(ceil(cellWidth)), 1)
        let pixelHeight = max(Int(ceil(lineHeight)), 1)
        guard let glyphContext = makeNativeBitmapContext(width: pixelWidth, height: pixelHeight) else {
            return nil
        }
        let graphicsContext = NSGraphicsContext(cgContext: glyphContext, flipped: false)

        glyphContext.clear(CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight)))

        // Full-block cursor: fill the entire cell with the foreground color so the
        // cursor is always exactly one character cell wide, regardless of font metrics.
        if scalar == UnicodeScalar(0x2588),
           let fgColor = attributes[.foregroundColor] as? NSColor {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            fgColor.setFill()
            NSRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)).fill()
            NSGraphicsContext.restoreGraphicsState()
            return glyphContext.makeImage()
        }

        let text = String(scalar)
        let textSize = (text as NSString).size(withAttributes: attributes)
        let point = NSPoint(
            x: max(0, floor((cellWidth - textSize.width) / 2)),
            y: textInsetY
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        (text as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        return glyphContext.makeImage()
    }

    /// Returns the cached glyph image for a rendered cell.
    private func nativeGlyphImage(for cell: NativeMatrixRenderer.RenderCell) -> CGImage? {
        let caches = cell.bold ? nativeBoldGlyphsByLevel : nativeRegularGlyphsByLevel
        guard !caches.isEmpty else {
            return nil
        }

        let level = min(max(cell.foregroundLevel, 0), caches.count - 1)
        return caches[level][cell.scalar]
    }

    /// Recreates the persistent frame buffer when the terminal grid size changes.
    private func rebuildNativeFrameContext(for size: TerminalSize) {
        let frameWidth = max(1, Int(ceil(CGFloat(size.columns) * cellWidth)))
        let frameHeight = max(1, Int(ceil(CGFloat(size.rows) * lineHeight)))
        let frameSize = CGSize(width: frameWidth, height: frameHeight)
        guard frameSize != nativeFrameSize || nativeFrameContext == nil || nativeFrameImage == nil else {
            return
        }

        releaseNativeFrameResources()

        let bytesPerRow = frameWidth * 4
        let bufferSize = bytesPerRow * frameHeight
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<UInt32>.alignment
        )
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)

        guard
            let frameContext = makeNativeBitmapContext(
                width: frameWidth,
                height: frameHeight,
                data: buffer,
                bytesPerRow: bytesPerRow
            ),
            let provider = CGDataProvider(
                dataInfo: nil,
                data: buffer,
                size: bufferSize,
                releaseData: { _, _, _ in }
            ),
            let frameImage = CGImage(
                width: frameWidth,
                height: frameHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: Self.nativeColorSpace,
                bitmapInfo: Self.nativeBitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            buffer.deallocate()
            return
        }

        nativeFrameBuffer = buffer
        nativeFrameContext = frameContext
        nativeFrameImage = frameImage
        nativeFrameSize = frameSize
    }

    /// Releases the persistent frame buffer and associated Core Graphics objects.
    private func releaseNativeFrameResources() {
        nativeFrameContext = nil
        nativeFrameImage = nil
        if let nativeFrameBuffer {
            nativeFrameBuffer.deallocate()
            self.nativeFrameBuffer = nil
        }
        nativeFrameSize = .zero
    }

    /// Creates a BGRA bitmap context for glyph or frame compositing.
    private func makeNativeBitmapContext(
        width: Int,
        height: Int,
        data: UnsafeMutableRawPointer? = nil,
        bytesPerRow: Int? = nil
    ) -> CGContext? {
        guard width > 0, height > 0 else {
            return nil
        }
        let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow ?? (width * 4),
            space: Self.nativeColorSpace,
            bitmapInfo: Self.nativeBitmapInfo.rawValue
        )
        context?.interpolationQuality = .none
        return context
    }

    /// Memoizes terminal palette colors as NSColor instances.
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

    /// Finds the largest font size that fits within the configured cell dimensions.
    private func fittedTerminalFontSize(forCellWidth cellWidth: CGFloat, cellHeight: CGFloat) -> CGFloat {
        let targetWidth = max(cellWidth, 1)
        let targetHeight = max(cellHeight, 1)
        var low: CGFloat = 1
        var high: CGFloat = max(targetHeight, 1)
        var best: CGFloat = 1

        for _ in 0..<16 {
            guard low <= high else {
                break
            }

            let mid = floor((((low + high) / 2) * 2)) / 2
            let font = NSFont.monospacedSystemFont(ofSize: max(mid, 1), weight: .medium)
            let measuredWidth = ceil(("W" as NSString).size(withAttributes: [.font: font]).width + 1)
            let measuredHeight = max(1, round(mid * 1.35))

            if measuredWidth <= targetWidth && measuredHeight <= targetHeight {
                best = max(mid, 1)
                low = mid + 0.5
            } else {
                high = mid - 0.5
            }
        }

        return best
    }

    /// Applies options coming back from the configure sheet.
    func applySaverOptionsFromSheet(_ options: MatrixScreenSaverOptions) {
        let restart = options.sanitized().requiresSceneRestart(comparedTo: saverOptions)
        applySaverOptions(options, persist: true, restartAnimation: animationActive && restart)
    }

    /// Applies host-persisted rendering options without resetting a coordinated wallpaper session.
    ///
    /// - Parameter options: Visual options that do not require a grid or scene rebuild.
    func applyWallpaperOptions(_ options: MatrixScreenSaverOptions) {
        applySaverOptions(options, persist: false, restartAnimation: false)
    }

    /// Offers the current wallpaper frame without copying or restarting its simulation.
    ///
    /// - Returns: A private shared-memory file, or nil if this host cannot publish it.
    func shareWallpaperFrames() -> URL? {
        guard isWallpaperHost, animationActive else { return nil }
        let scale = window?.backingScaleFactor ?? 1
        if sharedFrameBuffer?.pointSize != bounds.size || sharedFrameBuffer?.displayID != UInt32(displaySeed) ||
            sharedFrameBuffer?.pixelWidth != Int(ceil(bounds.width * scale)) ||
            sharedFrameBuffer?.pixelHeight != Int(ceil(bounds.height * scale)) {
            stopSharingWallpaperFrames()
            sharedFrameBuffer = try? SharedWallpaperFrame(displayID: UInt32(displaySeed), pointSize: bounds.size, scale: scale)
        }
        publishWallpaperFrame(redraw: publishedWallpaperImage == nil)
        return sharedFrameBuffer?.url
    }

    /// Unlinks producer storage while retaining the actual animation session.
    func stopSharingWallpaperFrames() {
        sharedFrameBuffer = nil
        publishedWallpaperImage = nil
        markDisplayDirty()
    }

    /// Builds rounded coverage at backing resolution without changing the CPU fallback geometry.
    private func makeWallpaperCompositor(for buffer: SharedWallpaperFrame) -> SharedWallpaperCompositor? {
        guard !showsWindowChrome, let base = wallpaperSceneBase,
              let context = makeNativeBitmapContext(width: buffer.pixelWidth, height: buffer.pixelHeight) else { return nil }
        context.scaleBy(x: CGFloat(buffer.pixelWidth) / bounds.width, y: CGFloat(buffer.pixelHeight) / bounds.height)
        context.clear(bounds)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: terminalRect, xRadius: Self.terminalCornerRadius,
                     yRadius: Self.terminalCornerRadius).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let mask = context.makeImage() else { return nil }
        return SharedWallpaperCompositor(base: base, mask: mask, scanLines: wallpaperScanLines, terminalSize: nativeFrameSize)
    }

    /// Rasterizes only the cursor layer; clipping and final layering remain on the GPU.
    private func wallpaperCursorImage(for buffer: SharedWallpaperFrame) -> CGImage? {
        guard let cursor = nativeRenderer.neoSceneCursor, cursor.visible else { return nil }
        let palette = nativeRenderer.levelColors
        let color = palette[min(max(palette.count / 2, 1), palette.count - 1)]
        if let cached = wallpaperCursor, cached.column == cursor.column, cached.color == color { return cached.image }
        guard let context = makeNativeBitmapContext(width: buffer.pixelWidth, height: buffer.pixelHeight) else { return nil }
        context.scaleBy(x: CGFloat(buffer.pixelWidth) / bounds.width, y: CGFloat(buffer.pixelHeight) / bounds.height)
        context.clear(bounds)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawNativeCursor()
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        wallpaperCursor = (cursor.column, color, image)
        return image
    }

    /// Renders the full canvas once at backing resolution only while a consumer needs it.
    private func publishWallpaperFrame(redraw: Bool) {
        guard let buffer = sharedFrameBuffer else { return }
        guard redraw || wallpaperFrameNeedsRedraw || publishedWallpaperImage == nil else { buffer.refresh(); return }
        if wallpaperSceneBase == nil,
           let context = makeNativeBitmapContext(width: buffer.pixelWidth, height: buffer.pixelHeight) {
            context.scaleBy(x: CGFloat(buffer.pixelWidth) / bounds.width, y: CGFloat(buffer.pixelHeight) / bounds.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            drawBackground()
            if showsWindowChrome { drawWindow() }
            drawTerminalSurface()
            NSGraphicsContext.restoreGraphicsState()
            wallpaperSceneBase = context.makeImage()
            if saverOptions.scanLinesIntensity > 0 {
                context.clear(bounds)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                drawScanLines()
                NSGraphicsContext.restoreGraphicsState()
                wallpaperScanLines = context.makeImage()
            }
        }
        var changedBands: [CGRect] = []
        if !wallpaperFrameNeedsRedraw, publishedWallpaperImage != nil, wallpaperSceneBase != nil,
           let terminalSize, nativeFrameSize.height > 0 {
            let rowHeight = lineHeight * terminalRect.height / nativeFrameSize.height
            let scale = CGFloat(buffer.pixelHeight) / bounds.height
            for row in 0..<min(terminalSize.rows, nativeRenderer.rows) where nativeRenderer.isRowDirty(row) {
                let minY = max(0, floor((terminalRect.maxY - CGFloat(row + 1) * rowHeight) * scale) - 1) / scale
                let maxY = min(CGFloat(buffer.pixelHeight), ceil((terminalRect.maxY - CGFloat(row) * rowHeight) * scale) + 1) / scale
                let band = CGRect(x: 0, y: minY, width: bounds.width, height: maxY - minY)
                if let last = changedBands.last, last.intersects(band) {
                    changedBands[changedBands.count - 1] = last.union(band)
                } else {
                    changedBands.append(band)
                }
            }
        }
        if !wallpaperGPUAttempted {
            wallpaperGPUAttempted = true
            wallpaperCompositor = makeWallpaperCompositor(for: buffer)
        }
        if let compositor = wallpaperCompositor, let terminalSize,
           let terminal = nativeTerminalImage(terminalSize) {
            let cursorState = nativeRenderer.neoSceneCursor
            if cursorState == nil { wallpaperCursor = nil }
            let hasCursor = cursorState?.visible == true
            let cursor = hasCursor ? wallpaperCursorImage(for: buffer) : nil
            if !hasCursor || cursor != nil {
                do {
                    if let image = try compositor.publish(terminal: terminal, cursor: cursor, to: buffer) {
                        publishedWallpaperImage = image
                        wallpaperFrameNeedsRedraw = false
                        needsDisplay = true
                    }
                    return
                } catch {
                    NSLog("MatrixScreenSaver GPU composition failed; retaining native CPU fallback: %@", String(describing: error))
                }
            }
            wallpaperCompositor = nil
        }
        if let image = buffer.publish({ context in
            context.scaleBy(x: CGFloat(buffer.pixelWidth) / bounds.width, y: CGFloat(buffer.pixelHeight) / bounds.height)
            if !changedBands.isEmpty { context.clip(to: changedBands) }
            if let base = wallpaperSceneBase {
                context.saveGState()
                context.setBlendMode(.copy)
                context.interpolationQuality = .none
                context.draw(base, in: bounds)
                context.restoreGState()
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            if wallpaperSceneBase != nil {
                drawTerminalContent()
                if showsWindowChrome { drawTitlebar() }
            } else {
                drawScene()
            }
            NSGraphicsContext.restoreGraphicsState()
        }) {
            publishedWallpaperImage = image
            wallpaperFrameNeedsRedraw = false
            needsDisplay = true
        }
    }

    /// Stops framework frame scheduling without releasing cells or scene-barrier membership.
    func pauseWallpaperAnimation() {
        guard isWallpaperHost, animationActive, !wallpaperAnimationPaused else { return }
        wallpaperAnimationPaused = true
        super.stopAnimation()
    }

    /// Resumes the preserved wallpaper scene after excluding a shared suspension interval.
    ///
    /// - Parameter duration: Wall-clock pause duration, identical for every display.
    func resumeWallpaperAnimation(after duration: TimeInterval) {
        guard wallpaperAnimationPaused else { return }
        nativeRenderer.shiftTimeline(by: duration)
        wallpaperAnimationPaused = false
        super.startAnimation()
    }

    /// Applies options to the live saver and optionally persists or restarts it.
    private func applySaverOptions(_ options: MatrixScreenSaverOptions, persist: Bool, restartAnimation: Bool) {
        let sanitizedOptions = options.sanitized()
        saverOptions = sanitizedOptions

        if persist {
            sanitizedOptions.save(to: Self.defaults)
            shouldReloadOptionsOnStart = false
        }

        if restartAnimation {
            stopAnimation()
        }

        let skipSyncDelay = animationActive ? !nativePlaybackSynchronized
            : isPreview || (!isWallpaperHost && !Self.isRunningInScreenSaverEngine)
        nativeRenderer.updateConfiguration(sanitizedOptions.rendererConfiguration(isPreview: skipSyncDelay))
        animationTimeInterval = nativeRenderer.preferredAnimationTimeInterval

        updateLayout()

        if restartAnimation {
            startAnimation()
        } else {
            needsDisplay = true
        }
    }

    /// Loads persisted options from ScreenSaverDefaults.
    static func loadSaverOptions() -> MatrixScreenSaverOptions {
        defaults.synchronize()
        return MatrixScreenSaverOptions.load(from: defaults)
    }

    /// Creates a fresh configure-sheet controller for each presentation.
    private func makeOptionsSheetController() -> MatrixScreenSaverOptionsSheetController {
        let controller = MatrixScreenSaverOptionsSheetController { [weak self] options in
            self?.applySaverOptionsFromSheet(options)
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller, self.optionsSheetController === controller else {
                return
            }
            self.optionsSheetController = nil
        }
        optionsSheetController = controller
        return controller
    }

    /// Keeps the saver view aligned to the host content rect during layout.
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

    /// Chooses the most reliable host content size from the current container hierarchy.
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

    /// Resyncs the saver view when AppKit reports a host size that differs materially.
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

/// Appends a timestamped line to the saver debug log file.
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
