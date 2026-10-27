import AppKit

/// Exercises the real host's menu actions, notifications, rebuilds, and cleanup.
func wallpaperAppTests() {
    wallpaperIconTests()
    wallpaperSyncMenuTests()
    wallpaperDeferredLaunchTests()
    let suite = "MatrixWallpaperPlaybackTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let desktop = DesktopWallpaperFixture()
    let desktopController = desktop.controller()
    let host = WallpaperApp(defaults: defaults, desktopWallpaper: desktopController)
    host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    defer { host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
    let status: NSStatusItem? = stored("statusItem", in: host)
    check(status?.menu?.items.first?.title == "Stop", "launch installs playback controls before returning")
    check(stored("windows", in: host, as: [DesktopWindow].self)?.isEmpty == true &&
          ScreenSyncCoordinator.shared.registeredCount == 0 &&
          desktop.images["first"]?.url.path == "/original-a.jpg" && desktop.images["second"]?.url.path == "/original-b.jpg",
          "launch returns before creating views, registering playback, or acquiring desktops")
    check(eventually { desktopWindowCount() == NSScreen.screens.count }, "queued launch starts playback on the main run loop")
    check(desktop.images.values.allSatisfy { $0.url == desktopController.blackImageURL }, "host launch applies black desktop images")
    check(desktopWindowCount() == NSScreen.screens.count, "app creates one desktop window per display")
    check(ScreenSyncCoordinator.shared.registeredCount == NSScreen.screens.count, "app starts every display as one coordinated session")
    let originalWindows = NSApp.windows.compactMap { $0 as? DesktopWindow }.filter(\.isVisible)
    let originalIDs = Set(originalWindows.map(ObjectIdentifier.init))

    let workspace = NSWorkspace.shared.notificationCenter
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    check(desktop.images.values.allSatisfy { $0.url == desktopController.blackImageURL }, "temporary sleep retains black desktops and backups")
    check(desktopWindowCount() == 0 && ScreenSyncCoordinator.shared.registeredCount == originalWindows.count,
          "sleep hides windows but retains scene synchronization membership")
    check(originalWindows.allSatisfy { ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false },
          "sleep stops framework animation scheduling without destroying the views")
    workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    check(desktopWindowCount() == 0, "computer wake does not override display sleep")

    workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    let resumedIDs = Set(NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(ObjectIdentifier.init))
    check(resumedIDs == originalIDs && originalWindows.allSatisfy { ($0.contentView as? MatrixScreenSaverView)?.isAnimating == true },
          "wake resumes the same native views instead of replaying the intro")
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(Set(NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(ObjectIdentifier.init)) == originalIDs,
          "unchanged display notifications do not restart a resumed scene")
    if let source = originalWindows.first?.contentView as? MatrixScreenSaverView,
       let screen = originalWindows.first?.screen,
       let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
        var reader: WallpaperFrameReader? = WallpaperFrameReader()
        _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        var first: SharedWallpaperFrame.Frame?
        let deadline = Date(timeIntervalSinceNow: 10)
        repeat {
            wait(0.1)
            first = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        } while first == nil && Date() < deadline
        check(first != nil, "host discovery publishes a matching display without restarting its renderer")
        let distributed = DistributedNotificationCenter.default()
        distributed.postNotificationName(Notification.Name("com.apple.screensaver.willstart"), object: nil,
                                         userInfo: nil, deliverImmediately: true)
        wait(0.2)
        check(desktopWindowCount() == 0 && source.isAnimating,
              "active saver consumers hide desktop windows but keep their sole renderer running")
        wait(0.6)
        let next = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        check(next != nil && next!.sequence > (first?.sequence ?? 0),
              "hidden wallpaper publishes advancing frames for the saver")
        let sharedURL = source.shareWallpaperFrames()!
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        check(!FileManager.default.fileExists(atPath: sharedURL.path) && !source.isAnimating,
              "disabling sync removes the active offer and stops hidden wallpaper work")
        for _ in 0..<3 {
            _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
            wait(0.3)
            check(!FileManager.default.fileExists(atPath: sharedURL.path) && !source.isAnimating,
                  "disabled sync ignores repeated consumer requests")
        }
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        check(eventually(5) {
            _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
            return source.isAnimating && stored("sharedFrameBuffer", in: source, as: SharedWallpaperFrame?.self).flatMap { $0 } != nil
        }, "re-enabling sync reconnects through normal frame discovery")
        check(Set(NSApp.windows.filter { $0 is DesktopWindow }.map(ObjectIdentifier.init)).isSuperset(of: originalIDs),
              "sync reconnect retains the existing wallpaper views")
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        wait(0.6)
        check(!source.isAnimating && desktopWindowCount() == 0, "enabling sync cannot override system sleep")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        check(eventually(5) {
            _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
            return source.isAnimating && stored("sharedFrameBuffer", in: source, as: SharedWallpaperFrame?.self).flatMap { $0 } != nil
        }, "wake resumes frame sharing when sync remains enabled")
        if let other = originalWindows.first(where: {
            ($0.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) != displayID
        }), let otherSource = other.contentView as? MatrixScreenSaverView,
           let otherID = other.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
            var otherReader: WallpaperFrameReader? = WallpaperFrameReader()
            var otherFrame: SharedWallpaperFrame.Frame?
            let deadline = Date(timeIntervalSinceNow: 10)
            repeat {
                _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
                otherFrame = otherReader?.frame(displayID: otherID, pointSize: otherSource.bounds.size)
                wait(0.1)
            } while otherFrame == nil && Date() < deadline
            check(otherFrame != nil, "each display offers its own matching wallpaper frame")
            let otherURL = otherSource.shareWallpaperFrames()
            otherReader = nil
            let expiry = Date(timeIntervalSinceNow: SharedWallpaperFrame.freshnessInterval + 0.6)
            while Date() < expiry {
                _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
                wait(0.1)
            }
            check(otherURL != nil && !FileManager.default.fileExists(atPath: otherURL!.path) && source.isAnimating,
                  "one display's consumer expiry releases its buffer while another stays connected")
        }
        reader = nil
        wait(SharedWallpaperFrame.freshnessInterval + 0.6)
        check(!source.isAnimating && desktopWindowCount() == 0,
              "an expired consumer lease stops hidden rendering without discarding the session")
        distributed.postNotificationName(Notification.Name("com.apple.screensaver.didstop"), object: nil,
                                         userInfo: nil, deliverImmediately: true)
        wait(0.2)
        check(source.isAnimating && Set(NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(ObjectIdentifier.init)) == originalIDs,
              "saver exit reveals the same wallpaper views without replaying the intro")
    }
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)

    check(NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil), "Stop menu action is connected")
    check(desktop.images["first"]?.url.path == "/original-a.jpg" && desktop.images["second"]?.url.path == "/original-b.jpg",
          "Stop restores desktop images even during suspension")
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    check(desktopWindowCount() == 0, "host preserves Stop after suspension clears")
    NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
    wait(0.1)
    let optionsWindow = NSApp.windows.first { $0.isVisible && !($0 is DesktopWindow) && $0.canBecomeKey }
    check(optionsWindow != nil, "Options opens a normal native window while stopped")
    check(desktopWindowCount() == 0, "opening Options does not start stopped playback")
    optionsWindow?.performClose(nil)

    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    check(desktopWindowCount() == NSScreen.screens.count, "Start recreates wallpaper on all displays")
    check(desktop.images.values.allSatisfy { $0.url == desktopController.blackImageURL }, "Start reapplies black desktops")
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(desktopWindowCount() == NSScreen.screens.count && ScreenSyncCoordinator.shared.registeredCount == NSScreen.screens.count,
          "display reconciliation replaces rather than duplicates session membership")
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    check(desktopWindowCount() == 0 && ScreenSyncCoordinator.shared.registeredCount == 0, "Quit removes windows and animation participants")
    check(desktop.images["first"]?.url.path == "/original-a.jpg" && desktop.images["second"]?.url.path == "/original-b.jpg",
          "Quit restores desktop images after display reconciliation")
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(desktopWindowCount() == 0, "Quit unregisters system observers")
    wallpaperTerminationRecoveryTests()
}

/// Exercises launch cancellation and notifications before the queued continuation can run.
private func wallpaperDeferredLaunchTests() {
    let suite = "MatrixWallpaperDeferredLaunchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let workspace = NSWorkspace.shared.notificationCenter
    do {
        let desktop = DesktopWallpaperFixture()
        let controller = desktop.controller()
        try controller.start()
        var recoveredBeforeAcquiring = false
        desktop.beforeWrite = {
            if desktop.images["first"]?.url.path == "/original-a.jpg" && desktop.images["second"]?.url.path == "/original-b.jpg" {
                recoveredBeforeAcquiring = true
            }
        }
        defer { desktop.beforeWrite = nil }
        let host = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller())
        host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer { host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        check(!recoveredBeforeAcquiring && ScreenSyncCoordinator.shared.registeredCount == 0,
              "stale desktop recovery is deferred until after launch returns")
        check(eventually { desktopWindowCount() == NSScreen.screens.count }, "queued launch recovers a stale desktop backup")
        check(recoveredBeforeAcquiring && desktop.images.values.allSatisfy { $0.url == controller.blackImageURL },
              "queued launch restores every original before acquiring black desktops again")
        NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
        check(desktop.images["first"]?.url.path == "/original-a.jpg" && desktop.images["second"]?.url.path == "/original-b.jpg",
              "Stop after deferred recovery restores the original images")
    } catch {
        check(false, "deferred recovery fixture: \(error)")
    }
    for action in ["Stop", "Quit", "Stop then Start"] {
        let desktop = DesktopWallpaperFixture()
        var writes = 0
        desktop.beforeWrite = { writes += 1 }
        let host = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller())
        host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer { host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        if action == "Quit" {
            host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        } else {
            NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
            check(writes == 0 && ScreenSyncCoordinator.shared.registeredCount == 0,
                  "immediate Stop cancels launch without acquiring desktops")
            if action == "Stop then Start" {
                NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
                check(desktopWindowCount() == NSScreen.screens.count,
                      "explicit Start after cancelling launch remains synchronous")
            }
        }
        let windows = stored("windows", in: host, as: [DesktopWindow].self) ?? []
        let windowIDs = Set(windows.map(ObjectIdentifier.init))
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        var drained = false
        DispatchQueue.main.async { drained = true }
        check(eventually { drained }, "\(action) drains the stale launch continuation")
        check(Set((stored("windows", in: host, as: [DesktopWindow].self) ?? []).map(ObjectIdentifier.init)) == windowIDs,
              "\(action) cannot be undone or duplicated by queued launch work")
        check(writes == (action == "Stop then Start" ? desktop.connected.count : 0) &&
              ScreenSyncCoordinator.shared.registeredCount == windows.count,
              "\(action) leaves only the requested desktop ownership and session membership")
        if action == "Quit" {
            check(stored("observers", in: host, as: [(NotificationCenter, NSObjectProtocol)].self)?.isEmpty == true &&
                  stored("statusItem", in: host, as: NSStatusItem?.self).flatMap { $0 } == nil,
                  "immediate Quit removes observers and the status item")
        }
    }

    let desktop = DesktopWallpaperFixture()
    var writes = 0
    desktop.beforeWrite = { writes += 1 }
    let host = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller())
    host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    defer { host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(writes == 0 && ScreenSyncCoordinator.shared.registeredCount == 0,
          "display reconciliation cannot bypass pending launch")
    NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
    let optionsController: MatrixScreenSaverOptionsSheetController? = stored("optionsController", in: host)
    check(optionsController != nil, "pending launch exposes the options controller")
    check(writes == 0 && ScreenSyncCoordinator.shared.registeredCount == 0,
          "opening options cannot bypass pending launch")
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    if let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
        DistributedNotificationCenter.default().postNotificationName(SharedWallpaperFrame.requestNotification,
            object: String(displayID), userInfo: nil, deliverImmediately: true)
    }
    check(writes == 0 && stored("windows", in: host, as: [DesktopWindow].self)?.isEmpty == true,
          "pending launch notifications and sync changes cannot acquire desktops or create views")
    var drained = false
    DispatchQueue.main.async { drained = true }
    check(eventually { drained }, "suspended launch continuation drains")
    check(writes == 0 && ScreenSyncCoordinator.shared.registeredCount == 0,
          "sleep and session suspension prevent queued startup and frame requests from starting playback")
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    check(writes == 0, "wake during launch suspension does not override an inactive session")
    workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    check(desktopWindowCount() == NSScreen.screens.count && ScreenSyncCoordinator.shared.registeredCount == NSScreen.screens.count,
          "resuming deferred launch starts one session using the current displays")
}

/// Ensures a failed restore cannot block Quit and stale entries cannot replace a newer choice.
private func wallpaperTerminationRecoveryTests() {
    let suite = "MatrixWallpaperRecoveryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let desktop = DesktopWallpaperFixture()
    let controller = desktop.controller()
    let host = WallpaperApp(defaults: defaults, desktopWallpaper: controller)
    host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    check(eventually { desktopWindowCount() == NSScreen.screens.count }, "recovery fixture awaits launch playback")
    desktop.unreadable = ["first"]
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    check(NSApp.modalWindow == nil && desktopWindowCount() == 0,
          "restore failure during Quit returns without a modal dialog")
    check(desktop.images["first"]?.url == controller.blackImageURL && desktop.images["second"]?.url.path == "/original-b.jpg",
          "Quit retains the failed display backup and restores other displays")

    desktop.unreadable = []
    desktop.images["first"] = .init(url: URL(fileURLWithPath: "/new-after-failed-quit.jpg"), options: [:])
    let relaunched = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller())
    relaunched.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    check(eventually { desktopWindowCount() == NSScreen.screens.count }, "relaunch awaits recovery and playback")
    check(desktop.images.values.allSatisfy { $0.url == controller.blackImageURL }, "relaunch recovers stale entries and starts black")
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: relaunched, from: nil)
    check(desktop.images["first"]?.url.path == "/new-after-failed-quit.jpg",
          "relaunch captures a newer user choice instead of restoring a stale original")
    relaunched.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
}

/// Exercises installation discovery and persistent menu state without touching real installations.
private func wallpaperSyncMenuTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let user = root.appendingPathComponent("user")
    let local = root.appendingPathComponent("local")
    let suite = "MatrixWallpaperTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    var loginStatus = LoginItemController.Status.notRegistered
    let login = LoginItemController(readStatus: { loginStatus })
    let desktop = DesktopWallpaperFixture()
    let host = WallpaperApp(loginItems: login, defaults: defaults, screenSaverDirectories: [user, local], desktopWallpaper: desktop.controller())
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    defer { host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
    guard let status: NSStatusItem = stored("statusItem", in: host), let menu = status.menu,
          let sync = menu.items.first(where: { $0.title == "Sync with Screen Saver" }) else {
        check(false, "host installs the screen saver sync menu control")
        return
    }
    func refresh() { menu.delegate?.menuWillOpen?(menu) }
    func install(_ directory: URL, name: String, identifier: String) -> URL {
        let bundle = directory.appendingPathComponent(name)
        let contents = bundle.appendingPathComponent("Contents")
        try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier],
                                                        format: .xml, options: 0)
        try! data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }
    refresh()
    check(sync.isHidden && sync.state == .on, "sync defaults on but is hidden without an installed saver")
    let unrelated = install(user, name: "Other.saver", identifier: "test.other")
    refresh()
    check(sync.isHidden, "unrelated saver bundles do not expose sync")
    let installed = install(user, name: "Renamed.saver", identifier: "dev.patsch.MatrixScreenSaver")
    refresh()
    check(!sync.isHidden && sync.state == .on, "renamed user installation exposes default-enabled sync")
    menu.performActionForItem(at: menu.index(of: sync))
    check(sync.state == .off, "sync menu action unchecks the persisted preference")
    try! FileManager.default.removeItem(at: installed)
    refresh()
    check(sync.isHidden && sync.state == .off, "removal hides sync without resetting its choice")
    let localInstall = install(local, name: "Matrix.saver", identifier: "dev.patsch.MatrixScreenSaver")
    refresh()
    check(!sync.isHidden && sync.state == .off, "local installation restores visibility and preserves sync off")
    try! FileManager.default.removeItem(at: localInstall)
    try! Data("invalid plist".utf8).write(to: unrelated.appendingPathComponent("Contents/Info.plist"))
    refresh()
    check(sync.isHidden, "malformed bundle metadata is ignored")
    let target = install(root, name: "Target.saver", identifier: "dev.patsch.MatrixScreenSaver")
    try! FileManager.default.createSymbolicLink(at: local.appendingPathComponent("Linked.saver"), withDestinationURL: target)
    loginStatus = .enabled
    refresh()
    check(!sync.isHidden && login.item.state == .on, "menu refresh follows saver symlinks and refreshes Launch at Login")
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    let relaunched = WallpaperApp(defaults: UserDefaults(suiteName: suite)!, screenSaverDirectories: [user, local],
                                 desktopWallpaper: desktop.controller())
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: relaunched, from: nil)
    relaunched.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    defer { relaunched.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
    let relaunchedStatus: NSStatusItem? = stored("statusItem", in: relaunched)
    check(relaunchedStatus?.menu?.items.first(where: { $0.title == sync.title })?.state == .off,
          "explicit sync off survives host relaunch")
}

/// Checks the shipped artwork rather than duplicating the generator's drawing logic.
private func wallpaperIconTests() {
    let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
    guard let image = NSImage(contentsOf: resources.appendingPathComponent("WallpaperIcon.png")),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        check(false, "app icon preview loads")
        return
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    check(bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 1024, "app icon has a full-resolution master")
    check(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0 &&
          bitmap.colorAt(x: 150, y: 512)!.brightnessComponent == 0,
          "app icon has transparent outer corners and a black tile")
    let greens = (300..<700).map { bitmap.colorAt(x: 380, y: $0)!.usingColorSpace(.sRGB)! }
    check(greens.contains { $0.greenComponent > 0.7 && $0.greenComponent > $0.redComponent * 2 },
          "app glyph uses saturated rain green")
    check(zip(greens, greens.dropFirst()).contains { abs($0.greenComponent - $1.greenComponent) > 0.2 },
          "app glyph includes contrasting scanlines")
    check(bitmap.colorAt(x: 300, y: 267)!.usingColorSpace(.sRGB)!.greenComponent > 0.7 &&
          bitmap.colorAt(x: 350, y: 760)!.usingColorSpace(.sRGB)!.greenComponent > 0.4 &&
          bitmap.colorAt(x: 700, y: 760)!.usingColorSpace(.sRGB)!.greenComponent < 0.15,
          "app glyph retains the SVG M's stepped shoulder and uneven feet")
    let icon = NSImage(contentsOf: resources.appendingPathComponent("WallpaperIcon.icns"))
    check(icon != nil && icon!.representations.count > 1, "app icon includes multiple native resolutions")

    guard let document = CGPDFDocument(resources.appendingPathComponent("MenuBarIcon.pdf") as CFURL),
          let page = document.page(at: 1),
          let context = CGContext(data: nil, width: 72, height: 72, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        check(false, "menu icon loads as vector artwork")
        return
    }
    check(page.getBoxRect(.mediaBox).size == CGSize(width: 18, height: 18), "menu icon fits the status bar")
    context.scaleBy(x: 4, y: 4)
    context.drawPDFPage(page)
    let menu = NSBitmapImageRep(cgImage: context.makeImage()!)
    let stem = (12..<60).map { menu.colorAt(x: 20, y: $0)! }
    check(menu.colorAt(x: 0, y: 0)!.alphaComponent == 0 &&
          stem.contains { $0.alphaComponent == 0 } && stem.contains { $0.alphaComponent > 0.9 },
          "menu icon has transparent background and scanline gaps through the M")
    check(stem.allSatisfy { $0.redComponent == $0.greenComponent && $0.greenComponent == $0.blueComponent },
          "menu icon is monochrome for system template tinting")
}

/// Counts visible desktop surfaces without inspecting the host's private storage.
private func desktopWindowCount() -> Int {
    NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.count
}
