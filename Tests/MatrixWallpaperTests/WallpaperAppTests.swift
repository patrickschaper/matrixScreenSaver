import AppKit

/// Exercises the real host's menu actions, notifications, rebuilds, and cleanup.
func wallpaperAppTests() {
    wallpaperSelectionPreservationTests()
    wallpaperIconTests()
    wallpaperSyncMenuTests()
    wallpaperDeferredLaunchTests()
    let suite = "MatrixWallpaperPlaybackTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let saverDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
    let saverContents = saverDirectory.appendingPathComponent("MatrixScreenSaver.saver/Contents")
    try! FileManager.default.createDirectory(at: saverContents, withIntermediateDirectories: true)
    let saverMetadata = try! PropertyListSerialization.data(
        fromPropertyList: ["CFBundleIdentifier": "dev.patsch.MatrixScreenSaver"], format: .xml,
        options: 0)
    try! saverMetadata.write(to: saverContents.appendingPathComponent("Info.plist"))
    defer { try? FileManager.default.removeItem(at: saverDirectory) }
    let host = WallpaperApp(defaults: defaults, screenSaverDirectories: [saverDirectory])
    host.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    defer {
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
    let status: NSStatusItem? = stored("statusItem", in: host)
    let menuItems = status?.menu?.items ?? []
    let donationItem = menuItems.first { $0.action == NSSelectorFromString("openDonationPage:") }
    check(
        donationItem?.title == "Buy Me a Coffee"
            && donationItem?.image?.size == NSSize(width: 16, height: 16)
            && donationItem?.image?.isTemplate == false,
        "donation menu uses the full-color favicon at 16 points with the requested title")
    if let donationItem, donationItem.responds(to: NSSelectorFromString("preferredImageVisibility"))
    {
        check(
            donationItem.value(forKey: "preferredImageVisibility") as? Int == 1,
            "donation menu keeps the favicon visible on macOS 27")
    }
    let stopItem = menuItems.first { $0.action == NSSelectorFromString("togglePlayback:") }
    let pauseItem = menuItems.first { $0.action == NSSelectorFromString("togglePause:") }
    check(
        menuItems.filter { !$0.isHidden }.prefix(2).map(\.title) == [
            "Pause Animation", "Stop Wallpaper",
        ] && menuItems.allSatisfy { $0.view == nil } && pauseItem?.image != nil
            && stopItem?.image != nil,
        "playback commands lead the menu as native items with symbols")
    let settingsItem = menuItems.first { $0.action == NSSelectorFromString("showOptions:") }
    check(
        settingsItem?.title == "Settings…" && settingsItem?.keyEquivalent == ","
            && settingsItem?.keyEquivalentModifierMask == .command,
        "Settings uses the standard macOS label and Command-comma shortcut")
    if let loginIndex = menuItems.firstIndex(where: { $0.title.hasPrefix("Launch at Login") }),
        let syncIndex = menuItems.firstIndex(where: {
            $0.title == "Sync with Screen Saver" || $0.title == "Install Screen Saver"
                || $0.title == "Set Matrix Screen Saver"
        })
    {
        check(
            syncIndex == loginIndex + 1 && loginIndex > 1
                && menuItems[loginIndex - 1] === settingsItem
                && menuItems[loginIndex - 2].isSeparatorItem && syncIndex + 1 < menuItems.count
                && menuItems[syncIndex + 1].isSeparatorItem,
            "settings, login, and screen saver sync form one preference group")
    } else {
        check(false, "menu contains login and screen saver sync controls")
    }
    check(
        stored("windows", in: host, as: [DesktopWindow].self)?.isEmpty == true
            && ScreenSyncCoordinator.shared.registeredCount == 0,
        "launch returns before creating views or registering playback")
    // AppKit can spend over two seconds drawing the previous fixture before servicing queued startup on CI.
    let started = eventually(10) { desktopWindowCount() == NSScreen.screens.count }
    check(started, "queued launch starts playback on the main run loop")
    guard started else { return }
    check(
        desktopWindowCount() == NSScreen.screens.count, "app creates one desktop window per display"
    )
    check(
        ScreenSyncCoordinator.shared.registeredCount == NSScreen.screens.count,
        "app starts every display as one coordinated session")
    let originalWindows = NSApp.windows.compactMap { $0 as? DesktopWindow }.filter(\.isVisible)
    let originalIDs = Set(originalWindows.map(ObjectIdentifier.init))

    let workspace = NSWorkspace.shared.notificationCenter
    wait(0.3)
    if let pauseItem, let menu = status?.menu {
        menu.performActionForItem(at: menu.index(of: pauseItem))
    }
    check(
        pauseItem?.title == "Resume Animation" && stopItem?.title == "Stop Wallpaper"
            && pauseItem?.isEnabled == true,
        "native Pause command freezes playback and offers Resume Animation")
    check(
        originalWindows.allSatisfy {
            $0.isVisible && ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false
        },
        "Pause freezes every display without hiding its wallpaper")
    if let source = originalWindows.first?.contentView {
        let frozen = pixels(of: source)
        wait(0.3)
        check(
            frozen != nil && pixels(of: source) == frozen,
            "paused wallpaper retains the same pixels")
    }
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    check(desktopWindowCount() == 0, "sleep hides an already manually paused wallpaper")
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    check(
        originalWindows.allSatisfy {
            $0.isVisible && ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false
        },
        "wake reveals the frozen wallpaper without clearing manual pause")
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    check(
        desktopWindowCount() == 0
            && originalWindows.allSatisfy {
                ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false
            },
        "Resume cannot override system sleep")
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    check(
        pauseItem?.title == "Pause Animation"
            && originalWindows.allSatisfy {
                $0.isVisible && ($0.contentView as? MatrixScreenSaverView)?.isAnimating == true
            },
        "Resume continues the original views after the system suspension ends")
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    check(
        desktopWindowCount() == 0
            && ScreenSyncCoordinator.shared.registeredCount == originalWindows.count,
        "sleep hides windows but retains scene synchronization membership")
    check(
        originalWindows.allSatisfy {
            ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false
        },
        "sleep stops framework animation scheduling without destroying the views")
    workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    check(desktopWindowCount() == 0, "computer wake does not override display sleep")

    workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    let resumedIDs = Set(
        NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(ObjectIdentifier.init))
    check(
        resumedIDs == originalIDs
            && originalWindows.allSatisfy {
                ($0.contentView as? MatrixScreenSaverView)?.isAnimating == true
            },
        "wake resumes the same native views instead of replaying the intro")
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(
        Set(NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(ObjectIdentifier.init))
            == originalIDs,
        "unchanged display notifications do not restart a resumed scene")
    if let source = originalWindows.first?.contentView as? MatrixScreenSaverView,
        let screen = originalWindows.first?.screen,
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? UInt32
    {
        NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
        check(!source.isAnimating, "wallpaper is paused before saver discovery")
        var reader: WallpaperFrameReader? = WallpaperFrameReader()
        _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        var first: SharedWallpaperFrame.Frame?
        let deadline = Date(timeIntervalSinceNow: 10)
        repeat {
            wait(0.1)
            first = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        } while first == nil && Date() < deadline
        check(
            first != nil && source.isAnimating && pauseItem?.title == "Resume Animation",
            "saver discovery advances the paused scene without clearing manual pause")
        let distributed = DistributedNotificationCenter.default()
        distributed.postNotificationName(
            Notification.Name("com.apple.screensaver.willstart"), object: nil,
            userInfo: nil, deliverImmediately: true)
        wait(0.2)
        check(
            desktopWindowCount() == 0 && source.isAnimating,
            "active saver consumers hide desktop windows but keep their sole renderer running")
        wait(0.6)
        let next = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        check(
            next != nil && next!.sequence > (first?.sequence ?? 0),
            "hidden wallpaper publishes advancing frames for the saver")
        NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
        NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
        check(
            source.isAnimating && pauseItem?.title == "Resume Animation"
                && desktopWindowCount() == 0,
            "changing manual pause during saver playback preserves the active shared scene")
        let sharedURL = source.shareWallpaperFrames()!
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        check(
            !FileManager.default.fileExists(atPath: sharedURL.path) && !source.isAnimating,
            "disabling sync removes the active offer and stops hidden wallpaper work")
        for _ in 0..<3 {
            _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
            wait(0.3)
            check(
                !FileManager.default.fileExists(atPath: sharedURL.path) && !source.isAnimating,
                "disabled sync ignores repeated consumer requests")
        }
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        check(
            eventually(5) {
                _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
                return source.isAnimating
                    && stored("sharedFrameBuffer", in: source, as: SharedWallpaperFrame?.self)
                        .flatMap { $0 } != nil
            }, "re-enabling sync reconnects through normal frame discovery")
        check(
            Set(NSApp.windows.filter { $0 is DesktopWindow }.map(ObjectIdentifier.init)).isSuperset(
                of: originalIDs),
            "sync reconnect retains the existing wallpaper views")
        reader = nil
        distributed.postNotificationName(
            Notification.Name("com.apple.screensaver.didstop"), object: nil,
            userInfo: nil, deliverImmediately: true)
        wait(0.2)
        check(
            !source.isAnimating && pauseItem?.title == "Resume Animation"
                && Set(originalWindows.filter(\.isVisible).map(ObjectIdentifier.init))
                    == originalIDs,
            "saver exit immediately reveals the preserved paused wallpaper before its lease expires"
        )
        let frozen = pixels(of: source)
        wait(0.3)
        check(
            frozen != nil && pixels(of: source) == frozen,
            "returned wallpaper stays frozen at the advanced scene")
        distributed.postNotificationName(
            Notification.Name("com.apple.screensaver.willstart"), object: nil,
            userInfo: nil, deliverImmediately: true)
        reader = WallpaperFrameReader()
        check(
            eventually(5) {
                reader?.frame(displayID: displayID, pointSize: source.bounds.size) != nil
                    && source.isAnimating
            }, "a second saver session resumes sharing while manual pause remains set")
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
        _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
        wait(0.6)
        check(
            !source.isAnimating && desktopWindowCount() == 0,
            "enabling sync cannot override system sleep")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        check(
            eventually(5) {
                _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
                return source.isAnimating
                    && stored("sharedFrameBuffer", in: source, as: SharedWallpaperFrame?.self)
                        .flatMap { $0 } != nil
            }, "wake resumes frame sharing when sync remains enabled")
        if let other = originalWindows.first(where: {
            ($0.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                != displayID
        }), let otherSource = other.contentView as? MatrixScreenSaverView,
            let otherID = other.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? UInt32
        {
            var otherReader: WallpaperFrameReader? = WallpaperFrameReader()
            var otherFrame: SharedWallpaperFrame.Frame?
            let deadline = Date(timeIntervalSinceNow: 10)
            repeat {
                _ = reader?.frame(displayID: displayID, pointSize: source.bounds.size)
                otherFrame = otherReader?.frame(
                    displayID: otherID, pointSize: otherSource.bounds.size)
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
            check(
                otherURL != nil && !FileManager.default.fileExists(atPath: otherURL!.path)
                    && source.isAnimating,
                "one display's consumer expiry releases its buffer while another stays connected")
        }
        reader = nil
        wait(SharedWallpaperFrame.freshnessInterval + 0.6)
        check(
            !source.isAnimating && desktopWindowCount() == 0,
            "an expired consumer lease stops hidden rendering without discarding the session")
        distributed.postNotificationName(
            Notification.Name("com.apple.screensaver.didstop"), object: nil,
            userInfo: nil, deliverImmediately: true)
        wait(0.2)
        check(
            !source.isAnimating && pauseItem?.title == "Resume Animation"
                && Set(
                    NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(
                        ObjectIdentifier.init)) == originalIDs,
            "saver exit after lease expiry keeps the same wallpaper views paused")
        NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
        check(source.isAnimating, "manual Resume still works after synced saver playback")
    }
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)

    check(
        NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil),
        "Stop menu action is connected")
    check(
        stopItem?.title == "Start Wallpaper" && pauseItem?.title == "Pause Animation"
            && pauseItem?.isEnabled == false,
        "Stop offers Start Wallpaper and leaves Pause Animation visible but disabled")
    NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    check(desktopWindowCount() == 0, "host preserves Stop after suspension clears")
    NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
    wait(0.1)
    let optionsWindow = NSApp.windows.first {
        $0.isVisible && !($0 is DesktopWindow) && $0.canBecomeKey
    }
    check(optionsWindow != nil, "Options opens a normal native window while stopped")
    let saverOptionsHost = MatrixScreenSaverView(
        frame: NSRect(x: 0, y: 0, width: 640, height: 360), isPreview: true)!
    let saverOptionsWindow = saverOptionsHost.configureSheet
    let saverOptionsController: MatrixScreenSaverOptionsSheetController? = stored(
        "optionsSheetController", in: saverOptionsHost)
    let wallpaperOptionsController: MatrixScreenSaverOptionsSheetController? = stored(
        "optionsController", in: host)
    check(
        saverOptionsController != nil && wallpaperOptionsController != nil
            && saverOptionsWindow === saverOptionsController?.configureSheet()
            && optionsWindow === wallpaperOptionsController?.configureSheet(),
        "saver and wallpaper both present the shared native options controller")
    check(
        saverOptionsWindow?.contentView?.bounds.size == optionsWindow?.contentView?.bounds.size,
        "saver sheet and wallpaper options window use identical dialog dimensions")
    check(desktopWindowCount() == 0, "opening Options does not start stopped playback")
    if let controller = wallpaperOptionsController, let window = optionsWindow {
        wallpaperEditingShortcutTests(controller: controller, window: window)
    }
    optionsWindow?.performClose(nil)

    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    check(
        desktopWindowCount() == NSScreen.screens.count, "Start recreates wallpaper on all displays")
    check(
        pauseItem?.isEnabled == true
            && (stored("windows", in: host, as: [DesktopWindow].self) ?? []).allSatisfy {
                ($0.contentView as? MatrixScreenSaverView)?.isAnimating == true
            }, "Start runs normally after stopping a paused session")
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(
        desktopWindowCount() == NSScreen.screens.count
            && ScreenSyncCoordinator.shared.registeredCount == NSScreen.screens.count,
        "display reconciliation replaces rather than duplicates session membership")
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    check(
        desktopWindowCount() == 0 && ScreenSyncCoordinator.shared.registeredCount == 0,
        "Quit removes windows and animation participants")
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(desktopWindowCount() == 0, "Quit unregisters system observers")
}

/// Guards against reintroducing desktop-image changes or legacy wallpaper backup handling.
private func wallpaperSelectionPreservationTests() {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
    guard let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    else {
        check(false, "wallpaper preservation guard can read runtime sources")
        return
    }
    do {
        let swiftFiles = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        guard !swiftFiles.isEmpty else {
            check(false, "wallpaper preservation guard finds runtime sources")
            return
        }
        let source = try swiftFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(
            separator: "\n")
        check(
            !source.contains("setDesktopImageURL"),
            "runtime sources never set the native desktop image")
        check(
            !source.contains("DesktopWallpaperController") && !source.contains("originals.plist"),
            "runtime sources cannot acquire or restore legacy wallpaper backups")
    } catch { check(false, "wallpaper preservation source guard: \(error)") }
}

/// Checks registered shortcuts against the real field editor without requiring foreground activation.
private func wallpaperEditingShortcutTests(
    controller: MatrixScreenSaverOptionsSheetController, window: NSWindow
) {
    guard let field: NSTextField = stored("nameField", in: controller) else {
        check(false, "options exposes an editable name field")
        return
    }
    let pasteboard = NSPasteboard.general
    let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
        let saved = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { saved.setData(data, forType: type) }
        }
        return saved
    }
    let original = field.stringValue
    let wasEnabled = field.isEnabled
    let scroll: NSScrollView? = stored("optionsScrollView", in: controller)
    let tabs = scroll?.documentView as? NSTabView
    let selectedTab = tabs?.selectedTabViewItem
    tabs?.selectTabViewItem(at: 1)
    defer {
        field.stringValue = original
        field.isEnabled = wasEnabled
        if let selectedTab { tabs?.selectTabViewItem(selectedTab) }
        pasteboard.clearContents()
        pasteboard.writeObjects(savedItems)
    }
    field.isEnabled = true
    field.stringValue = "Neo"
    window.makeKeyAndOrderFront(nil)
    check(
        window.makeFirstResponder(field) && field.currentEditor() != nil,
        "options field receives editing focus")
    func shortcut(_ key: String) -> Bool {
        guard
            let item = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu?.items.first(where: {
                $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command
            }), item.target == nil, let action = item.action, let editor = field.currentEditor()
        else { return false }
        return NSApp.sendAction(action, to: editor, from: item)
    }
    check(
        shortcut("a")
            && (field.currentEditor() as? NSTextView)?.selectedRange()
                == NSRange(location: 0, length: 3),
        "Command-A selects the focused options field")
    check(
        shortcut("c") && pasteboard.string(forType: .string) == "Neo",
        "Command-C copies selected dialog text")
    check(
        shortcut("x") && field.currentEditor()?.string == "", "Command-X cuts selected dialog text")
    check(
        shortcut("v") && field.currentEditor()?.string == "Neo",
        "Command-V pastes into the focused dialog field")
}

/// Exercises launch cancellation and notifications before the queued continuation can run.
private func wallpaperDeferredLaunchTests() {
    let suite = "MatrixWallpaperDeferredLaunchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let workspace = NSWorkspace.shared.notificationCenter
    do {
        let host = WallpaperApp(defaults: defaults)
        host.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            host.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification))
        }
        NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
        check(
            eventually { desktopWindowCount() == NSScreen.screens.count },
            "Pause during queued launch still creates desktop surfaces")
        check(
            (stored("windows", in: host, as: [DesktopWindow].self) ?? []).allSatisfy {
                ($0.contentView as? MatrixScreenSaverView)?.isAnimating == false
            }, "queued startup preserves an immediate manual pause")
        NSApp.sendAction(NSSelectorFromString("togglePause:"), to: host, from: nil)
        check(
            (stored("windows", in: host, as: [DesktopWindow].self) ?? []).allSatisfy {
                ($0.contentView as? MatrixScreenSaverView)?.isAnimating == true
            }, "Resume starts the session paused during launch")
    }
    for action in ["Stop", "Quit", "Stop then Start"] {
        let host = WallpaperApp(defaults: defaults)
        host.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            host.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification))
        }
        if action == "Quit" {
            host.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification))
        } else {
            NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
            check(
                ScreenSyncCoordinator.shared.registeredCount == 0,
                "immediate Stop cancels launch before registering playback")
            if action == "Stop then Start" {
                NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
                check(
                    desktopWindowCount() == NSScreen.screens.count,
                    "explicit Start after cancelling launch remains synchronous")
            }
        }
        let windows = stored("windows", in: host, as: [DesktopWindow].self) ?? []
        let windowIDs = Set(windows.map(ObjectIdentifier.init))
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        var drained = false
        DispatchQueue.main.async { drained = true }
        check(eventually { drained }, "\(action) drains the stale launch continuation")
        check(
            Set(
                (stored("windows", in: host, as: [DesktopWindow].self) ?? []).map(
                    ObjectIdentifier.init)) == windowIDs,
            "\(action) cannot be undone or duplicated by queued launch work")
        check(
            ScreenSyncCoordinator.shared.registeredCount == windows.count,
            "\(action) leaves only the requested session membership")
        if action == "Quit" {
            check(
                stored("observers", in: host, as: [(NotificationCenter, NSObjectProtocol)].self)?
                    .isEmpty == true
                    && stored("statusItem", in: host, as: NSStatusItem?.self).flatMap { $0 } == nil,
                "immediate Quit removes observers and the status item")
        }
    }

    let host = WallpaperApp(defaults: defaults)
    host.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    defer {
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(
        ScreenSyncCoordinator.shared.registeredCount == 0,
        "display reconciliation cannot bypass pending launch")
    NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
    let optionsController: MatrixScreenSaverOptionsSheetController? = stored(
        "optionsController", in: host)
    check(optionsController != nil, "pending launch exposes the options controller")
    check(
        ScreenSyncCoordinator.shared.registeredCount == 0,
        "opening options cannot bypass pending launch")
    workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    NSApp.sendAction(NSSelectorFromString("toggleScreenSaverSync:"), to: host, from: nil)
    if let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? UInt32
    {
        DistributedNotificationCenter.default().postNotificationName(
            SharedWallpaperFrame.requestNotification,
            object: String(displayID), userInfo: nil, deliverImmediately: true)
    }
    check(
        stored("windows", in: host, as: [DesktopWindow].self)?.isEmpty == true,
        "pending launch notifications and sync changes cannot create views")
    var drained = false
    DispatchQueue.main.async { drained = true }
    check(eventually { drained }, "suspended launch continuation drains")
    check(
        ScreenSyncCoordinator.shared.registeredCount == 0,
        "sleep and session suspension prevent queued startup and frame requests from starting playback"
    )
    workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    check(
        ScreenSyncCoordinator.shared.registeredCount == 0,
        "wake during launch suspension does not override an inactive session")
    workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    check(
        desktopWindowCount() == NSScreen.screens.count
            && ScreenSyncCoordinator.shared.registeredCount == NSScreen.screens.count,
        "resuming deferred launch starts one session using the current displays")
}

/// Exercises installation, selection, and persistent menu state using temporary bundles and stores.
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
    let selection = root.appendingPathComponent("selection.plist")
    let app = root.appendingPathComponent("Test App.app")
    try! writeSelectionHelper(at: app)
    let installation = ScreenSaverInstallationController(
        directories: [user, local], appURL: app, recordURL: nil, selectionURL: selection)
    let host = WallpaperApp(
        loginItems: login, defaults: defaults, screenSaverInstallation: installation)
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
    host.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    defer {
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
    guard let status: NSStatusItem = stored("statusItem", in: host), let menu = status.menu,
        let sync = menu.items.first(where: { $0.title == "Install Screen Saver" })
    else {
        check(false, "host installs the screen saver sync menu control")
        return
    }
    check(
        !menu.items.contains { $0.title == "Version Mismatch…" },
        "menu has no companion-version warning")
    check(
        status.button?.accessibilityLabel() == "Matrix Wallpaper",
        "status icon has no version-warning state")
    /// Reopens the menu so external installation and selection changes are rediscovered.
    func refresh() { menu.delegate?.menuWillOpen?(menu) }
    /// Creates a discoverable fixture bundle without installing a real screen saver.
    /// - Returns: The temporary bundle URL used by the selection fixture.
    func install(_ directory: URL, name: String, identifier: String) -> URL {
        let bundle = directory.appendingPathComponent(name)
        let contents = bundle.appendingPathComponent("Contents")
        try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try! PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier],
            format: .xml, options: 0)
        try! data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }
    refresh()
    check(
        !sync.isHidden && sync.title == "Install Screen Saver" && sync.state == .off
            && sync.action == NSSelectorFromString("installScreenSaver:"),
        "missing saver offers an unchecked installation action")
    let unrelated = install(user, name: "Other.saver", identifier: "test.other")
    refresh()
    check(sync.title == "Install Screen Saver", "unrelated saver bundles do not expose sync")
    let installed = install(user, name: "Renamed.saver", identifier: "dev.patsch.MatrixScreenSaver")
    refresh()
    check(
        sync.title == "Set Matrix Screen Saver" && sync.state == .off && sync.isEnabled
            && sync.action == NSSelectorFromString("selectScreenSaver:"),
        "installed but unselected saver offers a direct unchecked selection action")
    check(
        defaults.bool(forKey: "syncWithScreenSaver"),
        "selection action preserves default sync intent")
    try! writeScreenSaverSelection(
        at: root.appendingPathComponent("selected.plist"), saver: installed)
    menu.performActionForItem(at: menu.index(of: sync))
    check(
        !sync.isEnabled && sync.title == "Setting Matrix Screen Saver…",
        "direct selection disables repeat clicks while the helper runs")
    check(
        eventually(10) { sync.title == "Sync with Screen Saver" && sync.isEnabled },
        "successful selection restores the sync menu without reopening it")
    refresh()
    check(
        !sync.isHidden && sync.title == "Sync with Screen Saver" && sync.state == .on
            && sync.action == NSSelectorFromString("toggleScreenSaverSync:"),
        "renamed user installation exposes default-enabled sync")
    menu.performActionForItem(at: menu.index(of: sync))
    check(sync.state == .off, "sync menu action unchecks the persisted preference")
    try! writeScreenSaverSelection(at: selection, saver: nil)
    refresh()
    check(
        sync.title == "Set Matrix Screen Saver" && sync.state == .off,
        "switching to a built-in saver replaces sync with selection")
    check(
        !defaults.bool(forKey: "syncWithScreenSaver"),
        "changing selection preserves explicit sync-off intent")
    try! FileManager.default.removeItem(at: installed)
    refresh()
    check(
        sync.title == "Install Screen Saver" && sync.state == .off,
        "removal offers installation without resetting sync choice")
    let localInstall = install(
        local, name: "Matrix.saver", identifier: "dev.patsch.MatrixScreenSaver")
    try! writeScreenSaverSelection(at: selection, saver: localInstall)
    refresh()
    check(
        !sync.isHidden && sync.state == .off,
        "local installation restores visibility and preserves sync off")
    try! FileManager.default.removeItem(at: localInstall)
    try! Data("invalid plist".utf8).write(
        to: unrelated.appendingPathComponent("Contents/Info.plist"))
    refresh()
    check(sync.title == "Install Screen Saver", "malformed bundle metadata is ignored")
    let target = install(root, name: "Target.saver", identifier: "dev.patsch.MatrixScreenSaver")
    try! FileManager.default.createSymbolicLink(
        at: local.appendingPathComponent("Linked.saver"), withDestinationURL: target)
    try! writeScreenSaverSelection(at: selection, saver: target)
    loginStatus = .enabled
    refresh()
    check(
        !sync.isHidden && login.item.state == .on,
        "menu refresh follows saver symlinks and refreshes Launch at Login")
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    let relaunched = WallpaperApp(
        defaults: UserDefaults(suiteName: suite)!, screenSaverInstallation: installation)
    NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: relaunched, from: nil)
    relaunched.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
    defer {
        relaunched.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification))
    }
    let relaunchedStatus: NSStatusItem? = stored("statusItem", in: relaunched)
    check(
        relaunchedStatus?.menu?.items.first(where: { $0.title == sync.title })?.state == .off,
        "explicit sync off survives host relaunch")
}

/// Checks the shipped artwork rather than duplicating the generator's drawing logic.
private func wallpaperIconTests() {
    let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
    guard let image = NSImage(contentsOf: resources.appendingPathComponent("WallpaperIcon.png")),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        check(false, "app icon preview loads")
        return
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    check(
        bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 1024,
        "app icon has a full-resolution master")
    check(
        bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0
            && bitmap.colorAt(x: 150, y: 512)!.brightnessComponent == 0,
        "app icon has transparent outer corners and a black tile")
    let greens = (300..<700).map { bitmap.colorAt(x: 380, y: $0)!.usingColorSpace(.sRGB)! }
    check(
        greens.contains { $0.greenComponent > 0.7 && $0.greenComponent > $0.redComponent * 2 },
        "app glyph uses saturated rain green")
    check(
        zip(greens, greens.dropFirst()).contains {
            abs($0.greenComponent - $1.greenComponent) > 0.2
        },
        "app glyph includes contrasting scanlines")
    check(
        bitmap.colorAt(x: 300, y: 267)!.usingColorSpace(.sRGB)!.greenComponent > 0.7
            && bitmap.colorAt(x: 350, y: 760)!.usingColorSpace(.sRGB)!.greenComponent > 0.4
            && bitmap.colorAt(x: 700, y: 760)!.usingColorSpace(.sRGB)!.greenComponent < 0.15,
        "app glyph retains the SVG M's stepped shoulder and uneven feet")
    let icon = NSImage(contentsOf: resources.appendingPathComponent("WallpaperIcon.icns"))
    check(
        icon != nil && icon!.representations.count > 1,
        "app icon includes multiple native resolutions")

    guard
        let document = CGPDFDocument(resources.appendingPathComponent("MenuBarIcon.pdf") as CFURL),
        let page = document.page(at: 1),
        let context = CGContext(
            data: nil, width: 72, height: 72, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        check(false, "menu icon loads as vector artwork")
        return
    }
    check(
        page.getBoxRect(.mediaBox).size == CGSize(width: 18, height: 18),
        "menu icon fits the status bar")
    context.scaleBy(x: 4, y: 4)
    context.drawPDFPage(page)
    let menu = NSBitmapImageRep(cgImage: context.makeImage()!)
    let stem = (12..<60).map { menu.colorAt(x: 20, y: $0)! }
    check(
        menu.colorAt(x: 0, y: 0)!.alphaComponent == 0
            && stem.allSatisfy { $0.alphaComponent > 0.9 },
        "menu icon has transparent background and a solid, high-contrast M stem")
    check(
        stem.allSatisfy {
            $0.redComponent == $0.greenComponent && $0.greenComponent == $0.blueComponent
        },
        "menu icon is monochrome for system template tinting")
}

/// Counts visible desktop surfaces without inspecting the host's private storage.
private func desktopWindowCount() -> Int {
    NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.count
}
