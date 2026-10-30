import AppKit
import ScreenSaver

/// Menu bar host for native Matrix animation behind desktop content.
final class WallpaperApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Retains the status item for the lifetime of the application.
    private var statusItem: NSStatusItem?

    /// Owns login controls independently of wallpaper playback and preferences.
    private let loginItems: LoginItemController

    /// Owns the original desktop images independently of animation windows.
    private let desktopWallpaper: DesktopWallpaperController
    /// Avoids repeating the same alert for every system notification.
    private var lastWallpaperError: String?

    /// Wallpaper-only preferences, separate from shared rendering options.
    private let defaults: UserDefaults
    /// Installed saver locations, replaceable with temporary directories in tests.
    private let screenSaverDirectories: [URL]
    /// Persists user intent even while no saver is installed.
    private static let syncPreferenceKey = "syncWithScreenSaver"
    /// Reflects whether the wallpaper may serve frames to the saver.
    private let syncItem = NSMenuItem(title: "Sync with Screen Saver", action: #selector(toggleScreenSaverSync(_:)), keyEquivalent: "")

    /// Creates the host with system login operations, or an isolated test controller.
    ///
    /// - Parameters:
    ///   - loginItems: Menu controller backed by macOS registration.
    ///   - defaults: Store for wallpaper-only preferences.
    ///   - screenSaverDirectories: User and local installed-saver directories.
    ///   - desktopWallpaper: Durable desktop settings controller, isolated in tests.
    init(loginItems: LoginItemController = LoginItemController(), defaults: UserDefaults = .standard,
         screenSaverDirectories: [URL] = FileManager.default.urls(for: .libraryDirectory, in: [.userDomainMask, .localDomainMask])
            .map { $0.appendingPathComponent("Screen Savers") },
         desktopWallpaper: DesktopWallpaperController = DesktopWallpaperController()) {
        self.loginItems = loginItems
        self.defaults = defaults
        self.screenSaverDirectories = screenSaverDirectories
        self.desktopWallpaper = desktopWallpaper
        super.init()
        defaults.register(defaults: [Self.syncPreferenceKey: true])
    }

    /// Owns the native desktop surfaces until playback ends.
    private var windows: [DesktopWindow] = []

    /// User intent and independent suspension conditions for this session.
    private var playback = WallpaperPlaybackState()

    /// Gates reconciliation until launch has yielded and desktop recovery has completed.
    private var pendingLaunch: DispatchWorkItem?

    /// Prevents queued notifications or menu callbacks from restarting a terminated host.
    private var isTerminating = false

    /// Menu action whose label follows requested playback, not temporary suspension.
    private let playbackItem = NSMenuItem(title: "Stop", action: #selector(togglePlayback(_:)), keyEquivalent: "")

    /// Retains native options UI independently of transient wallpaper views.
    private var optionsController: MatrixScreenSaverOptionsSheetController?

    /// Notification registrations paired with their owning centers for deterministic cleanup.
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// Shared wall-clock pause anchor; duplicate suspension events must not replace it.
    private var suspendedAt: TimeInterval?

    /// Options currently applied to the preserved session.
    private var currentOptions = MatrixScreenSaverOptions()

    private var frameRequests: [UInt32: TimeInterval] = [:]
    private var frameLeaseTimer: Timer?

    /// Captured display geometry distinguishes real topology changes from wake notifications.
    private struct DisplayLayout: Equatable {
        let id: UInt32
        let frame: NSRect
        let scale: CGFloat
    }

    private var displayLayout: [DisplayLayout] = []

    private var currentDisplayLayout: [DisplayLayout] {
        NSScreen.screens.map {
            DisplayLayout(id: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0,
                          frame: $0.frame, scale: $0.backingScaleFactor)
        }.sorted { $0.id < $1.id }
    }

    /// Installs menu controls and observers, then queues desktop recovery and playback on the main run loop.
    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditingMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "M"
        }
        item.button?.toolTip = "Matrix Wallpaper"
        item.button?.setAccessibilityLabel("Matrix Wallpaper")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        playbackItem.target = self
        menu.addItem(playbackItem)
        let options = NSMenuItem(title: "Options…", action: #selector(showOptions(_:)), keyEquivalent: "")
        options.target = self
        menu.addItem(options)
        syncItem.target = self
        menu.addItem(syncItem)
        menu.addItem(.separator())
        menu.addItem(loginItems.item)
        menu.addItem(.separator())
        let coffee = NSMenuItem(title: "Buy me a coffee ☕", action: #selector(openDonationPage(_:)), keyEquivalent: "")
        coffee.target = self
        menu.addItem(coffee)
        let quit = NSMenuItem(title: "Quit Matrix Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        menuWillOpen(menu)

        observeSystemState()
        frameLeaseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let expired = self.frameRequests.filter { now - $0.value >= SharedWallpaperFrame.freshnessInterval }
            guard !expired.isEmpty else { return }
            for id in expired.keys { self.frameRequests.removeValue(forKey: id) }
            for window in self.windows {
                guard let id = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                      expired[id] != nil else { continue }
                (window.contentView as? MatrixScreenSaverView)?.stopSharingWallpaperFrames()
            }
            if self.frameRequests.isEmpty {
                self.endFrameSharing()
                self.reconcilePlayback()
            }
        }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            playback.setSuspended(.sessionInactive, (session[kCGSessionOnConsoleKey as String] as? Bool) == false)
        }
        playback.setSuspended(.displaysSleeping, NSScreen.screens.allSatisfy { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
            return CGDisplayIsAsleep(id) != 0
        })
        let startup = DispatchWorkItem { [weak self] in
            guard let self, !self.isTerminating, self.pendingLaunch != nil else { return }
            if self.playback.isRequested { self.updateDesktopWallpaper(restoring: true) }
            // Recovery alerts can pump the run loop and receive Stop or Quit.
            guard !self.isTerminating, self.pendingLaunch != nil else { return }
            self.pendingLaunch = nil
            self.reconcilePlayback()
        }
        pendingLaunch = startup
        DispatchQueue.main.async(execute: startup)
    }

    /// Provides standard text shortcuts through the focused dialog's responder chain.
    private func installEditingMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem())
        mainMenu.items[0].submenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    /// Refreshes both optional controls when installations or system settings change.
    func menuWillOpen(_ menu: NSMenu) {
        loginItems.menuWillOpen(menu)
        syncItem.state = defaults.bool(forKey: Self.syncPreferenceKey) ? .on : .off
        syncItem.isHidden = !screenSaverDirectories.contains { directory in
            let bundles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return bundles.contains { url in
                guard url.pathExtension.lowercased() == "saver",
                      let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                      let metadata = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                else { return false }
                return metadata["CFBundleIdentifier"] as? String == "dev.patsch.MatrixScreenSaver"
            }
        }
    }

    /// Stores the choice without changing the wallpaper's requested playback state.
    @objc private func toggleScreenSaverSync(_ sender: Any?) {
        let enabled = !defaults.bool(forKey: Self.syncPreferenceKey)
        defaults.set(enabled, forKey: Self.syncPreferenceKey)
        syncItem.state = enabled ? .on : .off
        if !enabled {
            endFrameSharing()
            reconcilePlayback()
        }
    }

    /// Starts or stops at the user's request without overriding system suspension.
    @objc private func togglePlayback(_ sender: Any?) {
        guard !isTerminating else { return }
        pendingLaunch?.cancel()
        pendingLaunch = nil
        if !playback.isRequested { updateDesktopWallpaper(restoring: true) }
        playback.isRequested.toggle()
        reconcilePlayback()
    }

    /// Presents the shared native options window; only this explicit action activates the app.
    @objc private func showOptions(_ sender: Any?) {
        if let optionsController {
            optionsController.configureSheet().makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = MatrixScreenSaverOptionsSheetController { [weak self] options in
            self?.applyOptions(options)
        }
        controller.onClose = { [weak self] in self?.optionsController = nil }
        controller.prepare(using: MatrixScreenSaverView.loadSaverOptions())
        optionsController = controller
        controller.configureSheet().center()
        controller.configureSheet().makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the project's donation page in the default browser.
    @objc private func openDonationPage(_ sender: Any?) {
        if let url = URL(string: "https://www.buymeacoffee.com/yesman82") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Updates ordinary rendering settings in place; grid and scene-cycle changes restart together.
    private func applyOptions(_ options: MatrixScreenSaverOptions) {
        let options = options.sanitized()
        let restart = options.requiresSceneRestart(comparedTo: currentOptions)
        options.save(to: MatrixScreenSaverView.defaults)
        currentOptions = options
        if restart {
            reconcilePlayback(restart: true)
        } else {
            for window in windows { (window.contentView as? MatrixScreenSaverView)?.applyWallpaperOptions(options) }
        }
    }

    /// Rebuilds the whole participating session, never leaving stale scene-barrier members.
    ///
    /// - Parameter restart: Forces coordinated reconstruction after options or display changes.
    private func reconcilePlayback(restart: Bool = false) {
        guard !isTerminating, pendingLaunch == nil else { return }
        playbackItem.title = playback.isRequested ? "Stop" : "Start"
        if !playback.isRequested { updateDesktopWallpaper(restoring: true) }
        if !playback.isRequested || restart { removeDesktopWindows() }
        guard playback.isRequested else { return }
        guard playback.shouldRun else {
            if suspendedAt == nil && !windows.isEmpty {
                suspendedAt = Date.timeIntervalSinceReferenceDate
                for window in windows {
                    (window.contentView as? MatrixScreenSaverView)?.pauseWallpaperAnimation()
                    window.orderOut(nil)
                }
            }
            return
        }
        updateDesktopWallpaper(restoring: false)
        guard !isTerminating, playback.shouldRun else { return }
        if let suspendedAt {
            let duration = Date.timeIntervalSinceReferenceDate - suspendedAt
            ScreenSyncCoordinator.shared.shiftTimeline(by: duration)
            for window in windows {
                (window.contentView as? MatrixScreenSaverView)?.resumeWallpaperAnimation(after: duration)
            }
            self.suspendedAt = nil
        }
        if windows.isEmpty {
            currentOptions = MatrixScreenSaverView.loadSaverOptions()
            displayLayout = currentDisplayLayout
            for screen in NSScreen.screens {
                guard let saver = MatrixScreenSaverView(frame: NSRect(origin: .zero, size: screen.frame.size), isPreview: false) else {
                    let alert = NSAlert()
                    alert.messageText = "Could not start Matrix Wallpaper"
                    alert.informativeText = "The native screen saver view could not be created."
                    alert.runModal()
                    NSApp.terminate(nil)
                    return
                }
                saver.isWallpaperHost = true
                saver.rendersWallpaperWhileHidden = playback.isServingScreenSaver
                let window = DesktopWindow(screen: screen, saverView: saver)
                windows.append(window)
            }
            // Attach every display before starting registration and the framework's animation timers.
            for window in windows {
                if playback.shouldShowDesktop { window.orderBack(nil) }
                (window.contentView as? ScreenSaverView)?.startAnimation()
            }
        }
        for window in windows {
            (window.contentView as? MatrixScreenSaverView)?.rendersWallpaperWhileHidden = playback.isServingScreenSaver
            if playback.shouldShowDesktop {
                if !window.isVisible { window.orderBack(nil) }
            } else if window.isVisible { window.orderOut(nil) }
        }
    }

    /// Changes desktop ownership without coupling it to transient animation windows.
    /// - Parameter restoring: Restores originals instead of acquiring newly connected desktops.
    private func updateDesktopWallpaper(restoring: Bool) {
        do {
            if restoring { try desktopWallpaper.restore() }
            else { try desktopWallpaper.start() }
            lastWallpaperError = nil
        } catch {
            let message = error.localizedDescription
            NSLog("Matrix Wallpaper desktop image: %@", message)
            // Black is cosmetic; keep animation running without hiding restore failures.
            guard restoring else { return }
            guard lastWallpaperError != message else { return }
            lastWallpaperError = message
            let alert = NSAlert()
            alert.messageText = "Could not restore the desktop wallpaper"
            alert.informativeText = "\(message)\nSaved wallpaper settings are kept for retry on Stop or the next launch."
            alert.runModal()
        }
    }

    /// Unregisters every view before closing any window or starting a replacement session.
    private func removeDesktopWindows() {
        endFrameSharing()
        for window in windows { (window.contentView as? ScreenSaverView)?.stopAnimation() }
        for window in windows {
            window.close()
        }
        windows.removeAll()
        suspendedAt = nil
        displayLayout = []
    }

    /// Observes documented workspace state plus best-effort lock/saver distributed signals.
    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (start, end, reason) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, WallpaperPlaybackState.Suspension.sleeping),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, .displaysSleeping),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive),
        ] {
            observeSuspension(in: workspace, start: start, end: end, reason: reason)
        }
        let distributed = DistributedNotificationCenter.default()
        let frameRequests = distributed.addObserver(forName: SharedWallpaperFrame.requestNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let id = notification.object as? String, let displayID = UInt32(id) else { return }
                self?.shareFrames(for: displayID)
            }
        observers.append((distributed, frameRequests))
        // These names are best-effort macOS observations, not a documented lock/security contract.
        observeSuspension(in: distributed, start: Notification.Name("com.apple.screenIsLocked"),
                          end: Notification.Name("com.apple.screenIsUnlocked"), reason: .locked)
        observeSuspension(in: distributed, start: Notification.Name("com.apple.screensaver.didstart"),
                          end: Notification.Name("com.apple.screensaver.didstop"), reason: .screenSaver)
        observe(distributed, name: Notification.Name("com.apple.screensaver.willstart")) { [weak self] in
            self?.setSuspended(.screenSaver, true)
        }
        observe(NotificationCenter.default, name: NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self, self.displayLayout != self.currentDisplayLayout else { return }
            self.reconcilePlayback(restart: true)
        }
    }

    /// Registers a matching pair of notifications for one independent suspension reason.
    private func observeSuspension(in center: NotificationCenter, start: Notification.Name, end: Notification.Name,
                                   reason: WallpaperPlaybackState.Suspension) {
        observe(center, name: start) { [weak self] in self?.setSuspended(reason, true) }
        observe(center, name: end) { [weak self] in self?.setSuspended(reason, false) }
    }

    /// Retains a main-thread notification registration until Quit.
    private func observe(_ center: NotificationCenter, name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    /// Applies a system condition without starting a stopped or still-suspended session.
    private func setSuspended(_ reason: WallpaperPlaybackState.Suspension, _ suspended: Bool) {
        if reason == .screenSaver && !suspended { endFrameSharing() }
        playback.setSuspended(reason, suspended)
        reconcilePlayback()
    }

    /// Wakes the existing session for a matching saver, then offers only that display's pixels.
    ///
    /// - Parameter displayID: Display requested through the sandbox-safe discovery notification.
    private func shareFrames(for displayID: UInt32) {
        guard defaults.bool(forKey: Self.syncPreferenceKey), playback.isRequested,
              currentDisplayLayout.contains(where: { $0.id == displayID }) else { return }
        let starting = !playback.isServingScreenSaver
        if starting {
            let options = MatrixScreenSaverView.loadSaverOptions()
            if options != currentOptions { applyOptions(options) }
        }
        frameRequests[displayID] = ProcessInfo.processInfo.systemUptime
        playback.isServingScreenSaver = true
        if starting { reconcilePlayback() }
        guard playback.shouldRun else { return }
        for window in windows {
            guard let id = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  id == displayID, let saver = window.contentView as? MatrixScreenSaverView,
                  let url = saver.shareWallpaperFrames() else { continue }
            DistributedNotificationCenter.default().postNotificationName(SharedWallpaperFrame.offerNotification,
                object: url.path, userInfo: nil, deliverImmediately: true)
        }
    }

    private func endFrameSharing() {
        frameRequests.removeAll()
        playback.isServingScreenSaver = false
        for window in windows {
            (window.contentView as? MatrixScreenSaverView)?.stopSharingWallpaperFrames()
        }
    }

    /// Removes observers and native animation work before the process exits.
    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        pendingLaunch?.cancel()
        pendingLaunch = nil
        playback.isRequested = false
        frameLeaseTimer?.invalidate()
        frameLeaseTimer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        // Installers request Quit too; a recovery error must not hold termination in a modal loop.
        do { try desktopWallpaper.restore() }
        catch { NSLog("Matrix Wallpaper desktop restore deferred until next launch: %@", error.localizedDescription) }
        removeDesktopWindows()
        optionsController?.configureSheet().close()
        optionsController = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
