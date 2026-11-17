import AppKit

/// Persists captured Matrix images before selecting them as native desktop images.
/// Never restores an original wallpaper or removes previously selected images.
final class StillWallpaperController {
    /// One display's immutable renderer output, captured before file or desktop changes.
    struct Frame {
        /// Connected display that should receive the image.
        let screen: NSScreen
        /// Full backing-resolution pixels without other applications or desktop UI.
        let image: CGImage
    }

    /// Persistent parent directory; each request creates a unique child directory.
    private let directory: URL
    /// Native desktop boundary, replaced by a recorder in tests.
    private let setDesktopImage: (URL, NSScreen) throws -> Void

    /// Creates a writer without touching storage or the current wallpaper.
    ///
    /// - Parameters:
    ///   - directory: Persistent storage, or an isolated temporary directory in tests.
    ///   - setDesktopImage: Main-thread operation that selects a saved file for one screen.
    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MatrixWallpaper/Stills"),
        setDesktopImage: @escaping (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) {
        self.directory = directory
        self.setDesktopImage = setDesktopImage
    }

    /// Saves the complete batch before attempting any desktop changes, on the main thread.
    ///
    /// Files remain after partial failure because macOS may already reference them.
    /// Older captures also remain: another Space can still have one selected.
    /// - Parameter frames: Current renderer images for all participating displays.
    /// - Throws: A preparation error before any desktop changes, or a display-specific
    ///   error after attempting every setter; successful selections are not rolled back.
    func apply(_ frames: [Frame]) throws {
        guard !frames.isEmpty else {
            throw NSError(
                domain: "MatrixWallpaper.Still", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No Matrix frames are available. Start the wallpaper and try again."
                ])
        }
        let captureDirectory = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: captureDirectory, withIntermediateDirectories: true)
        var images: [URL] = []
        for (index, frame) in frames.enumerated() {
            guard
                let png = NSBitmapImageRep(cgImage: frame.image).representation(
                    using: .png, properties: [:])
            else {
                throw NSError(
                    domain: "MatrixWallpaper.Still", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Could not encode the Matrix frame for \(frame.screen.localizedName). No wallpapers were changed."
                    ])
            }
            let url = captureDirectory.appendingPathComponent("display-\(index + 1).png")
            try png.write(to: url, options: .atomic)
            images.append(url)
        }
        var failures: [String] = []
        for (frame, url) in zip(frames, images) {
            do {
                try setDesktopImage(url, frame.screen)
            } catch {
                failures.append("\(frame.screen.localizedName): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw NSError(
                domain: "MatrixWallpaper.Still", code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not set wallpaper on:\n\(failures.joined(separator: "\n"))\n\nOther displays may have changed. Saved images were kept. Try again or choose a wallpaper in System Settings."
                ])
        }
    }
}
