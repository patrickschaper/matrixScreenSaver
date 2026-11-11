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

// Homebrew can write the cleanup agent but cannot bootstrap it from sandboxed cask hooks.
ScreenSaverInstallationController.runLifecycle(action: "activate", appURL: Bundle.main.bundleURL) { result in
    if case .failure(let error) = result {
        NSLog("Could not activate Matrix cleanup: %@", error.localizedDescription)
    }
}

/// Accessory application without a Dock icon or desktop activation.
let app = NSApplication.shared
/// Retains the application delegate for the lifetime of the menu bar host.
let delegate = WallpaperApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
