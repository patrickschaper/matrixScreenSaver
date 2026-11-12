import CoreGraphics
import CoreImage
import Foundation
import Metal

/// Composes wallpaper layers on the GPU before synchronously copying completed pixels into transport.
final class SharedWallpaperCompositor {
    /// Reuses compiled kernels and the command queue across display-local compositors.
    private static let renderer: (device: MTLDevice, context: CIContext)? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return (
            device,
            CIContext(
                mtlDevice: device,
                options: [
                    .workingColorSpace: NSNull(), .workingFormat: CIFormat.RGBA8,
                ])
        )
    }()

    private let context: CIContext
    private let background: CIImage
    private let mask: CIImage
    private let scanLines: CIImage
    private let transform: CGAffineTransform
    private let terminalSize: CGSize
    private let output: MTLBuffer
    private let terminalSurface: (buffer: MTLBuffer, texture: MTLTexture, bytesPerRow: Int)
    private let destination: CIRenderDestination
    private let pixelBounds: CGRect
    private let bytesPerRow: Int

    /// Creates resources only when Metal and exact Core Graphics sampling are available.
    ///
    /// - Parameters:
    ///   - base: Cached opaque background at backing resolution.
    ///   - mask: Cached rounded terminal coverage at that same resolution.
    ///   - scanLines: Cached transparent stripes, or nil when disabled.
    ///   - terminalSize: Unscaled dirty-row bitmap dimensions.
    init?(base: CGImage, mask: CGImage, scanLines: CGImage?, terminalSize: CGSize) {
        guard let renderer = Self.renderer,
            let phaseX = Self.samplingPhase(
                source: Int(terminalSize.width), target: base.width,
                vertical: false, context: renderer.context),
            let phaseY = Self.samplingPhase(
                source: Int(terminalSize.height), target: base.height,
                vertical: true, context: renderer.context)
        else { return nil }
        guard
            let outputSurface = Self.makeSurface(
                device: renderer.device, width: base.width, height: base.height),
            let terminalSurface = Self.makeSurface(
                device: renderer.device, width: Int(terminalSize.width),
                height: Int(terminalSize.height))
        else { return nil }
        context = renderer.context
        let options: [CIImageOption: Any] = [.colorSpace: NSNull()]
        background = CIImage(cgImage: base, options: options)
        self.mask = CIImage(cgImage: mask, options: options)
        self.scanLines = scanLines.map { CIImage(cgImage: $0, options: options) } ?? CIImage.empty()
        self.terminalSize = terminalSize
        transform = CGAffineTransform(
            a: CGFloat(base.width) / terminalSize.width, b: 0, c: 0,
            d: CGFloat(base.height) / terminalSize.height, tx: phaseX, ty: -phaseY)
        output = outputSurface.buffer
        bytesPerRow = outputSurface.bytesPerRow
        self.terminalSurface = terminalSurface
        pixelBounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        destination = CIRenderDestination(mtlTexture: outputSurface.texture, commandBuffer: nil)
        destination.colorSpace = nil
        destination.alphaMode = .premultiplied
        destination.isFlipped = true
        destination.isDithered = false
    }

    /// Publishes only after GPU completion, leaving partial or failed renders in private scratch storage.
    ///
    /// - Parameters:
    ///   - terminal: Current immutable snapshot of the native dirty-row bitmap.
    ///   - cursor: Optional full-resolution cursor raster, not yet rounded-clipped.
    ///   - buffer: Existing locked transport, which makes its own immutable presentation copy.
    /// - Returns: The transport's immutable presentation image, or nil under lock contention.
    /// - Throws: GPU submission/completion failure or incompatible frame dimensions.
    func publish(terminal: CGImage, cursor: CGImage?, to buffer: SharedWallpaperFrame) throws
        -> CGImage?
    {
        guard terminal.width == Int(terminalSize.width),
            terminal.height == Int(terminalSize.height),
            buffer.pixelWidth == Int(pixelBounds.width),
            buffer.pixelHeight == Int(pixelBounds.height)
        else {
            throw NSError(domain: "SharedWallpaperCompositor", code: 1)
        }
        let options: [CIImageOption: Any] = [.colorSpace: NSNull()]
        guard let terminalImage = terminalInputImage(terminal) else {
            throw NSError(domain: "SharedWallpaperCompositor", code: 4)
        }
        let content = terminalImage.clampedToExtent().samplingNearest()
            .transformed(by: transform, highQualityDownsample: false)
        var scene = clipped(content).composited(over: background).insertingIntermediate(
            cache: false)
        if let cursor {
            scene = clipped(CIImage(cgImage: cursor, options: options))
                .composited(over: scene).insertingIntermediate(cache: false)
        }
        let task = try context.startTask(
            toRender: scanLines.composited(over: scene),
            from: pixelBounds, to: destination, at: .zero)
        _ = try task.waitUntilCompleted()

        let retainedOutput = Unmanaged<AnyObject>.passRetained(output as AnyObject).toOpaque()
        guard
            let provider = CGDataProvider(
                dataInfo: retainedOutput, data: output.contents(),
                size: bytesPerRow * Int(pixelBounds.height),
                releaseData: { info, _, _ in
                    if let info { Unmanaged<AnyObject>.fromOpaque(info).release() }
                })
        else {
            Unmanaged<AnyObject>.fromOpaque(retainedOutput).release()
            throw NSError(domain: "SharedWallpaperCompositor", code: 2)
        }
        guard
            let image = CGImage(
                width: Int(pixelBounds.width), height: Int(pixelBounds.height), bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                        | CGImageAlphaInfo.premultipliedFirst.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw NSError(domain: "SharedWallpaperCompositor", code: 3)
        }
        // This scratch image never escapes: only the transport's completed immutable copy is presented.
        return buffer.publish { target in
            target.setBlendMode(.copy)
            target.interpolationQuality = .none
            target.draw(image, in: pixelBounds)
        }
    }

    /// Quantizes coverage before the next blend, matching Core Graphics' 8-bit intermediate rounding.
    private func clipped(_ image: CIImage) -> CIImage {
        image.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
            ]
        ).insertingIntermediate(cache: false)
    }

    /// Avoids Core Image's per-frame CGImage upload and CPU texture compression.
    private func terminalInputImage(_ image: CGImage) -> CIImage? {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
            image.alphaInfo == .premultipliedFirst,
            image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little,
            let pixels = image.dataProvider?.data
        else { return nil }
        let data = pixels as Data
        let rowBytes = image.width * 4
        guard data.count >= (image.height - 1) * image.bytesPerRow + rowBytes else { return nil }
        data.withUnsafeBytes { source in
            for row in 0..<image.height {
                terminalSurface.buffer.contents().advanced(by: row * terminalSurface.bytesPerRow)
                    .copyMemory(
                        from: source.baseAddress!.advanced(by: row * image.bytesPerRow),
                        byteCount: rowBytes)
            }
        }
        return CIImage(mtlTexture: terminalSurface.texture, options: [.colorSpace: NSNull()])?
            .oriented(.downMirrored)
    }

    /// Allocates aligned linear storage usable as either a Core Image input or completed output.
    private static func makeSurface(device: MTLDevice, width: Int, height: Int)
        -> (buffer: MTLBuffer, texture: MTLTexture, bytesPerRow: Int)?
    {
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
        return (buffer, texture, rowBytes)
    }

    /// Calibrates coordinate boundaries once per layout; a global epsilon changes other supported grids.
    private static func samplingPhase(source: Int, target: Int, vertical: Bool, context: CIContext)
        -> CGFloat?
    {
        guard source > 0, target > 0 else { return nil }
        let sw = vertical ? 1 : source
        let sh = vertical ? source : 1
        let width = vertical ? 1 : target
        let height = vertical ? target : 1
        let bitmapInfo =
            CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard
            let input = CGContext(
                data: nil, width: sw, height: sh, bitsPerComponent: 8,
                bytesPerRow: sw * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
            let bytes = input.data?.assumingMemoryBound(to: UInt8.self),
            let reference = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
            ),
            let referenceBytes = reference.data
        else { return nil }
        for index in 0..<source {
            bytes[index * 4] = UInt8(index & 255)
            bytes[index * 4 + 1] = UInt8((index >> 8) & 255)
            bytes[index * 4 + 2] = 117
            bytes[index * 4 + 3] = 255
        }
        guard let image = input.makeImage() else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        reference.interpolationQuality = .none
        reference.draw(image, in: rect)
        let expected = Data(bytes: referenceBytes, count: target * 4)
        let ciImage = CIImage(cgImage: image, options: [.colorSpace: NSNull()]).clampedToExtent()
            .samplingNearest()
        var actual = Data(count: expected.count)
        var bestStart = 0
        var bestCount = 0
        var runStart = 0
        var runCount = 0
        for step in -100...100 {
            let shift = CGFloat(step) / 100_000
            let transform = CGAffineTransform(
                a: CGFloat(width) / CGFloat(sw), b: 0, c: 0,
                d: CGFloat(height) / CGFloat(sh),
                tx: vertical ? 0 : shift, ty: vertical ? -shift : 0)
            actual.withUnsafeMutableBytes {
                context.render(
                    ciImage.transformed(by: transform, highQualityDownsample: false),
                    toBitmap: $0.baseAddress!, rowBytes: width * 4, bounds: rect, format: .BGRA8,
                    colorSpace: nil)
            }
            if actual == expected {
                if runCount == 0 { runStart = step }
                runCount += 1
                if runCount > bestCount {
                    bestStart = runStart
                    bestCount = runCount
                }
            } else {
                runCount = 0
            }
        }
        return bestCount == 0 ? nil : CGFloat(bestStart + bestCount / 2) / 100_000
    }
}
