import AppKit
import Foundation

func nativeMatrixRendererTests() {
    rainFontTests()
    rainGlyphPresetTests()

    commandCaptureLifecycleTests()
    customTraceHandoffTests()
    customShellCommandSequenceTests()
    customScrollingViewportTests()
    customLiveOutputTests()
    introDirtyRowTests()
    traceFrameRateTests()
    ok(NativeMatrixRenderer().seedOffset == 0,
       "NativeMatrixRenderer: seedOffset defaults to 0")
    var named = NativeMatrixRenderer.Configuration()
    named.neoMessageName = "Trinity"
    ok(named.sanitized().neoMessageLines.first == "Wake up, Trinity...",
       "NativeMatrixRenderer: a name customizes default intro lines without explicit lines")

    let palette = NativeMatrixRenderer().levelColors
    let hasNoPureWhite = !palette.contains { color in
        color.red == 255 && color.green == 255 && color.blue == 255
    }
    ok(hasNoPureWhite,
       "NativeMatrixRenderer: palette avoids pure white highlight")

    let hasMaxGreenHighlight = palette.contains { color in
        color.green == 255
    }
    ok(hasMaxGreenHighlight,
       "NativeMatrixRenderer: palette keeps max-green highlight")

    let r1: NativeMatrixRenderer = .init()
    let r2: NativeMatrixRenderer = .init()
    r1.seedOffset = 0
    r2.seedOffset = 0xDEAD_BEEF
    var cfg = NativeMatrixRenderer.Configuration()
    cfg.neoMessageSceneEnabled = false
    cfg.numberSceneEnabled = false
    r1.resize(to: TerminalSize(columns: 40, rows: 20))
    r2.resize(to: TerminalSize(columns: 40, rows: 20))
    r1.updateConfiguration(cfg)
    r2.updateConfiguration(cfg)
    r1.start()
    r2.start()
    for _ in 0..<60 { r1.advance(); r2.advance() }
    let differ = (0..<20).contains { row in (0..<40).contains { col in r1[row, col] != r2[row, col] } }
    ok(differ, "NativeMatrixRenderer: renderers with different seedOffsets diverge after 60 frames")

    var neo = NeoMessageScene()
    neo.reset(startTime: 100, seed: 1)
    neo.advance(now: 100.25)
    let before = neo.renderState
    neo.shiftTimeline(by: 3600)
    neo.advance(now: 3700.25)
    let after = neo.renderState
    ok(before.currentLine == after.currentLine && before.visibleCharCount == after.visibleCharCount && before.cursorVisible == after.cursorVisible,
       "NeoMessageScene: suspension preserves text and cursor rather than skipping the intro")

    let paused = NativeMatrixRenderer()
    var intro = NativeMatrixRenderer.Configuration()
    intro.neoMessageSpeedFactor = 0.1
    paused.updateConfiguration(intro)
    paused.resize(to: TerminalSize(columns: 40, rows: 20))
    paused.overrideSceneStartTime = Date.timeIntervalSinceReferenceDate - 0.25
    paused.start()
    Thread.sleep(forTimeInterval: 0.05)
    paused.advance()
    let cursorBefore = paused.neoSceneCursor
    let rain = NativeMatrixRenderer()
    cfg.twinkleEnabled = false
    rain.updateConfiguration(cfg)
    rain.resize(to: TerminalSize(columns: 40, rows: 20))
    rain.start()
    let rainBefore = (0..<20).flatMap { row in (0..<40).map { rain[row, $0] } }
    let pauseStart = Date.timeIntervalSinceReferenceDate
    Thread.sleep(forTimeInterval: 1.2)
    let pausedDuration = Date.timeIntervalSinceReferenceDate - pauseStart
    paused.shiftTimeline(by: pausedDuration)
    rain.shiftTimeline(by: pausedDuration)
    paused.advance()
    rain.advance()
    let rainAfter = (0..<20).flatMap { row in (0..<40).map { rain[row, $0] } }
    ok(rainBefore == rainAfter, "NativeMatrixRenderer: rain cells retain their positions across suspension")
    let cursorAfter = paused.neoSceneCursor
    ok(cursorBefore != nil && cursorBefore?.column == cursorAfter?.column && cursorBefore?.visible == cursorAfter?.visible,
       "NativeMatrixRenderer: resuming excludes suspended time without resetting the intro")

    let early = NativeMatrixRenderer(), late = NativeMatrixRenderer(), lateStartup = NativeMatrixRenderer()
    var scripted = NativeMatrixRenderer.Configuration()
    scripted.neoMessageLines = ["X"]
    scripted.neoMessageSpeedFactor = 1000
    let sharedStart = Date.timeIntervalSinceReferenceDate - 3
    var schedule = NeoMessageScene()
    schedule.reset(startTime: sharedStart, seed: UInt64(bitPattern: Int64(sharedStart)) &+ 1,
                   lines: scripted.neoMessageLines, speedFactor: scripted.neoMessageSpeedFactor)
    for renderer in [early, late] {
        renderer.updateConfiguration(scripted)
        renderer.resize(to: TerminalSize(columns: 100, rows: 12))
        renderer.overrideSceneStartTime = sharedStart
        renderer.start()
    }
    early.advanceToNextScene()
    let suspendedAt = Date.timeIntervalSinceReferenceDate
    Thread.sleep(forTimeInterval: 1.2)
    let duration = Date.timeIntervalSinceReferenceDate - suspendedAt
    early.shiftTimeline(by: duration)
    late.shiftTimeline(by: duration)
    late.advanceToNextScene()
    lateStartup.updateConfiguration(scripted)
    lateStartup.resize(to: TerminalSize(columns: 100, rows: 12))
    lateStartup.overrideSceneStartTime = sharedStart + duration
    lateStartup.overrideSceneContentStartTime = sharedStart
    lateStartup.start()
    lateStartup.advanceToNextScene()
    let timestamp = Date(timeIntervalSinceReferenceDate: sharedStart + schedule.scheduledDuration + 2)
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd-yy"
    let dateText = formatter.string(from: timestamp)
    formatter.dateFormat = "H:mm:ss"
    let expectedText = "Call trans opt: received. \(dateText) \(formatter.string(from: timestamp)) REC:Log>"
    var typingRNG = Xorshift64(seed: UInt64(bitPattern: Int64(sharedStart)) &+ 2)
    let typingDuration = NativeMatrixRenderer.naturalTypingTimings(for: expectedText,
                                                                 baseInterval: 1.0 / 40 / scripted.neoMessageSpeedFactor,
                                                                 rng: &typingRNG).last ?? 0
    let typingTime = sharedStart + duration + schedule.scheduledDuration + 2 + typingDuration + 0.1
    Thread.sleep(forTimeInterval: max(0, typingTime - Date.timeIntervalSinceReferenceDate))
    early.advance()
    late.advance()
    lateStartup.advance()
    let row = NativeMatrixRenderer.contentMargin
    let earlyText = (0..<100).map { early[row, $0].scalar }
    let lateText = (0..<100).map { late[row, $0].scalar }
    let startupText = (0..<100).map { lateStartup[row, $0].scalar }
    ok(String(String.UnicodeScalarView(earlyText)).contains(expectedText) && earlyText == lateText,
       "NativeMatrixRenderer: pause between display phase advances preserves identical Number-scene timestamps")
    ok(earlyText == startupText, "NativeMatrixRenderer: a display starting after resume keeps the same scripted content and seed")
}

/// Covers the rain font tables and catalog using Menlo, which ships with every macOS install.
private func rainFontTests() {
    let tables = NativeMatrixRenderer.makeRainTables(fonts: ["Menlo"])
    ok(tables.pools.count == 1 && !(tables.pools.first ?? []).isEmpty,
       "RainFont: an installed font yields one non-empty glyph pool")
    ok((tables.pools.first ?? []).count <= NativeMatrixRenderer.RainFontTables.maximumGlyphsPerFont,
       "RainFont: a pool never exceeds the per-font glyph limit")
    ok(tables.pools.flatMap { $0 }.allSatisfy { $0.value >= 0xF0000 && tables.sourceByScalar[$0] != nil },
       "RainFont: every glyph is aliased so Unicode intro text keeps the system font")
    let mixed = NativeMatrixRenderer.makeRainTables(fonts: ["Menlo", "Monaco"], characters: "ABé")
    ok(mixed.pools.count == 2 && mixed.pools.allSatisfy { pool in
        Set(pool.compactMap { mixed.sourceByScalar[$0] }) == Set("ABé".unicodeScalars)
    } && Set(mixed.pools.flatMap { $0 }).count == 6,
       "RainFont: overlapping ASCII and Unicode characters remain available in every selected font")

    ok(NativeMatrixRenderer.makeRainTables(fonts: ["No Such Font 9F3A"]).pools.isEmpty,
       "RainFont: fonts that are not installed are skipped")
    ok(NativeMatrixRenderer.makeRainTables(fonts: ["Menlo", "Menlo"]).pools.count == 1,
       "RainFont: a duplicate font adds no second pool")

    ok(RainFontCatalog.font(named: "Menlo", size: 12) != nil && RainFontCatalog.font(named: "No Such Font 9F3A", size: 12) == nil,
       "RainFontCatalog: resolves installed fonts and rejects missing ones")
    let everything = RainFontCatalog.families(alwaysInclude: [])
    ok(Set(NSFontManager.shared.availableFontFamilies).isSubset(of: Set(everything)) && everything == everything.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
       "RainFontCatalog: always lists every installed family in sorted order")
    let systemFiles = FileManager.default.enumerator(at: URL(fileURLWithPath: "/System/Library/Fonts"), includingPropertiesForKeys: nil)!
    var checkedHiddenFont = false
    for case let url as URL in systemFiles {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { continue }
        for descriptor in descriptors {
            guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                  !NSFontManager.shared.availableFontFamilies.contains(family),
                  let resolved = RainFontCatalog.font(named: family, size: 16) else { continue }
            let actualFamily = CTFontCopyFamilyName(resolved) as String
            ok(everything.contains(family) && actualFamily == family,
               "RainFontCatalog: automatically discovers hidden file-backed families and resolves their actual font")
            checkedHiddenFont = true
            break
        }
        if checkedHiddenFont { break }
    }
    ok(checkedHiddenFont, "RainFontCatalog: exercises an installed hidden system font")
    ok(RainFontCatalog.families(alwaysInclude: ["Chosen Font"]).contains("Chosen Font"),
       "RainFontCatalog: a missing selected font stays available for deselection")
    let defaultKatakana = Set((UInt32(0xFF70)...UInt32(0xFF9D)).compactMap(UnicodeScalar.init))
    let menlo = RainFontCatalog.font(named: "Menlo", size: 16)!
    let menloCoverage = CTFontCopyCharacterSet(menlo) as CharacterSet
    ok(!defaultKatakana.allSatisfy { menloCoverage.contains($0) } &&
       defaultKatakana.isSubset(of: Set(tables.sourceByScalar.values)),
       "RainFont: default katakana missing from the selected font stay in the pool for fallback")
    let customFallback = NativeMatrixRenderer.makeRainTables(fonts: ["Menlo"], characters: "Aｱ")
    ok(Set(customFallback.sourceByScalar.values) == Set("Aｱ".unicodeScalars),
       "RainFont: custom characters missing from the selected font stay in the pool for fallback")

    let renderer = NativeMatrixRenderer()
    var config = NativeMatrixRenderer.Configuration()
    config.rainFonts = ["Menlo"]
    ok(config.sanitized().rainFonts == ["Menlo"], "RainFont: configuration sanitizing keeps the selected fonts")
    renderer.updateConfiguration(config)
    ok(renderer.activeRainFonts == ["Menlo"] && !renderer.rainSourceByScalar.isEmpty && renderer.rainFontByScalar.values.allSatisfy { $0 == "Menlo" },
       "RainFont: the renderer builds glyph tables for the selected fonts")
    ok(renderer.rainSourceByScalar.keys.allSatisfy { renderer.supportedScalars.contains($0) },
       "RainFont: the renderer supports the aliased rain glyphs")
    config.characters = "A"
    renderer.updateConfiguration(config)
    ok(Set(renderer.rainSourceByScalar.values) == Set("A".unicodeScalars),
       "RainFont: custom characters use the selected font")
    config.characters = "B"
    renderer.updateConfiguration(config)
    ok(Set(renderer.rainSourceByScalar.values) == Set("B".unicodeScalars),
       "RainFont: editing characters rebuilds the font table without changing fonts")
    config.rainFonts = []
    renderer.updateConfiguration(config)
    ok(renderer.activeRainFonts.isEmpty && renderer.rainFontByScalar.isEmpty,
       "RainFont: clearing the selection drops the font glyph tables")

    config.rainFonts = ["Menlo", "Hiragino Sans"]
    config.characters = "A" + String(String.UnicodeScalarView((0x30A1...0x30FA).compactMap { UnicodeScalar($0) }))
    config.neoMessageSceneEnabled = false
    config.numberSceneEnabled = false
    config.cmdSceneEnabled = false
    config.twinkleEnabled = false
    let mixedFallback = NativeMatrixRenderer.makeRainTables(fonts: config.rainFonts, characters: config.characters)
    ok(mixedFallback.pools.count == 2 && mixedFallback.pools.allSatisfy { pool in
        Set(pool.compactMap { mixedFallback.sourceByScalar[$0] }) == Set(config.characters.unicodeScalars)
    }, "RainFont: every selected font retains the full custom set regardless of native coverage")
    renderer.updateConfiguration(config)
    renderer.resize(to: TerminalSize(columns: 80, rows: 24))
    renderer.overrideSceneStartTime = 1_000
    renderer.start()
    defer { renderer.stop() }
    var counts: [String: Int] = [:]
    for _ in 0..<120 {
        renderer.shiftTimeline(by: -0.1)
        renderer.advance()
        for row in 0..<24 {
            for column in 0..<80 {
                let cell = renderer[row, column]
                if cell.foregroundLevel > 0, let font = renderer.rainFontByScalar[cell.scalar] {
                    counts[font, default: 0] += 1
                }
            }
        }
    }
    let total = counts.values.reduce(0, +)
    let menloShare = Double(counts["Menlo", default: 0]) / Double(max(total, 1))
    ok(total > 1_000 && (0.35...0.65).contains(menloShare),
       "RainFont: rendered rain mixes selected fonts evenly with fallback-enabled glyph pools")
}

/// Exercises bundled preset coverage and switching back to the retained custom rain settings.
private func rainGlyphPresetTests() {
    let renderer = NativeMatrixRenderer()
    var config = NativeMatrixRenderer.Configuration()
    config.rainFonts = ["Menlo"]
    config.characters = "ATGC"
    renderer.updateConfiguration(config)
    let customSources = renderer.rainSourceByScalar
    for (preset, count) in [(RainGlyphSet.classic, 57), (.resurrections, 135)] {
        config.rainGlyphSet = preset
        renderer.updateConfiguration(config)
        ok(renderer.rainSourceByScalar.count == count && renderer.activeRainFonts == [preset.fontName!],
           "Rain presets: \(preset.rawValue) uses its complete bundled glyph set instead of custom characters")
        let font = RainFontCatalog.font(named: preset.fontName!, size: 16)
        let loadedURL = font.flatMap { CTFontCopyAttribute($0, kCTFontURLAttribute) as? URL }
        let bundledURL = Bundle(for: NativeMatrixRenderer.self).url(forResource: preset.fontName!, withExtension: "ttf", subdirectory: "Fonts")
        let sources = Array(renderer.rainSourceByScalar.values)
        let coverage = font.map { CTFontCopyCharacterSet($0) as CharacterSet }
        ok(loadedURL != nil && loadedURL?.resolvingSymlinksInPath() == bundledURL?.resolvingSymlinksInPath() &&
           sources.count == count && sources.allSatisfy { coverage?.contains($0) == true },
           "Rain presets: \(preset.rawValue) resolves every glyph from its bundled font")
    }
    config.rainGlyphSet = .default
    renderer.updateConfiguration(config)
    ok(renderer.activeRainFonts == ["Menlo"] && renderer.rainSourceByScalar == customSources,
       "Rain presets: Default restores the custom font and character pool")
}

/// Checks idle intro frames and cursor-only updates through the host's dirty-row contract.
private func introDirtyRowTests() {
    for neo in [true, false] {
        let renderer = NativeMatrixRenderer()
        var configuration = NativeMatrixRenderer.Configuration()
        configuration.neoMessageSceneEnabled = neo
        configuration.neoMessageLines = ["X"]
        configuration.neoMessageSpeedFactor = 1000
        renderer.updateConfiguration(configuration)
        renderer.resize(to: TerminalSize(columns: 40, rows: 12))
        renderer.overrideSceneStartTime = Date.timeIntervalSinceReferenceDate
        // This seed finishes typing X before 0.1s, without a random hesitation between the idle frames.
        renderer.overrideSceneContentStartTime = 1000
        renderer.start()
        defer { renderer.stop() }
        renderer.shiftTimeline(by: -0.1)
        renderer.advance()
        renderer.clearDirtyRows()
        renderer.shiftTimeline(by: -0.1)
        ok(!renderer.advance() && !(0..<12).contains(where: renderer.isRowDirty),
           "Intro redraw: \(neo ? "Neo" : "trace") skips an unchanged pause frame")
        renderer.shiftTimeline(by: -0.4)
        ok(renderer.advance() && (0..<12).filter(renderer.isRowDirty) == [NativeMatrixRenderer.contentMargin],
           "Intro redraw: \(neo ? "Neo" : "trace") cursor blink invalidates only its text row")
    }

    let renderer = NativeMatrixRenderer()
    var configuration = NativeMatrixRenderer.Configuration()
    configuration.neoMessageSceneEnabled = false
    configuration.numberSceneEnabled = false
    configuration.cmdSceneEnabled = true
    configuration.commands = ["printf X; sleep 2"]
    renderer.updateConfiguration(configuration)
    renderer.resize(to: TerminalSize(columns: 40, rows: 12))
    renderer.start()
    defer { renderer.stop() }
    renderer.shiftTimeline(by: -20)
    renderer.advance()
    let margin = NativeMatrixRenderer.contentMargin
    let deadline = Date(timeIntervalSinceNow: 1)
    while renderer[margin, margin].scalar != "X" && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        renderer.advance()
    }
    ok(renderer[margin, margin].scalar == "X", "Intro redraw: live custom output replaces its command at the top of the grid")
    renderer.clearDirtyRows()
    ok(!renderer.advance(), "Intro redraw: idle custom output does not request another frame")
    renderer.shiftTimeline(by: -0.5)
    ok(renderer.advance() && (0..<12).filter(renderer.isRowDirty) == [margin],
       "Intro redraw: custom cursor blink invalidates only its output row")
}

/// Compares trace grid motion over equal elapsed time at different configured frame rates.
private func traceFrameRateTests() {
    var frames: [[NativeMatrixRenderer.RenderCell]] = []
    for fps in [25.0, 60.0] {
        let renderer = NativeMatrixRenderer()
        var configuration = NativeMatrixRenderer.Configuration()
        configuration.neoMessageSceneEnabled = false
        configuration.frameRate = fps
        configuration.twinkleEnabled = false
        renderer.updateConfiguration(configuration)
        renderer.resize(to: TerminalSize(columns: 40, rows: 12))
        renderer.overrideSceneStartTime = Date.timeIntervalSinceReferenceDate
        renderer.overrideSceneContentStartTime = 1000
        renderer.start()
        defer { renderer.stop() }
        let schedule = Mirror(reflecting: renderer).children.first { $0.label == "numberIntroSchedule" }!.value
        let rainStart = Mirror(reflecting: schedule).children.first { $0.label == "rainStart" }!.value as! TimeInterval
        for frame in 0...Int(fps * 0.4) {
            let anchor = Mirror(reflecting: renderer).children.first { $0.label == "numberIntroAnchor" }!.value as! TimeInterval
            let target = rainStart + 0.005 + Double(frame) / fps
            renderer.shiftTimeline(by: Date.timeIntervalSinceReferenceDate - anchor - target)
            renderer.advance()
        }
        frames.append((0..<12).flatMap { row in (0..<40).map { renderer[row, $0] } })
    }
    ok(frames[0].contains(where: \.hasForeground), "Trace scrolling: comparison includes visible digits")
    ok(frames[0] == frames[1], "Trace scrolling: equal elapsed time produces the same grid at 25 and 60 FPS")
}

/// Exercises command side effects through renderer setup, playback, and teardown.
private func commandCaptureLifecycleTests() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("launches")
    let renderer = NativeMatrixRenderer()
    var configuration = NativeMatrixRenderer.Configuration()
    configuration.neoMessageSceneEnabled = false
    configuration.cmdSceneEnabled = true
    configuration.numberSceneEnabled = false
    configuration.commands = ["printf x >> '\(output.path)'"]
    renderer.updateConfiguration(configuration)
    renderer.resize(to: TerminalSize(columns: 40, rows: 20))
    renderer.updateConfiguration(configuration)
    Thread.sleep(forTimeInterval: 0.2)
    ok(!FileManager.default.fileExists(atPath: output.path),
       "Command capture: stopped setup and layout never execute commands")

    renderer.start()
    Thread.sleep(forTimeInterval: 0.1)
    renderer.advance()
    ok(!FileManager.default.fileExists(atPath: output.path),
       "Command capture: command typing cannot execute shell side effects early")
    renderer.shiftTimeline(by: -20)
    renderer.advance()
    Thread.sleep(forTimeInterval: 0.3)
    renderer.stop()
    ok((try? String(contentsOf: output, encoding: .utf8)) == "x",
       "Command capture: start executes exactly once after stopped setup")

    let delayed = directory.appendingPathComponent("after-stop")
    configuration.commands = ["sleep 0.4; printf x > '\(delayed.path)'"]
    renderer.updateConfiguration(configuration)
    renderer.start()
    renderer.shiftTimeline(by: -20)
    renderer.advance()
    Thread.sleep(forTimeInterval: 0.1)
    renderer.stop()
    Thread.sleep(forTimeInterval: 0.6)
    ok(!FileManager.default.fileExists(atPath: delayed.path),
       "Command capture: stop cancels active work and its later side effects")

    configuration.commands = ["printf CAPTURE"]
    renderer.updateConfiguration(configuration)
    renderer.start()
    renderer.shiftTimeline(by: -20)
    renderer.advance()
    let row = NativeMatrixRenderer.contentMargin
    func displaysCapture() -> Bool {
        let scalars = (0..<40).map { renderer[row, $0].scalar }
        return String(String.UnicodeScalarView(scalars)).contains("CAPTURE")
    }
    let deadline = Date(timeIntervalSinceNow: 2)
    repeat {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        renderer.advance()
    } while !displaysCapture() && Date() < deadline
    ok(displaysCapture(), "Command capture: an active frame reveals the captured output")
    let pauseStart = Date.timeIntervalSinceReferenceDate
    Thread.sleep(forTimeInterval: 3)
    renderer.shiftTimeline(by: Date.timeIntervalSinceReferenceDate - pauseStart)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    renderer.advance()
    ok(displaysCapture() && !renderer.consumeCmdSceneDone(),
       "Command capture: resume retains output instead of consuming its hold during suspension")
    renderer.stop()

    renderer.start()
    let capturePauseStart = Date.timeIntervalSinceReferenceDate
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 3))
    renderer.shiftTimeline(by: Date.timeIntervalSinceReferenceDate - capturePauseStart)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    renderer.advance()
    ok(!displaysCapture() && !renderer.consumeCmdSceneDone(),
        "Command capture: suspension during command typing does not skip to execution on resume")
    renderer.stop()
}

/// Custom completion must enter the full trace introduction, with its own playback clock.
private func customTraceHandoffTests() {
    let renderer = NativeMatrixRenderer()
    var configuration = NativeMatrixRenderer.Configuration()
    configuration.neoMessageSceneEnabled = false
    configuration.cmdSceneEnabled = true
    configuration.commands = ["printf CUSTOM"]
    configuration.cmdOutputHoldSeconds = 0.1
    configuration.numberSceneEnabled = true
    renderer.updateConfiguration(configuration)
    renderer.resize(to: TerminalSize(columns: 100, rows: 20))
    renderer.start()
    renderer.shiftTimeline(by: -20)
    renderer.advance()
    defer { renderer.stop() }
    var completed = false
    let deadline = Date(timeIntervalSinceNow: 10)
    while !completed && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        renderer.advance()
        completed = renderer.consumeCmdSceneDone()
    }
    ok(completed, "Custom trace: custom messages finish before the display barrier")
    renderer.advanceToNextScene()
    renderer.advance()
    let m = NativeMatrixRenderer.contentMargin
    func firstLine() -> String {
        String(String.UnicodeScalarView((m..<100).map { renderer[m, $0].scalar }))
    }
    ok(!firstLine().contains("CUSTOM") && !(m..<100).contains { renderer[m, $0].scalar.properties.numericType != nil },
       "Custom trace: handoff clears custom output and begins blinking, not number rain")
    let typingDeadline = Date(timeIntervalSinceNow: 6)
    while !firstLine().contains("Call trans opt:") && Date() < typingDeadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        renderer.advance()
    }
    ok(firstLine().contains("Call trans opt:"), "Custom trace: full trace first line types after custom completion")
}

/// Verifies that the native grid consumes output before shell completion.
private func customLiveOutputTests() {
    let renderer = NativeMatrixRenderer()
    var configuration = NativeMatrixRenderer.Configuration()
    configuration.neoMessageSceneEnabled = false
    configuration.numberSceneEnabled = false
    configuration.cmdSceneEnabled = true
    configuration.neoMessageSpeedFactor = 100
    configuration.commands = ["printf 'FIRST\\n'; sleep 1.5; printf 'SECOND\\n'; sleep 0.2"]
    renderer.updateConfiguration(configuration)
    renderer.resize(to: TerminalSize(columns: 40, rows: 12))
    renderer.start()
    renderer.shiftTimeline(by: -20)
    renderer.advance()
    defer { renderer.stop() }
    let m = NativeMatrixRenderer.contentMargin
    func row(_ index: Int) -> String {
        String(String.UnicodeScalarView((m..<(40 - m)).map { renderer[index, $0].scalar }))
    }
    let deadline = Date(timeIntervalSinceNow: 1)
    var first = false
    var sawCursor = false
    while (!first || !sawCursor) && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        renderer.advance()
        first = row(m).hasPrefix("FIRST")
        if first { sawCursor = row(m).contains("█") }
    }
    ok(first && !row(m + 1).contains("SECOND") && !renderer.consumeCmdSceneDone(),
       "Custom live output: first row appears while the command is still executing")
    ok(sawCursor, "Custom live output: the current output row includes a full-block cursor")
    let finalDeadline = Date(timeIntervalSinceNow: 2)
    while !row(m + 1).hasPrefix("SECOND") && Date() < finalDeadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        renderer.advance()
    }
    ok(row(m).hasPrefix("FIRST") && row(m + 1).hasPrefix("SECOND"),
       "Custom live output: later rows append without clearing earlier output")
    let cursorDeadline = Date(timeIntervalSinceNow: 1)
    var movedCursor = false
    while !movedCursor && Date() < cursorDeadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        renderer.advance()
        movedCursor = !row(m).contains("█") && row(m + 1).contains("█")
    }
    ok(movedCursor, "Custom live output: cursor follows the bottom output row rather than remaining at the top")
}

/// Checks clipping, scrolling and per-command clearing through the rendered grid.
private func customScrollingViewportTests() {
    let renderer = NativeMatrixRenderer()
    var configuration = NativeMatrixRenderer.Configuration()
    configuration.neoMessageSceneEnabled = false
    configuration.numberSceneEnabled = false
    configuration.cmdSceneEnabled = true
    configuration.neoMessageSpeedFactor = 100
    configuration.cmdOutputHoldSeconds = 1
    configuration.commandsRunInSequence = true
    configuration.commands = ["printf 'first\nsecond\nthird\nlast-wide\n'", "sleep 0.2; printf NEXT"]
    renderer.updateConfiguration(configuration)
    renderer.resize(to: TerminalSize(columns: 8, rows: 6))
    renderer.start()
    defer { renderer.stop() }
    let m = NativeMatrixRenderer.contentMargin
    func row(_ index: Int) -> String {
        String(String.UnicodeScalarView((m..<(8 - m)).map { renderer[index, $0].scalar }))
    }
    var scrolled = false
    var cleared = false
    var next = false
    // Allow shared startup and both command schedules, as in the sequence test below.
    let deadline = Date(timeIntervalSinceNow: 20)
    while !next && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        renderer.shiftTimeline(by: -0.1)
        renderer.advance()
        if row(m) == "thir" && row(m + 1) == "last" { scrolled = true }
        if scrolled && row(m + 1) == "    " { cleared = true }
        if row(m) == "NEXT" { next = true }
    }
    ok(scrolled, "Custom viewport: last two rows scroll into the native grid with horizontal clipping")
    ok(cleared && next && row(m + 1) == "    ", "Custom viewport: next command clears prior rows and shows only new output")
}

/// Checks command selection through observable shell side effects on each scene entry.
private func customShellCommandSequenceTests() {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: output) }
    let renderer = NativeMatrixRenderer()
    var configuration = NativeMatrixRenderer.Configuration()
    configuration.neoMessageSceneEnabled = false
    configuration.cmdSceneEnabled = true
    configuration.numberSceneEnabled = false
    configuration.commands = [
        "printf A >> '\(output.path)'; sleep 0.15; printf a >> '\(output.path)'",
        "printf b >> '\(output.path)'",
        "printf c >> '\(output.path)'",
    ]
    configuration.commandsRunInSequence = true
    configuration.neoMessageSpeedFactor = 100
    configuration.cmdOutputHoldSeconds = 0.1
    renderer.updateConfiguration(configuration)
    renderer.resize(to: TerminalSize(columns: 40, rows: 20))
    for cycle in 1...2 {
        renderer.start()
        let deadline = Date(timeIntervalSinceNow: 20)
        var completed = false
        while !completed && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            renderer.shiftTimeline(by: -0.1)
            renderer.advance()
            completed = renderer.consumeCmdSceneDone()
        }
        renderer.stop()
        ok(completed && (try? String(contentsOf: output, encoding: .utf8)) == String(repeating: "Aabc", count: cycle),
           "Custom shell commands: every scene entry waits for each command and executes all three in order")
    }
    try? FileManager.default.removeItem(at: output)
    configuration.commandsRunInSequence = false
    renderer.updateConfiguration(configuration)
    renderer.start()
    let deadline = Date(timeIntervalSinceNow: 8)
    var completed = false
    while !completed && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        renderer.shiftTimeline(by: -0.1)
        renderer.advance()
        completed = renderer.consumeCmdSceneDone()
    }
    renderer.stop()
    let result = try? String(contentsOf: output, encoding: .utf8)
    ok(completed && (result == "Aa" || result == "b" || result == "c"), "Custom shell commands: random mode executes only one command")
    configuration.commandsRunInSequence = true
    configuration.commandsShuffleSequence = true
    renderer.updateConfiguration(configuration)
    var orders: [String] = []
    for seed in [1000, 1000, 1001, 1002, 1003] {
        try? FileManager.default.removeItem(at: output)
        renderer.overrideSceneContentStartTime = Double(seed)
        renderer.overrideSceneStartTime = Date.timeIntervalSinceReferenceDate
        renderer.start()
        let deadline = Date(timeIntervalSinceNow: 12)
        var completed = false
        while !completed && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            renderer.shiftTimeline(by: -0.1)
            renderer.advance()
            completed = renderer.consumeCmdSceneDone()
        }
        renderer.stop()
        let order = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        orders.append(order)
        ok(completed && order.sorted() == Array("Aabc") && order.contains("Aa"),
           "Shuffled commands: every command runs once and finishes before the next begins")
    }
    ok(orders[0] == orders[1], "Shuffled commands: matching display seeds produce the same full order")
    ok(Set(orders).count > 1, "Shuffled commands: new scene seeds reshuffle the list")
}
