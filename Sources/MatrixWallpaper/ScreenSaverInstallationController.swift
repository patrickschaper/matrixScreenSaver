import Foundation

/// Discovers the installed saver and serializes explicit recovery requests on the main thread.
final class ScreenSaverInstallationController {
    /// Presentation state shared by the menu and the settings banner.
    enum State {
        /// No matching installed bundle was found.
        case missing
        /// A matching installed bundle is available for synchronization.
        case installed
        /// The lifecycle script is restoring the companion bundle.
        case installing
    }

    /// Injectable asynchronous installation boundary; completion may arrive on any queue.
    typealias InstallOperation = (@escaping (Result<Void, Error>) -> Void) -> Void

    /// Latest observed presence, or an in-flight installation that refresh must not replace.
    private(set) var state: State = .missing
    /// Called on the main thread whenever presentation should be refreshed.
    var onChange: (() -> Void)?
    /// Standard user and system locations, injectable to avoid real installations in tests.
    private let directories: [URL]
    /// App identity used to recognize its managed installation record.
    private let appURL: URL
    /// Optional lifecycle record supplying a Homebrew custom saver destination.
    private let recordURL: URL?
    /// Executes the packaged lifecycle script, or an isolated test operation.
    private let operation: InstallOperation

    /// Creates installation state without changing the filesystem or user preferences.
    ///
    /// - Parameters:
    ///   - directories: Locations to scan for renamed or system-wide saver bundles.
    ///   - appURL: App whose packaged saver and lifecycle registration are used.
    ///   - recordURL: Managed installation record; `nil` disables record discovery in tests.
    ///   - operation: Optional replacement for the real asynchronous installer.
    init(directories: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers"),
            URL(fileURLWithPath: "/Library/Screen Savers")],
         appURL: URL = Bundle.main.bundleURL,
         recordURL: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MatrixWallpaper/Installation/installation.plist"),
         operation: InstallOperation? = nil) {
        self.directories = directories
        self.appURL = appURL
        self.recordURL = recordURL
        self.operation = operation ?? { completion in
            Self.runLifecycle(action: "install-saver", appURL: appURL, completion: completion)
        }
        refresh()
    }

    /// Re-reads presence without caching bundle metadata or disturbing an active transaction.
    func refresh() {
        guard state != .installing else { return }
        var candidates = directories.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        if let recordedSaver { candidates.append(recordedSaver) }
        state = candidates.contains(where: Self.isInstalledSaver) ? .installed : .missing
        onChange?()
    }

    /// Restores only a missing saver and reports the verified result on the main thread.
    ///
    /// Duplicate requests during installation are ignored. A fresh presence check avoids
    /// replacing a saver installed externally since the menu or settings last opened.
    /// - Parameter completion: Receives any installation failure after both surfaces refresh.
    func install(completion: @escaping (Result<Void, Error>) -> Void) {
        guard state != .installing else { return }
        refresh()
        guard state == .missing else { completion(.success(())); return }
        state = .installing
        onChange?()
        operation { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = .missing
                self.refresh()
                if case .success = result, self.state != .installed {
                    completion(.failure(Self.failure("The screen saver could not be found after installation. Try again.")))
                } else {
                    completion(result)
                }
            }
        }
    }

    /// Returns only this app's canonical, recognized managed destination.
    private var recordedSaver: URL? {
        guard let recordURL, recordURL.standardizedFileURL == recordURL.resolvingSymlinksInPath(),
              let record = Self.metadata(at: recordURL),
              let app = record["app"] as? String, let saver = record["saver"] as? String,
              let owner = record["owner"] as? String, ["local", "homebrew"].contains(owner),
              app.hasPrefix("/"), saver.hasPrefix("/"),
              URL(fileURLWithPath: app).standardizedFileURL == appURL.standardizedFileURL,
              URL(fileURLWithPath: app).lastPathComponent == "Matrix Wallpaper.app" else { return nil }
        let destination = URL(fileURLWithPath: saver)
        guard destination.lastPathComponent == "MatrixScreenSaver.saver",
              destination.path == destination.standardizedFileURL.path,
              destination.standardizedFileURL == destination.resolvingSymlinksInPath() else { return nil }
        return destination
    }

    /// Reads plist data directly so external deletions and replacements are visible immediately.
    /// - Returns: A dictionary for valid plist files, otherwise `nil`.
    private static func metadata(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Recognizes installed bundles while excluding only a transaction's known incomplete output.
    ///
    /// The sibling marker records device/inode before promotion. A replacement installed by
    /// another process has a different identity and must remain discoverable immediately.
    /// - Returns: Whether the bundle is available for synchronization.
    private static func isInstalledSaver(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "saver",
              metadata(at: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String ==
                "dev.patsch.MatrixScreenSaver" else { return false }
        guard let marker = try? String(contentsOfFile: url.path + ".installing", encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return true }
        return marker != "\(device):\(inode)"
    }

    /// Creates a user-facing failure shared by subprocess and verification errors.
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MatrixScreenSaverInstallation", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Runs recovery or cleanup activation off the UI thread, draining output without pipe deadlock.
    ///
    /// The child owns rollback and can finish safely even if the wallpaper app exits.
    /// - Parameters:
    ///   - action: `install-saver` restores the saver; `activate` starts existing managed cleanup.
    ///   - appURL: App containing the signed recovery resources.
    ///   - completion: Receives process success or a bounded diagnostic on the worker queue.
    static func runLifecycle(action: String, appURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [appURL.appendingPathComponent("Contents/Resources/ScreenSaver/product-lifecycle.sh").path,
                                 action, appURL.path]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                // Drain all output, retaining only its tail for an actionable, bounded alert.
                var output = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.readData(ofLength: 4096)
                    if chunk.isEmpty { break }
                    output.append(chunk)
                    if output.count > 4096 { output = Data(output.suffix(4096)) }
                }
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    let message = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(failure(message.isEmpty ? "Could not complete \(action). Try again." : message)))
                }
            } catch { completion(.failure(error)) }
        }
    }
}
