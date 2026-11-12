import AppKit
import ServiceManagement

/// Keeps the login menu tied to macOS registration rather than a saved preference.
final class LoginItemController: NSObject, NSMenuDelegate {
    /// System registration states, including availability on older macOS versions.
    enum Status {
        case enabled, notRegistered, requiresApproval, notFound, unavailable
    }

    /// Menu control for adding or removing the main application as a login item.
    let item = NSMenuItem(title: "Launch at Login", action: #selector(toggle), keyEquivalent: "")

    /// Reads the authoritative state each time the menu opens or an operation finishes.
    private let readStatus: () -> Status
    /// Registers the app; injectable so tests cannot change actual login items.
    private let register: () throws -> Void
    /// Removes registration without stopping the current wallpaper session.
    private let unregister: () throws -> Void
    /// Opens the documented Login Items pane.
    private let openSettings: () -> Void
    /// Presents operation errors without changing the displayed system state.
    private let reportError: (Error) -> Void

    /// Creates menu actions with system operations, or substitutes for isolated tests.
    ///
    /// - Parameters:
    ///   - readStatus: Current macOS registration state.
    ///   - register: Operation to enable login startup.
    ///   - unregister: Operation to disable login startup.
    ///   - openSettings: Action for reviewing system approval.
    ///   - reportError: Presentation for failed operations.
    init(
        readStatus: @escaping () -> Status = LoginItemController.systemStatus,
        register: @escaping () throws -> Void = {
            if #available(macOS 13.0, *) { try SMAppService.mainApp.register() }
        },
        unregister: @escaping () throws -> Void = {
            if #available(macOS 13.0, *) { try SMAppService.mainApp.unregister() }
        },
        openSettings: @escaping () -> Void = {
            if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
        },
        reportError: @escaping (Error) -> Void = { error in
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText =
                "\(error.localizedDescription)\nInstall Matrix Wallpaper in Applications and review Login Items Settings."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        self.reportError = reportError
        super.init()
        item.target = self
        refresh()
    }

    /// Refreshes external System Settings changes before showing the menu.
    func menuWillOpen(_ menu: NSMenu) { refresh() }

    /// Displays only the current registration, including unapproved or unsupported states.
    private func refresh() {
        let status = readStatus()
        item.state = status == .enabled ? .on : .off
        item.title =
            status == .requiresApproval ? "Launch at Login — Approval Required" : "Launch at Login"
        item.isEnabled = status != .unavailable
        switch status {
        case .requiresApproval:
            item.toolTip = "Click to approve Matrix Wallpaper in System Settings."
        case .notFound:
            item.toolTip = "Click to register Matrix Wallpaper for launch at login."
        case .unavailable:
            item.toolTip = "Launch at Login requires macOS 13 or later."
        default:
            item.toolTip = nil
        }
    }

    /// Toggles from the latest system state, never from a potentially stale menu tick.
    @objc private func toggle() {
        do {
            switch readStatus() {
            case .enabled: try unregister()
            case .requiresApproval: break
            case .notRegistered, .notFound: try register()
            case .unavailable: return
            }
        } catch {
            if readStatus() != .requiresApproval { reportError(error) }
        }
        refresh()
        if readStatus() == .requiresApproval { openSettings() }
    }

    /// Maps Service Management state without requiring macOS 13 for manual launching.
    static func systemStatus() -> Status {
        guard #available(macOS 13.0, *) else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
}
