import AppKit

// Run from the repository root: swift Tools/GenerateWallpaperIcons.swift
// Generated assets are checked in; normal builds do not need to regenerate them.

/// The M contour from the reference SVG's final white wordmark path.
///
/// The horizontal connector to the A is trimmed at the M's right stem.
/// Source: https://upload.wikimedia.org/wikipedia/de/2/20/Matrix-logo.svg
///
/// - Parameter rect: Visible glyph bounds in the output coordinate system.
/// - Returns: The original outline, centered and scaled without a font substitution.
func glyph(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 18.322, y: -14.3147))
    path.addCurve(
        to: CGPoint(x: 18.0979, y: -14.5228),
        control1: CGPoint(x: 18.3215, y: -14.4357), control2: CGPoint(x: 18.2588, y: -14.5226))
    path.addLine(to: CGPoint(x: 17.6334, y: -14.5238))
    path.addLine(to: CGPoint(x: 17.6328, y: -14.6515))
    path.addLine(to: CGPoint(x: 18.2221, y: -14.6575))
    path.addCurve(
        to: CGPoint(x: 18.1813, y: -14.9078),
        control1: CGPoint(x: 18.2092, y: -14.8052), control2: CGPoint(x: 18.2156, y: -14.8674))
    path.addCurve(
        to: CGPoint(x: 17.8689, y: -14.9787),
        control1: CGPoint(x: 18.1372, y: -14.9598), control2: CGPoint(x: 18.0375, y: -14.967))
    path.addCurve(
        to: CGPoint(x: 17.3196, y: -15.0079),
        control1: CGPoint(x: 17.6959, y: -14.9887), control2: CGPoint(x: 17.4926, y: -14.9982))
    path.addLine(to: CGPoint(x: 17.3196, y: -15.1462))
    path.addLine(to: CGPoint(x: 18.7116, y: -15.1462))
    path.addCurve(
        to: CGPoint(x: 18.723, y: -15.1302),
        control1: CGPoint(x: 18.7154, y: -15.1412), control2: CGPoint(x: 18.7192, y: -15.1355))
    path.addLine(to: CGPoint(x: 18.723, y: -14.6575))
    path.addLine(to: CGPoint(x: 18.9876, y: -14.6595))
    path.addLine(to: CGPoint(x: 20.5006, y: -11.4455))
    path.addLine(to: CGPoint(x: 22.0286, y: -14.6545))
    path.addLine(to: CGPoint(x: 22.425, y: -14.6615))
    path.addLine(to: CGPoint(x: 22.4278, y: -14.1231))
    path.addLine(to: CGPoint(x: 22.428, y: -13.9757))
    path.addLine(to: CGPoint(x: 22.428, y: -10.3897))
    path.addLine(to: CGPoint(x: 21.388, y: -10.3738))
    path.addCurve(
        to: CGPoint(x: 21.388, y: -10.51),
        control1: CGPoint(x: 21.3766, y: -10.3897), control2: CGPoint(x: 21.3653, y: -10.4462))
    path.addLine(to: CGPoint(x: 21.8236, y: -10.5394))
    path.addCurve(
        to: CGPoint(x: 22.0681, y: -10.8599),
        control1: CGPoint(x: 21.9744, y: -10.5541), control2: CGPoint(x: 22.0771, y: -10.6028))
    path.addLine(to: CGPoint(x: 22.0681, y: -14.0839))
    path.addLine(to: CGPoint(x: 20.4531, y: -10.6729))
    path.addCurve(
        to: CGPoint(x: 20.3745, y: -10.3961),
        control1: CGPoint(x: 20.4041, y: -10.5695), control2: CGPoint(x: 20.3774, y: -10.5191))
    path.addCurve(
        to: CGPoint(x: 20.2163, y: -10.3991),
        control1: CGPoint(x: 20.3184, y: -10.3931), control2: CGPoint(x: 20.2724, y: -10.4011))
    path.addCurve(
        to: CGPoint(x: 20.137, y: -10.8077),
        control1: CGPoint(x: 20.2162, y: -10.591), control2: CGPoint(x: 20.2033, y: -10.6513))
    path.addCurve(
        to: CGPoint(x: 18.733, y: -13.6777),
        control1: CGPoint(x: 19.7139, y: -11.8046), control2: CGPoint(x: 19.2009, y: -12.7207))
    path.addLine(to: CGPoint(x: 18.7299, y: -11.4417))
    path.addLine(to: CGPoint(x: 18.6162, y: -11.3053))
    path.addLine(to: CGPoint(x: 18.6162, y: -9.7893))
    path.addLine(to: CGPoint(x: 17.6364, y: -9.7893))
    path.addLine(to: CGPoint(x: 17.6336, y: -9.923))
    path.addLine(to: CGPoint(x: 18.1119, y: -9.9967))
    path.addCurve(
        to: CGPoint(x: 18.3326, y: -10.4054),
        control1: CGPoint(x: 18.2991, y: -10.0445), control2: CGPoint(x: 18.3129, y: -10.1846))
    path.addLine(to: CGPoint(x: 18.3215, y: -14.3154))
    path.closeSubpath()
    let bounds = path.boundingBoxOfPath
    let scale = min(rect.width / bounds.width, rect.height / bounds.height)
    var transform = CGAffineTransform(
        a: scale, b: 0, c: 0, d: -scale,
        tx: rect.midX - bounds.midX * scale, ty: rect.midY + bounds.midY * scale)
    return path.copy(using: &transform)!
}

/// Draws the app's black tile and green phosphor glyph at a 1024-point design size.
///
/// - Parameter context: Output context, already scaled to the design coordinate system.
func drawAppIcon(in context: CGContext) {
    context.setFillColor(NSColor.black.cgColor)
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
            cornerWidth: 184, cornerHeight: 184, transform: nil))
    context.fillPath()
    let path = glyph(in: CGRect(x: 270, y: 248, width: 484, height: 528))
    // Rain's xterm-47 green (0, 255, 95), with its pale green leading highlight.
    let green = NSColor(srgbRed: 0, green: 1, blue: 95.0 / 255, alpha: 1).cgColor
    for blur: CGFloat in [64, 24, 8] {
        context.saveGState()
        context.setShadow(offset: .zero, blur: blur, color: green)
        context.setFillColor(green)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            NSColor(srgbRed: 0, green: 0.53, blue: 0.2, alpha: 1).cgColor,
            green,
            NSColor(srgbRed: 0.84, green: 1, blue: 0.84, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.65, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 512, y: 248),
        end: CGPoint(x: 512, y: 776), options: [])
    context.setFillColor(NSColor(white: 0, alpha: 0.65).cgColor)
    for y in stride(from: 248, to: 776, by: 8) {
        context.fill(CGRect(x: 260, y: y, width: 504, height: 2))
    }
    context.restoreGState()
}

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let resources = root.appendingPathComponent("Resources")
private let iconset = root.appendingPathComponent("build/WallpaperIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        drawAppIcon(in: context)
        let png = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: iconset.appendingPathComponent(name))
        if pixels == 1024 {
            try png.write(to: resources.appendingPathComponent("WallpaperIcon.png"))
        }
    }
}

// A vector template keeps crisp edges on both standard and Retina menu bars.
private let pdf = NSMutableData()
private let consumer = CGDataConsumer(data: pdf)!
private var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
private let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
context.beginPDFPage(nil)
context.addPath(glyph(in: CGRect(x: 2, y: 2, width: 14, height: 14)))
// Solid, slightly heavier strokes keep the small template legible at menu-bar size.
context.setFillColor(NSColor.black.cgColor)
context.setStrokeColor(NSColor.black.cgColor)
context.setLineWidth(0.45)
context.setLineJoin(.round)
context.drawPath(using: .fillStroke)
context.endPDFPage()
context.closePDF()
try (pdf as Data).write(to: resources.appendingPathComponent("MenuBarIcon.pdf"))

private let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path, "-o", resources.appendingPathComponent("WallpaperIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
print("Generated WallpaperIcon.icns, WallpaperIcon.png, and MenuBarIcon.pdf")
