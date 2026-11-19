# Matrix Screen Saver and Wallpaper — Project Roadmap

Created: 2026-11-10

This roadmap records future work for the native macOS screen saver and animated wallpaper. It does not authorize implementation or set release dates. Feature-specific implementation plans remain in this directory.

## Current foundation

- Native Swift/AppKit screen saver and wallpaper app share the Matrix animation and options.
- `NativeMatrixRenderer.swift` supplies the falling glyphs and intro scenes.
- `SharedWallpaperCompositor.swift` uses Metal and Core Image when the wallpaper publishes frames for a synchronized saver. The standalone saver and wallpaper now use a Metal glyph atlas for dense frames, with Core Graphics for sparse updates and fallback.

## Planned: Check hardware acceleration for the current 2D rain

- [ ] **Profile the current code first.** Trace one frame from animation update through glyph drawing and compositing to display in both the `.saver` host and the wallpaper app. Record which stages already use the GPU, which run on the CPU, and whether the existing paths can use more GPU acceleration without code changes.
- [ ] **Test the smallest useful change.** If a CPU stage limits playback, prototype accelerating just that stage. For example, if glyph drawing is the bottleneck, keep the animation logic and draw the glyphs in batches with Metal. Compare frame times, CPU/GPU use, and energy impact against the unchanged renderer at the same resolution, frame rate, and rain settings; check that the rain looks the same.
- [ ] **Record a recommendation for each host.** Use the measurements to recommend keeping the current path or changing the 2D renderer. Separately, identify what could be reused for the 3D proof of concept below and what new rendering code it would need. A 3D scene is optional; it is not a prerequisite for accelerating 2D rain.

### First measurements — 2026-11-19, Apple M5 Pro

**Finding:** No existing setting moves glyph drawing to the GPU. Keep the Swift simulation; the first experiment should replace the per-cell bitmap draws, not the animation rules or the frame-sharing transport.

| Playback path             | What was measured                                                                                                                                                                                                                                                                                    | Implication                                                                                                        |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Ordinary wallpaper        | A 4-second stack sample of the installed 0.7.0 app with three displays attached found 291 main-thread samples in scene drawing versus 10 in simulation advance. The largest raster stacks called `CGContextDrawImage`, `CGContextFillRect`, and `CGContextClearRect`.                                | Accelerating only the final composite would leave the sampled work intact.                                         |
| Standalone saver          | Release build at `83cd3ba`, real saver view drawing offscreen at 1920×1080, 25 fps, 13×24 cells, diffuse and vertical scanlines. After 100 warmup frames, 100 rain frames averaged 0.38 ms to advance and 17.02 ms to draw (18.43 ms total at p95).                                                  | The same 2D drawing experiment is relevant to the saver. These are bitmap timings, not macOS presentation latency. |
| Wallpaper serving a saver | `./wallpaper-tests.sh --gpu-composition-benchmark`: at 3456×2234, CPU vs. linear GPU composition and publication averaged 21.14 vs. 6.41 ms including consumer snapshot; at 1920×1080, 5.60 vs. 2.88 ms. Pixel comparisons passed. These fixtures exclude glyph drawing and CPU dirty-band clipping. | Keep the existing GPU compositor. Its speedup is not a prediction for GPU glyph drawing.                           |
| Synchronized saver        | `./wallpaper-tests.sh --consumer-host` confirmed that receiving a frame stops local simulation and that producer loss restarts standalone playback. `--composition-benchmark` measured 24.22 ms p95 for three producers combined (one Retina, two 1080p), excluding presentation.                    | Optimize the producer once; a connected saver does not need its own glyph renderer running.                        |

### 2D optimization results — 2026-11-19, Apple M5 Pro

The shared saver view now draws dense glyph updates and diffuse backgrounds in one Metal compute pass. The standalone view also skips the part of the background gradient covered by the opaque terminal. The simulation stays in Swift.

Using the same 1920×1080 offscreen saver fixture described above, mean drawing time fell from 17.02 to 10.42 ms over 100 measured rain frames. The 95th percentile for simulation plus drawing fell from 18.43 to 11.62 ms. The Metal-only run averaged 15.45 ms to draw. A frozen 1080p GPU glyph frame matched the Core Graphics reference byte-for-byte. Drawing the background in edge strips matched the full gradient at 437×293, 1728×1117 and 1920×1080 points, each at 1× and 2× scale.

Remaining measurements include full-screen presentation, multi-display GPU utilization and energy use. The current pass returns a bitmap for AppKit. A 3D prototype could write its pixels to a texture for a perspective plane.

## Planned: GPU-accelerated 3D Matrix hallway scene

### Goal

Render the scene from _The Matrix_ in which three Agents stand in a hallway aiming their guns toward the camera. Use the project's own animated falling glyphs as textures across the walls and throughout the scene, rather than relying on a prerecorded video or baked-in code texture.

The goal is a real 3D scene with depth and perspective, available in both the screen saver and animated wallpaper. Keep the existing 2D rain available.

### Milestones

1. **Find a suitable 3D model.**
   - Look for the complete hallway scene with all three Agents in the intended poses and camera composition.
   - Check model quality, UV mapping, material separation, and suitability for real-time rendering.
   - Verify permission to modify and redistribute the model and its textures with both products. Record the source, author, license, and required attribution; a downloadable model is not automatically redistributable.
   - If no suitable complete scene is available, bring back options for assembling licensed assets or commissioning a model before changing the intended scene or spending money.
   - Deliverable: a model shortlist with reference images, licensing evidence, and an asset recommendation. No model has been selected yet.

2. **Validate native, GPU-accelerated 3D rendering.**
   - Evaluate a native macOS rendering path, taking the existing Metal integration into account. Choose the framework after checking compatibility with both the `.saver` host and wallpaper app.
   - Start with a small scene to verify model loading, camera projection, lighting, depth, and rendering at display backing resolution.
   - Measure frame time, GPU/CPU use, memory, and energy impact on representative supported hardware and multiple displays before setting performance targets.
   - Deliverable: a rendering proof of concept and a technical implementation plan, not a rewrite of the existing renderer.

3. **Use our falling glyphs as live scene textures.**
   - Reuse the project's glyph artwork and animation rather than substituting someone else's Matrix-code effect.
   - Map the animated glyphs onto the hallway walls, floor, ceiling, and Agent/model surfaces to achieve the code-covered scene. Check orientation, scale, seams, and readability on each surface.
   - The glyphs must follow the 3D surfaces and perspective, not act as a flat overlay in front of the camera.
   - Reuse textures and rendering resources where possible; measure the cost of updating the live glyph textures.
   - Deliverable: the chosen model rendered with the project's animated glyph textures.

4. **Integrate and verify the hallway scene.**
   - Add the scene to the shared playback/options flow without removing existing rain or intro scenes.
   - Preserve Start, Stop, Pause, Quit, sleep/wake, display synchronization, and desktop-wallpaper restoration.
   - Keep playback local after installation; bundle approved assets rather than fetching models at runtime.
   - Verify the scene in the actual screen saver host, preview host, and wallpaper app, including display changes and resource cleanup.
   - Deliverable: a user-selectable scene with visual, lifecycle, and performance checks.

### Acceptance criteria

- Three Agents stand in the hallway aiming toward the camera, with composition reviewed against the intended movie scene.
- Geometry, depth, lighting, and animated materials are rendered using hardware-accelerated 3D graphics.
- The project's falling glyphs animate across scene surfaces, including walls and other visible geometry.
- Both products render the scene without breaking existing playback, synchronization, or desktop restoration.
- All bundled models and textures have documented modification and redistribution rights.
- Frame-rate and resource-use targets are agreed from the rendering measurements and verified before release.

### Decisions still open

- Exact movie reference frame and model source.
- Native 3D framework, asset format, and any necessary model conversion.
- Supported-hardware performance budget and behavior when the 3D rendering path is unavailable.
- Whether the first version keeps the camera and Agent poses fixed or adds motion. Motion beyond the falling glyphs is not yet specified.

## Next planning step

Measure full-screen presentation and energy use with batched 2D glyph drawing. The 3D model search can proceed independently: confirm the reference composition and use the model shortlist and rendering proof of concept to plan the hallway scene.
