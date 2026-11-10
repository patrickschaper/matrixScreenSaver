import Foundation

/// Exercises installed metadata without changing real bundles or shared preferences.
func matrixVersionStatusTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let user = root.appendingPathComponent("user")
    let local = root.appendingPathComponent("local")

    func install(_ url: URL, identifier: String, version: String?) -> URL {
        let contents = url.appendingPathComponent("Contents")
        try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var metadata = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "BNDL"]
        metadata["CFBundleShortVersionString"] = version
        let data = try! PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try! data.write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    let wallpaper = install(root.appendingPathComponent("Wallpaper.app"), identifier: "dev.patsch.MatrixWallpaper", version: "1.4.0")
    let host = Bundle(url: wallpaper)!
    func status() -> MatrixVersionStatus {
        MatrixVersionStatus.current(hostBundle: host, screenSaverDirectories: [user, local], wallpaperURLs: [])
    }
    ok(status().state == .missingCompanion, "wallpaper alone is not a version mismatch")
    let saver = install(user.appendingPathComponent("Renamed.saver"), identifier: "dev.patsch.MatrixScreenSaver", version: " 1.4.0\n")
    ok(status().state == .matching, "renamed saver with whitespace-trimmed matching version is recognized")
    _ = install(saver, identifier: "dev.patsch.MatrixScreenSaver", version: "1.3.0")
    ok(status().state == .mismatch && status().message.contains("1.3.0") && status().message.contains("1.4.0"),
       "replacing installed saver refreshes versions without Bundle metadata caching")
    _ = install(saver, identifier: "dev.patsch.MatrixScreenSaver", version: "1.5.0")
    ok(status().state == .mismatch, "newer saver also triggers mismatch")
    _ = install(saver, identifier: "dev.patsch.MatrixScreenSaver", version: nil)
    ok(status().state == .unverified && status().message.contains("Version unavailable"), "missing version is unverified rather than compatible")
    _ = install(saver, identifier: "test.unrelated", version: "0.1.0")
    ok(status().state == .missingCompanion, "matching filename cannot substitute for bundle identity")
    try! Data("not a plist".utf8).write(to: saver.appendingPathComponent("Contents/Info.plist"))
    ok(status().state != .mismatch, "malformed metadata never invents a version mismatch")
    _ = install(saver, identifier: "dev.patsch.MatrixScreenSaver", version: "1.4.0")
    let duplicate = install(local.appendingPathComponent("Other.saver"), identifier: "dev.patsch.MatrixScreenSaver", version: "1.2.0")
    ok(status().state == .mismatch && status().screenSavers.contains { $0.url == duplicate.resolvingSymlinksInPath() }, "different installed copies retain their paths")
    try! FileManager.default.removeItem(at: duplicate)
    try! FileManager.default.createSymbolicLink(at: duplicate, withDestinationURL: saver)
    ok(status().state == .matching && status().screenSavers.count == 1, "symlinks to the same installation are deduplicated")

    let saverHostURL = install(root.appendingPathComponent("Loaded.saver"), identifier: "dev.patsch.MatrixScreenSaver", version: "1.1.0")
    let saverHost = Bundle(url: saverHostURL)!
    _ = saverHost.infoDictionary
    _ = install(saverHostURL, identifier: "dev.patsch.MatrixScreenSaver", version: "1.4.0")
    let fromSaver = MatrixVersionStatus.current(hostBundle: saverHost, screenSaverDirectories: [], wallpaperURLs: [wallpaper])
    ok(fromSaver.state == .mismatch && fromSaver.screenSavers.first?.version == "1.1.0",
       "screen saver compares its loaded metadata rather than the system host or replacement on disk")
    let matchingWallpaper = install(root.appendingPathComponent("Matching.app"), identifier: "dev.patsch.MatrixWallpaper", version: "1.1.0")
    let multiple = MatrixVersionStatus.current(hostBundle: saverHost, screenSaverDirectories: [],
                                              wallpaperURLs: [matchingWallpaper, wallpaper, matchingWallpaper])
    ok(multiple.state == .mismatch && multiple.wallpapers.count == 2 && multiple.wallpapers.contains { $0.url == wallpaper.resolvingSymlinksInPath() },
       "a matching wallpaper candidate cannot hide a differently versioned copy")
    let alone = MatrixVersionStatus.current(hostBundle: saverHost, screenSaverDirectories: [], wallpaperURLs: [])
    ok(alone.state == .missingCompanion, "screen saver alone is not a mismatch")
    try! FileManager.default.removeItem(at: saver)
    ok(status().state != .mismatch, "removing saver clears mismatch even with a dangling symlink")
}
