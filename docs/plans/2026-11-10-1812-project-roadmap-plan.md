# Matrix Screen Saver and Wallpaper — Project Roadmap

Created: 2026-11-10

This roadmap records future work for the native macOS screen saver and animated wallpaper. It does not authorize implementation or set release dates. Feature-specific implementation plans remain in this directory.

## Current foundation

- Native Swift/AppKit screen saver and wallpaper app share the Matrix animation and options.
- `NativeMatrixRenderer.swift` supplies the falling glyphs and intro scenes.
- `SharedWallpaperCompositor.swift` already uses Metal and Core Image for GPU-assisted wallpaper compositing. This is not a full 3D scene renderer.

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

Source the model candidates and confirm the reference composition. Use those findings and the rendering proof of concept to write a bounded implementation plan before starting production changes.
