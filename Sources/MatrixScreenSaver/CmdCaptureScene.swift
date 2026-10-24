import Foundation
import Darwin

/// The drawing state snapshot the view uses to render the current cmd capture frame.
struct CmdCaptureRenderState {
    let lines: [String]
    let visibleLineCount: Int
    let statusLine: String?
}

/// Time-driven state machine that runs an external command in the background,
/// captures its stdout, and reveals the captured lines a row at a time before
/// handing off to the next scene (the trace program / number intro).
struct CmdCaptureScene {
    enum Phase: Equatable {
        case launching
        case revealing
        case holding
        case done
    }

    static let linesPerSecond: Double = 14.0
    static let holdDuration: TimeInterval = 2.5
    static let captureTimeout: TimeInterval = 12.0
    static let statusLineText = "Querying..."

    private(set) var phase: Phase = .done
    private(set) var visibleLineCount: Int = 0
    private(set) var lines: [String] = []

    private var startTime: TimeInterval = 0
    private var captureElapsed: TimeInterval?
    private var revealEndElapsed: TimeInterval = 0
    private var holdEndElapsed: TimeInterval = 0

    /// Wall-clock duration of the scene once capture completes; `nil` while still launching.
    var scheduledDuration: TimeInterval? {
        captureElapsed == nil ? nil : holdEndElapsed
    }

    /// Resets the scene for a new session. Does not launch anything itself — callers run
    /// `command` (e.g. via ``captureOutput(command:timeout:)`` on a background queue) and
    /// report the result back through ``receiveCapture(_:maxLines:maxColumns:now:)``.
    ///
    /// - Parameters:
    ///   - startTime: Reference-relative wall-clock time the scene begins.
    ///   - command: The command that will be run. Empty skips straight to `.done`.
    mutating func reset(startTime: TimeInterval, command: String) {
        self.startTime = startTime
        lines = []
        visibleLineCount = 0
        captureElapsed = nil
        revealEndElapsed = 0
        holdEndElapsed = 0
        phase = command.isEmpty ? .done : .launching
    }

    /// Records the captured output once the background command finishes.
    /// `now` is the same reference-relative clock used by `advance(now:)`.
    mutating func receiveCapture(_ output: String, maxLines: Int, maxColumns: Int, now: TimeInterval) {
        guard phase == .launching else { return }
        let trimmedLines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0.prefix(max(maxColumns, 1))) }
            .filter { !$0.isEmpty }
        lines = trimmedLines.isEmpty ? ["(no output)"] : Array(trimmedLines.prefix(max(maxLines, 1)))

        let elapsed = max(now - startTime, 0)
        captureElapsed = elapsed
        let revealDuration = Double(lines.count) / Self.linesPerSecond
        revealEndElapsed = elapsed + revealDuration
        holdEndElapsed = revealEndElapsed + Self.holdDuration
        phase = .revealing
    }

    mutating func advance(now: TimeInterval) {
        guard phase != .done else { return }
        guard let captureElapsed else { return } // still launching; waiting on receiveCapture
        let sceneTime = now - startTime

        if sceneTime < captureElapsed {
            visibleLineCount = 0
            phase = .revealing
        } else if sceneTime < revealEndElapsed {
            let revealElapsed = sceneTime - captureElapsed
            visibleLineCount = min(lines.count, Int(revealElapsed * Self.linesPerSecond) + 1)
            phase = .revealing
        } else if sceneTime < holdEndElapsed {
            visibleLineCount = lines.count
            phase = .holding
        } else {
            visibleLineCount = lines.count
            phase = .done
        }
    }

    var renderState: CmdCaptureRenderState {
        switch phase {
        case .done:
            return CmdCaptureRenderState(lines: [], visibleLineCount: 0, statusLine: nil)
        case .launching:
            return CmdCaptureRenderState(lines: [], visibleLineCount: 0, statusLine: Self.statusLineText)
        case .revealing, .holding:
            return CmdCaptureRenderState(lines: lines, visibleLineCount: visibleLineCount, statusLine: nil)
        }
    }

    /// Runs `command` via `/bin/sh -c` on the calling thread (intended to be a background
    /// queue) and returns captured stdout, or an empty string if the command fails, is
    /// missing, or exceeds `timeout`. Reads both pipes concurrently with process execution
    /// to avoid the classic `Process`/`Pipe` deadlock on large output. stderr is always
    /// logged via `NSLog` for diagnostics, and is used as a fallback result when stdout is
    /// empty so a failing command (e.g. a sandboxed screen saver process unable to reach a
    /// tool's usual environment) reads its failure reason on screen instead of just
    /// "(no output)".
    /// Common Homebrew/system binary directories, prepended to `PATH` so commands resolve
    /// the same way they would from an interactive shell. The screen saver host process
    /// (`legacyScreenSaver.appex`) is sandboxed and its inherited `PATH` typically omits
    /// these, so tools like `kubectl` installed under `/usr/local/bin` or
    /// `/opt/homebrew/bin` otherwise fail with "command not found".
    private static let extraPathDirectories = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin",
        "/usr/local/bin", "/usr/local/sbin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    /// The real user home directory, read from the system password database rather than
    /// the `HOME` environment variable. App Sandbox redirects `HOME` for the (sandboxed)
    /// screen saver host process to a container path, which breaks tools that locate their
    /// config relative to home (e.g. `kubectl` looking for `~/.kube/config`).
    private static var realHomeDirectory: String? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return String(cString: dir)
    }

    static func captureOutput(command: String, timeout: TimeInterval = captureTimeout) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        let existingComponents = Set(existingPath.split(separator: ":").map(String.init))
        let mergedPath = (extraPathDirectories.filter { !existingComponents.contains($0) } + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        environment["PATH"] = mergedPath
        if let realHome = realHomeDirectory {
            environment["HOME"] = realHome
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            NSLog("MatrixScreenSaver cmd capture failed to launch '%@': %@", command, error.localizedDescription)
            return ""
        }

        var capturedOutput = Data()
        var capturedError = Data()
        let readQueue = DispatchQueue(label: "dev.patsch.MatrixScreenSaver.cmdCapture.read", attributes: .concurrent)
        let outputDone = DispatchSemaphore(value: 0)
        let errorDone = DispatchSemaphore(value: 0)
        readQueue.async {
            capturedOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputDone.signal()
        }
        readQueue.async {
            capturedError = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorDone.signal()
        }

        let deadline = DispatchTime.now() + timeout
        guard outputDone.wait(timeout: deadline) == .success,
              errorDone.wait(timeout: deadline) == .success else {
            process.terminate()
            NSLog("MatrixScreenSaver cmd capture timed out after %.1fs: '%@'", timeout, command)
            return ""
        }
        process.waitUntilExit()

        let stdout = String(data: capturedOutput, encoding: .utf8) ?? ""
        let stderr = String(data: capturedError, encoding: .utf8) ?? ""
        logCapture(command: command, exitCode: process.terminationStatus, stdout: stdout, stderr: stderr, environment: environment)
        if !stderr.isEmpty {
            NSLog("MatrixScreenSaver cmd capture stderr for '%@' (exit %d): %@", command, process.terminationStatus, stderr)
        }
        if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !stderr.isEmpty {
            return stderr
        }
        return stdout
    }

    /// Appends a full record of a capture attempt (command, exit code, PATH/HOME used,
    /// stdout, stderr) to a plain-text log file under the process's Logs directory.
    /// Exists purely for troubleshooting sandboxed-environment failures (missing PATH
    /// entries, redirected HOME, network restrictions) from outside the sandbox, since the
    /// on-screen output is otherwise the only place this ever surfaces.
    private static func logCapture(command: String, exitCode: Int32, stdout: String, stderr: String, environment: [String: String]) {
        guard let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent("MatrixScreenSaver-cmd-debug.log")

        let entry = """
        ---
        \(Date())
        command: \(command)
        exitCode: \(exitCode)
        PATH: \(environment["PATH"] ?? "")
        HOME: \(environment["HOME"] ?? "")
        stdout (\(stdout.utf8.count) bytes):
        \(stdout)
        stderr (\(stderr.utf8.count) bytes):
        \(stderr)

        """

        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile)
            }
        }
    }
}
