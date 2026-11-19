import CoreGraphics
import Foundation
import Metal

/// Compares a dense grid against Core Graphics, including asymmetric glyphs and diffuse alpha.
func metalGlyphRasterizerTests() {
    guard MTLCreateSystemDefaultDevice() != nil else {
        print("# Metal glyph comparison skipped because this host has no Metal device")
        return
    }
    let info =
        CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    func bitmap(_ width: Int, _ height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
    }
    let tile = bitmap(3, 5)
    tile.setFillColor(red: 0.1, green: 0.8, blue: 0.4, alpha: 0.6)
    tile.fill(CGRect(x: 0, y: 1, width: 2, height: 3))
    let glyph = tile.makeImage()!
    let background = CGColor(red: 0.3, green: 0.5, blue: 0.1, alpha: 0.2)
    let renderer = NativeMatrixRenderer()
    var options = NativeMatrixRenderer.Configuration()
    options.neoMessageSceneEnabled = false
    options.numberSceneEnabled = false
    options.diffuseEnabled = true
    renderer.updateConfiguration(options)
    renderer.resize(to: TerminalSize(columns: 40, rows: 20))
    renderer.start()
    defer { renderer.stop() }
    for _ in 0..<50 {
        renderer.shiftTimeline(by: -0.1)
        renderer.advance()
    }
    guard renderer.hasVisibleContent,
        let rasterizer = MetalGlyphRasterizer(
            images: [[UnicodeScalar("X"): glyph]],
            diffuse: Array(repeating: background, count: renderer.levelColors.count))
    else {
        ok(false, "Metal glyph atlas prepares a populated rain fixture")
        return
    }
    for diffuse in [true, false] {
        let reference = bitmap(renderer.columns * 3, renderer.rows * 5)
        reference.setFillColor(background)
        for row in 0..<renderer.rows {
            for column in 0..<renderer.columns {
                let cell = renderer[row, column]
                let rect = CGRect(
                    x: column * 3, y: (renderer.rows - 1 - row) * 5, width: 3, height: 5)
                if diffuse && cell.backgroundLevel > 0 { reference.fill(rect) }
                if cell.hasForeground { reference.draw(glyph, in: rect) }
            }
        }
        let actual = rasterizer.image(renderer: renderer, diffuse: diffuse) { _ in glyph }
        let expected = Data(bytes: reference.data!, count: reference.height * reference.bytesPerRow)
        ok(
            actual?.dataProvider?.data as Data? == expected,
            "Metal glyphs match Core Graphics byte-for-byte with diffuse = \(diffuse)")
    }
}
