import AppKit
import ScreenSaver

/// Exercises the shared view and options controller through their hosting boundaries.
func sharedSaverTests() {
    glyphCacheTests()
    guard let screen = NSScreen.main,
          let first = MatrixScreenSaverView(frame: screen.frame, isPreview: false),
          let second = MatrixScreenSaverView(frame: screen.frame, isPreview: false) else {
        check(false, "shared saver views can be created")
        return
    }
    first.isWallpaperHost = true
    second.isWallpaperHost = true
    let firstWindow = DesktopWindow(screen: screen, saverView: first)
    let secondWindow = DesktopWindow(screen: screen, saverView: second)
    let additionalWindows = NSScreen.screens.dropFirst(2).map { screen -> DesktopWindow in
        let saver = MatrixScreenSaverView(frame: screen.frame, isPreview: false)!
        saver.isWallpaperHost = true
        return DesktopWindow(screen: screen, saverView: saver)
    }
    secondWindow.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 960, height: 600), display: false)
    firstWindow.orderBack(nil)
    secondWindow.orderBack(nil)
    let beforeStartup = Date.timeIntervalSinceReferenceDate
    first.startAnimation()
    second.startAnimation()
    for window in additionalWindows {
        window.orderBack(nil)
        (window.contentView as! ScreenSaverView).startAnimation()
    }
    check(ScreenSyncCoordinator.shared.registeredCount == 2 + additionalWindows.count, "wallpaper hosts register for coordinated scenes")
    let startup = ScreenSyncCoordinator.shared.resolvedStartTime()
    check(startup != nil && startup! >= beforeStartup && startup! - Date.timeIntervalSinceReferenceDate <= 0.1,
          "wallpaper hosts resolve a shared start without the screensaver's one-second lead-in")
    check(first.bounds.size != second.bounds.size, "coordinated hosts retain their individual canvas sizes")
    wait(2)
    check(ScreenSyncCoordinator.shared.resolvedStartTime() != nil, "wallpaper participants share a resolved start")
    let sharedStart = ScreenSyncCoordinator.shared.resolvedStartTime()
    var liveOptions = MatrixScreenSaverView.loadSaverOptions()
    liveOptions.frameRate = 42
    liveOptions.characters = "ATGC"
    first.applyWallpaperOptions(liveOptions)
    second.applyWallpaperOptions(liveOptions)
    check(first.animationTimeInterval == 1.0 / 42 && second.animationTimeInterval == 1.0 / 42,
          "live options update frame scheduling across wallpaper views")
    check(ScreenSyncCoordinator.shared.resolvedStartTime() == sharedStart,
          "live options preserve the coordinated scene anchor")
    for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop"] {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
    }
    wait(0.2)
    check(first.isAnimating && second.isAnimating, "saver-stop notifications do not disable wallpaper-host views")
    firstWindow.orderOut(nil)
    wait(0.1)
    check(first.isAnimating, "temporarily hidden wallpaper retains animation for automatic resumption")
    firstWindow.orderBack(nil)
    first.stopAnimation()
    second.stopAnimation()
    for window in additionalWindows {
        (window.contentView as! ScreenSaverView).stopAnimation()
        window.close()
    }
    check(ScreenSyncCoordinator.shared.registeredCount == 0, "stopping all hosts removes synchronization membership")
    firstWindow.close()
    secondWindow.close()

    // Keep real saver preferences untouched while exercising persistence and the native Apply action.
    let domain = "dev.patsch.MatrixWallpaper.tests.\(UUID().uuidString)"
    let defaults = ScreenSaverDefaults(forModuleWithName: domain)!
    defer { defaults.removePersistentDomain(forName: domain); defaults.synchronize() }
    MatrixScreenSaverOptions.registerDefaults(in: defaults)
    var options = MatrixScreenSaverOptions.load(from: defaults)
    options.frameRate = 42
    options.neoMessageLines = ["Shared options"]
    var applied = false
    let controller = MatrixScreenSaverOptionsSheetController { edited in
        edited.save(to: defaults)
        applied = true
    }
    controller.prepare(using: options)
    checkOptionsLayout(in: controller.configureSheet())
    let applyButton = buttons(in: controller.configureSheet().contentView!).first { $0.title == "OK" }
    check(applyButton != nil, "native options window exposes Apply")
    applyButton?.performClick(nil)
    let loaded = MatrixScreenSaverOptions.load(from: defaults)
    check(applied && loaded.frameRate == 42 && loaded.neoMessageLines == ["Shared options"] && !loaded.numberSceneEnabled,
          "native Apply validates and delivers options through the reusable callback")
    options.frameRate = -10
    options.save(to: defaults)
    check(MatrixScreenSaverOptions.load(from: defaults).frameRate > 0, "shared persistence retains option sanitization")

    var fontOptions = MatrixScreenSaverOptions()
    check(fontOptions.rainFonts.isEmpty, "rain fonts default to none, keeping the built-in glyphs")
    fontOptions.rainFonts = ["  Matrix-Code ", "Matrix-Code", "", "Matrix-Resurrected"] + (1...10).map { "Font \($0)" }
    let cleanFonts = fontOptions.sanitized().rainFonts
    check(cleanFonts.prefix(2) == ["Matrix-Code", "Matrix-Resurrected"] && Set(cleanFonts).count == cleanFonts.count,
          "rain font sanitizing trims names and drops blanks and duplicates")
    check(cleanFonts.count == MatrixScreenSaverOptions.maximumRainFonts, "rain font sanitizing caps the selection")
    fontOptions.rainFonts = ["Matrix-Code", "Matrix-Resurrected"]
    fontOptions.save(to: defaults)
    check(MatrixScreenSaverOptions.load(from: defaults).rainFonts == ["Matrix-Code", "Matrix-Resurrected"],
          "rain fonts persist through save and load")
    check(fontOptions.rendererConfiguration(isPreview: false).rainFonts == ["Matrix-Code", "Matrix-Resurrected"],
          "rain fonts reach the renderer configuration")

    let original = MatrixScreenSaverOptions()
    var live = original
    live.twinkleEnabled.toggle()
    live.diffuseEnabled.toggle()
    live.rainDensity = 2
    live.frameRate = 42
    live.errorRate = 2
    live.characters = "ATGC"
    live.scanLinesIntensity = 0.5
    live.scanLinesVertical.toggle()
    check(!live.requiresSceneRestart(comparedTo: original), "visual and rain rendering settings apply without scene restart")
    let structuralChanges: [(String, (inout MatrixScreenSaverOptions) -> Void)] = [
        ("character size", { $0.characterWidth += 1 }),
        ("character height", { $0.characterHeight += 1 }),
        ("Neo enablement", { $0.neoMessageSceneEnabled.toggle() }),
        ("intro speed", { $0.neoMessageSpeedFactor = 2 }),
        ("Neo lines", { $0.neoMessageLines = ["Changed intro"] }),
        ("number intro", { $0.numberSceneEnabled.toggle() }),
        ("rain cycle mode", { $0.rainRunForever.toggle() }),
        ("rain cycle duration", { $0.rainDurationSeconds += 1 }),
    ]
    for (name, change) in structuralChanges {
        var changed = original
        change(&changed)
        check(changed.requiresSceneRestart(comparedTo: original), "\(name) requests a coordinated scene restart")
    }
}

/// Checks raster reuse through layout and option updates, retaining images to compare identity safely.
private func glyphCacheTests() {
    let view = MatrixScreenSaverView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), isPreview: true)!
    func glyph(_ scalar: UnicodeScalar, bold: Bool = false) -> CGImage? {
        let name = bold ? "nativeBoldGlyphsByLevel" : "nativeRegularGlyphsByLevel"
        let levels: [[UnicodeScalar: CGImage]]? = stored(name, in: view)
        return levels?.last?[scalar]
    }
    let original = glyph("A")
    let originalBold = glyph("A", bold: true)
    view.setFrameSize(NSSize(width: 800, height: 480))
    view.layout()
    view.startAnimation()
    check(original != nil && original === glyph("A") && originalBold === glyph("A", bold: true),
          "layout, canvas resize, and animation startup reuse unchanged glyph rasters")
    var options = MatrixScreenSaverView.loadSaverOptions()
    options.frameRate = 42
    view.applyWallpaperOptions(options)
    check(original === glyph("A"), "frame-rate changes preserve glyph rasters")
    options.characters = "☃"
    view.applyWallpaperOptions(options)
    check(glyph("☃") != nil && glyph("☃", bold: true) != nil,
          "custom characters populate both glyph caches")
    let custom = glyph("☃")
    options.characterWidth += 2
    view.applyWallpaperOptions(options)
    check(custom != nil && custom !== glyph("☃") && glyph("☃")?.width == custom!.width + 2 &&
          glyph("☃")?.height == custom!.height,
          "character-width changes regenerate glyphs at the new width")
    let wider = glyph("☃")
    options.characterHeight += 2
    view.applyWallpaperOptions(options)
    check(wider !== glyph("☃") && glyph("☃")?.height == wider!.height + 2,
          "character-height changes regenerate glyphs at the new height")
    view.stopAnimation()
    view.startAnimation()
    check(glyph("A") != nil && glyph("A", bold: true) != nil,
          "restarting after resource cleanup recreates usable glyph caches")
    view.stopAnimation()
}

/// Checks every native tab at its laid-out size and leaves an edit on an inactive page for Apply.
private func checkOptionsLayout(in window: NSWindow) {
    let content = window.contentView!
    content.layoutSubtreeIfNeeded()
    let size = content.bounds.size
    // The Rain tab gained the Fonts section, so the sheet is taller than the original 600 point budget.
    check(size.width <= 600 && size.height <= 650,
          "options fit in a compact window without screen-sized help text")
    guard let tabs = descendants(of: content).compactMap({ $0 as? NSTabView }).first else {
        check(false, "options organize settings into native tabs")
        return
    }
    for item in tabs.tabViewItems {
        tabs.selectTabViewItem(item)
        content.layoutSubtreeIfNeeded()
        let page = item.view!
        let controls = descendants(of: page).compactMap { $0 as? NSControl }
        check(!controls.isEmpty && controls.allSatisfy { page.bounds.contains($0.convert($0.bounds, to: page)) },
              "\(item.label) keeps every control and help label inside its page")
        let top = controls.map { $0.convert($0.bounds, to: page).maxY }.max() ?? 0
        check((12...20).contains(page.bounds.maxY - top), "\(item.label) starts with a consistent small top margin")
        if let stack = page.subviews.first as? NSStackView {
            let sections = stack.arrangedSubviews
            check(zip(sections, sections.dropFirst()).allSatisfy { $0.frame.minY >= $1.frame.maxY },
                  "\(item.label) sections do not overlap")
        }
        if let number = controls.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Show number scene" }) {
            number.performClick(nil)
        }
        if let forever = controls.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Run forever" }),
           let seconds = controls.compactMap({ $0 as? NSTextField }).first(where: { $0.accessibilityLabel() == "Rain duration in seconds" }) {
            forever.performClick(nil)
            check(seconds.isEnabled, "rain duration becomes editable when Run forever is off")
            forever.performClick(nil)
            check(!seconds.isEnabled, "rain duration is disabled again when Run forever is on")
        }
        check(content.bounds.size == size, "switching to \(item.label) keeps the window size stable")
    }
    tabs.selectTabViewItem(at: 0)
}

/// Traverses the native hierarchy, including labels and editable controls.
private func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
}

/// Finds actual controls so integration checks use the native UI action, not private methods.
private func buttons(in view: NSView) -> [NSButton] {
    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
}
