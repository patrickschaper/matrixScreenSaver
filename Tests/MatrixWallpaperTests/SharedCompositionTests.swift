import AppKit

/// Controls backing resolution without depending on the test machine's attached displays.
final class CompositionWindow: NSWindow {
    /// Backing scale requested by this fixture.
    var testScale: CGFloat = 1
    override var backingScaleFactor: CGFloat { testScale }
}

/// Captures the view through the same device-RGB BGRA context used by publication.
func scenePixels(_ view: MatrixScreenSaverView, scale: CGFloat) -> Data? {
    let width = Int(ceil(view.bounds.width * scale))
    let height = Int(ceil(view.bounds.height * scale))
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue)
    else { return nil }
    context.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    return context.data.map { Data(bytes: $0, count: width * height * 4) }
}

/// Compares frozen native output against shared publication, including static option edits.
func sharedCompositionTests() {
    for scale: CGFloat in [1, 2] {
        for vertical in [false, true] {
            let size = NSSize(width: 437, height: 293)
            let view = MatrixScreenSaverView(
                frame: NSRect(origin: .zero, size: size), isPreview: false)!
            let window = CompositionWindow(
                contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.testScale = scale
            window.contentView = view
            view.startAnimation()
            view.isWallpaperHost = true
            view.rendersWallpaperWhileHidden = true
            var options = MatrixScreenSaverView.loadSaverOptions()
            options.scanLinesVertical = vertical
            options.scanLinesIntensity = 0.25
            view.applyWallpaperOptions(options)
            let reference = scenePixels(view, scale: scale)
            let url = view.shareWallpaperFrames()
            check(
                url != nil && reference != nil && scenePixels(view, scale: scale) == reference,
                "shared frozen composition matches native at \(scale)x, vertical=\(vertical)")
            let displayID =
                window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? UInt32 ?? 0
            let reader = url.flatMap {
                try? SharedWallpaperFrame(reading: $0, displayID: displayID, pointSize: size)
            }
            let sequence = reader?.snapshot()?.sequence
            options.scanLinesIntensity = 0.75
            view.applyWallpaperOptions(options)
            _ = view.shareWallpaperFrames()
            check(
                reader?.snapshot()?.sequence != sequence
                    && scenePixels(view, scale: scale) != reference,
                "static visual option edit republishes at \(scale)x, vertical=\(vertical)")
            view.stopSharingWallpaperFrames()
            let editedReference = scenePixels(view, scale: scale)
            _ = view.shareWallpaperFrames()
            check(
                editedReference != nil && scenePixels(view, scale: scale) == editedReference,
                "edited shared pixels match uncached native composition")
            let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view)!
            for neo in [false, true] {
                options.neoMessageSceneEnabled = neo
                options.numberSceneEnabled = false
                options.diffuseEnabled = true
                view.applyWallpaperOptions(options)
                renderer.overrideSceneStartTime =
                    Date.timeIntervalSinceReferenceDate - (neo ? 2 : 120)
                renderer.start()
                for _ in 0..<12 {
                    Thread.sleep(forTimeInterval: 0.041)
                    view.animateOneFrame()
                }
                let incremental = scenePixels(view, scale: scale)
                view.stopSharingWallpaperFrames()
                let full = scenePixels(view, scale: scale)
                check(
                    incremental != nil && incremental == full,
                    "incremental \(neo ? "Neo/cursor" : "rain/diffuse") matches full composition at \(scale)x, vertical=\(vertical)"
                )
                _ = view.shareWallpaperFrames()
            }
            let resized = NSSize(width: 503, height: 347)
            window.setContentSize(resized)
            view.layout()
            let resizedURL = view.shareWallpaperFrames()
            let resizedReader = resizedURL.flatMap {
                try? SharedWallpaperFrame(reading: $0, displayID: displayID, pointSize: resized)
            }
            check(
                resizedReader?.pixelWidth == Int(resized.width * scale)
                    && resizedReader?.pixelHeight == Int(resized.height * scale),
                "resize rebuilds publication at the current backing resolution")
            view.stopAnimation()
            window.close()
        }
    }
}

/// Measures the real view's complete publication cost; never a machine-dependent CI gate.
func compositionBenchmark() {
    for (size, scale) in [
        (NSSize(width: 1728, height: 1117), CGFloat(2)),
        (NSSize(width: 1920, height: 1080), CGFloat(1)),
    ] {
        let view = MatrixScreenSaverView(
            frame: NSRect(origin: .zero, size: size), isPreview: false)!
        view.rendersWallpaperWhileHidden = true
        let window = CompositionWindow(
            contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.testScale = scale
        window.contentView = view
        view.startAnimation()
        // Start independently so a one-display fixture does not wait for absent displays.
        view.isWallpaperHost = true
        var options = MatrixScreenSaverView.loadSaverOptions()
        options.frameRate = 25
        options.characterWidth = 13
        options.characterHeight = 24
        options.neoMessageSceneEnabled = false
        options.numberSceneEnabled = false
        options.diffuseEnabled = true
        options.scanLinesVertical = true
        options.scanLinesIntensity = 0.25
        view.applyWallpaperOptions(options)
        let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view)!
        renderer.overrideSceneStartTime = Date.timeIntervalSinceReferenceDate - 120
        renderer.start()
        _ = view.shareWallpaperFrames()
        var durations: [Double] = []
        for _ in 0..<100 {
            Thread.sleep(forTimeInterval: 0.041)
            let start = ProcessInfo.processInfo.systemUptime
            view.animateOneFrame()
            durations.append(ProcessInfo.processInfo.systemUptime - start)
        }
        let sorted = durations.sorted()
        print(
            "composition \(Int(size.width * scale))x\(Int(size.height * scale)): mean=\(durations.reduce(0, +) * 1000 / Double(durations.count))ms p95=\(sorted[94] * 1000)ms (25FPS, 13x24, diffuse, vertical 0.25)"
        )
        view.stopAnimation()
        window.close()
    }
    threeDisplayCompositionBenchmark()
}

/// Measures aggregate producer work with three live compositors sharing one Core Image context.
func threeDisplayCompositionBenchmark() {
    var fixtures: [(MatrixScreenSaverView, CompositionWindow)] = []
    defer {
        for (view, window) in fixtures {
            view.stopAnimation()
            window.close()
        }
    }
    for (size, scale, seed) in [
        (NSSize(width: 1728, height: 1117), CGFloat(2), UInt64(1)),
        (NSSize(width: 1920, height: 1080), CGFloat(1), UInt64(5)),
        (NSSize(width: 1920, height: 1080), CGFloat(1), UInt64(2)),
    ] {
        let view = MatrixScreenSaverView(
            frame: NSRect(origin: .zero, size: size), isPreview: false)!
        let window = CompositionWindow(
            contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.testScale = scale
        window.contentView = view
        fixtures.append((view, window))
        view.rendersWallpaperWhileHidden = true
        view.startAnimation()
        view.isWallpaperHost = true
        var options = MatrixScreenSaverView.loadSaverOptions()
        options.frameRate = 25
        options.characterWidth = 13
        options.characterHeight = 24
        options.neoMessageSceneEnabled = false
        options.numberSceneEnabled = false
        options.diffuseEnabled = true
        options.scanLinesVertical = true
        options.scanLinesIntensity = 0.25
        view.applyWallpaperOptions(options)
        let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view)!
        renderer.seedOffset = seed
        renderer.overrideSceneStartTime = Date.timeIntervalSinceReferenceDate - 120
        renderer.start()
        _ = view.shareWallpaperFrames()
    }
    let buffers: [SharedWallpaperFrame?] = fixtures.map { stored("sharedFrameBuffer", in: $0.0) }
    let initialSequences = buffers.map { $0?.snapshot()?.sequence ?? 0 }
    var durations: [Double] = []
    for frame in 0..<200 {
        Thread.sleep(forTimeInterval: 0.041)
        let start = ProcessInfo.processInfo.systemUptime
        for (view, _) in fixtures { view.animateOneFrame() }
        if frame >= 100 { durations.append(ProcessInfo.processInfo.systemUptime - start) }
    }
    let gpuCount = fixtures.filter { view, _ in
        let compositor: SharedWallpaperCompositor? = stored("wallpaperCompositor", in: view)
        return compositor != nil
    }.count
    check(gpuCount == 3, "three-display benchmark exercises all three GPU compositors")
    check(
        zip(buffers, initialSequences).allSatisfy { buffer, initial in
            initial > 0 && (buffer?.snapshot()?.sequence ?? 0) > initial + 100
        },
        "three-display benchmark publishes changing frames rather than timing startup early returns"
    )
    let mean = durations.reduce(0, +) * 1000 / Double(durations.count)
    let p95 = durations.sorted()[94] * 1000
    print(
        "composition three-display aggregate: mean=\(mean)ms p95=\(p95)ms; 100 measured cycles after 100 warmup, includes simulation/glyph raster/publication, excludes actual timer scheduling and consumer presentation"
    )
    for (view, window) in fixtures {
        let shared = scenePixels(view, scale: window.testScale)
        view.stopSharingWallpaperFrames()
        check(
            shared != nil && shared == scenePixels(view, scale: window.testScale),
            "three-display texture reuse preserves the final dense native frame at \(window.testScale)x"
        )
    }
}
