import CoreGraphics
import Darwin
import Foundation

/// Shares completed BGRA frames through a private file mapped read-only by the saver.
///
/// Discovery sends only paths. No renderer state, desktop capture, or writable access
/// to the wallpaper process is given to the screensaver host.
final class SharedWallpaperFrame {
    /// Requests a current frame for the display ID carried in the notification object.
    static let requestNotification = Notification.Name("dev.patsch.MatrixWallpaper.requestFrame")
    /// Announces a producer-owned file path without a sandbox-incompatible userInfo dictionary.
    static let offerNotification = Notification.Name("dev.patsch.MatrixWallpaper.frameAvailable")
    /// Maximum silence before a consumer falls back to its independent renderer.
    static let freshnessInterval: TimeInterval = 3
    private static let filenamePrefix = "MatrixWallpaperFrame-"
    /// Fixed header capacity, independent of Swift struct layout.
    private static let headerSize = 128
    /// Bounds mapping allocations while supporting an 8K BGRA display.
    private static let maximumPixelBytes = 256 * 1024 * 1024

    /// Word offsets in the versioned, same-machine shared-memory format.
    private enum Field: Int {
        case magic, version, displayID, width, height, pointWidth, pointHeight, processID, sequence,
            updatedAt
    }

    /// One immutable presentation copy and its source sequence number.
    struct Frame {
        /// Owned pixels remain stable after the producer releases its write lock.
        let image: CGImage
        /// Increasing within the lifetime of one producer buffer.
        let sequence: UInt64
    }

    /// The path offered to read-only consumers and unlinked by its creator on teardown.
    let url: URL
    /// Logical canvas size, used to reject mismatched layouts rather than stretch them.
    let pointSize: CGSize
    /// Width of the physical backing image.
    let pixelWidth: Int
    /// Height of the physical backing image.
    let pixelHeight: Int
    /// The display whose animation this mapping contains.
    let displayID: UInt32
    /// Locking and mapping must refer to the same open inode, not a replaceable path.
    private let descriptor: Int32
    private let memory: UnsafeMutableRawPointer
    private let byteCount: Int
    private let isProducer: Bool
    private var cachedFrame: Frame?
    private var cachedUpdate: TimeInterval = 0

    /// Creates an owner-only buffer at the display's backing resolution.
    ///
    /// - Parameters:
    ///   - displayID: Physical display identity shared by both hosts.
    ///   - pointSize: Full canvas in AppKit points.
    ///   - scale: Display backing scale, without downsampling Retina output.
    /// - Throws: A file-system error or an unsupported-layout error.
    convenience init(displayID: UInt32, pointSize: CGSize, scale: CGFloat) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            Self.filenamePrefix + UUID().uuidString)
        try self.init(url: url, displayID: displayID, pointSize: pointSize, scale: scale)
    }

    /// Imports a private producer file without granting the saver write permission.
    ///
    /// - Parameters:
    ///   - url: Path announced by the wallpaper app.
    ///   - displayID: Expected physical display.
    ///   - pointSize: Expected full-screen canvas in points.
    /// - Throws: Invalid ownership, format, layout, permissions, or file access.
    convenience init(reading url: URL, displayID: UInt32, pointSize: CGSize) throws {
        try self.init(url: url, displayID: displayID, pointSize: pointSize, scale: nil)
    }

    /// Validates the entire fixed layout before mapping any untrusted pixel storage.
    private init(url: URL, displayID: UInt32, pointSize: CGSize, scale: CGFloat?) throws {
        guard Self.isFrameURL(url), pointSize.width.isFinite, pointSize.height.isFinite,
            pointSize.width >= 1, pointSize.height >= 1, pointSize.width <= 16384,
            pointSize.height <= 16384
        else {
            throw Self.invalidBuffer()
        }
        if let scale, !scale.isFinite || scale < 1 || scale > 4 { throw Self.invalidBuffer() }
        let creating = scale != nil
        let flags =
            (creating ? O_RDWR | O_CREAT | O_EXCL : O_RDONLY | O_NONBLOCK) | O_NOFOLLOW | O_CLOEXEC
        let fd = open(url.path, flags, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var ready = false
        defer {
            if !ready {
                close(fd)
                if creating { unlink(url.path) }
            }
        }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
            info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0
        else { throw Self.invalidBuffer() }
        var header = [UInt64](repeating: 0, count: Self.headerSize / 8)
        if let scale {
            header[Field.magic.rawValue] = 0x4D41_5452_4958_4631
            header[Field.version.rawValue] = 1
            header[Field.displayID.rawValue] = UInt64(displayID)
            header[Field.width.rawValue] = UInt64(ceil(pointSize.width * scale))
            header[Field.height.rawValue] = UInt64(ceil(pointSize.height * scale))
            header[Field.pointWidth.rawValue] = Double(pointSize.width).bitPattern
            header[Field.pointHeight.rawValue] = Double(pointSize.height).bitPattern
            header[Field.processID.rawValue] = UInt64(getpid())
        } else {
            let count = header.withUnsafeMutableBytes {
                pread(fd, $0.baseAddress, Self.headerSize, 0)
            }
            guard count == Self.headerSize else { throw Self.invalidBuffer() }
        }
        let width = header[Field.width.rawValue]
        let height = header[Field.height.rawValue]
        guard header[Field.magic.rawValue] == 0x4D41_5452_4958_4631,
            header[Field.version.rawValue] == 1,
            header[Field.displayID.rawValue] == displayID,
            header[Field.pointWidth.rawValue] == Double(pointSize.width).bitPattern,
            header[Field.pointHeight.rawValue] == Double(pointSize.height).bitPattern,
            width > 0, height > 0, width <= 16384, height <= 16384,
            width * height * 4 <= Self.maximumPixelBytes,
            header[Field.processID.rawValue] > 0, header[Field.processID.rawValue] <= Int32.max
        else {
            throw Self.invalidBuffer()
        }
        let size = Self.headerSize + Int(width * height * 4)
        if creating {
            guard ftruncate(fd, off_t(size)) == 0,
                header.withUnsafeBytes({ pwrite(fd, $0.baseAddress, Self.headerSize, 0) })
                    == Self.headerSize
            else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
            info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_size == size
        else {
            throw Self.invalidBuffer()
        }
        guard
            let mapped = mmap(
                nil, size, PROT_READ | (creating ? PROT_WRITE : 0), MAP_SHARED, fd, 0),
            mapped != MAP_FAILED
        else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        self.url = url
        self.displayID = displayID
        self.pointSize = pointSize
        pixelWidth = Int(width)
        pixelHeight = Int(height)
        descriptor = fd
        memory = mapped
        byteCount = size
        isProducer = creating
        ready = true
    }

    /// Restricts discovery to this product's files in macOS's per-user global temporary tree.
    ///
    /// - Parameter url: An offered file URL, never a general-purpose file capability.
    /// - Returns: Whether its standardized location is eligible for further ownership checks.
    static func isFrameURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return url.isFileURL
            && (path.hasPrefix("/var/folders/") || path.hasPrefix("/private/var/folders/"))
            && url.deletingLastPathComponent().lastPathComponent == "T"
            && url.lastPathComponent.hasPrefix(filenamePrefix)
    }

    /// Draws one complete frame under a nonblocking exclusive lock.
    ///
    /// - Parameter draw: Draws into physical pixels, including overlays and scanlines.
    /// - Returns: The exact immutable image available to both hosts, or nil under contention.
    func publish(_ draw: (CGContext) -> Void) -> CGImage? {
        guard isProducer, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return nil }
        defer { flock(descriptor, LOCK_UN) }
        guard
            let context = CGContext(
                data: memory.advanced(by: Self.headerSize), width: pixelWidth, height: pixelHeight,
                bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        draw(context)
        store(value(.sequence) &+ 1, at: .sequence)
        store(ProcessInfo.processInfo.systemUptime.bitPattern, at: .updatedAt)
        cachedFrame = copyFrame()
        return cachedFrame?.image
    }

    /// Keeps a static intro frame fresh without redrawing or copying its pixels.
    func refresh() {
        guard isProducer, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(descriptor, LOCK_UN) }
        if value(.sequence) > 0 {
            store(ProcessInfo.processInfo.systemUptime.bitPattern, at: .updatedAt)
        }
    }

    /// Reads a consistent presentation copy, retaining a fresh cached frame during contention.
    ///
    /// - Returns: A complete, current frame; nil on shutdown, silence, or invalid storage.
    func snapshot() -> Frame? {
        let now = ProcessInfo.processInfo.systemUptime
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_nlink == 1, info.st_size == byteCount else {
            return nil
        }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else {
            return now - cachedUpdate < Self.freshnessInterval ? cachedFrame : nil
        }
        defer { flock(descriptor, LOCK_UN) }
        let updatedAt = Double(bitPattern: value(.updatedAt))
        let readTime = ProcessInfo.processInfo.systemUptime
        guard updatedAt.isFinite, updatedAt <= readTime,
            readTime - updatedAt < Self.freshnessInterval,
            value(.sequence) > 0
        else { return nil }
        if cachedFrame?.sequence != value(.sequence) { cachedFrame = copyFrame() }
        cachedUpdate = updatedAt
        return cachedFrame
    }

    /// Copies only under a kernel lock so later writes cannot tear a displayed frame.
    private func copyFrame() -> Frame? {
        let data = Data(
            bytes: memory.advanced(by: Self.headerSize), count: byteCount - Self.headerSize)
        guard let provider = CGDataProvider(data: data as CFData),
            let image = CGImage(
                width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                        | CGImageAlphaInfo.premultipliedFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return Frame(image: image, sequence: value(.sequence))
    }

    /// Reads one aligned header word from the validated mapping.
    private func value(_ field: Field) -> UInt64 {
        memory.load(fromByteOffset: field.rawValue * 8, as: UInt64.self)
    }

    /// Updates one aligned header word while holding the producer lock.
    private func store(_ value: UInt64, at field: Field) {
        memory.storeBytes(of: value, toByteOffset: field.rawValue * 8, as: UInt64.self)
    }

    private static func invalidBuffer() -> NSError {
        NSError(
            domain: "dev.patsch.MatrixWallpaper.SharedFrame", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid or incompatible wallpaper frame buffer"])
    }

    /// Removes the offer before releasing producer memory so readers fall back immediately.
    deinit {
        if isProducer { unlink(url.path) }
        munmap(memory, byteCount)
        close(descriptor)
    }
}
