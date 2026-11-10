import AppKit

/// Compares the loaded component with discoverable companion installations, not another process's memory.
struct MatrixVersionStatus: Equatable {
    /// Missing and unreadable metadata must not be presented as proven compatibility.
    enum State {
        case matching, mismatch, missingCompanion, unverified
    }

    /// Identifies a copy without assuming macOS has selected it as the active screen saver.
    struct Installation: Equatable {
        /// Canonical bundle location, also used to collapse symlinks.
        let url: URL
        /// Release version; nil means the bundle is recognized but its version is unavailable.
        let version: String?
        /// Distinguishes this process's metadata from metadata read off disk.
        let isLoaded: Bool
    }

    /// Wallpaper copies relevant to this host.
    let wallpapers: [Installation]
    /// Loaded and installed screen-saver copies, deduplicated by canonical path.
    let screenSavers: [Installation]
    /// Records a failed discovery read, so an inaccessible directory is not treated as empty.
    let discoveryIncomplete: Bool

    /// Standard user and machine-wide screen-saver installation directories.
    static var screenSaverDirectories: [URL] {
        FileManager.default.urls(for: .libraryDirectory, in: [.userDomainMask, .localDomainMask])
            .map { $0.appendingPathComponent("Screen Savers") }
    }

    /// Recovery destination shared by both native hosts.
    static let releasesURL = URL(string: "https://github.com/patrickschaper/matrixScreenSaver/releases")!

    /// Standard macOS warning triangle shared by dialogs, menus, and blocked playback.
    static let warningImage = NSImage(named: NSImage.cautionName)

    /// A confirmed differing pair takes precedence over other unreadable copies.
    var state: State {
        let wallpaperVersions = wallpapers.compactMap(\.version)
        let saverVersions = screenSavers.compactMap(\.version)
        if !wallpaperVersions.isEmpty && !saverVersions.isEmpty && Set(wallpaperVersions + saverVersions).count > 1 {
            return .mismatch
        }
        if discoveryIncomplete || (wallpapers + screenSavers).contains(where: { $0.version == nil }) {
            return .unverified
        }
        return wallpapers.isEmpty || screenSavers.isEmpty ? .missingCompanion : .matching
    }

    /// Shared heading for persistent warnings and the launch alert.
    var title: String {
        state == .mismatch ? "Version Mismatch" : "Version Unavailable"
    }

    /// Compact version information suitable for the menu and options banner.
    var versionSummary: String {
        "Wallpaper \(Self.versions(wallpapers)) · Screen Saver \(Self.versions(screenSavers))"
    }

    /// Gives the shortest recovery instruction for the current status.
    var explanation: String {
        if state == .mismatch {
            return "Install matching versions to play."
        }
        return "Couldn’t check versions."
    }

    /// Keeps native dialogs to version numbers and one recovery sentence.
    var message: String {
        "\(versionSummary)\n\(explanation)"
    }

    /// Reads disk metadata afresh while preserving the hosting bundle's loaded version.
    ///
    /// - Parameters:
    ///   - hostBundle: The bundle containing Matrix code, never System Settings or ScreenSaverEngine.
    ///   - screenSaverDirectories: Bounded installation directories; replace with isolated fixtures in tests.
    ///   - wallpaperURLs: Explicit candidates, or nil to use macOS discovery and standard app locations.
    /// - Returns: A snapshot; inaccessible reads remain unverified rather than implying a match.
    static func current(hostBundle: Bundle, screenSaverDirectories: [URL] = screenSaverDirectories,
                        wallpaperURLs: [URL]? = nil) -> MatrixVersionStatus {
        let saverID = "dev.patsch.MatrixScreenSaver"
        let wallpaperID = "dev.patsch.MatrixWallpaper"
        var incomplete = false
        var savers: [Installation] = []
        var wallpapers: [Installation] = []

        func read(_ url: URL, identifier: String) -> Installation? {
            do {
                let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
                guard let metadata = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      metadata["CFBundleIdentifier"] as? String == identifier else { return nil }
                return Installation(url: url.resolvingSymlinksInPath().standardizedFileURL,
                                    version: version(in: metadata), isLoaded: false)
            } catch {
                if !isMissing(error) { incomplete = true }
                return nil
            }
        }

        for directory in screenSaverDirectories {
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                savers += urls.filter { $0.pathExtension.lowercased() == "saver" }.compactMap { read($0, identifier: saverID) }
            } catch {
                if !isMissing(error) { incomplete = true }
            }
        }

        let hostID = hostBundle.bundleIdentifier
        if hostID == wallpaperID || hostID == saverID {
            let loaded = Installation(url: hostBundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL,
                                      version: version(in: hostBundle.infoDictionary ?? [:]), isLoaded: true)
            if hostID == wallpaperID {
                wallpapers = [loaded]
            } else {
                savers.removeAll { $0.url == loaded.url }
                savers.append(loaded)
                let candidates = wallpaperURLs ?? wallpaperCandidates(identifier: wallpaperID)
                wallpapers = candidates.compactMap { read($0, identifier: wallpaperID) }
            }
        }
        return MatrixVersionStatus(wallpapers: unique(wallpapers), screenSavers: unique(savers), discoveryIncomplete: incomplete)
    }

    private static func version(in metadata: [String: Any]) -> String? {
        guard let value = (metadata["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func versions(_ installations: [Installation]) -> String {
        guard !installations.isEmpty else { return "Not found" }
        return Set(installations.map { $0.version ?? "Version unavailable" }).sorted().joined(separator: ", ")
    }

    private static func unique(_ installations: [Installation]) -> [Installation] {
        var seen = Set<URL>()
        return installations.filter { seen.insert($0.url).inserted }.sorted { $0.url.path < $1.url.path }
    }

    private static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
    }

    private static func wallpaperCandidates(identifier: String) -> [URL] {
        var urls = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).compactMap(\.bundleURL)
        urls += NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier)
        for directory in FileManager.default.urls(for: .applicationDirectory, in: [.userDomainMask, .localDomainMask]) {
            for name in ["Matrix Wallpaper.app", "MatrixWallpaper.app"] {
                urls.append(directory.appendingPathComponent(name))
            }
        }
        return urls
    }
}
