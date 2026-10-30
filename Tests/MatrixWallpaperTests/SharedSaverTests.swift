import AppKit
import ScreenSaver

/// Exercises the shared view and options controller through their hosting boundaries.
func sharedSaverTests() {
    glyphCacheTests()
    rainFontResetTests()
    rainGlyphOptionsTests()
    firstSceneSynchronizationTests()
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
    check(!options.commandsShuffleSequence, "existing command playback defaults to unshuffled order")
    defaults.set(40, forKey: "CmdTypingSpeedFactor")
    check(options.cmdOutputHoldSeconds == 10 && MatrixScreenSaverOptions().cmdOutputHoldSeconds == 10
          && NativeMatrixRenderer.Configuration().cmdOutputHoldSeconds == 10
          && MatrixScreenSaverOptions.load(from: defaults).cmdOutputHoldSeconds == 10,
          "output hold defaults to ten without interpreting the retired custom speed as a duration")
    options.cmdOutputHoldSeconds = 0
    options.save(to: defaults)
    check(MatrixScreenSaverOptions.load(from: defaults).cmdOutputHoldSeconds == 0,
          "output hold preserves an explicitly saved zero")
    options.frameRate = 42
    options.neoMessageLines = ["Shared options"]
    options.name = "Trinity"
    options.neoMessageSceneEnabled = false
    options.cmdSceneEnabled = true
    options.numberSceneEnabled = false
    options.commands = ["printf first", "printf second"]
    options.commandsRunInSequence = true
    options.commandsShuffleSequence = true
    options.neoMessageSpeedFactor = 2
    options.cmdOutputHoldSeconds = 4.5
    var applied = false
    let controller = MatrixScreenSaverOptionsSheetController { edited in
        edited.save(to: defaults)
        applied = true
    }
    controller.prepare(using: options)
    let shuffleRadio: NSButton? = stored("commandsShuffleRadio", in: controller)
    check(shuffleRadio?.state == .on, "options restores the shuffled command playback choice")
    let randomRadio: NSButton? = stored("commandsRandomRadio", in: controller)
    let sequenceRadio: NSButton? = stored("commandsSequenceRadio", in: controller)
    randomRadio?.performClick(nil)
    check(randomRadio?.state == .on && shuffleRadio?.state == .off && sequenceRadio?.state == .off,
          "one random command clears both whole-list playback choices")
    shuffleRadio?.performClick(nil)
    check(shuffleRadio?.state == .on && randomRadio?.state == .off && sequenceRadio?.state == .off,
          "shuffled playback is mutually exclusive with the existing modes")
    checkOptionsLayout(in: controller.configureSheet())
    checkSceneOptions(controller, options: options)
    let applyButton = buttons(in: controller.configureSheet().contentView!).first { $0.title == "OK" }
    check(applyButton != nil, "native options window exposes Apply")
    applyButton?.performClick(nil)
    let loaded = MatrixScreenSaverOptions.load(from: defaults)
    check(applied && loaded.frameRate == 42 && loaded.neoMessageLines == ["Shared options"] && !loaded.numberSceneEnabled,
          "native Apply validates and delivers options through the reusable callback")
    check(loaded.name == "Trinity" && loaded.cmdSceneEnabled && loaded.commands == options.commands
           && !loaded.neoMessageSceneEnabled && loaded.commandsRunInSequence && loaded.neoMessageSpeedFactor == 2
           && loaded.cmdOutputHoldSeconds == 4.5 && loaded.rendererConfiguration().cmdOutputHoldSeconds == 4.5,
           "tabbed options preserve the Neo name and command settings through Apply and persistence")
    check(loaded.commandsShuffleSequence && loaded.rendererConfiguration().commandsShuffleSequence,
          "shuffled playback survives Apply, persistence and renderer configuration")
    var cancelApplied = false
    let cancelController = MatrixScreenSaverOptionsSheetController { _ in cancelApplied = true }
    cancelController.prepare(using: options)
    buttons(in: cancelController.configureSheet().contentView!).first { $0.title == "Reset to defaults" }!.performClick(nil)
    buttons(in: cancelController.configureSheet().contentView!).first { $0.title == "Cancel" }!.performClick(nil)
    check(!cancelApplied && MatrixScreenSaverOptions.load(from: defaults).commands == options.commands,
          "main Cancel discards edits without invoking persistence")
    options.frameRate = -10
    options.save(to: defaults)
    check(MatrixScreenSaverOptions.load(from: defaults).frameRate > 0, "shared persistence retains option sanitization")

    var fontOptions = MatrixScreenSaverOptions()
    check(fontOptions.rainFonts.isEmpty, "rain fonts default to none, keeping the built-in glyphs")
    fontOptions.rainFonts = ["  Matrix-Code ", "Matrix-Code", "", "Matrix-Resurrected"] + (1...10).map { "Font \($0)" }
    let cleanFonts = fontOptions.sanitized().rainFonts
    check(cleanFonts == ["Matrix-Code"], "rain font sanitizing retains only the first nonempty trimmed name")
    defaults.set(["", " Menlo ", "Hiragino Sans"], forKey: "RainFonts")
    check(MatrixScreenSaverOptions.load(from: defaults).rainFonts == ["Menlo"],
          "existing multi-font preferences migrate to the first nonempty font")
    fontOptions.rainFonts = ["Matrix-Code", "Matrix-Resurrected"]
    fontOptions.save(to: defaults)
    check(MatrixScreenSaverOptions.load(from: defaults).rainFonts == ["Matrix-Code"],
           "only one rain font persists through save and load")
    check(fontOptions.rendererConfiguration(isPreview: false).rainFonts == ["Matrix-Code"],
           "only one selected font reaches the renderer configuration")

    let original = MatrixScreenSaverOptions()
    var commandOptions = original
    commandOptions.commands = [String(repeating: "x", count: 513), "printf safe", "printf bad\0ignored"]
    check(commandOptions.sanitized().commands == ["printf safe"],
           "command sanitization rejects invalid text instead of executing a clipped command")
    for value in [Double.nan, .infinity, -1] {
        commandOptions.cmdOutputHoldSeconds = value
        var configuration = NativeMatrixRenderer.Configuration()
        configuration.cmdOutputHoldSeconds = value
        check(commandOptions.sanitized().cmdOutputHoldSeconds == 10
              && configuration.sanitized().cmdOutputHoldSeconds == 10,
              "output hold rejects nonfinite and negative durations in persistence and renderer configuration")
    }
    commandOptions = original
    commandOptions.cmdOutputHoldSeconds = 100
    check(commandOptions.requiresSceneRestart(comparedTo: original),
          "output hold changes restart all participating displays")
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
        ("Neo name", { $0.name = "Trinity" }),
        ("command enablement", { $0.cmdSceneEnabled.toggle() }),
        ("command list", { $0.commands = ["printf hello"] }),
        ("command shuffle", { $0.commandsShuffleSequence = true }),
        ("number intro", { $0.numberSceneEnabled.toggle() }),
        ("rain cycle mode", { $0.rainRunForever.toggle() }),
        ("rain cycle duration", { $0.rainDurationSeconds += 1 }),
    ]
    for (name, change) in structuralChanges {
        var changed = original
        change(&changed)
        check(changed.requiresSceneRestart(comparedTo: original), "\(name) requests a coordinated scene restart")
    }
    var custom = original
    custom.neoMessageLines = ["Custom intro"]
    var renamed = custom
    renamed.name = "Trinity"
    check(!renamed.requiresSceneRestart(comparedTo: custom),
          "unused Neo name does not restart custom intro lines")
}

/// Every first scene must wait for the shared clock, not just Neo's own message timeline.
private func firstSceneSynchronizationTests() {
    for scene in ["custom", "trace", "rain"] {
        let participant = NSObject()
        let coordinator = ScreenSyncCoordinator.shared
        coordinator.register(ObjectIdentifier(participant), expectedCount: max(NSScreen.screens.count, 2) + 1,
                             startupDelay: 0.5)
        let views = (0..<max(NSScreen.screens.count, 2)).map { _ in
            MatrixScreenSaverView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), isPreview: false)!
        }
        var options = MatrixScreenSaverOptions()
        options.neoMessageSceneEnabled = false
        options.cmdSceneEnabled = scene == "custom"
        options.numberSceneEnabled = scene == "trace"
        options.commands = ["printf synchronized"]
        for view in views {
            view.isWallpaperHost = true
            view.rendersWallpaperWhileHidden = true
            view.startAnimation()
            view.applyWallpaperOptions(options)
        }
        let start = coordinator.resolvedStartTime()!
        for view in views { view.animateOneFrame() }
        check(Date.timeIntervalSinceReferenceDate < start && views.allSatisfy {
            let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: $0)!
            return stored("pendingSync", in: $0, as: Bool.self) == true
                && stored("running", in: renderer, as: Bool.self) == false
        }, "\(scene) first play waits on every display with Neo disabled")
        wait(max(0, start - Date.timeIntervalSinceReferenceDate) + 0.05)
        for view in views { view.animateOneFrame() }
        check(views.allSatisfy {
            let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: $0)!
            return stored("pendingSync", in: $0, as: Bool.self) == false
                && stored("running", in: renderer, as: Bool.self) == true
                && stored("overrideSceneStartTime", in: renderer, as: TimeInterval.self) == start
        }, "\(scene) first play starts every display on the shared clock")
        for view in views { view.stopAnimation() }
        coordinator.unregister(ObjectIdentifier(participant))
    }
}

/// Checks that the font reset updates the menu and accepted options without resetting other settings.
private func rainFontResetTests() {
    var applied: MatrixScreenSaverOptions?
    let controller = MatrixScreenSaverOptionsSheetController { applied = $0 }
    var options = MatrixScreenSaverOptions()
    options.rainFonts = ["Menlo", "Hiragino Sans"]
    options.characters = "ATGC"
    options.frameRate = 42
    controller.prepare(using: options)
    let window = controller.configureSheet()
    let tabs = descendants(of: window.contentView!).compactMap { $0 as? NSTabView }.first!
    tabs.selectTabViewItem(tabs.tabViewItems.first { $0.label == "Rain" }!)
    window.contentView!.layoutSubtreeIfNeeded()
    let picker: NSPopUpButton? = stored("rainFontsButton", in: controller)
    let reset = buttons(in: window.contentView!).first { $0.title == "Reset" }
    let bundledNames = ["Matrix-Code", "Matrix-Resurrected"]
    let items = picker?.menu?.items ?? []
    check(items.count > 4 && Array(items.dropFirst(2).prefix(2).map(\.title)) == bundledNames && items[4].isSeparatorItem &&
          bundledNames.allSatisfy { name in items.filter { $0.representedObject as? String == name }.count == 1 },
          "bundled fonts appear once directly after Default and before the divider")
    check(reset?.controlSize == .small && picker?.title == "Menlo" &&
          picker?.menu?.items.filter { $0.state == .on }.count == 1,
          "font picker exposes a small reset button beside a custom selection")
    for _ in 0..<2 {
        if let menu = picker?.menu, let index = menu.items.firstIndex(where: { $0.representedObject as? String == "Hiragino Sans" }) {
            menu.performActionForItem(at: index)
        }
        check(picker?.title == "Hiragino Sans" && picker?.menu?.items.filter { $0.state == .on }.count == 1 &&
              picker?.menu?.items.first { $0.title == "Menlo" }?.state == .off,
              "choosing a font replaces the previous selection and selecting it again keeps it selected")
    }
    for name in bundledNames {
        if let menu = picker?.menu, let index = menu.items.firstIndex(where: { $0.representedObject as? String == name }) {
            menu.performActionForItem(at: index)
        }
        check(picker?.title == name && picker?.menu?.items.filter { $0.state == .on }.count == 1,
              "bundled font \(name) can be selected from the dropdown")
    }
    reset?.performClick(nil)
    check(picker?.title.hasPrefix("Default - ") == true && picker?.menu?.items[1].state == .on &&
          picker?.menu?.items.filter { $0.representedObject is String }.allSatisfy { $0.state == .off } == true,
          "font reset restores the system-font summary and clears custom-font checkmarks")
    buttons(in: window.contentView!).first { $0.title == "OK" }?.performClick(nil)
    check(applied?.rainFonts.isEmpty == true && applied?.characters == "ATGC" && applied?.frameRate == 42,
          "font reset applies the default font without changing other options")
}

/// Exercises preset persistence, exclusive radio selection, cancellation and retained customization.
private func rainGlyphOptionsTests() {
    let domain = "dev.patsch.MatrixWallpaper.glyph-tests.\(UUID().uuidString)"
    let defaults = ScreenSaverDefaults(forModuleWithName: domain)!
    defer { defaults.removePersistentDomain(forName: domain); defaults.synchronize() }
    MatrixScreenSaverOptions.registerDefaults(in: defaults)
    check(MatrixScreenSaverOptions.load(from: defaults).rainGlyphSet == .default,
          "existing installations keep the default glyph set")
    defaults.set("unknown-preset", forKey: "RainGlyphSet")
    check(MatrixScreenSaverOptions.load(from: defaults).rainGlyphSet == .default,
          "unknown persisted glyph sets safely use Default")
    var options = MatrixScreenSaverOptions()
    options.characters = "ATGC"
    options.rainFonts = ["Menlo"]
    for preset in RainGlyphSet.allCases {
        options.rainGlyphSet = preset
        options.save(to: defaults)
        let loaded = MatrixScreenSaverOptions.load(from: defaults)
        check(loaded.rainGlyphSet == preset && loaded.rendererConfiguration().rainGlyphSet == preset &&
              loaded.characters == "ATGC" && loaded.rainFonts == ["Menlo"],
              "\(preset.title) persists and reaches the renderer without overwriting customization")
    }
    var applied: MatrixScreenSaverOptions?
    let controller = MatrixScreenSaverOptionsSheetController { applied = $0 }
    controller.prepare(using: options)
    let window = controller.configureSheet()
    let tabs = descendants(of: window.contentView!).compactMap { $0 as? NSTabView }.first!
    let rainTab = tabs.tabViewItems.first { $0.label == "Rain" }!
    tabs.selectTabViewItem(rainTab)
    let controls = buttons(in: rainTab.view!)
    let radios = RainGlyphSet.allCases.compactMap { preset in controls.first { $0.title == preset.title } }
    let picker: NSPopUpButton? = stored("rainFontsButton", in: controller)
    let characters: NSTextField? = stored("charactersField", in: controller)
    let reset = controls.first { $0.title == "Reset" }
    let preview: NSTextField? = stored("rainGlyphPreview", in: controller)
    check(radios.count == 3 && radios.last?.state == .on && picker?.isEnabled == false,
          "Rain restores the saved Resurrections radio with custom font controls inactive")
    guard radios.count == 3 else { return }
    for (index, radio) in radios.enumerated() {
        radio.performClick(nil)
        check(radios.enumerated().allSatisfy { $0.element.state == ($0.offset == index ? .on : .off) },
              "\(radio.title) is mutually exclusive with the other glyph presets")
        check(picker?.isEnabled == (index == 0) && characters?.isEnabled == (index == 0) && reset?.isEnabled == (index == 0),
              "\(radio.title) enables custom settings only for Default")
        let expectedCount = [4, 57, 135][index]
        check(preview?.stringValue.unicodeScalars.count == expectedCount && preview?.drawsBackground == true &&
              preview?.backgroundColor == .black && preview?.textColor == .green,
              "\(radio.title) previews every active glyph in green on black")
        let expectedFont = index == 0 ? "Menlo-Regular" : ["Matrix-Code", "Matrix-Resurrected"][index - 1]
        check(preview?.font?.fontName == expectedFont, "\(radio.title) preview uses its current rendering font")
    }
    window.contentView!.layoutSubtreeIfNeeded()
    check(preview != nil && preview!.frame.height > (preview!.font?.pointSize ?? 0) * 1.5 && (rainTab.view as? NSScrollView)?.hasVerticalScroller == true,
          "long glyph sets wrap onto multiple lines in a scrollable Rain tab")
    buttons(in: window.contentView!).first { $0.title == "OK" }?.performClick(nil)
    check(applied?.rainGlyphSet == .resurrections && applied?.rainFonts == ["Menlo"] && applied?.characters == "ATGC",
          "accepting a film preset keeps custom fonts and characters for switching back")
    controller.prepare(using: applied!)
    radios[0].performClick(nil)
    check(characters?.stringValue == "ATGC" && picker?.title.contains("Menlo") == true,
          "switching back to Default restores editable custom settings")
    characters?.stringValue = "XYZ"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: characters))
    check(preview?.stringValue == "XYZ", "editing custom characters refreshes the glyph preview immediately")
    if let menu = picker?.menu, let index = menu.items.firstIndex(where: { $0.representedObject as? String == "Hiragino Sans" }) {
        menu.performActionForItem(at: index)
    }
    check(preview?.font?.familyName == "Hiragino Sans", "choosing another font refreshes the preview typeface")
    reset?.performClick(nil)
    check(preview?.font?.fontName == NSFont.monospacedSystemFont(ofSize: 16, weight: .medium).fontName,
          "font Reset restores the system typeface in the preview")
    var cancelled = false
    let cancelController = MatrixScreenSaverOptionsSheetController { _ in cancelled = true }
    cancelController.prepare(using: options)
    buttons(in: cancelController.configureSheet().contentView!).first { $0.title == "Reset to defaults" }?.performClick(nil)
    let resetRadios: [NSButton] = stored("rainGlyphRadios", in: cancelController) ?? []
    check(resetRadios.first?.state == .on, "Reset to defaults restores the default glyph set")
    buttons(in: cancelController.configureSheet().contentView!).first { $0.title == "Cancel" }?.performClick(nil)
    check(!cancelled && MatrixScreenSaverOptions.load(from: defaults).rainGlyphSet == .resurrections,
          "Cancel does not persist a changed glyph preset")
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
    // These checks exercise plain scalar keys, independent of the user's saved font selection.
    options.rainFonts = []
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
    options.rainFonts = ["Menlo"]
    options.characters = "A"
    view.applyWallpaperOptions(options)
    let rainKey = UnicodeScalar(0xF0000)!
    let rainA = glyph(rainKey)
    let regularLevels: [[UnicodeScalar: CGImage]] = stored("nativeRegularGlyphsByLevel", in: view) ?? []
    let boldLevels: [[UnicodeScalar: CGImage]] = stored("nativeBoldGlyphsByLevel", in: view) ?? []
    check(!regularLevels.isEmpty && regularLevels.count == boldLevels.count &&
          zip(regularLevels, boldLevels).allSatisfy { regular, bold in
              regular[rainKey] != nil && regular[rainKey] === bold[rainKey] &&
              regular["A"] != nil && bold["A"] != nil && regular["A"] !== bold["A"]
          }, "selected-font rasters share every weight-cache level while system bold stays separate")
    options.characters = "B"
    view.applyWallpaperOptions(options)
    check(rainA != nil && glyph(rainKey) != nil && rainA !== glyph(rainKey),
          "editing custom rain characters refreshes rasters even when alias keys stay unchanged")
    options.characters = "ｱ"
    view.applyWallpaperOptions(options)
    let fallbackImage = glyph(rainKey)
    let selectedFonts: [String: NSFont] = stored("rainFonts", in: view) ?? [:]
    let selectedFont = selectedFonts["Menlo"]!
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "ｱ", attributes: [.font: selectedFont]))
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    let usesFallback = runs.contains { run in
        let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        var glyphID: CGGlyph = 0
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyphID)
        return CTFontCopyFamilyName(font) != CTFontCopyFamilyName(selectedFont) && glyphID != 0
    }
    let hasFallbackInk = fallbackImage.map { image in
        let bitmap = NSBitmapImageRep(cgImage: image)
        return (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
    } ?? false
    check(usesFallback && hasFallbackInk, "missing selected-font katakana resolves to a real fallback glyph and a visible cached raster")
    view.applyWallpaperOptions(options)
    check(fallbackImage != nil && fallbackImage === glyph(rainKey), "unchanged options reuse the fallback raster without resolving fonts again")
    options.rainFonts = ["Hiragino Sans"]
    options.characters = "カ"
    options.characterWidth = 16
    options.characterHeight = 30
    view.applyWallpaperOptions(options)
    if let image = glyph(rainKey) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        // Core Text antialiasing can reach past its measured ink bounds; solid strokes must not.
        let edgesHaveNoSolidInk = (0..<bitmap.pixelsHigh).allSatisfy { y in
            (bitmap.colorAt(x: 0, y: y)?.alphaComponent ?? 0) < 0.5 &&
            (bitmap.colorAt(x: bitmap.pixelsWide - 1, y: y)?.alphaComponent ?? 0) < 0.5
        }
        let hasInk = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
        check(edgesHaveNoSolidInk && hasInk, "wide selected-font glyphs fit inside the cell without cutting solid strokes")
    } else {
        check(false, "wide selected-font glyphs fit inside the cell without cutting solid strokes")
    }
    for (preset, count) in [(RainGlyphSet.classic, 57), (.resurrections, 135)] {
        let previousRaster = glyph(rainKey)
        options.rainGlyphSet = preset
        view.applyWallpaperOptions(options)
        let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view)!
        let resolved: [String: NSFont] = stored("rainFonts", in: view) ?? [:]
        let font = resolved[preset.fontName!]
        let usesOriginalFont = font.map { CTFontCopyPostScriptName($0) as String == preset.fontName } ?? false
        check(usesOriginalFont && renderer.rainSourceByScalar.count == count &&
              renderer.rainSourceByScalar.keys.allSatisfy { glyph($0) != nil } && previousRaster !== glyph(rainKey),
              "\(preset.title) rebuilds all preset rasters using the original bundled font")
        let cached = glyph(rainKey)
        view.applyWallpaperOptions(options)
        check(cached != nil && cached === glyph(rainKey) && cached === glyph(rainKey, bold: true),
              "\(preset.title) reuses cached artwork across unchanged options and font weights")
    }
    options.rainGlyphSet = .default
    view.applyWallpaperOptions(options)
    check(glyph(UnicodeScalar(0xF0001)!) == nil && glyph(rainKey) != nil,
          "returning to custom rain removes stale film-preset glyphs")
    var capturedOptions = MatrixScreenSaverOptions()
    capturedOptions.neoMessageSceneEnabled = false
    capturedOptions.cmdSceneEnabled = true
    capturedOptions.numberSceneEnabled = false
    capturedOptions.commands = ["printf '\\303\\251'"]
    capturedOptions.neoMessageSpeedFactor = 100
    capturedOptions.scanLinesIntensity = 0
    capturedOptions.rainFonts = ["Menlo"]
    let container = NSView(frame: view.frame)
    container.addSubview(view)
    defer { view.removeFromSuperview() }
    view.startAnimation()
    view.applyWallpaperOptions(capturedOptions)
    let renderer: NativeMatrixRenderer? = stored("nativeRenderer", in: view)
    let captured = eventually(8) {
        view.animateOneFrame()
        return renderer?[NativeMatrixRenderer.contentMargin, NativeMatrixRenderer.contentMargin].scalar == "é"
    }
    check(captured, "command output reaches the active native view before raster comparison")
    let fallbackPixels = pixels(of: view)
    capturedOptions.characters = "é"
    view.applyWallpaperOptions(capturedOptions)
    check(captured && fallbackPixels != nil && fallbackPixels == pixels(of: view),
          "captured Unicode text matches glyphs explicitly included in the rain character cache")
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
    check(tabs.tabViewItems.map(\.label) == ["General", "Intro scenes", "Rain"],
          "command capture integrates into the current native tab structure")
    for item in tabs.tabViewItems {
        tabs.selectTabViewItem(item)
        content.layoutSubtreeIfNeeded()
        let page = (item.view as? NSScrollView)?.documentView ?? item.view!
        let controls = descendants(of: page).compactMap { $0 as? NSControl }
        check(!controls.isEmpty && controls.allSatisfy { page.bounds.contains($0.convert($0.bounds, to: page)) },
              "\(item.label) keeps every control and help label inside its page")
        let sections = (page.subviews.first as? NSStackView)?.arrangedSubviews ?? []
        let frames = sections.map { $0.convert($0.bounds, to: page) }
        let topMargin = page.isFlipped ? (frames.map(\.minY).min() ?? 0) - page.bounds.minY
            : page.bounds.maxY - (frames.map(\.maxY).max() ?? 0)
        check((12...20).contains(topMargin), "\(item.label) starts with a consistent small top margin")
        if let stack = page.subviews.first as? NSStackView {
            let sections = stack.arrangedSubviews
            check(zip(sections, sections.dropFirst()).allSatisfy {
                stack.isFlipped ? $0.frame.maxY <= $1.frame.minY : $0.frame.minY >= $1.frame.maxY
            },
                  "\(item.label) sections do not overlap")
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

/// Exercises scene ownership and actions without reaching into controller storage.
private func checkSceneOptions(_ controller: MatrixScreenSaverOptionsSheetController, options: MatrixScreenSaverOptions) {
    let window = controller.configureSheet()
    let tabs = descendants(of: window.contentView!).compactMap { $0 as? NSTabView }.first!
    let page = tabs.tabViewItems.first { $0.label == "Intro scenes" }!.view!
    tabs.selectTabViewItem(at: 1)
    let groups = descendants(of: page).compactMap { $0 as? NSBox }
    check(groups.count == 3, "intro scenes have three native fieldsets")
    guard groups.count == 3 else { return }
    let titles = ["Show Neo message scene", "Show custom scene", "Show trace program scene"]
    check(groups.map { buttons(in: $0).first?.title ?? "" } == titles,
          "fieldsets follow Neo, custom, trace playback order")
    for group in groups {
        let controls = descendants(of: group).compactMap { $0 as? NSControl }
        check(controls.allSatisfy { group.bounds.contains($0.convert($0.bounds, to: group)) },
              "fieldset keeps its controls inside native bounds")
        let stacks = descendants(of: group).compactMap { $0 as? NSStackView }.filter { $0.orientation == .vertical }
        check(stacks.allSatisfy { stack in
            zip(stack.arrangedSubviews, stack.arrangedSubviews.dropFirst()).allSatisfy { $0.frame.minY >= $1.frame.maxY }
        }, "fieldset rows do not overlap")
    }
    let customCopy = "Execute custom commands and show its output as messages. Off by default."
    let labels = descendants(of: groups[1]).compactMap { $0 as? NSTextField }
    check(labels.contains { $0.isEditable && $0.accessibilityLabel() == "Command output hold in seconds" && $0.stringValue == "4.5" }
          && !labels.contains { $0.stringValue == "Typing speed" || $0.accessibilityLabel() == "Custom typing speed" },
          "custom fieldset replaces independent typing speed with an output hold control")
    check(labels.filter { $0.stringValue == customCopy }.count == 1
          && labels.contains { $0.stringValue == "Commands" }, "custom group has exact description and separate Commands row")
    check(descendants(of: groups[0]).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Lines" },
          "Neo fieldset owns its Lines editor")
    let speed = descendants(of: page).compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.stringValue == "2" }!
    check(!groups.contains { speed.isDescendant(of: $0) }, "shared typing speed is outside the fieldsets")
    for (index, group) in groups.enumerated() {
        let toggle = buttons(in: group).first { $0.title == titles[index] }!
        let editors = descendants(of: group).compactMap { $0 as? NSControl }.filter {
            $0 !== toggle && (($0 as? NSTextField)?.isEditable == true || $0 is NSButton)
        }
        let initiallyOn = toggle.state == .on
        let otherEditors = groups.filter { $0 !== group }.flatMap { descendants(of: $0) }.compactMap { $0 as? NSControl }
        let otherStates = otherEditors.map(\.isEnabled)
        check(toggle.isEnabled && editors.allSatisfy { $0.isEnabled == initiallyOn }, "scene \(index) prepare initializes child enablement")
        toggle.performClick(nil)
        check(toggle.isEnabled && editors.allSatisfy { $0.isEnabled != initiallyOn } && speed.isEnabled,
              "scene \(index) toggle changes only its editable descendants")
        check(otherEditors.map(\.isEnabled) == otherStates, "scene \(index) toggle leaves other fieldsets unchanged")
        toggle.performClick(nil)
    }
    let name = descendants(of: groups[0]).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    check(name.stringValue == options.name, "scene toggles retain the Neo name")
    let customEdit = buttons(in: groups[1]).first { $0.title == "Edit…" }!
    customEdit.performClick(nil)
    if let editor = window.attachedSheet {
        let table = descendants(of: editor.contentView!).compactMap { $0 as? NSTableView }.first
        check(table != nil, "custom commands use the same editable row list as Neo messages")
        check(descendants(of: editor.contentView!).compactMap { $0 as? NSTextField }.contains {
            $0.stringValue.contains("host's permissions") && $0.stringValue.contains("screen is locked")
        }, "command editor retains its security warning")
        if let table {
            func field(_ row: Int) -> NSTextField {
                (table.view(atColumn: 1, row: row, makeIfNecessary: true) as! NSTableCellView).textField!
            }
            func values() -> [String] { (0..<table.numberOfRows).map { field($0).stringValue } }
            check(values() == options.commands, "scene toggles retain commands")
            let add = buttons(in: editor.contentView!).first { $0.title == "+" }!
            add.performClick(nil)
            field(table.numberOfRows - 1).stringValue = "printf added"
            field(0).stringValue = "printf edited"
            let drag = CommandRowDrag(source: table)
            drag.draggingPasteboard.writeObjects([controller.tableView(table, pasteboardWriterForRow: table.numberOfRows - 1)!])
            let moved = controller.tableView(table, acceptDrop: drag, row: 0, dropOperation: .above)
            check(moved && values().first == "printf added" && values().dropFirst().first == "printf edited",
                  "dragging commands changes execution order and preserves edits")
            buttons(in: editor.contentView!).first { $0.title == "Cancel" }!.performClick(nil)
            customEdit.performClick(nil)
            check(values() == options.commands, "command editor Cancel discards adds, edits, and reordering")
            for _ in 0..<table.numberOfRows {
                (table.view(atColumn: 2, row: 0, makeIfNecessary: true) as! NSButton).performClick(nil)
            }
            check(table.numberOfRows == 0, "command list permits removing the last command")
            add.performClick(nil)
            field(0).stringValue = "printf 'accepted & unchanged'"
            buttons(in: editor.contentView!).first { $0.title == "OK" }!.performClick(nil)
            customEdit.performClick(nil)
            check(values() == ["printf 'accepted & unchanged'"], "command editor OK retains exact shell syntax until main acceptance")
            for _ in 0...MatrixScreenSaverOptions.maxCommandCount { add.performClick(nil) }
            check(table.numberOfRows == MatrixScreenSaverOptions.maxCommandCount && !add.isEnabled,
                  "command list supports twenty commands without using Neo's ten-line limit")
            buttons(in: editor.contentView!).first { $0.title == "Cancel" }!.performClick(nil)
        } else {
            buttons(in: editor.contentView!).first { $0.title == "Cancel" }!.performClick(nil)
        }
        buttons(in: groups[0]).first { $0.title == "Edit…" }!.performClick(nil)
        if let neoEditor = window.attachedSheet,
           let neoTable = descendants(of: neoEditor.contentView!).compactMap({ $0 as? NSTableView }).first {
            check(neoTable.numberOfRows == options.neoMessageLines.count
                  && buttons(in: neoEditor.contentView!).contains { $0.title == "Reset lines" && !$0.isHidden },
                  "opening Neo after commands retains its own lines and reset action")
            buttons(in: neoEditor.contentView!).first { $0.title == "Cancel" }!.performClick(nil)
        }
    } else {
        check(false, "custom Edit opens a native editor sheet")
    }
    buttons(in: window.contentView!).first { $0.title == "Reset to defaults" }!.performClick(nil)
    check(buttons(in: groups[0]).first!.state == .on && name.isEnabled
          && buttons(in: groups[1]).first!.state == .off && !customEdit.isEnabled
          && buttons(in: groups[2]).first!.state == .on && speed.isEnabled,
          "Reset restores scene enablement and leaves shared speed editable")
    controller.prepare(using: options)
    tabs.selectTabViewItem(at: 0)
}

/// Supplies the native table's own drag payload without synthesizing mouse events.
private final class CommandRowDrag: NSObject, NSDraggingInfo {
    /// Private pasteboard carrying the row produced by the real data source.
    let draggingPasteboard = NSPasteboard.withUniqueName()
    /// Only the originating table may reorder its rows.
    let draggingSource: Any?
    /// Creates a local table drag.
    init(source: NSTableView) { draggingSource = source }
    /// Releases the test pasteboard when the drag ends.
    deinit { draggingPasteboard.releaseGlobally() }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

/// Traverses the native hierarchy, including labels and editable controls.
private func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
}

/// Finds actual controls so integration checks use the native UI action, not private methods.
private func buttons(in view: NSView) -> [NSButton] {
    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
}
