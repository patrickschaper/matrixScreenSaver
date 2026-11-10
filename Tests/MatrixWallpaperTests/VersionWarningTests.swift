import AppKit

/// Uses real temporary bundle metadata for both native presentation paths.
private final class VersionWarningFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let hostBundle: Bundle
    let saverDirectory: URL

    init() {
        let appURL = root.appendingPathComponent("Wallpaper.app")
        saverDirectory = root.appendingPathComponent("Screen Savers")
        Self.write(appURL, identifier: "dev.patsch.MatrixWallpaper", version: "1.4.0")
        hostBundle = Bundle(url: appURL)!
        installSaver("1.3.0")
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func installSaver(_ version: String?) {
        Self.write(saverDirectory.appendingPathComponent("Renamed.saver"), identifier: "dev.patsch.MatrixScreenSaver", version: version)
    }

    func read() -> MatrixVersionStatus {
        MatrixVersionStatus.current(hostBundle: hostBundle, screenSaverDirectories: [saverDirectory], wallpaperURLs: [])
    }

    private static func write(_ url: URL, identifier: String, version: String?) {
        let contents = url.appendingPathComponent("Contents")
        try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var metadata = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "BNDL"]
        metadata["CFBundleShortVersionString"] = version
        let data = try! PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try! data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}

/// Checks the shared banner, launch-only alert, menu, icon, and refresh lifecycle.
func versionWarningTests() {
    versionOptionsTests()
    versionBlockedSaverTests()
    versionWallpaperTests()
}

private func versionOptionsTests() {
    let fixture = VersionWarningFixture()
    var applied: MatrixScreenSaverOptions?
    let controller = MatrixScreenSaverOptionsSheetController(readVersionStatus: fixture.read) { applied = $0 }
    controller.prepare(using: MatrixScreenSaverOptions())
    let window = controller.configureSheet()
    window.center()
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    let banner: NSStackView = stored("versionBanner", in: controller)!
    let description: NSTextField = stored("versionDescription", in: controller)!
    let heading: NSTextField = stored("versionHeading", in: controller)!
    let symbol: NSImageView = stored("versionSymbol", in: controller)!
    let name: NSTextField = stored("nameField", in: controller)!
    let scroll: NSScrollView = stored("optionsScrollView", in: controller)!
    let tabs = scroll.documentView as! NSTabView
    let content = window.contentView!
    check(!banner.isHidden && heading.stringValue == "Version Mismatch" &&
          description.stringValue.contains("1.4.0") && description.stringValue.contains("1.3.0"),
          "options show an explicit mismatch and both versions")
    check(description.isSelectable && description.stringValue.count < 110,
          "options keep version information selectable and concise")
    check(symbol.image === NSImage(named: NSImage.cautionName), "options use the standard macOS warning triangle")
    check(versionDescendants(banner).compactMap { $0 as? NSButton }.map(\.title) == ["View Releases…"],
          "the options banner offers only View Releases without a redundant Details button")
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        window.appearance = NSAppearance(named: appearance)
        for item in tabs.tabViewItems {
            tabs.selectTabViewItem(item)
            content.layoutSubtreeIfNeeded()
            check(!banner.isHidden && content.bounds.contains(banner.convert(banner.bounds, to: content)) &&
                  banner.convert(banner.bounds, to: content).minY >= scroll.convert(scroll.bounds, to: content).maxY,
                  "\(item.label) keeps the warning above its scrollable settings in \(appearance.rawValue)")
        }
        captureVersionView(content, name: "options-\(appearance.rawValue)")
    }
    let controls = versionDescendants(content).compactMap { $0 as? NSButton }
    let save = controls.first { $0.title == "Save" }!
    let cancel = controls.first { $0.title == "Cancel" }!
    check(save.isEnabled && cancel.isEnabled && save.keyEquivalent == "\r" && cancel.keyEquivalent == "\u{1b}",
          "mismatch preserves Save, Cancel, and their standard keyboard equivalents")
    check(content.bounds.contains(save.convert(save.bounds, to: content)) &&
          window.frame.height <= (window.screen?.visibleFrame.height ?? .infinity),
          "warning layout keeps actions inside the window and fits the current display")
    name.stringValue = "Unsaved Trinity"
    fixture.installSaver("1.4.0")
    controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
    check(banner.isHidden && name.stringValue == "Unsaved Trinity", "reactivating options clears resolved mismatch without losing edits")
    fixture.installSaver(nil)
    _ = controller.configureSheet()
    check(!banner.isHidden && heading.stringValue == "Version Unavailable" && description.stringValue.contains("Version unavailable"),
          "unreadable version is explained in options without claiming a mismatch")
    fixture.installSaver("1.3.0")
    _ = controller.configureSheet()
    save.performClick(nil)
    check(applied?.name == "Unsaved Trinity", "Save still delivers edited options during mismatch")
    var cancelledApply = false
    let cancelling = MatrixScreenSaverOptionsSheetController(readVersionStatus: fixture.read) { _ in cancelledApply = true }
    cancelling.prepare(using: MatrixScreenSaverOptions())
    let cancelWindow = cancelling.configureSheet()
    versionDescendants(cancelWindow.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }?.performClick(nil)
    check(!cancelledApply, "Cancel during mismatch does not apply preferences")
}

private func versionWallpaperTests() {
    let fixture = VersionWarningFixture()
    let suite = "MatrixVersionWarnings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let desktop = DesktopWallpaperFixture()
    var alerts = 0
    var host: WallpaperApp!
    host = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller(), readVersionStatus: fixture.read,
                        presentVersionAlert: { alert in
        alerts += 1
        check(alert.messageText == "Version Mismatch" && alert.informativeText.count < 110 &&
              alert.informativeText.contains("1.4.0") && alert.informativeText.contains("1.3.0") &&
              alert.buttons.map(\.title) == ["View Releases…", "Close"],
              "short error dialog shows versions and offers releases or Close")
        check(alert.alertStyle == .warning && alert.icon === NSImage(named: NSImage.cautionName),
              "version dialog uses the standard macOS warning triangle")
        do {
            let dismiss = Timer(timeInterval: 0.1, repeats: true) { _ in
                guard NSApp.modalWindow === alert.window else { return }
                if alerts == 1 { captureVersionView(alert.window.contentView!, name: "startup-alert") }
                NSApp.stopModal(withCode: .alertSecondButtonReturn)
            }
            RunLoop.main.add(dismiss, forMode: .modalPanel)
            defer { dismiss.invalidate() }
            let response = alert.runModal()
            alert.window.orderOut(nil)
            return response
        }
    })
    host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    defer {
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        host = nil
    }
    let status: NSStatusItem = stored("statusItem", in: host!)!
    let menu = status.menu!
    let warning = menu.items.first { $0.title == "Version Mismatch…" }!
    check(eventually(5) { alerts == 1 }, "mismatched launch presents one automatic warning")
    check(eventually {
        let windows: [DesktopWindow] = stored("windows", in: host!) ?? []
        return windows.count == NSScreen.screens.count && windows.allSatisfy {
            ($0.contentView as? MatrixScreenSaverView)?.isAnimating == true
        }
    }, "mismatch keeps desktop surfaces available for the moving error symbol")
    check((stored("windows", in: host!, as: [DesktopWindow].self) ?? []).allSatisfy {
        guard let view = $0.contentView as? MatrixScreenSaverView,
              let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view) else { return false }
        return stored("running", in: renderer, as: Bool.self) == false && view.shareWallpaperFrames() == nil
    }, "version mismatch blocks Matrix simulation and frame sharing")
    check(menu.items.filter { !$0.isHidden }.first === warning && warning.image != nil &&
          status.button?.accessibilityLabel() == "Matrix Wallpaper — version mismatch",
          "mismatch leads the menu and exposes a non-color status warning to accessibility")
    let visibleItems = menu.items.filter { !$0.isHidden }
    check(visibleItems.prefix(3).map(\.title) == ["Version Mismatch…", "", "Pause Animation"] && visibleItems[1].isSeparatorItem,
          "the mismatch menu section contains exactly one item followed by a separator")
    check(warning.image?.isTemplate == false && warning.image?.size == NSSize(width: 18, height: 18),
          "the first menu item uses a full-color warning image sized for the menu")
    if warning.responds(to: NSSelectorFromString("setPreferredImageVisibility:")) {
        check(warning.value(forKey: "preferredImageVisibility") as? Int == 1,
              "macOS 27 is instructed to keep the mismatch icon visible")
    }
    captureVersionMenu(menu)
    let warningImage = status.button?.image
    check(warningImage != nil && status.button?.toolTip == nil && warning.toolTip == nil,
          "persistent error icon has no menu or status-button hover text")
    menu.delegate?.menuWillOpen?(menu)
    let timer: Timer = stored("versionRefreshTimer", in: host!)!
    timer.fire()
    check(alerts == 1, "menu opening and periodic refresh do not repeat startup warning")
    menu.performActionForItem(at: menu.index(of: warning))
    check(alerts == 2, "menu warning can explicitly reopen version details")
    check((stored("windows", in: host!, as: [DesktopWindow].self) ?? []).allSatisfy {
        ($0.contentView as? MatrixScreenSaverView)?.isAnimating == true
    }, "dismissing the menu error preserves the moving error screen")
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    wait(1.2)
    fixture.installSaver("1.4.0")
    timer.fire()
    check((stored("windows", in: host!, as: [DesktopWindow].self) ?? []).allSatisfy {
        ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false
    }, "resolving a mismatch preserves manual pause")
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    check(warning.isHidden && status.button?.image !== warningImage && status.button?.toolTip == nil,
          "periodic refresh restores the normal icon and hides warning after matching update")
    check(eventually(0.3) {
        for window in stored("windows", in: host!, as: [DesktopWindow].self) ?? [] {
            guard let view = window.contentView as? MatrixScreenSaverView,
                  let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view) else { return false }
            view.animateOneFrame()
            if stored("running", in: renderer, as: Bool.self) != true { return false }
        }
        return true
    }, "Resume after resolving a paused mismatch does not wait through the old pause again")
    fixture.installSaver(nil)
    timer.fire()
    check(warning.isHidden && alerts == 2, "unknown version is not a confirmed menu mismatch or repeated alert")
    fixture.installSaver("1.3.0")
    timer.fire()
    check(!warning.isHidden && alerts == 2, "new mismatch while running updates persistent warnings without another startup alert")
    check((stored("windows", in: host!, as: [DesktopWindow].self) ?? []).allSatisfy {
        guard let view = $0.contentView as? MatrixScreenSaverView,
              let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view) else { return false }
        return stored("running", in: renderer, as: Bool.self) == false && view.shareWallpaperFrames() == nil
    }, "a mismatch found during playback stops Matrix and prevents shared frames")
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    check(!timer.isValid, "termination invalidates version refresh timer")

    var cancelledAlerts = 0
    let cancelled = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller(), readVersionStatus: fixture.read,
                                 presentVersionAlert: { _ in cancelledAlerts += 1; return .alertSecondButtonReturn })
    cancelled.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    cancelled.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    wait(0.1)
    check(cancelledAlerts == 0, "Quit before queued startup suppresses the pending warning")

    var quitDuringAlert: WallpaperApp!
    var modalReturned = false
    quitDuringAlert = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller(), readVersionStatus: fixture.read,
                                  presentVersionAlert: { alert in
        let quit = Timer(timeInterval: 0.1, repeats: true) { _ in
            guard NSApp.modalWindow === alert.window else { return }
            quitDuringAlert.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        RunLoop.main.add(quit, forMode: .modalPanel)
        defer { quit.invalidate() }
        let result = alert.runModal()
        modalReturned = true
        return result
    })
    quitDuringAlert.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    check(eventually { modalReturned } && NSApp.modalWindow == nil &&
          (stored("windows", in: quitDuringAlert!, as: [DesktopWindow].self) ?? []).isEmpty,
          "Quit during the warning unwinds its modal loop without starting wallpaper")
    quitDuringAlert = nil

    for companion in ["matching", "missing"] {
        if companion == "matching" { fixture.installSaver("1.4.0") }
        else { try! FileManager.default.removeItem(at: fixture.saverDirectory) }
        var unexpectedAlerts = 0
        let normal = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller(), readVersionStatus: fixture.read,
                                  presentVersionAlert: { _ in unexpectedAlerts += 1; return .alertSecondButtonReturn })
        normal.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        check(eventually { (stored("windows", in: normal, as: [DesktopWindow].self) ?? []).count == NSScreen.screens.count }
              && unexpectedAlerts == 0, "\(companion) companion launches without a version alert")
        normal.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
}

/// The real saver view must block before starting either its renderer or a wallpaper consumer.
private func versionBlockedSaverTests() {
    for preview in [true, false] {
        let fixture = VersionWarningFixture()
        let view = MatrixScreenSaverView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), isPreview: preview)!
        view.readVersionStatus = fixture.read
        let container = NSView(frame: view.frame)
        container.addSubview(view)
        defer { view.stopAnimation(); view.removeFromSuperview() }
        view.startAnimation()
        let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view)!
        let before = errorBitmap(view)
        for _ in 0..<90 { view.animateOneFrame() }
        let after = errorBitmap(view)
        if let directory = ProcessInfo.processInfo.environment["MATRIX_VERSION_SNAPSHOTS"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("blocked-saver-\(preview).png")
            try! after.representation(using: .png, properties: [:])!.write(to: url)
        }
        let black = after.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        let hasYellow = (0..<after.pixelsHigh).contains { y in
            (0..<after.pixelsWide).contains { x in
                let color = after.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                return color.redComponent > 0.6 && color.greenComponent > 0.4 && color.blueComponent < 0.3
            }
        }
        check(stored("running", in: renderer, as: Bool.self) == false &&
              stored("wallpaperFrameReader", in: view, as: WallpaperFrameReader.self) == nil,
              "saver preview=\(preview) blocks native and shared Matrix playback")
        check(black.redComponent == 0 && black.greenComponent == 0 && black.blueComponent == 0 && hasYellow,
              "saver preview=\(preview) renders a yellow warning triangle on black")
        check((before.representation(using: .png, properties: [:]) == after.representation(using: .png, properties: [:]))
              == NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              "error symbol moves unless Reduce Motion is enabled")
        view.applyWallpaperOptions(MatrixScreenSaverOptions())
        check(stored("running", in: renderer, as: Bool.self) == false,
              "editing settings cannot bypass the version block")
        fixture.installSaver("1.4.0")
        view.refreshVersionStatus()
        check(stored("running", in: renderer, as: Bool.self) == true,
              "saver resumes when installed versions match")
    }
}

private func errorBitmap(_ view: NSView) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

private func versionDescendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + versionDescendants($0) }
}

/// Captures the opened native menu, where macOS can suppress otherwise assigned item images.
private func captureVersionMenu(_ menu: NSMenu) {
    guard let directory = ProcessInfo.processInfo.environment["MATRIX_VERSION_SNAPSHOTS"],
          let screen = NSScreen.main else { return }
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let previous = menu.appearance
        menu.appearance = NSAppearance(named: appearance)
        defer { menu.appearance = previous }
        // Drain the modal dismissal event before entering menu tracking.
        wait(0.2)
        var captured = false
        let capture = Timer(timeInterval: 0.5, repeats: false) { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-R", "30,80,340,350", URL(fileURLWithPath: directory).appendingPathComponent("menu-\(appearance.rawValue).png").path]
            try! process.run()
            process.waitUntilExit()
            captured = process.terminationStatus == 0
            check(process.terminationStatus == 0, "opened native menu snapshot captured in \(appearance.rawValue)")
            menu.cancelTracking()
        }
        RunLoop.main.add(capture, forMode: .eventTracking)
        menu.popUp(positioning: nil, at: NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 80), in: nil)
        capture.invalidate()
        check(captured, "menu stayed open long enough to inspect its warning icon")
    }
}

/// Optional native snapshots support visual checks without modifying installed applications.
private func captureVersionView(_ view: NSView, name: String) {
    guard let directory = ProcessInfo.processInfo.environment["MATRIX_VERSION_SNAPSHOTS"],
          let window = view.window else { return }
    view.displayIfNeeded()
    window.displayIfNeeded()
    let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
    try! capture.run()
    capture.waitUntilExit()
    check(capture.terminationStatus == 0, "native window snapshot captured: \(name)")
}
