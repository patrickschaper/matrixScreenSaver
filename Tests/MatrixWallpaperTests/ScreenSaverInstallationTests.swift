import AppKit

/// Exercises recovery state and both UI entry points using only temporary bundles and a fake installer.
func screenSaverInstallationTests() {
    screenSaverInstallerProcessTests()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    let user = root.appendingPathComponent("savers")
    let app = root.appendingPathComponent("Matrix Wallpaper.app")
    let record = root.appendingPathComponent("installation.plist")
    let saver = user.appendingPathComponent("MatrixScreenSaver.saver")
    let suite = "MatrixSaverInstallationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    var operations = 0
    var pending: ((Result<Void, Error>) -> Void)?
    let installation = ScreenSaverInstallationController(directories: [user], appURL: app, recordURL: record) { completion in
        operations += 1
        pending = completion
    }
    var outcome: Result<Void, Error>?
    check(installation.state == .missing, "missing directories report a missing saver")
    installation.install { outcome = $0 }
    installation.install { _ in check(false, "duplicate installation must not complete separately") }
    installation.refresh()
    check(operations == 1 && installation.state == .installing, "busy installation ignores duplicate requests and refresh")
    pending?(.failure(NSError(domain: "fixture", code: 1)))
    check(eventually { installation.state == .missing && outcome != nil }, "failed installation restores retry state")
    outcome = nil
    installation.install { outcome = $0 }
    pending?(.success(()))
    check(eventually { outcome != nil }, "successful process completion returns to main thread")
    if case .failure = outcome { check(true, "process success without an installed saver reports a failure") }
    else { check(false, "process success without an installed saver reports a failure") }

    do {
        try writeInstallationBundle(at: saver)
        let attributes = try FileManager.default.attributesOfItem(atPath: saver.path)
        let marker = URL(fileURLWithPath: saver.path + ".installing")
        let identity = "\(attributes[.systemNumber] as! NSNumber):\(attributes[.systemFileNumber] as! NSNumber)"
        try identity.write(to: marker, atomically: true, encoding: .utf8)
        installation.refresh()
        check(installation.state == .missing, "incomplete rollback output does not expose sync")
        outcome = nil
        installation.install { outcome = $0 }
        pending?(.failure(NSError(domain: "fixture", code: 3)))
        check(eventually { outcome != nil } && installation.state == .missing,
              "failed recovery with a remaining partial bundle stays available for retry")
        let relaunched = ScreenSaverInstallationController(directories: [user], appURL: app, recordURL: record)
        check(relaunched.state == .missing, "incomplete recovery remains unavailable after relaunch")
        // Retain the old inode so the replacement cannot accidentally reuse it in this fixture.
        try FileManager.default.moveItem(at: saver, to: root.appendingPathComponent("failed-output.saver"))
        try writeInstallationBundle(at: saver)
        installation.refresh()
        check(installation.state == .installed, "an external replacement is not hidden by a stale recovery marker")
        try FileManager.default.removeItem(at: marker)
        installation.refresh()
        let before = operations
        installation.install { outcome = $0 }
        check(installation.state == .installed && operations == before, "external install before click avoids launching recovery")
        try FileManager.default.removeItem(at: saver)

        let custom = root.appendingPathComponent("custom/MatrixScreenSaver.saver")
        try writeInstallationBundle(at: custom)
        let metadata: [String: String] = ["app": app.path, "saver": custom.path, "owner": "homebrew"]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: record)
        installation.refresh()
        check(installation.state == .installed, "managed custom Homebrew destination counts as installed")
        let otherApp = ScreenSaverInstallationController(directories: [], appURL: root.appendingPathComponent("other.app"), recordURL: record)
        check(otherApp.state == .missing, "another app cannot adopt a managed installation record")
        try FileManager.default.removeItem(at: custom)
        installation.refresh()

        let desktop = DesktopWallpaperFixture()
        defaults.set(false, forKey: "syncWithScreenSaver")
        let host = WallpaperApp(defaults: defaults, desktopWallpaper: desktop.controller(), screenSaverInstallation: installation)
        // Stop before launch so this UI fixture never changes desktop images or starts rendering.
        NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
        host.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer { host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        guard let status: NSStatusItem = stored("statusItem", in: host), let menu = status.menu,
              let item = menu.items.first(where: { $0.title == "Install Screen Saver" }) else {
            check(false, "missing saver menu action exists"); return
        }
        NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
        guard let options: MatrixScreenSaverOptionsSheetController = stored("optionsController", in: host),
              let banner: NSStackView = stored("installationBanner", in: options),
              let button: NSButton = stored("installScreenSaverButton", in: options),
              let name: NSTextField = stored("nameField", in: options) else {
            check(false, "settings exposes the recovery banner"); return
        }
        let settingsWindow = options.configureSheet()
        name.stringValue = "Unsaved name"
        check(!banner.isHidden && button.isEnabled && button.keyEquivalent.isEmpty,
              "missing saver banner offers a non-default native install button")
        check(banner.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains("Screen saver isn’t installed."),
              "banner provides concise missing-saver copy")
        let beforeMenuInstall = operations
        menu.performActionForItem(at: menu.index(of: item))
        check(operations == beforeMenuInstall + 1 && !item.isEnabled && !button.isEnabled &&
              item.title == "Installing Screen Saver…", "menu installation makes both surfaces busy")
        try writeInstallationBundle(at: saver)
        pending?(.success(()))
        check(eventually { item.title == "Sync with Screen Saver" }, "verified restoration restores sync action")
        check(banner.isHidden && item.state == .off && name.stringValue == "Unsaved name",
              "restoration preserves sync-off and unsaved edits while hiding the banner")
        check(stored("windows", in: host, as: [DesktopWindow].self)?.isEmpty == true,
              "restoration does not start a stopped wallpaper")

        try FileManager.default.removeItem(at: saver)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: settingsWindow)
        check(!banner.isHidden && item.title == "Install Screen Saver" && name.stringValue == "Unsaved name",
              "settings refocus detects removal without resetting edits")
        let beforeButtonInstall = operations
        button.performClick(nil)
        check(operations == beforeButtonInstall + 1 && !item.isEnabled && !button.isEnabled,
              "banner button uses the shared installation operation")
        settingsWindow.close()
        try writeInstallationBundle(at: saver)
        pending?(.success(()))
        check(eventually { item.title == "Sync with Screen Saver" }, "installation completes after settings closes")
        check(stored("optionsController", in: host, as: MatrixScreenSaverOptionsSheetController.self) == nil && !settingsWindow.isVisible,
              "completion never reopens closed settings")

        try FileManager.default.removeItem(at: saver)
        menu.delegate?.menuWillOpen?(menu)
        menu.performActionForItem(at: menu.index(of: item))
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        pending?(.failure(NSError(domain: "fixture", code: 2)))
        check(eventually { installation.state == .missing }, "transaction completion after Quit is safe")
        check(NSApp.modalWindow == nil, "late failure after Quit does not present an alert")

        let saverOptions = MatrixScreenSaverOptionsSheetController { _ in }
        saverOptions.updateScreenSaverInstallation(isMissing: true, isInstalling: false)
        check(stored("installationBanner", in: saverOptions, as: NSStackView.self)?.isHidden == true,
              "actual screen saver options have no wallpaper recovery banner")
        saverOptions.configureSheet().close()
    } catch { check(false, "installation fixture: \(error)") }
}

/// Exercises the production subprocess boundary with a temporary script and output larger than a pipe buffer.
private func screenSaverInstallerProcessTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("App with spaces.app")
    let resources = app.appendingPathComponent("Contents/Resources/ScreenSaver")
    let savers = root.appendingPathComponent("savers")
    do {
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.patsch.MatrixScreenSaver"],
                                           format: .xml, options: 0).write(to: resources.appendingPathComponent("fixture.plist"))
        let script = #"""
        #!/bin/bash
        set -eu
        [[ "$1" == install-saver && $# == 2 ]]
        /usr/bin/head -c 131072 /dev/zero
        if [[ -f "$2/fail" ]]; then
          echo 'Fixture installation failed. Try again.' >&2
          exit 1
        fi
        /bin/mkdir -p "$2/../savers/MatrixScreenSaver.saver/Contents"
        /bin/cp "$2/Contents/Resources/ScreenSaver/fixture.plist" "$2/../savers/MatrixScreenSaver.saver/Contents/Info.plist"
        """#
        try script.write(to: resources.appendingPathComponent("product-lifecycle.sh"), atomically: true, encoding: .utf8)
        let controller = ScreenSaverInstallationController(directories: [savers], appURL: app, recordURL: nil)
        var outcome: Result<Void, Error>?
        var onMain = false
        controller.install { outcome = $0; onMain = Thread.isMainThread }
        check(eventually(10) { outcome != nil }, "real subprocess drains output larger than a pipe buffer")
        if case .success = outcome {
            check(onMain && controller.state == .installed, "process arguments preserve spaces and completion returns on the main thread")
        } else { check(false, "real fixture subprocess installs successfully") }
        try FileManager.default.removeItem(at: savers)
        try Data().write(to: app.appendingPathComponent("fail"))
        outcome = nil
        controller.install { outcome = $0; onMain = Thread.isMainThread }
        check(eventually(10) { outcome != nil }, "nonzero subprocess returns without blocking the UI")
        if case .failure(let error) = outcome {
            check(onMain && controller.state == .missing && error.localizedDescription.utf8.count <= 4096 &&
                  error.localizedDescription.contains("Fixture installation failed. Try again."),
                  "process failures retain a bounded actionable diagnostic and allow retry")
        } else { check(false, "nonzero subprocess reports failure") }
    } catch { check(false, "subprocess fixture: \(error)") }
}

/// Creates only the bundle metadata needed for discovery, never a runnable or installed saver.
/// - Parameter url: Destination inside the fixture's temporary directory.
private func writeInstallationBundle(at url: URL) throws {
    let contents = url.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.patsch.MatrixScreenSaver"], format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}
