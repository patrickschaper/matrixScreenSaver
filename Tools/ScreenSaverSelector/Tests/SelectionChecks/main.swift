import Foundation
import MatrixScreenSaverSelection
import PaperSaverKit

/// Requires an invalid bundle to fail before any screen saver selection can occur.
private func expectInvalidBundle(_ saver: URL) {
    do {
        _ = try MatrixScreenSaverSelection.moduleName(for: saver)
        fatalError("Invalid or unsupported bundle was accepted: \(saver.path)")
    } catch {}
}

/// Rejects a missing, unrelated, or nonstandard bundle before the helper can write system settings.
/// - Throws: A temporary fixture creation or metadata write error.
private func checkInvalidBundles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let saver = root.appendingPathComponent("MatrixScreenSaver.saver")
    expectInvalidBundle(saver)
    let contents = saver.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    for identifier in ["test.unrelated", "dev.patsch.MatrixScreenSaver"] {
        let metadata = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier], format: .binary, options: 0)
        try metadata.write(to: contents.appendingPathComponent("Info.plist"))
        expectInvalidBundle(saver)
    }
    print("ok - missing, unrelated, and unsupported bundles cannot select another module")
}

/// Pins PaperSaver's contract for linked and per-display desktop content and backup restoration.
/// - Throws: A fixture, store transformation, backup, or restoration error.
private func checkDesktopPreservation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = StoreFile(url: root.appendingPathComponent("Index.plist"))
    let desktop: [String: Any] = [
        "Content": [
            "Choices": [
                [
                    "Provider": "com.apple.wallpaper.choice.image",
                    "Configuration": Data([1, 2, 3]),
                    "Files": [["relative": "file:///wallpaper.jpg"]],
                ]
            ],
            "EncodedOptionValues": Data([4, 5]), "Shuffle": "$null",
        ], "LastSet": Date(timeIntervalSince1970: 123),
    ]
    let individual: [String: Any] = [
        "Type": "individual", "Desktop": desktop, "CustomKey": "retain",
    ]
    let original: [String: Any] = [
        "AllSpacesAndDisplays": ["Type": "idle"],
        "SystemDefault": individual,
        "Displays": ["display": individual],
        "Spaces": [
            "space": [
                "Default": ["Type": "linked", "Linked": desktop],
                "Displays": ["display": individual],
            ]
        ],
        "UnknownRootKey": ["keep": true],
    ]
    let originalData = try PropertyListSerialization.data(
        fromPropertyList: original, format: .binary, options: 0)
    try originalData.write(to: file.url)
    let saver = root.appendingPathComponent("Renamed Matrix.saver")
    let choice = SlotConfiguration(
        choice: try WallpaperChoice(
            provider: .screenSaver, configuration: .screenSaver(moduleURL: saver)),
        optionValues: .null, shuffle: .null)
    let updated = try file.read().setting(.screensaver, to: choice, in: .everywhere)
    try file.write(updated)
    let backup = try Data(contentsOf: file.backupURL)
    precondition(backup == originalData, "Backup must retain the exact previous store")
    let result = try file.readPlist()
    let allSpaces = result["AllSpacesAndDisplays"] as! [String: Any]
    precondition(
        allSpaces["Type"] as? String == "idle" && allSpaces["Desktop"] == nil,
        "An idle-only override must not replace per-Space wallpaper")
    let system = result["SystemDefault"] as! [String: Any]
    precondition(system["Desktop"] as? NSDictionary == desktop as NSDictionary)
    precondition(system["CustomKey"] as? String == "retain")
    precondition(result["UnknownRootKey"] as? NSDictionary == ["keep": true] as NSDictionary)
    let spaces = result["Spaces"] as! [String: [String: Any]]
    let spaceDefault = spaces["space"]!["Default"] as! [String: Any]
    precondition(spaceDefault["Linked"] == nil)
    precondition(spaceDefault["Desktop"] as? NSDictionary == desktop as NSDictionary)
    let displays = result["Displays"] as! [String: [String: Any]]
    precondition(displays["display"]!["Desktop"] as? NSDictionary == desktop as NSDictionary)
    let spaceDisplays = spaces["space"]!["Displays"] as! [String: [String: Any]]
    precondition(spaceDisplays["display"]!["Desktop"] as? NSDictionary == desktop as NSDictionary)
    for section in try file.read().allSections {
        guard case .screenSaver(let selected)? = section.idle?.configuration else {
            fatalError("Every stored section must select a traditional screen saver")
        }
        precondition(selected == saver)
    }
    try file.restoreFromBackupFile()
    let restored = try Data(contentsOf: file.url)
    precondition(restored == originalData)
    print("ok - PaperSaver preserves desktop choices, unknown keys, and a restorable backup")
}

try checkInvalidBundles()
try checkDesktopPreservation()
