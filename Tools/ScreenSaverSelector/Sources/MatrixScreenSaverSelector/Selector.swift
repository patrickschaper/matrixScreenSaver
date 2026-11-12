import Foundation
import MatrixScreenSaverSelection
import PaperSaverKit

/// Selects Matrix through PaperSaver's verified, backed-up write while preserving desktop choices.
@main
struct MatrixScreenSaverSelector {
    /// Accepts one installed saver path; failures are reported to the menu host over stderr.
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw PaperSaverError.invalidConfiguration(
                    "Expected the installed Matrix screen saver path.")
            }
            let saver = URL(fileURLWithPath: CommandLine.arguments[1])
            let module = try MatrixScreenSaverSelection.moduleName(for: saver)
            try await PaperSaver().setScreensaverEverywhere(module: module)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

}
