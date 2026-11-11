import AppKit
import ServiceManagement

// The uninstaller must unregister while the original app bundle still exists.
if CommandLine.arguments.contains("--unregister-login-item") {
    do {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval: try SMAppService.mainApp.unregister()
            default: break
            }
        }
        exit(0)
    } catch {
        fputs("Could not unregister Matrix Wallpaper: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

/// Accessory application without a Dock icon or desktop activation.
let app = NSApplication.shared
/// Retains the application delegate for the lifetime of the menu bar host.
let delegate = WallpaperApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
