import AppKit

/// Simulates connected displays while keeping persistence on a real, isolated filesystem.
final class DesktopWallpaperFixture {
    /// Isolated Application Support substitute, removed when the fixture is released.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    /// Display UUIDs currently visible to the controller.
    var connected = ["first", "second"]
    /// Fake system settings, deliberately different for each display.
    var images: [String: DesktopWallpaperController.Image] = [
        "first": .init(url: URL(fileURLWithPath: "/original-a.jpg"),
                       options: [.imageScaling: 2, .allowClipping: true, .fillColor: NSColor.red]),
        "second": .init(url: URL(fileURLWithPath: "/original-b.jpg"),
                        options: [.imageScaling: 0, .allowClipping: false, .fillColor: NSColor.blue])
    ]
    /// Displays on which the simulated desktop setter fails.
    var failing = Set<String>()
    /// Displays whose settings cannot be read.
    var unreadable = Set<String>()
    /// Observes writes to verify backup-before-mutation ordering.
    var beforeWrite: (() -> Void)?

    /// Creates another controller over the same storage to model process relaunch.
    func controller() -> DesktopWallpaperController {
        DesktopWallpaperController(directory: directory, screens: { self.connected }, readImage: {
            self.unreadable.contains($0) ? nil : self.images[$0]
        }, setImage: { image, id in
            self.beforeWrite?()
            if self.failing.contains(id) { throw NSError(domain: "TestDesktop", code: 1) }
            self.images[id] = image
        })
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Verifies round trips, durable recovery, and failures without changing the user's desktop.
func desktopWallpaperTests() {
    let fixture = DesktopWallpaperFixture()
    let originals = fixture.images
    let controller = fixture.controller()
    fixture.beforeWrite = {
        check(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("originals.plist").path),
              "original settings reach disk before desktop mutation")
    }
    do {
        try controller.start()
        fixture.beforeWrite = nil
        check(fixture.images.values.allSatisfy { $0.url == controller.blackImageURL }, "Start makes every desktop black")
        let bitmap = NSBitmapImageRep(data: try Data(contentsOf: controller.blackImageURL))
        let color = bitmap?.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
        check(color?.redComponent == 0 && color?.greenComponent == 0 && color?.blueComponent == 0 && color?.alphaComponent == 1,
              "generated wallpaper is opaque black")
        try controller.start()
        try fixture.controller().restore()
        for id in fixture.connected {
            check(fixture.images[id]?.url == originals[id]?.url &&
                  NSDictionary(dictionary: fixture.images[id]!.options).isEqual(to: originals[id]!.options),
                  "relaunch restores original URL, scaling, clipping, and color for \(id)")
        }
        try controller.start()
        fixture.connected = ["first"]
        try controller.restore()
        check(fixture.images["second"]?.url == controller.blackImageURL, "disconnected display remains pending")
        fixture.connected = ["first", "second"]
        fixture.failing = ["second"]
        do { try controller.restore(); check(false, "failed restore is reported") }
        catch { check(true, "failed restore is reported") }
        fixture.failing = []
        try fixture.controller().restore()
        check(fixture.images["second"]?.url == originals["second"]?.url, "failed and disconnected restore survives relaunch")
        try controller.start()
        fixture.images["first"] = .init(url: URL(fileURLWithPath: "/new-user-choice.jpg"), options: [:])
        try controller.start()
        check(fixture.images["first"]?.url.path == "/new-user-choice.jpg", "rebuild preserves a newer user-selected image")
        try controller.restore()
        check(fixture.images["first"]?.url.path == "/new-user-choice.jpg", "Stop preserves a newer user-selected image")
        try controller.start()
        try controller.restore()
        check(fixture.images["first"]?.url.path == "/new-user-choice.jpg", "next session backs up the newer choice")
    } catch { check(false, "desktop round trip: \(error)") }
    fixture.beforeWrite = nil

    let failed = DesktopWallpaperFixture()
    let failedController = failed.controller()
    failed.failing = ["first"]
    do { try failedController.start(); check(false, "failed black-image write is reported") }
    catch { check(true, "failed black-image write is reported") }
    check(failed.images["first"]?.url.path == "/original-a.jpg" && failed.images["second"]?.url == failedController.blackImageURL,
          "one desktop failure does not prevent other displays from starting")
    failed.failing = []
    do { try failed.controller().restore() }
    catch { check(false, "partial start can be restored") }
    check(failed.images["second"]?.url.path == "/original-b.jpg", "partial start retains a recoverable original")

    let corrupt = DesktopWallpaperFixture()
    do {
        try FileManager.default.createDirectory(at: corrupt.directory, withIntermediateDirectories: true)
        let backup = corrupt.directory.appendingPathComponent("originals.plist")
        try Data("broken".utf8).write(to: backup)
        do { try corrupt.controller().start(); check(false, "corrupt backup blocks mutation") }
        catch { check(corrupt.images["first"]?.url.path == "/original-a.jpg", "corrupt backup blocks mutation") }
        check(try Data(contentsOf: backup) == Data("broken".utf8), "corrupt backup is preserved for recovery")
    } catch { check(false, "corrupt-backup fixture: \(error)") }

    let unwritable = DesktopWallpaperFixture()
    do {
        try Data().write(to: unwritable.directory)
        do { try unwritable.controller().start(); check(false, "storage failure blocks desktop mutation") }
        catch { check(unwritable.images["first"]?.url.path == "/original-a.jpg", "storage failure blocks desktop mutation") }
    } catch { check(false, "storage-failure fixture: \(error)") }

    let unreadable = DesktopWallpaperFixture()
    unreadable.unreadable = ["first"]
    do { try unreadable.controller().start(); check(false, "unreadable desktop settings are reported") }
    catch { check(unreadable.images["first"]?.url.path == "/original-a.jpg", "unreadable desktop is left untouched") }
}
