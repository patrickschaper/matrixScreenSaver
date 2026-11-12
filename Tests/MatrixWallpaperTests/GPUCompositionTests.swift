import AppKit
import CoreImage
import Metal

/// Creates the same device-RGB BGRA storage used by shared publication.
private func gpuReferenceContext(width: Int, height: Int) -> CGContext? {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue)
}

/// Finds a sampling phase against independent Core Graphics coordinate labels, not scene colors.
///
/// - Parameters:
///   - sourceLength: Number of terminal pixels on the sampled axis.
///   - targetLength: Number of backing pixels on that axis.
///   - vertical: Whether to label rows instead of columns.
///   - context: Reused Metal-backed context with unmanaged 8-bit processing.
/// - Returns: A phase inside the longest exact interval, or nil if no tested phase matches.
private func gpuSamplingPhase(
    sourceLength: Int, targetLength: Int, vertical: Bool,
    context: CIContext
) -> CGFloat? {
    let shifts = (-100...100).map { CGFloat($0) / 100_000 }
    let sw = vertical ? 1 : sourceLength
    let sh = vertical ? sourceLength : 1
    let width = vertical ? 1 : targetLength
    let height = vertical ? targetLength : 1
    guard let source = gpuReferenceContext(width: sw, height: sh),
        let sourceBytes = source.data?.assumingMemoryBound(to: UInt8.self),
        let reference = gpuReferenceContext(width: width, height: height),
        let referenceBytes = reference.data
    else {
        check(false, "GPU sampling boundary fixture allocates its bitmaps")
        return nil
    }
    for index in 0..<sourceLength {
        sourceBytes[index * 4] = UInt8(index & 255)
        sourceBytes[index * 4 + 1] = UInt8((index >> 8) & 255)
        sourceBytes[index * 4 + 2] = 117
        sourceBytes[index * 4 + 3] = 255
    }
    guard let image = source.makeImage() else {
        check(false, "GPU sampling boundary fixture supplies an image")
        return nil
    }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    reference.interpolationQuality = .none
    reference.draw(image, in: rect)
    let expected = Data(bytes: referenceBytes, count: width * height * 4)
    let input = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
        .clampedToExtent().samplingNearest()
    var passingShifts = Set<Int>()
    var minimumDifferences = expected.count
    for (index, shift) in shifts.enumerated() {
        let transform = CGAffineTransform(
            a: CGFloat(width) / CGFloat(sw), b: 0, c: 0,
            d: CGFloat(height) / CGFloat(sh),
            tx: vertical ? 0 : shift, ty: vertical ? -shift : 0)
        var actual = Data(count: expected.count)
        actual.withUnsafeMutableBytes {
            context.render(
                input.transformed(by: transform, highQualityDownsample: false),
                toBitmap: $0.baseAddress!, rowBytes: width * 4, bounds: rect,
                format: .BGRA8, colorSpace: nil)
        }
        let differences = expected.indices.reduce(0) { $0 + (expected[$1] == actual[$1] ? 0 : 1) }
        minimumDifferences = min(minimumDifferences, differences)
        if differences == 0 { passingShifts.insert(index) }
    }
    print(
        "GPU phase sweep \(vertical ? "Y" : "X") \(sourceLength)->\(targetLength): \(passingShifts.count)/\(shifts.count) exact phases, minimum differing bytes=\(minimumDifferences)"
    )
    var best: [Int] = []
    var run: [Int] = []
    for index in shifts.indices {
        if passingShifts.contains(index) {
            run.append(index)
            if run.count > best.count { best = run }
        } else {
            run = []
        }
    }
    return best.isEmpty ? nil : shifts[best[best.count / 2]]
}

/// Keeps the smallest counterexamples that reject a universal hard-coded sampling offset.
private func gpuSamplingBoundaryTests(context: CIContext) {
    // Reduced from a sweep of all 17 cell presets at eleven canvas sizes and both scales.
    for (sourceLength, targetLength, vertical) in [
        (288, 293, true), (432, 437, false),
        (3838, 7680, false), (3818, 7680, false),
    ] {
        check(
            gpuSamplingPhase(
                sourceLength: sourceLength, targetLength: targetLength,
                vertical: vertical, context: context) != nil,
            "Core Image per-geometry phase can match \(sourceLength)->\(targetLength) \(vertical ? "Y" : "X") sampling"
        )
    }
}

/// Completes GPU readback into private storage before any shared publication is allowed.
///
/// - Parameters:
///   - image: Fully composed image in backing-pixel coordinates.
///   - context: Reused Metal-backed context.
///   - output: Private BGRA bitmap, never the mapped publication buffer.
/// - Throws: A task-submission or GPU-completion error.
private func completeGPUImage(_ image: CIImage, context: CIContext, output: CGContext) throws {
    let destination = CIRenderDestination(
        bitmapData: output.data!, width: output.width,
        height: output.height, bytesPerRow: output.bytesPerRow, format: .BGRA8)
    destination.colorSpace = nil
    destination.alphaMode = .premultiplied
    destination.isFlipped = true
    destination.isDithered = false
    let rect = CGRect(x: 0, y: 0, width: output.width, height: output.height)
    let task = try context.startTask(toRender: image, from: rect, to: destination, at: .zero)
    _ = try task.waitUntilCompleted()
}

/// Tests direct GPU readback through a private shared-storage texture, without a bitmap conversion copy.
private final class GPUReadbackSurface {
    private let buffer: MTLBuffer
    private let texture: MTLTexture
    private let bytesPerRow: Int

    /// Allocates one reusable, aligned output surface for the given backing dimensions.
    init?(device: MTLDevice, width: Int, height: Int) {
        let alignment = max(1, device.minimumLinearTextureAlignment(for: .bgra8Unorm))
        let rowBytes = (width * 4 + alignment - 1) / alignment * alignment
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard
            let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
            let texture = buffer.makeTexture(
                descriptor: descriptor, offset: 0, bytesPerRow: rowBytes)
        else { return nil }
        self.buffer = buffer
        self.texture = texture
        bytesPerRow = rowBytes
    }

    /// Completes GPU work before exposing pixels for a synchronous copy into the unchanged transport.
    ///
    /// The returned image borrows private scratch pixels until the next render. It must never
    /// become a presentation image; `SharedWallpaperFrame.publish` makes the immutable copies.
    /// - Throws: A task-submission, GPU-completion, or image-creation error.
    func render(_ image: CIImage, context: CIContext) throws -> CGImage {
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: nil)
        destination.colorSpace = nil
        destination.alphaMode = .premultiplied
        destination.isFlipped = true
        destination.isDithered = false
        let rect = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        let task = try context.startTask(toRender: image, from: rect, to: destination, at: .zero)
        _ = try task.waitUntilCompleted()
        let retainedBuffer = Unmanaged<AnyObject>.passRetained(buffer as AnyObject).toOpaque()
        guard
            let provider = CGDataProvider(
                dataInfo: retainedBuffer, data: buffer.contents(),
                size: bytesPerRow * texture.height,
                releaseData: { info, _, _ in
                    if let info { Unmanaged<AnyObject>.fromOpaque(info).release() }
                })
        else {
            Unmanaged<AnyObject>.fromOpaque(retainedBuffer).release()
            throw NSError(domain: "GPUReadbackSurface", code: 1)
        }
        guard
            let result = CGImage(
                width: texture.width, height: texture.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                        | CGImageAlphaInfo.premultipliedFirst.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw NSError(domain: "GPUReadbackSurface", code: 2)
        }
        return result
    }
}

/// Measures changing GPU composition, completed readback, publication, and both immutable snapshots.
///
/// This excludes simulation and dirty-glyph rasterization; it cannot establish actual-host acceptance.
private func gpuPublicationBenchmark(
    terminal: CGContext, transform: CGAffineTransform, base: CGImage,
    mask: CGImage, scanLines: CGImage?, context: CIContext, device: MTLDevice,
    size: CGSize, scale: CGFloat
) {
    do {
        let background = CIImage(cgImage: base, options: [.colorSpace: NSNull()])
        let stripes =
            scanLines.map { CIImage(cgImage: $0, options: [.colorSpace: NSNull()]) }
            ?? CIImage.empty()
        for engine in ["CPU", "GPU-bitmap", "GPU-linear"] {
            let gpu = engine != "CPU"
            let producer = try SharedWallpaperFrame(displayID: 0, pointSize: size, scale: scale)
            let reader = try SharedWallpaperFrame(
                reading: producer.url, displayID: 0, pointSize: size)
            let width = producer.pixelWidth
            let height = producer.pixelHeight
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            let maskImage = CIImage(cgImage: mask, options: [.colorSpace: NSNull()])
            guard let surface = GPUReadbackSurface(device: device, width: width, height: height)
            else {
                throw NSError(domain: "GPUCompositionBenchmark", code: 3)
            }
            var durations: [Double] = []
            var producerDurations: [Double] = []
            var lastSequence: UInt64 = 0
            var previousGreen: UInt8?
            var retainedImage: CGImage?
            var retainedGreen: UInt8 = 0
            let markerX = Int(25 * CGFloat(width) / CGFloat(terminal.width))
            let markerY = height - 1 - Int(30 * CGFloat(height) / CGFloat(terminal.height))
            let markerOffset = (markerY * width + markerX) * 4 + 1
            for frame in 0..<65 {
                let duration: Double = try autoreleasepool {
                    let start = ProcessInfo.processInfo.systemUptime
                    terminal.setFillColor(
                        CGColor(red: 0, green: CGFloat(frame % 64) / 63, blue: 0, alpha: 1))
                    terminal.fill(CGRect(x: 20, y: 20, width: 13, height: 24))
                    guard let input = terminal.makeImage() else {
                        throw NSError(domain: "GPUCompositionBenchmark", code: 1)
                    }
                    let image: CGImage?
                    if gpu {
                        let foreground = CIImage(cgImage: input, options: [.colorSpace: NSNull()])
                            .clampedToExtent().samplingNearest().transformed(
                                by: transform, highQualityDownsample: false)
                        let clipped = foreground.applyingFilter(
                            "CIBlendWithAlphaMask",
                            parameters: [
                                kCIInputBackgroundImageKey: CIImage.empty(),
                                kCIInputMaskImageKey: maskImage,
                            ]
                        ).insertingIntermediate(cache: false)
                        let scene = clipped.composited(over: background).insertingIntermediate(
                            cache: false)
                        if engine == "GPU-linear" {
                            image = try surface.render(
                                stripes.composited(over: scene), context: context)
                        } else {
                            guard let output = gpuReferenceContext(width: width, height: height)
                            else {
                                throw NSError(domain: "GPUCompositionBenchmark", code: 1)
                            }
                            try completeGPUImage(
                                stripes.composited(over: scene), context: context, output: output)
                            image = output.makeImage()
                        }
                    } else {
                        image = input
                    }
                    guard let image,
                        producer.publish({ target in
                            if gpu {
                                target.setBlendMode(.copy)
                                target.interpolationQuality = .none
                                target.draw(image, in: rect)
                            } else {
                                target.saveGState()
                                target.setBlendMode(.copy)
                                target.interpolationQuality = .none
                                target.draw(base, in: rect)
                                target.restoreGState()
                                target.saveGState()
                                target.scaleBy(x: scale, y: scale)
                                target.interpolationQuality = .none
                                let bounds = CGRect(origin: .zero, size: size)
                                target.saveGState()
                                target.clip(to: bounds.insetBy(dx: 0, dy: 10))
                                target.draw(image, in: bounds)
                                target.restoreGState()
                                target.saveGState()
                                target.clip(to: [
                                    CGRect(x: 0, y: 0, width: size.width, height: 10),
                                    CGRect(
                                        x: 0, y: size.height - 10, width: size.width, height: 10),
                                ])
                                NSGraphicsContext.saveGraphicsState()
                                NSGraphicsContext.current = NSGraphicsContext(
                                    cgContext: target, flipped: false)
                                NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
                                    .addClip()
                                target.draw(image, in: bounds)
                                NSGraphicsContext.restoreGraphicsState()
                                target.restoreGState()
                                target.restoreGState()
                                if let scanLines { target.draw(scanLines, in: rect) }
                            }
                        }) != nil
                    else {
                        throw NSError(domain: "GPUCompositionBenchmark", code: 2)
                    }
                    let producerEnd = ProcessInfo.processInfo.systemUptime
                    guard let snapshot = reader.snapshot(), snapshot.sequence > lastSequence else {
                        throw NSError(domain: "GPUCompositionBenchmark", code: 2)
                    }
                    lastSequence = snapshot.sequence
                    if frame >= 5 { producerDurations.append(producerEnd - start) }
                    let end = ProcessInfo.processInfo.systemUptime
                    guard let pixels = snapshot.image.dataProvider?.data else {
                        throw NSError(domain: "GPUCompositionBenchmark", code: 4)
                    }
                    let green = (pixels as Data)[markerOffset]
                    guard previousGreen == nil || previousGreen != green else {
                        throw NSError(domain: "GPUCompositionBenchmark", code: 5)
                    }
                    previousGreen = green
                    if frame == 1 {
                        retainedImage = snapshot.image
                        retainedGreen = green
                    }
                    return end - start
                }
                if frame >= 5 { durations.append(duration) }
            }
            let mean = durations.reduce(0, +) * 1000 / Double(durations.count)
            let producerMean =
                producerDurations.reduce(0, +) * 1000 / Double(producerDurations.count)
            let p95 = durations.sorted()[Int(ceil(Double(durations.count) * 0.95)) - 1] * 1000
            print(
                "\(engine) publication \(width)x\(height): producer-mean=\(producerMean)ms total-mean=\(mean)ms total-p95=\(p95)ms; 60 changing frames after 5 warmup, includes publication/immutable snapshots, excludes simulation/glyph rasterization/dirty-band clipping"
            )
            check(
                lastSequence == 65,
                "\(gpu ? "GPU" : "CPU") benchmark publishes and consumes every completed changing frame"
            )
            let retainedPixels = retainedImage?.dataProvider?.data
            check(
                retainedPixels.map { ($0 as Data)[markerOffset] == retainedGreen } == true,
                "\(engine) readback reuse leaves old presentation images immutable")
        }
    } catch {
        check(false, "GPU publication benchmark completes without partial publication: \(error)")
    }
}

/// Exercises the production compositor's failure boundary, scratch reuse, and recreation.
private func gpuPublicationFailureTests() {
    let size = CGSize(width: 37, height: 23)
    guard let base = gpuReferenceContext(width: 37, height: 23),
        let mask = gpuReferenceContext(width: 37, height: 23),
        let terminal = gpuReferenceContext(width: 37, height: 23),
        let invalid = gpuReferenceContext(width: 1, height: 1)?.makeImage()
    else {
        check(false, "GPU publication failure fixture allocates its layers")
        return
    }
    let rect = CGRect(origin: .zero, size: size)
    base.setFillColor(CGColor(gray: 0, alpha: 1))
    base.fill(rect)
    mask.setFillColor(CGColor(gray: 1, alpha: 1))
    mask.fill(rect)
    terminal.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    terminal.fill(rect)
    guard let baseImage = base.makeImage(), let maskImage = mask.makeImage(),
        let green = terminal.makeImage(),
        let compositor = SharedWallpaperCompositor(
            base: baseImage, mask: maskImage, scanLines: nil, terminalSize: size)
    else {
        check(false, "GPU publication failure fixture creates the production compositor")
        return
    }
    do {
        let producer = try SharedWallpaperFrame(displayID: 0, pointSize: size, scale: 1)
        let reader = try SharedWallpaperFrame(reading: producer.url, displayID: 0, pointSize: size)
        guard let first = try compositor.publish(terminal: green, cursor: nil, to: producer),
            let firstPixels = first.dataProvider?.data, let snapshot = reader.snapshot()
        else {
            throw NSError(domain: "GPUCompositionFixture", code: 3)
        }
        let original = firstPixels as Data
        let greenPixels = green.dataProvider?.data.map { $0 as Data }
        check(
            original == greenPixels,
            "production GPU preserves native device-RGB pixels with an aligned scratch stride")
        do {
            _ = try compositor.publish(terminal: invalid, cursor: nil, to: producer)
            check(false, "incompatible GPU input is rejected before publication")
        } catch {
            check(
                reader.snapshot()?.sequence == snapshot.sequence,
                "GPU failure does not advance or refresh a partial shared frame")
        }
        terminal.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        terminal.fill(rect)
        guard let red = terminal.makeImage(),
            let second = try compositor.publish(terminal: red, cursor: nil, to: producer),
            let secondPixels = second.dataProvider?.data
        else {
            throw NSError(domain: "GPUCompositionFixture", code: 4)
        }
        let redPixels = red.dataProvider?.data.map { $0 as Data }
        check(
            (secondPixels as Data) == redPixels && (secondPixels as Data) != original,
            "production GPU scratch reuse publishes changed pixels rather than a cached source")
        check(
            first.dataProvider?.data.map { $0 as Data } == original,
            "production GPU scratch reuse cannot mutate an old presentation image")
        let recreated = SharedWallpaperCompositor(
            base: baseImage, mask: maskImage, scanLines: nil, terminalSize: size)
        check(
            try recreated?.publish(terminal: red, cursor: nil, to: producer) != nil
                && reader.snapshot()?.sequence == 3,
            "GPU resource recreation preserves transport sequence and publication")
        check(
            SharedWallpaperCompositor(
                base: baseImage, mask: maskImage, scanLines: nil, terminalSize: .zero) == nil,
            "unsupported GPU layout declines composition instead of publishing incomplete pixels")
    } catch {
        check(false, "production GPU publication checks complete: \(error)")
    }
}

/// Confirms that preview chrome retains its native CPU path at both backing scales.
private func gpuPreviewFallbackTests() {
    for scale: CGFloat in [1, 2] {
        let view = MatrixScreenSaverView(
            frame: NSRect(x: 0, y: 0, width: 437, height: 293), isPreview: true)!
        let window = CompositionWindow(
            contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.testScale = scale
        window.contentView = view
        view.startAnimation()
        view.isWallpaperHost = true
        let reference = scenePixels(view, scale: scale)
        _ = view.shareWallpaperFrames()
        let compositor: SharedWallpaperCompositor? = stored("wallpaperCompositor", in: view)
        check(
            compositor == nil && reference != nil && scenePixels(view, scale: scale) == reference,
            "preview chrome retains byte-equivalent CPU composition at \(scale)x")
        view.stopAnimation()
        window.close()
    }
}

/// Characterizes the scaling and source-over primitives before attempting rounded clipping or integration.
///
/// Uses actual frozen renderer layers and an independent native full-scene reference.
/// Run explicitly with `./wallpaper-tests.sh --gpu-composition-tests`; failure blocks integration.
func gpuCompositionFeasibilityTests(benchmark: Bool = false) {
    guard let device = MTLCreateSystemDefaultDevice() else {
        check(false, "GPU feasibility requires an available Metal device")
        return
    }
    let candidates: [(String, CIContext)] = [
        (
            "unmanaged-byte",
            CIContext(
                mtlDevice: device,
                options: [
                    .workingColorSpace: NSNull(), .workingFormat: CIFormat.RGBA8,
                ])
        )
    ]
    gpuSamplingBoundaryTests(context: candidates[0].1)
    gpuPublicationFailureTests()
    gpuPreviewFallbackTests()
    let canvases =
        benchmark
        ? [(NSSize(width: 1728, height: 1117), 2), (NSSize(width: 1920, height: 1080), 1)]
        : [(NSSize(width: 437, height: 293), 1), (NSSize(width: 437, height: 293), 2)]
    let scenes =
        benchmark
        ? [(true, false, 0.25)]
        : [
            (false, false, 0.0), (false, false, 0.25), (true, false, 0.75),
            (true, false, 1.0), (false, true, 0.25), (true, true, 0.75),
        ]
    for (size, scale) in canvases {
        for (vertical, neo, intensity) in scenes {
            let width = Int(size.width) * scale
            let height = Int(size.height) * scale
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            let view = MatrixScreenSaverView(
                frame: NSRect(origin: .zero, size: size), isPreview: false)!
            let window = CompositionWindow(
                contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.testScale = CGFloat(scale)
            window.contentView = view
            view.startAnimation()
            view.isWallpaperHost = true
            view.rendersWallpaperWhileHidden = true
            defer {
                view.stopAnimation()
                window.close()
            }
            var options = MatrixScreenSaverView.loadSaverOptions()
            options.characterWidth = 13
            options.characterHeight = 24
            options.neoMessageSceneEnabled = neo
            options.neoMessageLines = ["Wake up, Neo."]
            options.numberSceneEnabled = false
            options.diffuseEnabled = true
            options.scanLinesIntensity = intensity
            options.scanLinesVertical = vertical
            view.applyWallpaperOptions(options)
            let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view)!
            renderer.overrideSceneStartTime = Date.timeIntervalSinceReferenceDate - (neo ? 2 : 120)
            renderer.start()
            _ = view.shareWallpaperFrames()
            for _ in 0..<(neo ? 4 : 12) {
                Thread.sleep(forTimeInterval: 0.041)
                view.animateOneFrame()
            }
            guard let frameContext: CGContext = stored("nativeFrameContext", in: view),
                let terminal = frameContext.makeImage(),
                let base: CGImage = stored("wallpaperSceneBase", in: view),
                let reference = gpuReferenceContext(width: width, height: height),
                let control = gpuReferenceContext(width: width, height: height)
            else {
                check(false, "GPU feasibility fixture supplies real renderer layers")
                return
            }
            reference.interpolationQuality = .none
            reference.draw(base, in: rect)
            reference.draw(terminal, in: rect)
            guard let image = reference.makeImage(), let bytes = reference.data else {
                check(false, "GPU feasibility reference is readable")
                return
            }
            let expected = Data(bytes: bytes, count: width * height * 4)
            control.interpolationQuality = .none
            control.draw(image, in: rect)
            check(
                control.data.map { Data(bytes: $0, count: expected.count) } == expected,
                "GPU fixture CPU round-trip preserves orientation and BGRA bytes at \(scale)x")
            check(
                expected.enumerated().contains { $0.offset % 4 != 3 && $0.element > 32 },
                "GPU fixture contains visible rain rather than an empty frame at \(scale)x")
            guard
                let samplingContext = gpuReferenceContext(
                    width: terminal.width, height: terminal.height),
                let samplingBytes = samplingContext.data?.assumingMemoryBound(to: UInt8.self)
            else {
                check(false, "GPU deterministic sampling fixture is writable")
                return
            }
            // Distinct opaque neighbours expose sampling-boundary differences even in blank rain rows.
            for y in 0..<terminal.height {
                for x in 0..<terminal.width {
                    let offset = y * samplingContext.bytesPerRow + x * 4
                    samplingBytes[offset] = UInt8(y % 251)
                    samplingBytes[offset + 1] = UInt8(x % 251)
                    samplingBytes[offset + 2] = UInt8((x + y) % 251)
                    samplingBytes[offset + 3] = 255
                }
            }
            guard let samplingImage = samplingContext.makeImage() else {
                check(false, "GPU deterministic sampling fixture produces an image")
                return
            }
            view.stopSharingWallpaperFrames()
            guard let fullReference = scenePixels(view, scale: CGFloat(scale)) else {
                check(false, "GPU full-scene reference captures native output")
                return
            }
            _ = view.shareWallpaperFrames()
            let activeCompositor: SharedWallpaperCompositor? = stored(
                "wallpaperCompositor", in: view)
            check(
                activeCompositor != nil, "production wallpaper publication uses the GPU compositor")
            check(
                scenePixels(view, scale: CGFloat(scale)) == fullReference,
                "production GPU publication matches the independent full native frame")
            let scanLines: CGImage? = stored("wallpaperScanLines", in: view)
            guard let maskContext = gpuReferenceContext(width: width, height: height) else {
                check(false, "GPU full-scene fixture supplies scanline and rounded-mask layers")
                return
            }
            maskContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: maskContext, flipped: false)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: view.bounds, xRadius: 10, yRadius: 10).fill()
            NSGraphicsContext.restoreGraphicsState()
            guard let mask = maskContext.makeImage() else {
                check(false, "GPU rounded-mask fixture produces an image")
                return
            }
            guard let cornerContext = gpuReferenceContext(width: width, height: height),
                let cornerBytes = cornerContext.data
            else {
                check(false, "GPU corner reference allocates a bitmap")
                return
            }
            cornerContext.draw(base, in: rect)
            cornerContext.saveGState()
            cornerContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cornerContext, flipped: false)
            NSBezierPath(roundedRect: view.bounds, xRadius: 10, yRadius: 10).addClip()
            cornerContext.interpolationQuality = .none
            cornerContext.draw(samplingImage, in: view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            cornerContext.restoreGState()
            if let scanLines { cornerContext.draw(scanLines, in: rect) }
            let cornerReference = Data(bytes: cornerBytes, count: width * height * 4)
            guard
                let phaseX = gpuSamplingPhase(
                    sourceLength: terminal.width, targetLength: width,
                    vertical: false, context: candidates[0].1),
                let phaseY = gpuSamplingPhase(
                    sourceLength: terminal.height, targetLength: height,
                    vertical: true, context: candidates[0].1)
            else {
                check(false, "Core Image sampling phases are available for the frozen scene")
                return
            }
            let terminalTransform = CGAffineTransform(
                a: rect.width / CGFloat(terminal.width), b: 0, c: 0,
                d: rect.height / CGFloat(terminal.height), tx: phaseX, ty: -phaseY)
            guard let cursorContext = gpuReferenceContext(width: width, height: height) else {
                check(false, "GPU cursor fixture allocates a bitmap")
                return
            }
            cursorContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            if let cursor = renderer.neoSceneCursor, cursor.visible {
                let palette = renderer.levelColors
                let color = palette[min(max(palette.count / 2, 1), palette.count - 1)]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(
                    cgContext: cursorContext, flipped: false)
                NSColor(
                    calibratedRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                    blue: CGFloat(color.blue) / 255, alpha: 1
                ).setFill()
                let x = CGFloat(cursor.column * options.characterWidth)
                let y =
                    size.height - CGFloat(NativeMatrixRenderer.contentMargin + 1)
                    * CGFloat(options.characterHeight)
                NSRect(
                    x: x, y: y, width: CGFloat(options.characterWidth),
                    height: CGFloat(options.characterHeight)
                ).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            if neo {
                check(
                    renderer.neoSceneCursor?.visible == true,
                    "GPU Neo fixture exercises a visible cursor")
            }
            guard let cursorImage = cursorContext.makeImage() else {
                check(false, "GPU cursor fixture produces an image")
                return
            }
            for (name, context) in candidates {
                let inputOptions: [CIImageOption: Any] = [.colorSpace: NSNull()]
                let samplingInput = CIImage(cgImage: samplingImage, options: inputOptions)
                    .samplingNearest()
                let sourceRect = CGRect(
                    x: 0, y: 0, width: samplingImage.width, height: samplingImage.height)
                let sourceCount = samplingContext.bytesPerRow * samplingContext.height
                var identity = Data(count: sourceCount)
                identity.withUnsafeMutableBytes {
                    context.render(
                        samplingInput, toBitmap: $0.baseAddress!,
                        rowBytes: samplingContext.bytesPerRow,
                        bounds: sourceRect, format: .BGRA8, colorSpace: nil)
                }
                check(
                    identity == Data(bytes: samplingBytes, count: sourceCount),
                    "Metal Core Image \(name) unscaled BGRA round-trip preserves fixture bytes")
                let background = CIImage(cgImage: base, options: inputOptions).samplingNearest()
                    .transformed(
                        by: CGAffineTransform(
                            scaleX: rect.width / CGFloat(base.width),
                            y: rect.height / CGFloat(base.height)))
                let foreground = CIImage(cgImage: terminal, options: inputOptions).clampedToExtent()
                    .samplingNearest()
                    .transformed(by: terminalTransform, highQualityDownsample: false)
                let composed = foreground.composited(over: background)
                var actual = Data(count: expected.count)
                actual.withUnsafeMutableBytes {
                    context.render(
                        composed, toBitmap: $0.baseAddress!, rowBytes: width * 4,
                        bounds: rect, format: .BGRA8, colorSpace: nil)
                }
                var differing = 0
                var maximumDelta = 0
                var first = "none"
                for offset in expected.indices where expected[offset] != actual[offset] {
                    if differing == 0 {
                        first =
                            "x=\((offset / 4) % width) y=\(offset / (width * 4)) BGRA-channel=\(offset % 4) CPU=\(expected[offset]) GPU=\(actual[offset])"
                    }
                    differing += 1
                    maximumDelta = max(
                        maximumDelta, abs(Int(expected[offset]) - Int(actual[offset])))
                }
                print(
                    "GPU primitive \(name) \(scale)x (\(terminal.width)x\(terminal.height) -> \(width)x\(height)): differing-bytes=\(differing)/\(expected.count), max-delta=\(maximumDelta), first: \(first)"
                )
                check(
                    actual == expected,
                    "Metal Core Image \(name) preserves scaled rain source-over bytes at \(scale)x")
                guard let scaleReference = gpuReferenceContext(width: width, height: height),
                    let sourceBytes = scaleReference.data
                else {
                    check(false, "GPU scale-only reference is readable")
                    return
                }
                scaleReference.interpolationQuality = .none
                scaleReference.draw(samplingImage, in: rect)
                let expectedScaled = Data(bytes: sourceBytes, count: expected.count)
                let sampling = samplingInput.clampedToExtent().samplingNearest()
                    .transformed(by: terminalTransform, highQualityDownsample: false)
                actual.withUnsafeMutableBytes {
                    context.render(
                        sampling, toBitmap: $0.baseAddress!, rowBytes: width * 4,
                        bounds: rect, format: .BGRA8, colorSpace: nil)
                }
                let scaleDifferences = expectedScaled.indices.filter {
                    expectedScaled[$0] != actual[$0]
                }.count
                let firstScaled = expectedScaled.indices.first { expectedScaled[$0] != actual[$0] }
                let detail =
                    firstScaled.map {
                        "x=\(($0 / 4) % width) y=\($0 / (width * 4)) BGRA-channel=\($0 % 4) CPU=\(expectedScaled[$0]) GPU=\(actual[$0])"
                    } ?? "none"
                print(
                    "GPU scale-only \(name) \(scale)x: differing-bytes=\(scaleDifferences), first: \(detail)"
                )
                check(
                    actual == expectedScaled,
                    "Metal Core Image \(name) deterministic nearest sampling matches Core Graphics at \(scale)x"
                )
                let clipped = foreground.applyingFilter(
                    "CIBlendWithAlphaMask",
                    parameters: [
                        kCIInputBackgroundImageKey: CIImage.empty(),
                        kCIInputMaskImageKey: CIImage(cgImage: mask, options: inputOptions),
                    ]
                ).insertingIntermediate(cache: false)
                let cursor = CIImage(cgImage: cursorImage, options: inputOptions)
                    .applyingFilter(
                        "CIBlendWithAlphaMask",
                        parameters: [
                            kCIInputBackgroundImageKey: CIImage.empty(),
                            kCIInputMaskImageKey: CIImage(cgImage: mask, options: inputOptions),
                        ]
                    ).insertingIntermediate(cache: false)
                let scene = clipped.composited(over: background).insertingIntermediate(cache: false)
                let withCursor = cursor.composited(over: scene).insertingIntermediate(cache: false)
                let stripes =
                    scanLines.map { CIImage(cgImage: $0, options: inputOptions) } ?? CIImage.empty()
                let fullScene = stripes.composited(over: withCursor)
                do {
                    guard let output = gpuReferenceContext(width: width, height: height),
                        let bytes = output.data
                    else {
                        throw NSError(domain: "GPUCompositionFixture", code: 1)
                    }
                    try completeGPUImage(fullScene, context: context, output: output)
                    actual = Data(bytes: bytes, count: fullReference.count)
                    check(
                        actual == fullReference,
                        "Core Image bitmap-destination fidelity holds before testing linear readback"
                    )
                    guard
                        let surface = GPUReadbackSurface(
                            device: device, width: width, height: height)
                    else {
                        throw NSError(domain: "GPUCompositionFixture", code: 2)
                    }
                    let image = try surface.render(fullScene, context: context)
                    output.setBlendMode(.copy)
                    output.interpolationQuality = .none
                    output.draw(image, in: rect)
                    actual = Data(bytes: bytes, count: fullReference.count)
                } catch {
                    check(false, "GPU full composition completes before readback: \(error)")
                    return
                }
                let fullDifferences = fullReference.indices.filter {
                    fullReference[$0] != actual[$0]
                }.count
                let firstFull = fullReference.indices.first { fullReference[$0] != actual[$0] }
                let fullDetail =
                    firstFull.map {
                        "x=\(($0 / 4) % width) y=\($0 / (width * 4)) BGRA-channel=\($0 % 4) CPU=\(fullReference[$0]) GPU=\(actual[$0])"
                    } ?? "none"
                print(
                    "GPU full scene \(name) \(scale)x neo=\(neo) vertical=\(vertical) intensity=\(intensity): differing-bytes=\(fullDifferences), first: \(fullDetail)"
                )
                check(
                    actual == fullReference,
                    "Metal Core Image \(name) rounded scene, cursor, and scanlines match native at \(scale)x neo=\(neo) vertical=\(vertical) intensity=\(intensity)"
                )
                let filledCorners = sampling.applyingFilter(
                    "CIBlendWithAlphaMask",
                    parameters: [
                        kCIInputBackgroundImageKey: CIImage.empty(),
                        kCIInputMaskImageKey: CIImage(cgImage: mask, options: inputOptions),
                    ]
                ).insertingIntermediate(cache: false).composited(over: background)
                    .insertingIntermediate(cache: false)
                actual.withUnsafeMutableBytes {
                    context.render(
                        stripes.composited(over: filledCorners), toBitmap: $0.baseAddress!,
                        rowBytes: width * 4,
                        bounds: rect, format: .BGRA8, colorSpace: nil)
                }
                let cornerDifferences = cornerReference.indices.filter {
                    cornerReference[$0] != actual[$0]
                }.count
                print(
                    "GPU filled corners \(scale)x intensity=\(intensity): differing-bytes=\(cornerDifferences)"
                )
                check(
                    actual == cornerReference,
                    "GPU rounded coverage preserves fully populated corner pixels at \(scale)x intensity=\(intensity)"
                )
                if benchmark && failures == 0 {
                    gpuPublicationBenchmark(
                        terminal: frameContext, transform: terminalTransform, base: base,
                        mask: mask, scanLines: scanLines, context: context, device: device,
                        size: size, scale: CGFloat(scale))
                }
            }
        }
    }
}
