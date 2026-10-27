import AppKit

/// Exercises menu state and operations without registering real login items.
func loginItemTests() {
    var status = LoginItemController.Status.notRegistered
    var registrationStatus = LoginItemController.Status.enabled
    var registrations = 0
    var removals = 0
    var settingsOpened = false
    var shouldFail = false
    var errors = 0
    let controller = LoginItemController(
        readStatus: { status },
        register: {
            if shouldFail { throw NSError(domain: "LoginItemTests", code: 1) }
            registrations += 1
            status = registrationStatus
        },
        unregister: {
            if shouldFail { throw NSError(domain: "LoginItemTests", code: 2) }
            removals += 1
            status = .notRegistered
        },
        openSettings: { settingsOpened = true },
        reportError: { _ in errors += 1 }
    )
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = controller
    menu.addItem(controller.item)
    controller.menuWillOpen(menu)
    check(controller.item.state == .off && controller.item.isEnabled, "unregistered login item is unchecked")
    menu.performActionForItem(at: 0)
    check(registrations == 1 && controller.item.state == .on, "checking Launch at Login registers and refreshes system state")
    menu.performActionForItem(at: 0)
    check(removals == 1 && controller.item.state == .off, "unchecking Launch at Login unregisters")
    status = .enabled
    controller.menuWillOpen(menu)
    check(controller.item.state == .on, "menu opening reflects login enabled in Settings")
    status = .notRegistered
    controller.menuWillOpen(menu)
    check(controller.item.state == .off, "menu opening reflects login disabled in Settings")
    status = .enabled
    controller.menuWillOpen(menu)
    shouldFail = true
    menu.performActionForItem(at: 0)
    check(errors == 1 && controller.item.state == .on, "failed removal reports error and retains actual enabled state")
    status = .notRegistered
    menu.performActionForItem(at: 0)
    check(errors == 2 && controller.item.state == .off, "failed registration does not show a false checkmark")
    shouldFail = false
    registrationStatus = .requiresApproval
    menu.performActionForItem(at: 0)
    check(registrations == 2 && controller.item.state == .off && settingsOpened,
          "registration requiring approval opens Settings without a false checkmark")
    controller.menuWillOpen(menu)
    check(controller.item.state == .off && controller.item.title.contains("Approval Required"), "pending approval is distinct from enabled")
    settingsOpened = false
    menu.performActionForItem(at: 0)
    check(settingsOpened && removals == 1, "clicking unapproved login startup opens Settings rather than removing it")
    status = .notFound
    controller.menuWillOpen(menu)
    check(controller.item.state == .off && controller.item.isEnabled,
          "not-found login service remains clickable for initial registration")
    shouldFail = true
    menu.performActionForItem(at: 0)
    check(errors == 3 && controller.item.state == .off,
          "failed registration from not-found reports the error without a false checkmark")
    shouldFail = false
    registrationStatus = .enabled
    menu.performActionForItem(at: 0)
    check(registrations == 3 && controller.item.state == .on,
          "clicking a not-found login service attempts registration and enables startup")
    status = .unavailable
    controller.menuWillOpen(menu)
    check(!controller.item.isEnabled, "older macOS disables unsupported login control")

    status = .enabled
    menu.removeAllItems()
    let desktop = DesktopWallpaperFixture()
    let host = WallpaperApp(loginItems: controller, desktopWallpaper: desktop.controller())
    host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    let hostMenu = controller.item.menu!
    status = .notRegistered
    hostMenu.delegate?.menuWillOpen?(hostMenu)
    check(hostMenu.items.filter { $0.target === controller }.count == 1 && controller.item.state == .off,
          "host menu contains exactly one login control and refreshes system status")
    check(eventually { ScreenSyncCoordinator.shared.registeredCount == NSScreen.screens.count },
          "login controls are ready before deferred wallpaper playback starts")
    status = .enabled
    let windows = Set(NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(ObjectIdentifier.init))
    hostMenu.delegate?.menuWillOpen?(hostMenu)
    hostMenu.performActionForItem(at: hostMenu.index(of: controller.item))
    check(Set(NSApp.windows.filter { $0 is DesktopWindow && $0.isVisible }.map(ObjectIdentifier.init)) == windows,
          "changing login startup leaves existing wallpaper playback untouched")
    host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    check(removals == 2, "quitting does not change login registration")
}
