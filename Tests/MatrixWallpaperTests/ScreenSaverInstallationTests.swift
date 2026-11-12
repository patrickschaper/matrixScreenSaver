import AppKit

/// Exercises recovery state and both UI entry points using only temporary bundles and a fake installer.
func screenSaverInstallationTests() {
    screenSaverSelectionTests()
    screenSaverSelectionOperationTests()
    screenSaverInstallerProcessTests()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .resolvingSymlinksInPath()
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
    let installation = ScreenSaverInstallationController(
        directories: [user], appURL: app, recordURL: record,
        selectionURL: root.appendingPathComponent("selection.plist")
    ) { completion in
        operations += 1
        pending = completion
    }
    var outcome: Result<Void, Error>?
    check(installation.state == .missing, "missing directories report a missing saver")
    installation.install { outcome = $0 }
    installation.install { _ in check(false, "duplicate installation must not complete separately")
    }
    installation.refresh()
    check(
        operations == 1 && installation.state == .installing,
        "busy installation ignores duplicate requests and refresh")
    pending?(.failure(NSError(domain: "fixture", code: 1)))
    check(
        eventually { installation.state == .missing && outcome != nil },
        "failed installation restores retry state")
    outcome = nil
    installation.install { outcome = $0 }
    pending?(.success(()))
    check(eventually { outcome != nil }, "successful process completion returns to main thread")
    if case .failure = outcome {
        check(true, "process success without an installed saver reports a failure")
    } else {
        check(false, "process success without an installed saver reports a failure")
    }

    do {
        try writeInstallationBundle(at: saver)
        let attributes = try FileManager.default.attributesOfItem(atPath: saver.path)
        let marker = URL(fileURLWithPath: saver.path + ".installing")
        let identity =
            "\(attributes[.systemNumber] as! NSNumber):\(attributes[.systemFileNumber] as! NSNumber)"
        try identity.write(to: marker, atomically: true, encoding: .utf8)
        installation.refresh()
        check(installation.state == .missing, "incomplete rollback output does not expose sync")
        outcome = nil
        installation.install { outcome = $0 }
        pending?(.failure(NSError(domain: "fixture", code: 3)))
        check(
            eventually { outcome != nil } && installation.state == .missing,
            "failed recovery with a remaining partial bundle stays available for retry")
        let relaunched = ScreenSaverInstallationController(
            directories: [user], appURL: app, recordURL: record)
        check(
            relaunched.state == .missing, "incomplete recovery remains unavailable after relaunch")
        // Retain the old inode so the replacement cannot accidentally reuse it in this fixture.
        try FileManager.default.moveItem(
            at: saver, to: root.appendingPathComponent("failed-output.saver"))
        try writeInstallationBundle(at: saver)
        installation.refresh()
        check(
            installation.state == .installed,
            "an external replacement is not hidden by a stale recovery marker")
        try FileManager.default.removeItem(at: marker)
        installation.refresh()
        let before = operations
        installation.install { outcome = $0 }
        check(
            installation.state == .installed && operations == before,
            "external install before click avoids launching recovery")
        try FileManager.default.removeItem(at: saver)

        let custom = root.appendingPathComponent("custom/MatrixScreenSaver.saver")
        try writeInstallationBundle(at: custom)
        let metadata: [String: String] = [
            "app": app.path, "saver": custom.path, "owner": "homebrew",
        ]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            .write(to: record)
        installation.refresh()
        check(
            installation.state == .installed,
            "managed custom Homebrew destination counts as installed")
        let otherApp = ScreenSaverInstallationController(
            directories: [], appURL: root.appendingPathComponent("other.app"), recordURL: record)
        check(otherApp.state == .missing, "another app cannot adopt a managed installation record")
        try FileManager.default.removeItem(at: custom)
        installation.refresh()

        defaults.set(false, forKey: "syncWithScreenSaver")
        let host = WallpaperApp(defaults: defaults, screenSaverInstallation: installation)
        // Stop before launch so this UI fixture never starts rendering.
        NSApp.sendAction(NSSelectorFromString("togglePlayback:"), to: host, from: nil)
        host.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            host.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification))
        }
        guard let status: NSStatusItem = stored("statusItem", in: host), let menu = status.menu,
            let item = menu.items.first(where: { $0.title == "Install Screen Saver" })
        else {
            check(false, "missing saver menu action exists")
            return
        }
        NSApp.sendAction(NSSelectorFromString("showOptions:"), to: host, from: nil)
        guard
            let options: MatrixScreenSaverOptionsSheetController = stored(
                "optionsController", in: host),
            let banner: NSStackView = stored("installationBanner", in: options),
            let button: NSButton = stored("installScreenSaverButton", in: options),
            let name: NSTextField = stored("nameField", in: options)
        else {
            check(false, "settings exposes the recovery banner")
            return
        }
        let settingsWindow = options.configureSheet()
        name.stringValue = "Unsaved name"
        check(
            !banner.isHidden && button.isEnabled && button.keyEquivalent.isEmpty,
            "missing saver banner offers a non-default native install button")
        check(
            banner.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains(
                "Screen saver isn’t installed."),
            "banner provides concise missing-saver copy")
        let beforeMenuInstall = operations
        menu.performActionForItem(at: menu.index(of: item))
        check(
            operations == beforeMenuInstall + 1 && !item.isEnabled && !button.isEnabled
                && item.title == "Installing Screen Saver…",
            "menu installation makes both surfaces busy")
        try writeInstallationBundle(at: saver)
        pending?(.success(()))
        check(
            eventually { item.title == "Set Matrix Screen Saver" },
            "verified restoration offers selection before sync")
        check(
            !banner.isHidden && button.title == "Set Matrix Screen Saver" && button.isEnabled
                && item.state == .off && name.stringValue == "Unsaved name",
            "restoration offers selection while preserving sync-off and unsaved edits")
        check(
            stored("windows", in: host, as: [DesktopWindow].self)?.isEmpty == true,
            "restoration does not start a stopped wallpaper")

        try FileManager.default.removeItem(at: saver)
        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification, object: settingsWindow)
        check(
            !banner.isHidden && item.title == "Install Screen Saver"
                && name.stringValue == "Unsaved name",
            "settings refocus detects removal without resetting edits")
        let beforeButtonInstall = operations
        button.performClick(nil)
        check(
            operations == beforeButtonInstall + 1 && !item.isEnabled && !button.isEnabled,
            "banner button uses the shared installation operation")
        settingsWindow.close()
        try writeInstallationBundle(at: saver)
        pending?(.success(()))
        check(
            eventually { item.title == "Set Matrix Screen Saver" },
            "installation completes after settings closes")
        check(
            stored("optionsController", in: host, as: MatrixScreenSaverOptionsSheetController.self)
                == nil && !settingsWindow.isVisible,
            "completion never reopens closed settings")

        try FileManager.default.removeItem(at: saver)
        menu.delegate?.menuWillOpen?(menu)
        menu.performActionForItem(at: menu.index(of: item))
        host.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        pending?(.failure(NSError(domain: "fixture", code: 2)))
        check(
            eventually { installation.state == .missing },
            "transaction completion after Quit is safe")
        check(NSApp.modalWindow == nil, "late failure after Quit does not present an alert")

        let saverOptions = MatrixScreenSaverOptionsSheetController { _ in }
        saverOptions.updateScreenSaverNotice(
            message: "Screen saver isn’t installed.", actionTitle: "Install Screen Saver",
            isEnabled: true)
        check(
            stored("installationBanner", in: saverOptions, as: NSStackView.self)?.isHidden == true,
            "actual screen saver options have no wallpaper recovery banner")
        saverOptions.configureSheet().close()
    } catch { check(false, "installation fixture: \(error)") }
}

/// Verifies current selection from nested macOS plists without modifying system preferences.
private func screenSaverSelectionTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let saver = root.appendingPathComponent("Renamed Matrix.saver")
    let selection = root.appendingPathComponent("selection.plist")
    let controller = ScreenSaverInstallationController(
        directories: [root], recordURL: nil, selectionURL: selection)
    do {
        try writeInstallationBundle(at: saver)
        controller.refresh()
        check(
            controller.state == .installed && !controller.isSelected,
            "installed saver with unreadable selection is not treated as current")
        try writeScreenSaverSelection(at: selection, saver: saver)
        check(
            controller.isSelected,
            "current selection recognizes renamed Matrix bundle and encoded file URL")
        try writeScreenSaverSelection(at: selection, saver: nil)
        check(!controller.isSelected, "built-in selection overrides previously selected Matrix")
        try writeScreenSaverSelection(at: selection, saver: saver, rootKey: "SystemDefault")
        check(
            controller.isSelected,
            "system default selection is used when no all-spaces override exists")
        try writeScreenSaverSelection(at: selection, saver: saver, linked: true)
        check(
            controller.isSelected, "linked wallpaper and screen saver selection recognizes Matrix")
        try Data("invalid plist".utf8).write(to: selection)
        check(!controller.isSelected, "malformed selection store does not expose sync")
        try writeScreenSaverSelection(at: selection, saver: saver)
        try Data("invalid metadata".utf8).write(
            to: saver.appendingPathComponent("Contents/Info.plist"))
        check(!controller.isSelected, "a selected path alone cannot identify a Matrix saver")
    } catch { check(false, "selection fixture: \(error)") }
}

/// Writes a minimal modern selection store using a real nested binary plist configuration.
/// - Parameters:
///   - url: Temporary store destination.
///   - saver: Selected bundle, or `nil` for the built-in Sequoia saver.
///   - rootKey: All-spaces override or system-default settings container.
///   - linked: Whether the desktop and idle screen share one selection.
/// - Throws: A property-list encoding or temporary-file write error.
func writeScreenSaverSelection(
    at url: URL, saver: URL?, rootKey: String = "AllSpacesAndDisplays", linked: Bool = false
) throws {
    let configuration =
        try saver.map {
            try PropertyListSerialization.data(
                fromPropertyList: ["module": ["relative": $0.absoluteString]], format: .binary,
                options: 0)
        } ?? Data()
    let choice: [String: Any] = [
        "Provider": saver == nil
            ? "com.apple.wallpaper.choice.sequoia" : "com.apple.wallpaper.choice.screen-saver",
        "Configuration": configuration,
    ]
    let settings: [String: Any] = [
        "Type": linked ? "linked" : "idle",
        linked ? "Linked" : "Idle": ["Content": ["Choices": [choice]]],
    ]
    try PropertyListSerialization.data(
        fromPropertyList: [rootKey: settings], format: .binary, options: 0
    )
    .write(to: url)
}

/// Exercises the real selector subprocess boundary without changing the user's wallpaper store.
private func screenSaverSelectionOperationTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: root) }
    let saver = root.appendingPathComponent("Renamed Matrix.saver")
    let selection = root.appendingPathComponent("selection.plist")
    let app = root.appendingPathComponent("Test App.app")
    do {
        try writeInstallationBundle(at: saver)
        try writeSelectionHelper(at: app)
        try writeScreenSaverSelection(
            at: root.appendingPathComponent("selected.plist"), saver: saver)
        let controller = ScreenSaverInstallationController(
            directories: [root], appURL: app, recordURL: nil, selectionURL: selection)
        var result: Result<Void, Error>?
        controller.select { result = $0 }
        controller.select { _ in check(false, "duplicate selection must not launch another helper")
        }
        check(controller.isSelecting, "selection returns immediately with a busy state")
        let completed = eventually(10) { result != nil }
        check(completed, "selection completes on the main run loop")
        guard completed else { return }
        if case .success = result {
            check(
                !controller.isSelecting && controller.isSelected,
                "successful helper result refreshes the selected state")
        } else {
            check(false, "selector fixture succeeds")
        }
        let arguments = try String(
            contentsOf: root.appendingPathComponent("arguments"), encoding: .utf8)
        let paths = arguments.split(separator: "\n")
        check(
            paths.count == 1
                && URL(fileURLWithPath: String(paths[0])).resolvingSymlinksInPath()
                    == saver.resolvingSymlinksInPath(),
            "helper receives the exact renamed saver path once, including spaces")
        result = nil
        controller.select { result = $0 }
        check(
            result != nil && !controller.isSelecting, "already selected saver needs no new process")

        try writeScreenSaverSelection(at: selection, saver: nil)
        try Data().write(to: root.appendingPathComponent("fail"))
        result = nil
        controller.select { result = $0 }
        check(eventually(10) { result != nil }, "helper failure returns without blocking the UI")
        if case .failure(let error) = result {
            check(
                !controller.isSelecting && !controller.isSelected
                    && error.localizedDescription.contains("Fixture selection failed"),
                "failed selection clears busy state and retains a useful diagnostic")
        } else {
            check(false, "selector failure is reported")
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent("fail"))
        try writeScreenSaverSelection(at: root.appendingPathComponent("selected.plist"), saver: nil)
        result = nil
        controller.select { result = $0 }
        check(eventually(10) { result != nil }, "unverified helper success completes")
        if case .failure = result {
            check(
                !controller.isSelecting,
                "helper exit zero alone cannot report a successful selection")
        } else {
            check(false, "unchanged selection must report failure")
        }
    } catch { check(false, "selection subprocess fixture: \(error)") }
}

/// Creates a fake bundled selector that only writes adjacent temporary fixture files.
/// - Parameter app: Temporary app bundle whose parent holds selection.plist and selected.plist.
/// - Throws: A fixture directory, executable, or permission write error.
func writeSelectionHelper(at app: URL) throws {
    let executable = app.appendingPathComponent("Contents/MacOS/MatrixScreenSaverSelector")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    #!/bin/bash
    set -eu
    root="$(cd "$(dirname "$0")/../../.." && pwd)"
    [[ $# == 1 ]]
    printf '%s\n' "$1" >> "$root/arguments"
    if [[ -f "$root/fail" ]]; then
      echo 'Fixture selection failed. Open Screen Saver Settings.' >&2
      exit 1
    fi
    /bin/cp "$root/selected.plist" "$root/selection.plist"
    """#.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
}

/// Exercises recovery and activation arguments, bounded failures, and output larger than a pipe buffer.
private func screenSaverInstallerProcessTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("App with spaces.app")
    let resources = app.appendingPathComponent("Contents/Resources/ScreenSaver")
    let savers = root.appendingPathComponent("savers")
    do {
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "dev.patsch.MatrixScreenSaver"],
            format: .xml, options: 0
        ).write(to: resources.appendingPathComponent("fixture.plist"))
        let script = #"""
            #!/bin/bash
            set -eu
            if [[ "$1" == activate && $# == 2 ]]; then
                touch "$2/activated"
                exit 0
            fi
            [[ "$1" == install-saver && $# == 2 ]]
            /usr/bin/head -c 131072 /dev/zero
            if [[ -f "$2/fail" ]]; then
              echo 'Fixture installation failed. Try again.' >&2
              exit 1
            fi
            /bin/mkdir -p "$2/../savers/MatrixScreenSaver.saver/Contents"
            /bin/cp "$2/Contents/Resources/ScreenSaver/fixture.plist" "$2/../savers/MatrixScreenSaver.saver/Contents/Info.plist"
            """#
        try script.write(
            to: resources.appendingPathComponent("product-lifecycle.sh"), atomically: true,
            encoding: .utf8)
        var activation: Result<Void, Error>?
        ScreenSaverInstallationController.runLifecycle(action: "activate", appURL: app) { result in
            DispatchQueue.main.async { activation = result }
        }
        check(
            eventually(10) { activation != nil },
            "cleanup activation finishes without blocking the main thread")
        check(
            FileManager.default.fileExists(atPath: app.appendingPathComponent("activated").path)
                && !FileManager.default.fileExists(atPath: savers.path),
            "startup activation passes the app path without installing a saver")
        let controller = ScreenSaverInstallationController(
            directories: [savers], appURL: app, recordURL: nil)
        var outcome: Result<Void, Error>?
        var onMain = false
        controller.install {
            outcome = $0
            onMain = Thread.isMainThread
        }
        check(
            eventually(10) { outcome != nil },
            "real subprocess drains output larger than a pipe buffer")
        if case .success = outcome {
            check(
                onMain && controller.state == .installed,
                "process arguments preserve spaces and completion returns on the main thread")
        } else {
            check(false, "real fixture subprocess installs successfully")
        }
        try FileManager.default.removeItem(at: savers)
        try Data().write(to: app.appendingPathComponent("fail"))
        outcome = nil
        controller.install {
            outcome = $0
            onMain = Thread.isMainThread
        }
        check(
            eventually(10) { outcome != nil }, "nonzero subprocess returns without blocking the UI")
        if case .failure(let error) = outcome {
            check(
                onMain && controller.state == .missing
                    && error.localizedDescription.utf8.count <= 4096
                    && error.localizedDescription.contains(
                        "Fixture installation failed. Try again."),
                "process failures retain a bounded actionable diagnostic and allow retry")
        } else {
            check(false, "nonzero subprocess reports failure")
        }
    } catch { check(false, "subprocess fixture: \(error)") }
}

/// Creates only the bundle metadata needed for discovery, never a runnable or installed saver.
/// - Parameter url: Destination inside the fixture's temporary directory.
private func writeInstallationBundle(at url: URL) throws {
    let contents = url.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleIdentifier": "dev.patsch.MatrixScreenSaver"], format: .xml,
        options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}
