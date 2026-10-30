import Foundation
import Darwin

/// The drawing state snapshot the view uses to render the current cmd capture frame.
struct CmdCaptureRenderState {
    /// Visible command and output rows, clipped to the scrolling viewport.
    let lines: [String]
    /// Uses the same blink cadence as Neo messages, including while waiting for output.
    let cursorVisible: Bool
}

/// Types a command with trace timing, then presents live output without a typing delay.
struct CmdCaptureScene {
    /// Stages of capture presentation.
    enum Phase: Equatable {
        /// Blinking, typing the command, and pausing before execution.
        case typingCommand
        /// Ready to execute, or waiting for the running command's first output.
        case launching
        /// Appending rows and holding the completed output.
        case presenting
        /// Finished or skipped because the command was empty.
        case done
    }

    /// Default deadline for bounded standalone captures; live scene commands run until exit or cancellation.
    static let captureTimeout: TimeInterval = 12.0
    /// Current presentation stage.
    private(set) var phase: Phase = .done
    /// All captured rows, clipped horizontally but retained for scrolling.
    private(set) var lines: [String] = []
    /// Original shell text; display clipping never changes what executes.
    private(set) var command = ""

    private var startTime: TimeInterval = 0
    private var lastAdvanceTime: TimeInterval = 0
    private var holdStart: TimeInterval?
    private var viewportRows = 1
    private var viewportColumns = 1
    private var charTimings: [TimeInterval] = []
    private var typingEnd: TimeInterval = 0
    private var launchTime: TimeInterval = 0
    private var holdDuration: TimeInterval = 10
    private var visibleCommandCount = 0

    private var displayCommand: String {
        command.components(separatedBy: .newlines).joined(separator: " ")
    }

    /// Projected active duration, available only after the command finishes.
    private(set) var scheduledDuration: TimeInterval?

    /// Resets presentation without launching a command.
    /// Poll the background task's latest snapshot on active animation frames.
    ///
    /// - Parameters:
    ///   - startTime: Reference-relative time the scene begins.
    ///   - command: Command to capture. Empty skips straight to `.done`.
    ///   - speedFactor: General intro typing multiplier, using trace's natural rhythm.
    ///   - seed: Shared content seed for identical command timing across displays.
    ///   - holdDuration: Seconds to retain output after exit; zero advances immediately.
    ///   - size: Available character viewport, excluding renderer margins.
    mutating func reset(startTime: TimeInterval, command: String, speedFactor: Double = 1,
                        seed: UInt64 = 1, holdDuration: TimeInterval = 10,
                        size: TerminalSize = TerminalSize(columns: 80, rows: 24)) {
        self.startTime = startTime
        self.command = command
        self.holdDuration = holdDuration.isFinite && holdDuration >= 0 ? holdDuration : 10
        viewportRows = max(size.rows, 1)
        viewportColumns = max(size.columns, 1)
        var rng = Xorshift64(seed: seed)
        let speed = speedFactor.isFinite && speedFactor > 0 ? speedFactor : 1
        charTimings = NativeMatrixRenderer.naturalTypingTimings(for: displayCommand,
                                                               baseInterval: 1.0 / 40 / speed, rng: &rng)
        typingEnd = 2 + (charTimings.last ?? 0)
        launchTime = typingEnd + Double.random(in: 1...3, using: &rng)
        visibleCommandCount = 0
        lastAdvanceTime = startTime
        holdStart = nil
        lines = []
        scheduledDuration = nil
        phase = command.isEmpty ? .done : .typingCommand
    }

    /// Publishes output immediately in the viewport cleared after command typing.
    ///
    /// - Parameters:
    ///   - output: Captured command output.
    ///   - maxLines: Visible viewport height, clamped to at least one.
    ///   - maxColumns: Maximum characters per row, clamped to at least one.
    ///   - now: Same reference-relative clock used by ``advance(now:)``.
    ///   - isComplete: Whether the shell has exited; only then can the final hold begin.
    mutating func receiveCapture(_ output: String, maxLines: Int, maxColumns: Int, now: TimeInterval,
                                 isComplete: Bool = true) {
        guard phase == .launching || phase == .presenting, holdStart == nil else { return }
        guard !output.isEmpty || isComplete else { return }
        viewportRows = max(maxLines, 1)
        viewportColumns = max(maxColumns, 1)
        var rows = output.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        if rows.last == "" { rows.removeLast() }
        lines = (rows.isEmpty ? ["(no output)"] : rows).map {
            String(String.UnicodeScalarView($0.unicodeScalars.prefix(max(maxColumns, 1))))
        }
        lastAdvanceTime = now
        if isComplete {
            scheduledDuration = max(now - startTime, 0) + holdDuration
            holdStart = now
        }
        phase = .presenting
    }

    /// Excludes a suspended interval without rebuilding the message schedule.
    ///
    /// - Parameter duration: Seconds during which animation was paused.
    mutating func shiftTimeline(by duration: TimeInterval) {
        startTime += duration
        lastAdvanceTime += duration
        if let holdStart { self.holdStart = holdStart + duration }
    }

    /// Advances command typing or the post-exit hold using active elapsed time.
    ///
    /// - Parameter now: Current reference-relative time in seconds.
    mutating func advance(now: TimeInterval) {
        guard phase != .done else { return }
        if phase == .typingCommand {
            let elapsed = now - startTime
            visibleCommandCount = charTimings.prefix(while: { $0 <= elapsed - 2 }).count
            if elapsed >= launchTime { phase = .launching }
        }
        if let holdStart, now >= holdStart + holdDuration { phase = .done }
        lastAdvanceTime = now
    }

    /// Snapshot for the native renderer at the current presentation stage.
    var renderState: CmdCaptureRenderState {
        let elapsed = max(0, lastAdvanceTime - startTime)
        let cursorElapsed = phase == .typingCommand
            ? (elapsed < 2 ? elapsed : elapsed < typingEnd ? elapsed - 2 : elapsed - typingEnd)
            : elapsed
        let cursorVisible = Int(cursorElapsed / NeoMessageScene.cursorBlinkInterval) % 2 == 0
        let commandLine = String(String.UnicodeScalarView(
            displayCommand.prefix(visibleCommandCount).unicodeScalars.prefix(viewportColumns)))
        switch phase {
        case .done:
            return CmdCaptureRenderState(lines: [], cursorVisible: false)
        case .typingCommand:
            return CmdCaptureRenderState(lines: [commandLine], cursorVisible: cursorVisible)
        case .launching:
            return CmdCaptureRenderState(lines: [""], cursorVisible: cursorVisible)
        case .presenting:
            return CmdCaptureRenderState(lines: Array(lines.suffix(viewportRows)), cursorVisible: cursorVisible)
        }
    }
}

/// Single-use synchronous command capture with thread-safe cancellation.
/// Owns a process group so timeout/cancellation also stops ordinary shell pipelines.
/// Commands and captured payloads are never logged; host HOME and sandbox restrictions remain intact.
/// Descendants that deliberately create a new session/process group are outside this group's control.
final class CmdCaptureTask {
    private let lock = NSLock()
    private var cancelled = false
    private var started = false
    private var latestOutput: String?
    private static let byteLimit = 64 * 1024
    private static let extraPathDirectories = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    /// Prevents launch or asks the running capture to stop; safe from any thread.
    /// Running work observes cancellation within its 20 ms poll interval, then cleans up.
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Latest terminal buffer prefix, coalesced under the task lock rather than queued per read.
    /// Poll on active frames so a suspended renderer cannot accumulate delivery callbacks.
    var outputSnapshot: String? {
        lock.lock()
        defer { lock.unlock() }
        return latestOutput
    }

    /// Executes `/bin/sh -c` on the calling background thread, once per task.
    /// Stdout and stderr share a terminal so line-buffered programs publish promptly.
    /// Retains at most 64 KiB while draining excess bytes; cancellation always kills the process group.
    /// Cleanup adds at most 100 ms TERM grace and a one-second exit-event wait;
    /// a kernel-delayed exit is reaped by that event without blocking the caller further.
    ///
    /// - Parameters:
    ///   - command: Shell command, interpreted with the host environment and extended tool PATH.
    ///   - timeout: Finite positive deadline, or `nil` to run until exit or cancellation.
    ///   - size: Character dimensions exposed through COLUMNS, LINES and stdin's terminal size.
    /// - Returns: Combined terminal output, including partial output on timeout. Invalid UTF-8
    ///   uses replacement characters. Empty on cancellation, launch failure, or repeated use.
    func captureOutput(command: String, timeout: TimeInterval? = CmdCaptureScene.captureTimeout,
                       size: TerminalSize = TerminalSize(columns: 80, rows: 24)) -> String {
        guard !command.isEmpty, !command.utf8.contains(0),
              timeout.map({ $0.isFinite && $0 > 0 }) ?? true else { return "" }
        let deadline = timeout.map { ProcessInfo.processInfo.systemUptime + $0 } ?? .infinity
        var master: Int32 = -1
        var slave: Int32 = -1
        var windowSize = winsize(ws_row: UInt16(clamping: max(size.rows, 1)),
                                 ws_col: UInt16(clamping: max(size.columns, 1)), ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else { return "" }
        defer { close(master); if slave >= 0 { close(slave) } }
        // Keep terminal-size ioctls available without waiting for input in an unattended host.
        var inputSettings = termios()
        guard tcgetattr(slave, &inputSettings) == 0 else { return "" }
        inputSettings.c_lflag &= ~tcflag_t(ICANON | ECHO)
        inputSettings.c_oflag &= ~tcflag_t(OPOST)
        withUnsafeMutableBytes(of: &inputSettings.c_cc) {
            $0[Int(VMIN)] = 0
            $0[Int(VTIME)] = 0
        }
        guard tcsetattr(slave, TCSANOW, &inputSettings) == 0 else { return "" }
        guard fcntl(master, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(slave, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(master, F_SETFL, O_NONBLOCK) == 0 else { return "" }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return "" }
        defer { posix_spawn_file_actions_destroy(&actions) }
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return "" }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, slave, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, slave, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, slave, STDERR_FILENO) == 0 else { return "" }

        var environment = ProcessInfo.processInfo.environment
        environment["COLUMNS"] = String(windowSize.ws_col)
        environment["LINES"] = String(windowSize.ws_row)
        let existingPath = environment["PATH"] ?? ""
        let existingComponents = Set(existingPath.split(separator: ":").map(String.init))
        environment["PATH"] = (Self.extraPathDirectories.filter { !existingComponents.contains($0) } + [existingPath])
            .filter { !$0.isEmpty }.joined(separator: ":")
        let arguments = ["/bin/sh", "-c", command].map { $0.withCString { strdup($0) } }
        let variables = environment.map { "\($0.key)=\($0.value)".withCString { strdup($0) } }
        defer { (arguments + variables).forEach { free($0) } }
        var argv = arguments + [nil]
        var envp = variables + [nil]
        var pid: pid_t = 0

        // Serialize the launch boundary with cancel so pre-launch cancellation cannot spawn.
        lock.lock()
        guard !cancelled, !started, ProcessInfo.processInfo.systemUptime < deadline else {
            lock.unlock()
            return ""
        }
        started = true
        let result = posix_spawn(&pid, "/bin/sh", &actions, &attributes, &argv, &envp)
        lock.unlock()
        guard result == 0 else { return "" }

        // Arm before observing exit, but do not reap until the process group has been killed.
        let reaped = DispatchSemaphore(value: 0)
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        exitSource.setEventHandler {
            var status: Int32 = 0
            // An exit event can arrive before the child is waitable; reap on this background queue.
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            exitSource.cancel()
            exitSource.setEventHandler {}
            reaped.signal()
        }
        close(slave)
        slave = -1

        var stdout = Data()
        var outputOpen = true
        var completed = false
        while !isCancelled && ProcessInfo.processInfo.systemUptime < deadline {
            let previousCount = stdout.count
            Self.drain(master, into: &stdout, open: &outputOpen)
            if stdout.count != previousCount {
                let snapshot = String(decoding: stdout, as: UTF8.self)
                lock.lock()
                latestOutput = snapshot
                lock.unlock()
            }
            var info = siginfo_t()
            // Keep the leader unreaped until group cleanup to prevent PID/group-ID reuse.
            let exited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 && info.si_pid == pid
            if exited && !outputOpen {
                completed = true
                break
            }
            var descriptors = [
                pollfd(fd: outputOpen ? master : -1, events: Int16(POLLIN), revents: 0),
            ]
            _ = poll(&descriptors, nfds_t(descriptors.count), 20)
        }

        if !completed {
            kill(-pid, SIGTERM)
            usleep(100_000)
        }
        // Kill remaining descendants even when the leader exited and closed both pipes.
        kill(-pid, SIGKILL)
        exitSource.resume()
        // Kernel-delayed exit must not block the caller; the exit event still reaps it later.
        _ = reaped.wait(timeout: .now() + 1)
        guard !isCancelled else { return "" }
        return String(decoding: stdout, as: UTF8.self)
    }

    /// Drains a bounded batch so a continuously writing child cannot starve cancellation checks.
    ///
    /// - Parameters:
    ///   - fd: Nonblocking read descriptor.
    ///   - data: Retained stream prefix, capped at ``byteLimit`` bytes.
    ///   - open: Cleared on EOF or a permanent read error; descriptor ownership stays with the caller.
    private static func drain(_ fd: Int32, into data: inout Data, open: inout Bool) {
        guard open else { return }
        var buffer = [UInt8](repeating: 0, count: 8192)
        for _ in 0..<8 {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(min(count, byteLimit - data.count)))
            } else {
                if count == 0 || (errno != EAGAIN && errno != EINTR) { open = false }
                return
            }
        }
    }
}
