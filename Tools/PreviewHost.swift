import AppKit
import ScreenSaver

@main
final class PreviewHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let fallbackPreviewSize = NSSize(width: 1280, height: 800)

    private let bundleURL: URL
    private let smokeTest: Bool
    private var window: NSWindow?
    private var saverView: ScreenSaverView?

    init(arguments: [String]) {
        let bundleArgument = arguments.first ?? "./build/MatrixScreenSaver.saver"
        bundleURL = URL(fileURLWithPath: bundleArgument).standardizedFileURL
        smokeTest = arguments.contains("--smoke-test")
        super.init()
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let host = PreviewHost(arguments: arguments)

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = host
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let saver = try loadSaverView()
            let window = makeWindow(with: saver)

            saver.startAnimation()
            saverView = saver
            self.window = window

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            if smokeTest {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("preview-ok")
                    NSApp.terminate(nil)
                }
            }
        } catch {
            fputs("Preview failed: \(error.localizedDescription)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saverView?.stopAnimation()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private func loadSaverView() throws -> ScreenSaverView {
        let previewSize = largestScreenReferenceSize()
        guard let bundle = Bundle(url: bundleURL) else {
            throw PreviewError.openBundle(bundleURL.path)
        }
        guard bundle.load() else {
            throw PreviewError.loadBundle(bundleURL.path)
        }
        guard let saverType = bundle.principalClass as? ScreenSaverView.Type else {
            throw PreviewError.principalClass
        }
        guard let saver = saverType.init(frame: NSRect(origin: .zero, size: previewSize), isPreview: false) else {
            throw PreviewError.instantiate
        }
        saver.autoresizingMask = [.width, .height]
        return saver
    }

    private func makeWindow(with saver: ScreenSaverView) -> NSWindow {
        let previewSize = largestScreenReferenceSize()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: previewSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MatrixScreenSaver Preview"
        window.center()
        window.delegate = self
        window.contentView = saver
        return window
    }

    private func largestScreenReferenceSize() -> NSSize {
        let screenSizes = NSScreen.screens.map(\.frame.size).filter { $0.width > 20 && $0.height > 20 }
        guard !screenSizes.isEmpty else {
            return Self.fallbackPreviewSize
        }

        let width = screenSizes.reduce(Self.fallbackPreviewSize.width) { max($0, $1.width) }
        let height = screenSizes.reduce(Self.fallbackPreviewSize.height) { max($0, $1.height) }
        return NSSize(width: width, height: height)
    }
}

private enum PreviewError: LocalizedError {
    case openBundle(String)
    case loadBundle(String)
    case principalClass
    case instantiate

    var errorDescription: String? {
        switch self {
        case let .openBundle(path):
            return "Could not open bundle at \(path)."
        case let .loadBundle(path):
            return "Could not load bundle at \(path)."
        case .principalClass:
            return "Bundle principal class is not a ScreenSaverView."
        case .instantiate:
            return "Failed to create the ScreenSaverView instance."
        }
    }
}
