import CoreGraphics
import Foundation
import Metal

/// Draws a complete terminal grid in one compute pass using the native premultiplied glyph rasters.
final class MetalGlyphRasterizer {
    private static let pipeline: MTLComputePipelineState? = {
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            kernel void raster(device const uint2 *cells [[buffer(0)]],
                               device const uchar4 *atlas [[buffer(1)]],
                               device uchar4 *output [[buffer(2)]],
                               constant uint4 &size [[buffer(3)]],
                               uint2 p [[thread_position_in_grid]]) {
                if (p.x >= size.x || p.y >= size.y) return;
                uint2 cell = p / size.zw;
                uint2 entry = cells[cell.y * (size.x / size.z) + cell.x];
                uint2 local = p % size.zw;
                uchar4 fg = atlas[entry.x + local.y * size.z + local.x];
                ushort4 bg = ushort4(as_type<uchar4>(entry.y));
                output[p.y * size.x + p.x] = fg + uchar4((bg * (255 - fg.a) + 127) / 255);
            }
            """
        guard let device = MTLCreateSystemDefaultDevice(),
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "raster")
        else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()

    private let pipeline: MTLComputePipelineState
    private let queue: MTLCommandQueue
    private let atlas: MTLBuffer
    private let offsets: [ObjectIdentifier: UInt32]
    private let backgrounds: [UInt32]
    private let width: Int
    private let height: Int
    private var cells: MTLBuffer?
    private var pixels: MTLBuffer?

    /// Packs the current font and palette once. Tile zero represents an empty cell.
    ///
    /// - Parameters:
    ///   - images: Native regular and bold caches, which can reference the same image.
    ///   - diffuse: Colors in renderer level order, with level zero reserved for transparency.
    init?(images: [[UnicodeScalar: CGImage]], diffuse: [CGColor]) {
        guard let pipeline = Self.pipeline, let queue = pipeline.device.makeCommandQueue(),
            let first = images.lazy.compactMap({ $0.values.first }).first,
            !diffuse.isEmpty
        else { return nil }
        let width = first.width
        let height = first.height
        let unique = Dictionary(
            images.flatMap(\.values).map { (ObjectIdentifier($0), $0) },
            uniquingKeysWith: { first, _ in first })
        let tileBytes = width * height * 4
        let length = (unique.count + 1) * tileBytes
        guard length <= 64 * 1024 * 1024,
            let atlas = pipeline.device.makeBuffer(length: length, options: .storageModeShared),
            let palette = CGContext(
                data: nil, width: diffuse.count, height: 1,
                bitsPerComponent: 8, bytesPerRow: diffuse.count * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: first.bitmapInfo.rawValue),
            let paletteData = palette.data
        else { return nil }
        palette.clear(CGRect(x: 0, y: 0, width: diffuse.count, height: 1))
        for index in diffuse.indices.dropFirst() {
            palette.setFillColor(diffuse[index])
            palette.fill(CGRect(x: index, y: 0, width: 1, height: 1))
        }
        backgrounds = Array(
            UnsafeBufferPointer(
                start: paletteData.assumingMemoryBound(to: UInt32.self),
                count: diffuse.count))
        var offsets: [ObjectIdentifier: UInt32] = [:]
        memset(atlas.contents(), 0, tileBytes)
        for (index, item) in unique.enumerated() {
            let image = item.value
            guard image.width == width, image.height == height, image.bitsPerPixel == 32,
                image.bytesPerRow == width * 4, let data = image.dataProvider?.data,
                CFDataGetLength(data) >= tileBytes, let bytes = CFDataGetBytePtr(data)
            else { return nil }
            let offset = (index + 1) * tileBytes
            memcpy(atlas.contents() + offset, bytes, tileBytes)
            offsets[item.key] = UInt32(offset / 4)
        }
        self.offsets = offsets
        self.atlas = atlas
        self.pipeline = pipeline
        self.queue = queue
        self.width = width
        self.height = height
    }

    /// Returns a snapshot independent of subsequent GPU writes, or nil to request native drawing.
    ///
    /// - Parameters:
    ///   - renderer: Current grid of glyphs and palette levels.
    ///   - diffuse: Whether to blend the cell background underneath each glyph.
    ///   - glyph: Looks up the exact native raster for a visible cell.
    /// - Returns: An immutable BGRA image, or nil when a native draw is required.
    func image(
        renderer: NativeMatrixRenderer, diffuse: Bool,
        glyph: (NativeMatrixRenderer.RenderCell) -> CGImage?
    ) -> CGImage? {
        let columns = renderer.columns
        let rows = renderer.rows
        guard columns > 0, rows > 0 else { return nil }
        let cellCount = columns * rows
        let frameWidth = width * columns
        let frameHeight = height * rows
        let pixelBytes = frameWidth * frameHeight * 4
        guard pixelBytes <= pipeline.device.maxBufferLength,
            cellCount * 8 <= pipeline.device.maxBufferLength
        else { return nil }
        if cells?.length != cellCount * 8 {
            cells = pipeline.device.makeBuffer(length: cellCount * 8, options: .storageModeShared)
        }
        if pixels?.length != pixelBytes {
            pixels = pipeline.device.makeBuffer(length: pixelBytes, options: .storageModeShared)
        }
        guard let cells, let pixels else { return nil }
        let entries = cells.contents().assumingMemoryBound(to: SIMD2<UInt32>.self)
        memset(entries, 0, cells.length)
        for row in 0..<rows where renderer.visibleCount(in: row) > 0 {
            for column in 0..<columns {
                let cell = renderer[row, column]
                var offset: UInt32 = 0
                if cell.hasForeground {
                    guard let image = glyph(cell), let found = offsets[ObjectIdentifier(image)]
                    else { return nil }
                    offset = found
                }
                let bg =
                    diffuse && backgrounds.indices.contains(cell.backgroundLevel)
                    ? backgrounds[cell.backgroundLevel] : 0
                entries[row * columns + column] = SIMD2(offset, bg)
            }
        }
        guard let command = queue.makeCommandBuffer(),
            let pass = command.makeComputeCommandEncoder()
        else { return nil }
        pass.setComputePipelineState(pipeline)
        pass.setBuffer(cells, offset: 0, index: 0)
        pass.setBuffer(atlas, offset: 0, index: 1)
        pass.setBuffer(pixels, offset: 0, index: 2)
        var size = SIMD4(UInt32(frameWidth), UInt32(frameHeight), UInt32(width), UInt32(height))
        pass.setBytes(&size, length: MemoryLayout.size(ofValue: size), index: 3)
        pass.dispatchThreadgroups(
            MTLSize(width: (frameWidth + 15) / 16, height: (frameHeight + 7) / 8, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        pass.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed,
            let provider = CGDataProvider(
                data: Data(bytes: pixels.contents(), count: pixelBytes) as CFData)
        else { return nil }
        return CGImage(
            width: frameWidth, height: frameHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: frameWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: [
                .byteOrder32Little,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            ],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
