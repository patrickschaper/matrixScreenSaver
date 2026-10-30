import Foundation
import Darwin

/// Runs unit tests for CmdCaptureScene and name-templated NeoMessageScene lines.
func cmdCaptureSceneTests() {
    // NeoMessageScene lines(forName:)
    let customLines = NeoMessageScene.lines(forName: "Trinity")
    ok(customLines.first == "Wake up, Trinity...", "NeoMessageScene: lines(forName:) uses custom name")
    ok(customLines.last == "Knock, knock, Trinity.", "NeoMessageScene: lines(forName:) uses custom name in closing line")

    let fallbackLines = NeoMessageScene.lines(forName: "")
    ok(fallbackLines.first == "Wake up, Neo...", "NeoMessageScene: empty name falls back to Neo")

    let whitespaceLines = NeoMessageScene.lines(forName: "   \t  ")
    ok(whitespaceLines.first == "Wake up, Neo...", "NeoMessageScene: whitespace name falls back to Neo")

    // Command typing follows trace's initial blink, natural character schedule and final pause.
    var scene = CmdCaptureScene()
    scene.reset(startTime: 100.0, command: "")
    ok(scene.phase == .done, "CmdCaptureScene: empty command resets immediately to done")

    scene.reset(startTime: 100.0, command: "echo hello")
    ok(scene.phase == .typingCommand && scene.renderState.lines == [""],
       "CmdCaptureScene: starts with a blank command and does not allow execution")
    scene.advance(now: 100.55)
    ok(!scene.renderState.cursorVisible, "CmdCaptureScene: initial cursor blinks at the trace cadence")
    scene.advance(now: 101.99)
    ok(scene.renderState.lines == [""] && scene.phase == .typingCommand,
       "CmdCaptureScene: waits for trace's two-second initial blink before typing")
    var rng = Xorshift64(seed: 1)
    let timings = NativeMatrixRenderer.naturalTypingTimings(for: "echo hello", baseInterval: 1.0 / 40, rng: &rng)
    let pause = Double.random(in: 1...3, using: &rng)
    scene.advance(now: 102 + (timings[0] + timings[1]) / 2)
    ok(scene.renderState.lines == ["e"] && scene.phase == .typingCommand,
       "CmdCaptureScene: types command characters using trace's natural schedule")
    var paused = scene
    paused.shiftTimeline(by: 20)
    paused.advance(now: 122 + (timings[0] + timings[1]) / 2)
    ok(paused.renderState.lines == ["e"] && paused.phase == .typingCommand,
       "CmdCaptureScene: suspension preserves command typing without permitting execution")
    scene.advance(now: 102 + timings.last! + pause - 0.01)
    ok(scene.renderState.lines == ["echo hello"] && scene.phase == .typingCommand,
       "CmdCaptureScene: holds the complete command through trace's final pause")
    scene.advance(now: 102 + timings.last! + pause + 0.01)
    ok(scene.phase == .launching && scene.scheduledDuration == nil,
       "CmdCaptureScene: permits execution only after typing and the final pause")
    ok(scene.renderState.lines == [""],
       "CmdCaptureScene: removes the command after its final pause while waiting for output")
    var fast = CmdCaptureScene()
    fast.reset(startTime: 100, command: "echo hello", speedFactor: 10)
    fast.advance(now: 102 + timings.last! + pause - 0.01)
    ok(fast.phase == .launching, "CmdCaptureScene: general typing speed accelerates the command")

    scene.receiveCapture("abcdef\n\nsecond\nthird\n", maxLines: 2, maxColumns: 3, now: 110)
    ok(scene.lines == ["abc", "", "sec", "thi"],
       "CmdCaptureScene: clips width, preserves blank rows and retains output beyond screen height")
    ok(scene.renderState.lines == ["sec", "thi"], "CmdCaptureScene: captured output appears immediately, clipped and scrolled")
    scene.advance(now: 119.99)
    ok(scene.phase == .presenting, "CmdCaptureScene: output remains visible for ten seconds after exit by default")
    scene.shiftTimeline(by: 20)
    scene.advance(now: 139.99)
    ok(scene.phase == .presenting && scene.renderState.lines == ["sec", "thi"],
       "CmdCaptureScene: suspension preserves completed output and its remaining hold")
    scene.advance(now: 140)
    ok(scene.phase == .done && scene.renderState.lines.isEmpty, "CmdCaptureScene: finishes after final hold")
    scene.reset(startTime: 100, command: "next", holdDuration: 0)
    ok(scene.renderState.lines == [""] && scene.lines.isEmpty, "CmdCaptureScene: new command clears prior output")
    scene.advance(now: 200)
    scene.receiveCapture("ready", maxLines: 2, maxColumns: 20, now: 201)
    scene.advance(now: 201)
    ok(scene.phase == .done, "CmdCaptureScene: zero hold advances immediately after exit")

    var emptyOutputScene = CmdCaptureScene()
    emptyOutputScene.reset(startTime: 100.0, command: "true")
    emptyOutputScene.advance(now: 200)
    emptyOutputScene.receiveCapture("", maxLines: 10, maxColumns: 50, now: 201)
    ok(emptyOutputScene.lines == ["(no output)"], "CmdCaptureScene: empty output falls back to placeholder")

    var live = CmdCaptureScene()
    live.reset(startTime: 100, command: "stream", holdDuration: 3)
    live.advance(now: 200)
    live.receiveCapture("one\n", maxLines: 2, maxColumns: 20, now: 201, isComplete: false)
    live.advance(now: 220)
    ok(live.phase == .presenting && live.renderState.lines == ["one"] && live.scheduledDuration == nil,
       "CmdCaptureScene: only output remains visible while an idle command is running")
    live.receiveCapture("one\ntwo\n", maxLines: 2, maxColumns: 20, now: 221, isComplete: false)
    ok(live.renderState.lines == ["one", "two"], "CmdCaptureScene: later output appends immediately without a command row")
    live.receiveCapture("one\ntwo\n", maxLines: 2, maxColumns: 20, now: 230)
    live.advance(now: 232.99)
    ok(live.phase == .presenting, "CmdCaptureScene: final hold starts at command exit, not first output")
    live.advance(now: 233)
    ok(live.phase == .done, "CmdCaptureScene: completes only after exit and final hold")
    live.reset(startTime: 100, command: "partial stream")
    live.advance(now: 200)
    live.receiveCapture("a", maxLines: 2, maxColumns: 20, now: 201, isComplete: false)
    live.receiveCapture("ab", maxLines: 2, maxColumns: 20, now: 211, isComplete: false)
    ok(live.renderState.lines.last == "ab", "CmdCaptureScene: partial-line updates appear immediately without a typing delay")
    live.reset(startTime: 100, command: "cursor")
    live.advance(now: 200)
    live.receiveCapture("a\nb\nc", maxLines: 2, maxColumns: 20, now: 201.1, isComplete: false)
    ok(live.renderState.lines == ["b", "c"] && live.renderState.cursorVisible,
       "CmdCaptureScene: scrolling output retains its blinking cursor")
    live.shiftTimeline(by: 20)
    live.advance(now: 221.1)
    ok(live.renderState.cursorVisible, "CmdCaptureScene: suspension preserves the cursor blink phase")
    live.advance(now: 221.6)
    ok(!live.renderState.cursorVisible, "CmdCaptureScene: output cursor continues blinking while the command is idle")
    live.receiveCapture("a\nb\nc", maxLines: 2, maxColumns: 20, now: 222)
    live.advance(now: 232)
    ok(!live.renderState.cursorVisible, "CmdCaptureScene: completion removes the cursor")

    cmdCaptureTaskTests()
}

/// Exercises only authored commands, with all side effects confined to a fresh temporary directory.
func cmdCaptureTaskTests() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("matrix-capture-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        ok(false, "CmdCaptureTask: creates temporary sandbox")
        return
    }
    defer { try? FileManager.default.removeItem(at: directory) }
    let marker = directory.appendingPathComponent("marker").path
    let ready = directory.appendingPathComponent("ready").path
    let late = directory.appendingPathComponent("late").path
    ok(CmdCaptureTask().captureOutput(command: "printf bad > '\(marker)'\0ignored").isEmpty && !FileManager.default.fileExists(atPath: marker),
       "CmdCaptureTask: embedded NUL cannot execute a truncated command")

    ok(CmdCaptureTask().captureOutput(command: "printf 'hello\\n'; printf 'diagnostic' >&2") == "hello\ndiagnostic", "CmdCaptureTask: stdout and stderr appear together in terminal order")
    ok(CmdCaptureTask().captureOutput(command: "printf '  '; printf 'diagnostic' >&2; exit 1") == "  diagnostic", "CmdCaptureTask: diagnostic output survives nonzero exit")
    ok(CmdCaptureTask().captureOutput(command: "printf '%s' \"$HOME\"") == (ProcessInfo.processInfo.environment["HOME"] ?? ""), "CmdCaptureTask: inherits host HOME")
    let dimensions = CmdCaptureTask().captureOutput(command: "printf '%s %s ' \"$COLUMNS\" \"$LINES\"; stty size",
                                                    size: TerminalSize(columns: 37, rows: 9))
    ok(dimensions == "37 9 9 37\n", "CmdCaptureTask: shell environment and native terminal report the viewport dimensions")
    ok(CmdCaptureTask().captureOutput(command: "printf before; /bin/cat; printf after", timeout: 1) == "beforeafter",
        "CmdCaptureTask: size-aware stdin returns EOF instead of blocking unattended readers")
    ok(CmdCaptureTask().captureOutput(command: "test -t 1 && test -t 2 && printf terminal") == "terminal",
       "CmdCaptureTask: both output streams are terminals so line-buffered programs flush promptly")
    let ping = CmdCaptureTask()
    let pingFinished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        _ = ping.captureOutput(command: "/sbin/ping -c 14 127.0.0.1", timeout: nil)
        pingFinished.signal()
    }
    let pingDeadline = ProcessInfo.processInfo.systemUptime + 1.5
    while ping.outputSnapshot?.contains("icmp_seq=0") != true && ProcessInfo.processInfo.systemUptime < pingDeadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    ok(ping.outputSnapshot?.contains("icmp_seq=0") == true && pingFinished.wait(timeout: .now()) == .timedOut,
       "CmdCaptureTask: real ping replies are observable before ping exits")
    ok(pingFinished.wait(timeout: .now() + 16) == .success && ping.outputSnapshot?.contains("14 packets transmitted") == true,
       "CmdCaptureTask: live ping runs beyond the former twelve-second limit and finishes with statistics")
    ok(CmdCaptureTask().captureOutput(command: "printf partial; sleep 2", timeout: 0.1) == "partial",
       "CmdCaptureTask: a bounded capture preserves partial output on timeout")

    let reusable = CmdCaptureTask()
    _ = reusable.captureOutput(command: "true")
    ok(reusable.captureOutput(command: "printf bad > '\(marker)'").isEmpty && !FileManager.default.fileExists(atPath: marker), "CmdCaptureTask: repeated execution cannot spawn")
    ok(CmdCaptureTask().captureOutput(command: "printf bad > '\(marker)'", timeout: .nan).isEmpty && !FileManager.default.fileExists(atPath: marker), "CmdCaptureTask: invalid timeout cannot spawn")

    let descriptorsBefore = (0..<256).filter { fcntl(Int32($0), F_GETFD) >= 0 }.count
    for _ in 0..<5 { _ = CmdCaptureTask().captureOutput(command: "printf checked") }
    let descriptorsAfter = (0..<256).filter { fcntl(Int32($0), F_GETFD) >= 0 }.count
    ok(descriptorsBefore == descriptorsAfter, "CmdCaptureTask: repeated captures close pipe descriptors")

    let flood = "(/usr/bin/head -c 262144 /dev/zero | /usr/bin/tr '\\000' x) & /usr/bin/head -c 262144 /dev/zero | /usr/bin/tr '\\000' e >&2; wait"
    let large = CmdCaptureTask().captureOutput(command: flood, timeout: 3)
    ok(large.utf8.count == 65536 && large.allSatisfy { $0 == "x" || $0 == "e" }, "CmdCaptureTask: drains simultaneous streams with bounded combined output")
    let largeError = CmdCaptureTask().captureOutput(command: "/usr/bin/head -c 262144 /dev/zero | /usr/bin/tr '\\000' e >&2", timeout: 3)
    ok(largeError.utf8.count == 65536, "CmdCaptureTask: stderr retention is bounded too")
    let unicodeBoundary = CmdCaptureTask().captureOutput(
        command: "/usr/bin/head -c 65535 /dev/zero | /usr/bin/tr '\\000' x; printf '\\303\\251'", timeout: 3)
    ok(unicodeBoundary.hasPrefix(String(repeating: "x", count: 65535)),
       "CmdCaptureTask: a UTF-8 sequence crossing the byte cap does not discard the valid prefix")

    let start = ProcessInfo.processInfo.systemUptime
    let timedOut = CmdCaptureTask().captureOutput(command: "exec 1>&- 2>&-; /bin/sleep 5", timeout: 0.1)
    ok(timedOut.isEmpty && ProcessInfo.processInfo.systemUptime - start < 1.5, "CmdCaptureTask: early EOF does not bypass timeout")

    let cancelled = CmdCaptureTask()
    cancelled.cancel()
    ok(cancelled.captureOutput(command: "printf bad > '\(marker)'").isEmpty && !FileManager.default.fileExists(atPath: marker), "CmdCaptureTask: cancellation before launch prevents side effects")

    let command = "trap '' TERM; (trap '' TERM; printf '%s' $$ > '\(ready)'; /bin/sleep 0.7; printf escaped > '\(late)') | /bin/cat; wait"
    // Repeat because process-exit notification can precede waitpid readiness on macOS.
    for _ in 0..<20 {
        try? FileManager.default.removeItem(atPath: ready)
        let running = CmdCaptureTask()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = running.captureOutput(command: command, timeout: 3)
            finished.signal()
        }
        let readyDeadline = ProcessInfo.processInfo.systemUptime + 2
        var pid: Int32 = 0
        repeat {
            let pidText = (try? String(contentsOfFile: ready, encoding: .utf8)) ?? ""
            pid = Int32(pidText) ?? 0
            if pid > 0 { break }
            Thread.sleep(forTimeInterval: 0.01)
        } while ProcessInfo.processInfo.systemUptime < readyDeadline
        ok(pid > 0, "CmdCaptureTask: descendant pipeline starts")
        running.cancel()
        ok(finished.wait(timeout: .now() + 1.5) == .success, "CmdCaptureTask: cancellation of TERM-refusing pipeline is bounded")
        ok(pid > 0 && kill(pid, 0) == -1 && errno == ESRCH, "CmdCaptureTask: cancelled shell is reaped")
    }
    Thread.sleep(forTimeInterval: 0.8)
    ok(!FileManager.default.fileExists(atPath: late), "CmdCaptureTask: cancelled descendants cannot write later")

    let timeoutStart = ProcessInfo.processInfo.systemUptime
    _ = CmdCaptureTask().captureOutput(command: command, timeout: 0.1)
    ok(ProcessInfo.processInfo.systemUptime - timeoutStart < 1.5, "CmdCaptureTask: TERM-refusing pipeline timeout is bounded")
    Thread.sleep(forTimeInterval: 0.8)
    ok(!FileManager.default.fileExists(atPath: late), "CmdCaptureTask: timed-out descendants cannot write later")
}
