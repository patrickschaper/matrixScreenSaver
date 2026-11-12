import Foundation
import PaperSaverKit

/// Validates the host's exact bundle before PaperSaver performs name-based selection.
public enum MatrixScreenSaverSelection {
    /// Checks bundle identity and PaperSaver's name resolution before allowing any settings write.
    ///
    /// PaperSaver 0.4.3 selects traditional savers by name in standard directories. A custom
    /// destination or a shadowed name must use System Settings rather than select another bundle.
    /// - Parameter saver: Exact installed bundle discovered by the host, including renamed bundles.
    /// - Returns: The name PaperSaver resolves to this bundle.
    /// - Throws: An invalid-bundle or unsupported-location error before any settings are changed.
    public static func moduleName(for saver: URL) throws -> String {
        let data = try Data(contentsOf: saver.appendingPathComponent("Contents/Info.plist"))
        let metadata =
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard saver.pathExtension.lowercased() == "saver",
            metadata?["CFBundleIdentifier"] as? String == "dev.patsch.MatrixScreenSaver"
        else {
            throw PaperSaverError.invalidConfiguration(
                "The installed bundle is not Matrix Screen Saver.")
        }
        let name = saver.deletingPathExtension().lastPathComponent
        guard let resolved = SystemPaths.screensaverModuleURL(inStandardDirectories: name),
            resolved.resolvingSymlinksInPath() == saver.resolvingSymlinksInPath()
        else {
            throw PaperSaverError.invalidConfiguration(
                "Select this screen saver in System Settings. Its location cannot be selected automatically."
            )
        }
        return name
    }
}
