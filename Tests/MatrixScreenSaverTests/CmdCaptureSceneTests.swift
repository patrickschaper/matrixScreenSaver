import Foundation

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

    // CmdCaptureScene
    var scene = CmdCaptureScene()
    scene.reset(startTime: 100.0, command: "")
    ok(scene.phase == .done, "CmdCaptureScene: empty command resets immediately to done")

    scene.reset(startTime: 100.0, command: "echo hello")
    ok(scene.phase == .launching, "CmdCaptureScene: command resets to launching phase")
    ok(scene.scheduledDuration == nil, "CmdCaptureScene: scheduledDuration is nil while launching")

    scene.receiveCapture("line 1\nline 2\nline 3\n", maxLines: 2, maxColumns: 50, now: 101.0)
    ok(scene.phase == .revealing, "CmdCaptureScene: receiveCapture transitions to revealing phase")
    ok(scene.lines.count == 2, "CmdCaptureScene: receiveCapture caps lines to maxLines")
    ok(scene.lines == ["line 1", "line 2"], "CmdCaptureScene: receiveCapture parses output correctly")
    ok(scene.scheduledDuration != nil, "CmdCaptureScene: scheduledDuration is populated after capture")

    var emptyOutputScene = CmdCaptureScene()
    emptyOutputScene.reset(startTime: 100.0, command: "true")
    emptyOutputScene.receiveCapture("", maxLines: 10, maxColumns: 50, now: 101.0)
    ok(emptyOutputScene.lines == ["(no output)"], "CmdCaptureScene: empty output falls back to placeholder")

    // Advance past reveal and hold
    let totalDuration = scene.scheduledDuration ?? 0
    scene.advance(now: 100.0 + totalDuration + 1.0)
    ok(scene.phase == .done, "CmdCaptureScene: advance past hold duration transitions to done")
}
