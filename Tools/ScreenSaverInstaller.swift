import Darwin
import Foundation

/// Provides the two filesystem operations the shell installer cannot safely express itself.
///
/// `validate-archive ZIP` accepts only the project's regular-file saver payload and metadata.
/// `promote SOURCE DESTINATION` moves a staged bundle without replacing or nesting in a target.
enum ScreenSaverInstaller {
    /// An actionable validation or command-line failure printed by this helper.
    struct Failure: LocalizedError {
        /// Describes why the operation was refused.
        let errorDescription: String?

        /// Creates a failure suitable for displaying in the install alert.
        init(_ message: String) { errorDescription = message }
    }

    /// Reads an archive listing while leaving diagnostic output on the installer's stderr.
    ///
    /// - Parameter arguments: ZipInfo arguments, with the archive path passed as data.
    /// - Returns: UTF-8 listing text after ZipInfo has successfully read the archive.
    /// - Throws: A process or archive error when the listing cannot be trusted.
    static func listing(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw Failure("The bundled screen saver archive could not be read. Reinstall Matrix Wallpaper.")
        }
        return text
    }

    /// Rejects redirects and unexpected entries before the archive is extracted with ditto.
    ///
    /// - Parameter path: The recovery ZIP sealed into the wallpaper app.
    /// - Throws: A validation error for traversal, duplicate, symlink, or non-Unix entries.
    static func validateArchive(at path: String) throws {
        let names = try listing(["-1", path]).split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        let modes = try listing(["-l", path]).split(separator: "\n").filter {
            $0.range(of: "^[bcdlps-][rwxstST-]{9} ", options: .regularExpression) != nil
        }
        guard !names.isEmpty, names.count == modes.count, Set(names).count == names.count else {
            throw Failure("The bundled screen saver archive has an invalid layout.")
        }
        for (name, mode) in zip(names, modes) {
            let trimmed = name.hasSuffix("/") ? name.dropLast() : name[...]
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            guard ["MatrixScreenSaver.saver", "__MACOSX"].contains(parts.first.map(String.init) ?? ""),
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !name.contains("\\"), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  mode.first == "-" || mode.first == "d",
                  mode.split(whereSeparator: { $0.isWhitespace }).dropFirst(2).first == "unx" else {
                throw Failure("The bundled screen saver archive contains an unsafe entry.")
            }
        }
    }

    /// Performs exclusive promotion so an external installer cannot be overwritten by a race.
    ///
    /// - Parameters:
    ///   - source: Validated staged bundle on the destination filesystem.
    ///   - destination: Absent final bundle path; an existing path always causes failure.
    /// - Throws: The filesystem error if promotion fails, including an occupied destination.
    static func promote(_ source: String, to destination: String) throws {
        guard renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination])
        }
    }

    /// Dispatches the internal command contract used by product-lifecycle.sh.
    ///
    /// - Throws: A usage, archive, or filesystem error; callers must leave existing installs intact.
    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "validate-archive" where arguments.count == 2:
            try validateArchive(at: arguments[1])
        case "promote" where arguments.count == 3:
            try promote(arguments[1], to: arguments[2])
        default:
            throw Failure("Usage: MatrixScreenSaverInstaller validate-archive ZIP | promote SOURCE DESTINATION")
        }
    }
}

do {
    try ScreenSaverInstaller.run()
} catch {
    fputs("Matrix installation: \(error.localizedDescription)\n", stderr)
    exit(1)
}
