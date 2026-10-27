import AppKit

/// Owns the temporary black desktop image and durable originals across app launches.
///
/// Call on the main thread. Failed restores and disconnected displays remain in the backup.
final class DesktopWallpaperController {
    /// A desktop image and the native scaling, clipping, and fill-color options needed to restore it.
    struct Image {
        /// File URL supplied by the desktop-image API.
        let url: URL
        /// Native options, including NSColor values that must survive persistence.
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    private struct SavedImage: Codable {
        let url: URL
        let options: Data
        /// Older backups omit this field; pending restores can be superseded by a new Start.
        var restorePending: Bool? = nil
    }

    /// Storage shared across launches, outside the replaceable application bundle.
    private let directory: URL
    private let screens: () -> [String]
    private let readImage: (String) -> Image?
    private let setImage: (Image, String) throws -> Void

    /// Location of the app-owned black image, also used to recognize wallpaper ownership.
    var blackImageURL: URL { directory.appendingPathComponent("black.png") }
    private var backupURL: URL { directory.appendingPathComponent("originals.plist") }

    /// Creates a desktop controller with replaceable system operations for isolated tests.
    ///
    /// - Parameters:
    ///   - directory: Durable storage for the black image and original settings.
    ///   - screens: Connected display UUIDs, stable across process launches.
    ///   - readImage: Current image and options for one connected display.
    ///   - setImage: Applies settings to a connected display, throwing on failure.
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MatrixWallpaper/DesktopWallpaper"),
         screens: @escaping () -> [String] = { Array(DesktopWallpaperController.systemScreens().keys) },
         readImage: @escaping (String) -> Image? = DesktopWallpaperController.systemImage,
         setImage: @escaping (Image, String) throws -> Void = DesktopWallpaperController.setSystemImage) {
        self.directory = directory
        self.screens = screens
        self.readImage = readImage
        self.setImage = setImage
    }

    /// Saves originals before changing any newly connected desktop to black.
    ///
    /// Repeated calls preserve existing backups, including when the renderer rebuilds.
    /// - Throws: A storage, serialization, desktop-read, or desktop-write error.
    func start() throws {
        var originals = try load()
        try prepareBlackImage()
        var failure: Error?
        for id in screens() where originals[id] == nil || originals[id]?.restorePending == true {
            do {
                guard let image = readImage(id), image.url.isFileURL,
                      image.url != blackImageURL || originals[id]?.restorePending == true else {
                    throw Self.error("Could not save the original wallpaper for display \(id).")
                }
                let saved: SavedImage
                if image.url == blackImageURL, let pending = originals[id] {
                    saved = SavedImage(url: pending.url, options: pending.options)
                } else {
                    let options = Dictionary(uniqueKeysWithValues: image.options.map { ($0.key.rawValue, $0.value) })
                    let archive = try NSKeyedArchiver.archivedData(withRootObject: options, requiringSecureCoding: true)
                    // Validate restoration before committing to replace the user's desktop.
                    _ = try decodeOptions(archive)
                    saved = SavedImage(url: image.url, options: archive)
                }
                var updated = originals
                updated[id] = saved
                try save(updated)
                originals = updated
                try setImage(Image(url: blackImageURL, options: [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue]), id)
            } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    /// Restores app-owned desktops; newer user choices win over saved originals.
    ///
    /// Call at launch to recover an interrupted session and on explicit Stop or Quit.
    /// - Throws: The first failure, after attempting the other connected displays.
    func restore() throws {
        var originals = try load()
        var failure: Error?
        for id in screens() {
            guard let saved = originals[id] else { continue }
            do {
                guard let current = readImage(id) else {
                    throw Self.error("Could not read the wallpaper for display \(id); its backup was kept.")
                }
                if current.url == blackImageURL || current.url == saved.url {
                    var pending = saved
                    pending.restorePending = true
                    var updated = originals
                    updated[id] = pending
                    try save(updated)
                    originals = updated
                    try setImage(Image(url: saved.url, options: try decodeOptions(saved.options)), id)
                    // A successful setter only accepts the request; reads can still report black.
                    guard let observed = readImage(id), observed.url != blackImageURL else { continue }
                }
                var updated = originals
                updated.removeValue(forKey: id)
                try save(updated)
                originals = updated
            } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    private func load() throws -> [String: SavedImage] {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return [:] }
        return try PropertyListDecoder().decode([String: SavedImage].self, from: Data(contentsOf: backupURL))
    }

    private func save(_ originals: [String: SavedImage]) throws {
        try PropertyListEncoder().encode(originals).write(to: backupURL, options: .atomic)
    }

    private func decodeOptions(_ data: Data) throws -> [NSWorkspace.DesktopImageOptionKey: Any] {
        guard let options = try NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSColor.self], from: data) as? [String: Any] else {
            throw Self.error("The saved desktop-image options could not be read.")
        }
        return Dictionary(uniqueKeysWithValues: options.map { (NSWorkspace.DesktopImageOptionKey(rawValue: $0.key), $0.value) })
    }

    private func prepareBlackImage() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: blackImageURL.path) else { return }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw Self.error("Could not create the black desktop image.")
        }
        bitmap.setColor(.black, atX: 0, y: 0)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Self.error("Could not encode the black desktop image.")
        }
        try data.write(to: blackImageURL, options: .atomic)
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "MatrixWallpaper.DesktopWallpaper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Resolves stable display UUIDs instead of persisting transient Core Graphics display IDs.
    static func systemScreens() -> [String: NSScreen] {
        var result: [String: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
            result[CFUUIDCreateString(nil, uuid) as String] = screen
        }
        return result
    }

    /// Reads only the desktop settings exposed by AppKit for the current Space.
    /// - Returns: Image settings, or nil if the display or settings are unavailable.
    static func systemImage(_ id: String) -> Image? {
        guard let screen = systemScreens()[id], let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let options = NSWorkspace.shared.desktopImageOptions(for: screen) else { return nil }
        // shortcut: AppKit exposes image settings only; exact dynamic/Space restoration needs a supported richer API.
        return Image(url: url, options: options)
    }

    /// Applies settings through the supported desktop-image API.
    /// - Throws: An unavailable-display error or the system's desktop-image error.
    static func setSystemImage(_ image: Image, _ id: String) throws {
        guard let screen = systemScreens()[id] else { throw error("Display \(id) is no longer connected.") }
        try NSWorkspace.shared.setDesktopImageURL(image.url, for: screen, options: image.options)
    }
}
