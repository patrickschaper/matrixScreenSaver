import AppKit

/// Discovers one display's wallpaper output without starting another animation session.
final class WallpaperFrameReader {
    private var displayID: UInt32 = 0
    private var pointSize = CGSize.zero
    private var buffer: SharedWallpaperFrame?
    private var lastRequest: TimeInterval = -.infinity
    private var observer: NSObjectProtocol?

    /// Observes only path notifications; no Mach lookup or sandbox entitlement is required.
    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: SharedWallpaperFrame.offerNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let path = notification.object as? String else { return }
            let url = URL(fileURLWithPath: path)
            guard self.buffer?.url != url else { return }
            if let offered = try? SharedWallpaperFrame(
                reading: url, displayID: self.displayID, pointSize: self.pointSize)
            {
                self.buffer = offered
            }
        }
    }

    /// Requests matching output, then reads only fresh, complete frames.
    ///
    /// - Parameters:
    ///   - displayID: Physical display hosting this saver instance.
    ///   - pointSize: Full canvas in AppKit points.
    /// - Returns: Shared output, or nil when the independent renderer must take over.
    func frame(displayID: UInt32, pointSize: CGSize) -> SharedWallpaperFrame.Frame? {
        if self.displayID != displayID || self.pointSize != pointSize {
            buffer = nil
            lastRequest = -.infinity
            self.displayID = displayID
            self.pointSize = pointSize
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRequest >= 0.5 {
            lastRequest = now
            DistributedNotificationCenter.default().postNotificationName(
                SharedWallpaperFrame.requestNotification,
                object: String(displayID), userInfo: nil, deliverImmediately: true)
        }
        return buffer?.snapshot()
    }

    /// Unregisters discovery and releases only the consumer's mapping.
    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
