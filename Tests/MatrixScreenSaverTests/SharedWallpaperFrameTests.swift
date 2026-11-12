import CoreGraphics
import Darwin
import Foundation

/// Exercises the actual mapped-file boundary, including read-only consumers and malformed offers.
func sharedWallpaperFrameTests() {
    let fifo = FileManager.default.temporaryDirectory.appendingPathComponent(
        "MatrixWallpaperFrame-\(UUID().uuidString)")
    if mkfifo(fifo.path, S_IRUSR | S_IWUSR) == 0 {
        defer { unlink(fifo.path) }
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { finished.signal() }
            do {
                _ = try SharedWallpaperFrame(
                    reading: fifo, displayID: 42, pointSize: CGSize(width: 8, height: 6))
                ok(false, "FIFO offers must never be accepted")
            } catch {}
        }
        ok(
            finished.wait(timeout: .now() + 1) == .success,
            "non-regular frame offers are rejected without blocking the saver")
    } else {
        ok(false, "FIFO rejection fixture can be created")
    }
    do {
        var writer: SharedWallpaperFrame? = try SharedWallpaperFrame(
            displayID: 42, pointSize: CGSize(width: 8, height: 6), scale: 2)
        let url = writer!.url
        let reader = try SharedWallpaperFrame(
            reading: url, displayID: 42, pointSize: CGSize(width: 8, height: 6))
        ok(
            reader.snapshot() == nil,
            "shared frames are unavailable before the first complete publication")
        let image = writer!.publish { context in
            context.setFillColor(red: 0, green: 0.5, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
        let first = reader.snapshot()
        ok(
            image?.width == 16 && image?.height == 12 && first?.image.width == 16,
            "shared frames retain the display backing resolution")
        ok(
            first != nil
                && first!.image.dataProvider!.data! as Data == image!.dataProvider!.data! as Data,
            "read-only mapping presents exactly the producer's pixels")
        let firstPixels = first!.image.dataProvider!.data! as Data
        _ = writer!.publish { context in
            context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
        let second = reader.snapshot()!
        ok(
            second.sequence > first!.sequence
                && second.image.dataProvider!.data! as Data != firstPixels,
            "one mapped animation publishes advancing frames")
        ok(
            first!.image.dataProvider!.data! as Data == firstPixels,
            "old presentation images stay immutable across mapped writes")
        let reconnected = try SharedWallpaperFrame(
            reading: url, displayID: 42, pointSize: CGSize(width: 8, height: 6))
        ok(
            reconnected.snapshot()?.sequence == second.sequence,
            "reconnecting does not reset the producer's sequence")
        let lock = open(url.path, O_RDWR)
        defer { close(lock) }
        flock(lock, LOCK_EX)
        ok(
            reader.snapshot()?.sequence == second.sequence && writer!.publish { _ in } == nil,
            "contended mappings keep a fresh cached frame without blocking animation")
        flock(lock, LOCK_UN)
        for (display, size) in [
            (UInt32(43), CGSize(width: 8, height: 6)), (42, CGSize(width: 9, height: 6)),
        ] {
            do {
                _ = try SharedWallpaperFrame(reading: url, displayID: display, pointSize: size)
                ok(false, "mismatched display or canvas is rejected")
            } catch { ok(true, "mismatched display or canvas is rejected") }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        do {
            _ = try SharedWallpaperFrame(
                reading: url, displayID: 42, pointSize: CGSize(width: 8, height: 6))
            ok(false, "publicly accessible frame files are rejected")
        } catch { ok(true, "publicly accessible frame files are rejected") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let malformed = url.deletingLastPathComponent().appendingPathComponent(
            "MatrixWallpaperFrame-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: url, to: malformed)
        defer { try? FileManager.default.removeItem(at: malformed) }
        let file = try FileHandle(forWritingTo: malformed)
        try file.write(contentsOf: Data(repeating: 0, count: 8))
        try file.close()
        do {
            _ = try SharedWallpaperFrame(
                reading: malformed, displayID: 42, pointSize: CGSize(width: 8, height: 6))
            ok(false, "malformed frame metadata is rejected before mapping")
        } catch { ok(true, "malformed frame metadata is rejected before mapping") }
        Thread.sleep(forTimeInterval: SharedWallpaperFrame.freshnessInterval + 0.1)
        ok(
            reader.snapshot() == nil,
            "a silent producer cannot leave a permanently frozen shared frame")
        writer!.refresh()
        ok(
            reader.snapshot() != nil,
            "shutdown invalidation is checked against a still-fresh shared frame")
        writer = nil
        ok(
            !FileManager.default.fileExists(atPath: url.path) && reader.snapshot() == nil,
            "producer shutdown unlinks its file and immediately invalidates readers")
    } catch { ok(false, "shared-frame transport: \(error)") }
}
