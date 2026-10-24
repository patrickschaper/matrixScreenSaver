import AppKit

/// Reads existing state without adding production-only test hooks.
func stored<Value>(_ name: String, in object: Any, as type: Value.Type = Value.self) -> Value? {
    guard let value = Mirror(reflecting: object).children.first(where: { $0.label == name })?.value else { return nil }
    return value as? Value
}

/// Waits for an observed transition with a bounded run-loop deadline.
func eventually(_ seconds: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: seconds)
    repeat {
        if condition() { return true }
        wait(0.02)
    } while Date() < deadline
    return condition()
}

/// Exercises production host detection, discovery, and the real consumer view.
func consumerHostTests() {
    check(ProcessInfo.processInfo.processName == "ScreenSaverEngine", "helper uses the production saver process name")
    // An unattached-to-window canvas uses display 0, isolating discovery from live wallpaper displays.
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 437, height: 293))
    let view = MatrixScreenSaverView(frame: container.bounds, isPreview: false)!
    container.addSubview(view)
    view.startAnimation()
    defer { view.stopAnimation(); view.removeFromSuperview() }
    guard let renderer: NativeMatrixRenderer = stored("nativeRenderer", in: view) else {
        check(false, "consumer renderer is observable")
        return
    }
    check(stored("wallpaperFrameReader", in: view, as: WallpaperFrameReader?.self) != nil,
          "real saver view enters wallpaper discovery")
    check(eventually { view.animateOneFrame(); return ScreenSyncCoordinator.shared.registeredCount == 1 },
          "discovery timeout starts coordinated standalone playback")

    var producer: SharedWallpaperFrame? = try! SharedWallpaperFrame(displayID: 0, pointSize: container.bounds.size, scale: 1)
    func publish(_ gray: CGFloat) {
        _ = producer!.publish { context in
            context.setFillColor(CGColor(gray: gray, alpha: 1))
            context.fill(container.bounds)
        }
        DistributedNotificationCenter.default().postNotificationName(SharedWallpaperFrame.offerNotification,
            object: producer!.url.path, userInfo: nil, deliverImmediately: true)
    }
    publish(0.25)
    check(eventually { view.animateOneFrame(); return stored("sharedWallpaperImage", in: view, as: CGImage?.self).flatMap { $0 } != nil },
          "consumer acquires a fresh matching producer")
    check(ScreenSyncCoordinator.shared.registeredCount == 0 && stored("running", in: renderer, as: Bool.self) == false,
          "shared consumer stops its native simulation and leaves barriers")
    let first = pixels(of: view)
    let frameIndex: Int? = stored("frameIndex", in: renderer)
    publish(0.75)
    check(eventually { view.animateOneFrame(); return pixels(of: view) != first },
          "new publication reaches the actual consumer presentation")
    check(stored("frameIndex", in: renderer, as: Int.self) == frameIndex,
          "shared frame ticks do not advance native simulation")

    let nativeContainers = (1..<max(NSScreen.screens.count, 1)).map { index -> NSView in
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 503 + index, height: 347))
        let native = MatrixScreenSaverView(frame: container.bounds, isPreview: false)!
        container.addSubview(native)
        native.startAnimation()
        return container
    }
    let nativeViews = nativeContainers.compactMap { $0.subviews.first as? MatrixScreenSaverView }
    defer { nativeViews.forEach { $0.stopAnimation() } }
    if !nativeViews.isEmpty {
        check(eventually(3) {
            nativeViews.forEach { $0.animateOneFrame() }
            return ScreenSyncCoordinator.shared.registeredCount == nativeViews.count &&
                ScreenSyncCoordinator.shared.resolvedStartTime() != nil
        }, "actual mixed shared/native views resolve startup without waiting for the shared display")
    }

    producer = nil
    view.animateOneFrame()
    check(stored("running", in: renderer, as: Bool.self) == true && ScreenSyncCoordinator.shared.registeredCount == nativeViews.count,
          "producer exit starts immediate independent fallback")
    var options = MatrixScreenSaverView.loadSaverOptions()
    options.scanLinesIntensity = 0.4
    view.applyWallpaperOptions(options)
    let configuration: NativeMatrixRenderer.Configuration? = stored("configuration", in: renderer)
    check(configuration?.skipSyncDelay == true, "live visual options retain independent fallback transitions")
    options.neoMessageSceneEnabled = true
    options.cmdSceneEnabled = false
    options.numberSceneEnabled = true
    options.neoMessageLines = ["X"]
    options.rainRunForever = false
    options.rainDurationSeconds = 1
    view.applyWallpaperOptions(options)
    var sawRain = false
    var restartedRain = false
    var returnedToIntro = false
    for _ in 0..<200 {
        // Advance the existing timeline instead of waiting through scripted intro and drain pauses.
        renderer.shiftTimeline(by: -10)
        view.animateOneFrame()
        if let scene: Any = stored("activeScene", in: renderer), String(describing: scene) == "rainForever" {
            if sawRain && returnedToIntro { restartedRain = true; break }
            sawRain = true
        } else if sawRain {
            returnedToIntro = true
        }
    }
    check(sawRain && restartedRain && stored("pendingSceneAdvance", in: view, as: Bool.self) == false &&
          stored("pendingRestart", in: view, as: Bool.self) == false,
          "fallback completes both intros and finite-rain restart without joining native barriers")

    producer = try! SharedWallpaperFrame(displayID: 0, pointSize: container.bounds.size, scale: 1)
    publish(0.5)
    check(eventually { view.animateOneFrame(); return stored("running", in: renderer, as: Bool.self) == false },
          "producer reconnect stops fallback and rejoins shared presentation")
    view.stopAnimation()
    nativeViews.forEach { $0.stopAnimation() }
    check(ScreenSyncCoordinator.shared.registeredCount == 0 && ScreenSyncCoordinator.shared.expected == 0,
          "consumer teardown clears synchronization state")
}
