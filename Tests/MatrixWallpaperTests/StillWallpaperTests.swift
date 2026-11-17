import AppKit
import ScreenSaver

/// Keeps automatic captures in the test bundle's disposable parent, with no native desktop I/O.
/// - Returns: A real PNG writer whose desktop setter is a no-op.
func isolatedStillWallpaperController() -> StillWallpaperController {
    StillWallpaperController(
        directory: Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("StillFixtures/\(UUID().uuidString)"),
        setDesktopImage: { _, _ in })
}

/// Checks capture, persistence, and menu intent without changing the user's wallpaper.
func stillWallpaperTests() {
    stillSnapshotTests()
    stillWriterTests()
    stillMenuTests()
    automaticStillTests()
    automaticStillOptionsTests()
}

/// Compares native and shared output at both backing scales while preserving pause state.
private func stillSnapshotTests() {
    for scale: CGFloat in [1, 2] {
        let size = NSSize(width: 437, height: 293)
        let view = MatrixScreenSaverView(
            frame: NSRect(origin: .zero, size: size), isPreview: false)!
        let window = CompositionWindow(
            contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.testScale = scale
        window.contentView = view
        defer {
            view.stopAnimation()
            window.close()
        }
        check(
            view.snapshotWallpaperFrame() == nil, "inactive views cannot supply a wallpaper still")
        // Start independently so this fixture does not wait for other physical displays.
        view.startAnimation()
        check(
            view.snapshotWallpaperFrame() == nil,
            "ordinary saver views do not export wallpaper stills")
        view.isWallpaperHost = true
        view.pauseWallpaperAnimation()
        let reference = scenePixels(view, scale: scale)
        let first = view.snapshotWallpaperFrame()
        let second = view.snapshotWallpaperFrame()
        check(
            first?.width == Int(size.width * scale) && first?.height == Int(size.height * scale),
            "still capture uses full canvas dimensions at \(scale)x")
        check(
            first?.dataProvider?.data as Data? == reference
                && second?.dataProvider?.data as Data? == reference && reference != nil,
            "paused stills match native pixels without advancing at \(scale)x")
        check(
            !view.isAnimating
                && stored("sharedFrameBuffer", in: view, as: SharedWallpaperFrame?.self).flatMap {
                    $0
                } == nil,
            "still capture keeps pause state and does not start frame sharing")
        let sharedURL = view.shareWallpaperFrames()
        let sharedReference = scenePixels(view, scale: scale)
        let shared = view.snapshotWallpaperFrame()
        let buffer: SharedWallpaperFrame? = stored(
            "sharedFrameBuffer", in: view, as: SharedWallpaperFrame?.self
        ).flatMap { $0 }
        check(
            sharedURL != nil && buffer?.url == sharedURL && !view.isAnimating
                && shared?.dataProvider?.data as Data? == sharedReference,
            "still capture preserves an existing shared producer at \(scale)x")
        view.stopAnimation()
        check(view.snapshotWallpaperFrame() == nil, "stopped views cannot export stale stills")
    }
}

/// Exercises real PNG writes and injected desktop calls, including partial failures.
private func stillWriterTests() {
    guard let screen = NSScreen.main else {
        check(false, "still writer checks require a connected display")
        return
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let context = CGContext(
        data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
    let image = context.makeImage()!
    let frames = [StillWallpaperController.Frame](
        repeating: .init(screen: screen, image: image), count: 2)
    var applied: [URL] = []
    let writer = StillWallpaperController(directory: root) { url, destination in
        let siblings = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        check(
            siblings.count == frames.count
                && siblings.allSatisfy { NSImage(contentsOf: $0) != nil },
            "every PNG is readable before any desktop setter runs")
        check(destination === screen, "writer forwards the captured screen")
        let png = NSBitmapImageRep(data: try Data(contentsOf: url))!
        check(
            png.pixelsWide == image.width && png.pixelsHigh == image.height
                && (png.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.9,
            "saved PNG preserves dimensions and pixel content")
        applied.append(url)
    }
    do {
        try writer.apply(frames)
        let originalURLs = applied
        try writer.apply(frames)
        check(
            Set(applied).count == 4
                && originalURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
            "repeated requests use new paths and retain previously selected images")
        let count = applied.count
        do {
            try writer.apply([])
            check(false, "empty captures must fail")
        } catch {
            check(applied.count == count, "empty captures fail before desktop changes")
        }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let blockedWriter = StillWallpaperController(directory: blocked) { _, _ in
            applied.append(blocked)
        }
        do {
            try blockedWriter.apply(frames)
            check(false, "unwritable captures must fail")
        } catch {
            check(
                applied.count == count, "storage failure leaves every desktop selection untouched")
        }
        var attempted: [URL] = []
        let partial = StillWallpaperController(directory: root) { url, _ in
            attempted.append(url)
            if attempted.count == 1 {
                throw NSError(
                    domain: "StillTest", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "setter rejected"])
            }
        }
        do {
            try partial.apply(frames)
            check(false, "desktop setter failure must be reported")
        } catch {
            check(
                attempted.count == frames.count
                    && error.localizedDescription.contains(screen.localizedName)
                    && error.localizedDescription.contains("setter rejected")
                    && error.localizedDescription.contains("Other displays may have changed"),
                "setter failure names the display, reports partial success, and still attempts other displays"
            )
            check(
                attempted.allSatisfy { NSImage(contentsOf: $0) != nil },
                "partial failure retains all potentially selected images")
        }
    } catch {
        check(false, "still writer test: \(error)")
    }
}

/// Exercises one persisted opt-in through both native controls without changing real preferences.
private func stillMenuTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "MatrixImageMenuTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(false, forKey: "syncWithScreenSaver")
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    var applied: [URL] = []
    var options = MatrixScreenSaverView.loadSaverOptions()
    options.useMatrixImageForLockScreen = false
    let writer = StillWallpaperController(directory: root) { url, _ in applied.append(url) }
    let host = WallpaperApp(
        defaults: defaults, stillWallpaper: writer, loadOptions: { options },
        saveOptions: { options = $0 })
    host.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    defer {
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
    let status: NSStatusItem? = stored("statusItem", in: host)
    guard let menu = status?.menu,
        let item = menu.items.first(where: {
            $0.action == NSSelectorFromString("toggleLockScreenImage:")
        }),
        let sync: NSMenuItem = stored("syncItem", in: host)
    else {
        check(false, "menu offers the shared lock-screen image option")
        return
    }
    check(
        item.title == "Use Matrix Image on Lock Screen" && item.target === host
            && item.view == nil && item.onStateImage != nil,
        "lock-screen image option uses the native checkmark")
    check(
        menu.index(of: item) == menu.index(of: sync) + 1,
        "lock-screen image option appears directly below screen saver sync")
    check(
        !menu.items.contains { $0.action == NSSelectorFromString("useCurrentFrameAsWallpaper:") }
            && !host.responds(to: NSSelectorFromString("useCurrentFrameAsWallpaper:")),
        "manual frame capture command is removed")
    check(
        item.state == .off && item.isEnabled && applied.isEmpty,
        "image opt-in starts unchecked and available before playback")
    check(
        eventually(10) { !(stored("windows", in: host, as: [DesktopWindow].self) ?? []).isEmpty },
        "saved-off image preference does not prevent animation startup")
    NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
    guard
        let controller = stored(
            "optionsController", in: host,
            as: MatrixScreenSaverOptionsSheetController?.self
        ).flatMap({ $0 }),
        let checkbox: NSButton = stored("lockScreenImageCheckbox", in: controller),
        let frameRate: NSTextField = stored("frameRateField", in: controller)
    else {
        check(false, "General options exposes the same image preference")
        return
    }
    check(
        checkbox.state == .off && checkbox.title == item.title,
        "General checkbox matches the menu label and saved state")
    frameRate.stringValue = "43"
    menu.performActionForItem(at: menu.index(of: item))
    check(
        options.useMatrixImageForLockScreen && item.state == .on && checkbox.state == .on,
        "menu opt-in persists and updates the already-open General checkbox")
    check(
        frameRate.stringValue == "43",
        "menu toggle preserves unrelated unsaved settings")
    checkbox.state = .off
    NSApp.sendAction(NSSelectorFromString("apply:"), to: controller, from: nil)
    check(
        !options.useMatrixImageForLockScreen && item.state == .off && options.frameRate == 43,
        "General Save updates the same persisted preference and menu checkmark")

    NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
    let reopened = stored(
        "optionsController", in: host,
        as: MatrixScreenSaverOptionsSheetController?.self
    ).flatMap({ $0 })
    let reopenedCheckbox: NSButton? = reopened.flatMap { stored("lockScreenImageCheckbox", in: $0) }
    check(reopenedCheckbox?.state == .off, "reopened General options reads the shared saved value")
    reopenedCheckbox?.state = .on
    NSApp.sendAction(NSSelectorFromString("apply:"), to: reopened, from: nil)
    check(
        options.useMatrixImageForLockScreen && item.state == .on,
        "General opt-in checks the menu item too")
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    let windows: [DesktopWindow] = stored("windows", in: host) ?? []
    menu.performActionForItem(at: menu.index(of: item))
    check(
        !options.useMatrixImageForLockScreen && item.state == .off
            && (stored("windows", in: host, as: [DesktopWindow].self) ?? []).map(
                ObjectIdentifier.init)
                == windows.map(ObjectIdentifier.init)
            && windows.allSatisfy {
                ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false
            },
        "turning off the image preserves paused playback and its views")
    check(
        !defaults.bool(forKey: "syncWithScreenSaver"),
        "lock-screen image opt-in remains independent of screen saver sync")
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    menu.performActionForItem(at: menu.index(of: item))
    check(
        options.useMatrixImageForLockScreen && item.state == .on && item.isEnabled,
        "image preference can be enabled while wallpaper playback is stopped")
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    let relaunched = WallpaperApp(
        defaults: defaults, stillWallpaper: writer, loadOptions: { options },
        saveOptions: { options = $0 })
    relaunched.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    let relaunchedStatus: NSStatusItem? = stored("statusItem", in: relaunched)
    check(
        relaunchedStatus?.menu?.items.first {
            $0.action == NSSelectorFromString("toggleLockScreenImage:")
        }?.state == .on, "relaunch preserves an explicit opt-in")
    relaunched.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
}

/// Exercises automatic scheduling and lock handling through real views with fake desktop writes.
private func automaticStillTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "MatrixAutomaticStillTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(false, forKey: "syncWithScreenSaver")
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    var options = MatrixScreenSaverOptions()
    options.useMatrixImageForLockScreen = false
    options.neoMessageSceneEnabled = false
    options.cmdSceneEnabled = false
    options.numberSceneEnabled = false
    var applied: [URL] = []
    var failWrites = false
    let writer = StillWallpaperController(directory: root) { url, _ in
        applied.append(url)
        if failWrites { throw NSError(domain: "StillTest", code: 1) }
    }
    let host = WallpaperApp(
        defaults: defaults, stillWallpaper: writer, loadOptions: { options },
        saveOptions: { options = $0 })
    host.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    defer {
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
    check(
        eventually(10) { !(stored("windows", in: host, as: [DesktopWindow].self) ?? []).isEmpty },
        "automatic host creates its desktop views")
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    guard let timer: Timer = stored("frameLeaseTimer", in: host, as: Timer?.self).flatMap({ $0 })
    else {
        check(false, "automatic stills reuse the existing maintenance timer")
        return
    }
    /// Prepares any scene without changing the user's options or advancing paused playback later.
    /// - Parameters:
    ///   - scene: Safe fixture configuration for the renderer.
    ///   - waitForContent: Whether to advance past an initially empty frame.
    func prepareScene(_ scene: MatrixScreenSaverOptions, waitForContent: Bool = true) {
        let windows: [DesktopWindow] = stored("windows", in: host) ?? []
        var renderers: [NativeMatrixRenderer] = []
        let anchor = Date.timeIntervalSinceReferenceDate
        for window in windows {
            let view = window.contentView as! MatrixScreenSaverView
            view.applyWallpaperOptions(scene)
            let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view)!
            renderer.overrideSceneStartTime = anchor
            renderer.overrideSceneContentStartTime = anchor
            renderer.start()
            // Seed visible content synchronously; pumping AppKit can skip short text phases.
            if waitForContent {
                renderer.shiftTimeline(by: -2.5)
                renderer.advance()
            }
            renderers.append(renderer)
        }
        if waitForContent {
            check(
                renderers.allSatisfy { renderer in
                    (0..<renderer.rows).contains { renderer.visibleCount(in: $0) > 0 }
                }, "scene fixture has visible content on every display")
            check(
                renderers.allSatisfy(\.hasVisibleContent),
                "visible content qualifies regardless of scene or rain coverage")
        }
    }
    var intro = options
    intro.neoMessageSceneEnabled = true
    intro.neoMessageLines = ["Intro fixture"]
    prepareScene(intro, waitForContent: false)
    options.useMatrixImageForLockScreen = true
    timer.fire()
    host.setSuspended(.locked, true)
    host.setSuspended(.locked, false)
    check(applied.isEmpty, "startup and locking skip empty frames even when opted in")
    options.useMatrixImageForLockScreen = false
    prepareScene(options)
    timer.fire()
    let displays = NSScreen.screens.count
    host.setSuspended(.locked, true)
    host.setSuspended(.locked, false)
    check(applied.isEmpty, "saved opt-out leaves wallpapers untouched on startup and locking")
    NSApp.sendAction(NSSelectorFromString("toggleLockScreenImage:"), to: host, from: nil)
    timer.fire()
    check(applied.count == displays, "explicit opt-in captures one rain image per display")
    timer.fire()
    timer.fire()
    check(applied.count == displays, "startup capture is one-shot rather than periodic")
    host.setSuspended(.screenSaver, true)
    host.setSuspended(.locked, true)
    check(
        applied.count == 2 * displays,
        "locking refreshes retained rain even after the saver hides desktop views")
    host.setSuspended(.locked, true)
    check(applied.count == 2 * displays, "duplicate lock notifications do not repeat capture")
    host.setSuspended(.locked, false)
    host.setSuspended(.screenSaver, false)
    timer.fire()
    check(applied.count == 2 * displays, "unlock and wake do not rearm startup capture")
    options.useMatrixImageForLockScreen = false
    host.setSuspended(.locked, true)
    host.setSuspended(.locked, false)
    check(applied.count == 2 * displays, "saved opt-out is read before each lock update")
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    prepareScene(options)
    timer.fire()
    check(applied.count == 2 * displays, "opt-out suppresses explicit Start capture too")
    options.useMatrixImageForLockScreen = true
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    prepareScene(options)
    timer.fire()
    check(applied.count == 3 * displays, "explicit Start rearms one capture when enabled")

    var command = options
    command.cmdSceneEnabled = true
    command.commands = ["printf 'Command fixture\\n'"]
    command.cmdOutputHoldSeconds = 60
    var trace = options
    trace.numberSceneEnabled = true
    intro.useMatrixImageForLockScreen = true
    for (name, scene) in [("intro", intro), ("command", command), ("trace", trace)] {
        options = scene
        NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
        NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
        NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
        prepareScene(scene)
        let previous = applied.count
        timer.fire()
        check(applied.count == previous + displays, "startup captures the current \(name) scene")
        let windows: [DesktopWindow] = stored("windows", in: host) ?? []
        let before = windows.map {
            ($0.contentView as? MatrixScreenSaverView)?.snapshotWallpaperFrame()?.dataProvider?.data
                as Data?
        }
        host.setSuspended(.locked, true)
        check(
            applied.count == previous + 2 * displays, "locking captures the current \(name) scene")
        check(
            windows.allSatisfy { ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false }
                && windows.map {
                    ($0.contentView as? MatrixScreenSaverView)?.snapshotWallpaperFrame()?
                        .dataProvider?.data as Data?
                } == before, "\(name) capture preserves the paused frame")
        host.setSuspended(.locked, false)
    }
    failWrites = true
    host.setSuspended(.locked, true)
    let status: NSStatusItem? = stored("statusItem", in: host)
    let item = status?.menu?.items.first {
        $0.action == NSSelectorFromString("toggleLockScreenImage:")
    }
    check(
        item?.toolTip?.contains("Image update failed") == true && NSApp.modalWindow == nil,
        "automatic errors remain inspectable without blocking locking with an alert")
    let attempts = applied.count
    timer.fire()
    host.setSuspended(.locked, true)
    check(applied.count == attempts, "automatic failure does not create a retry loop")
    host.setSuspended(.locked, false)
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    host.setSuspended(.locked, true)
    check(applied.count == attempts, "stopped wallpaper cannot refresh on lock")
}

/// Verifies default-on images, preserved opt-outs, and unchanged renderer restart rules.
private func automaticStillOptionsTests() {
    let domain = "MatrixImageOptionsTests.\(UUID().uuidString)"
    let defaults = ScreenSaverDefaults(forModuleWithName: domain)!
    defer {
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
    }
    defaults.set(false, forKey: "AutomaticWallpaperStills")
    check(
        MatrixScreenSaverOptions.load(from: defaults).useMatrixImageForLockScreen,
        "missing image preference defaults on even before registration")
    MatrixScreenSaverOptions.registerDefaults(in: defaults)
    let initial = MatrixScreenSaverOptions.load(from: defaults)
    check(
        initial.useMatrixImageForLockScreen
            && MatrixScreenSaverOptions().useMatrixImageForLockScreen,
        "image updates default on independently of the legacy preference")
    var saved: MatrixScreenSaverOptions?
    let controller = MatrixScreenSaverOptionsSheetController { saved = $0 }
    controller.prepare(using: initial)
    guard let checkbox: NSButton = stored("lockScreenImageCheckbox", in: controller) else {
        check(false, "General options exposes the image opt-in control")
        return
    }
    check(
        checkbox.state == .on && checkbox.title == "Use Matrix Image on Lock Screen",
        "General checkbox displays the default-on image policy")
    checkbox.state = .off
    NSApp.sendAction(NSSelectorFromString("resetToDefaults:"), to: controller, from: nil)
    check(checkbox.state == .on, "Restore Defaults enables image updates")
    checkbox.state = .off
    NSApp.sendAction(NSSelectorFromString("apply:"), to: controller, from: nil)
    check(saved?.useMatrixImageForLockScreen == false, "Save reads the General opt-out checkbox")
    saved?.save(to: defaults)
    check(
        !MatrixScreenSaverOptions.load(from: defaults).useMatrixImageForLockScreen,
        "explicit image opt-out survives persistence and sanitization")
    MatrixScreenSaverOptions.registerDefaults(in: defaults)
    check(
        !MatrixScreenSaverOptions.load(from: defaults).useMatrixImageForLockScreen,
        "registering default-on images preserves a saved opt-out")
    check(
        saved?.requiresSceneRestart(comparedTo: initial) == false,
        "changing the image preference does not restart the renderer")
    saved?.useMatrixImageForLockScreen = true
    saved?.save(to: defaults)
    check(
        MatrixScreenSaverOptions.load(from: defaults).useMatrixImageForLockScreen,
        "turning image updates back on persists too")
}
