# Shader Debug Automation (RenderDoc + Fabric Client Tests)

## Current status in this repo

- The `VoxReader` NPE is fixed (bad `.vox` parsing no longer crashes `WorldCompilerThread`).
- Complementary patching is active and shader reload is stable.
- `PHOTONICS_ENABLED` option-resolution warnings are gone.
- `block.properties` legacy `:variant` parse warnings are gone.

## Is "ray tracing" visible in-game right now?

Short answer: **not as a clearly obvious "full RT renderer swap" yet**.

What is confirmed right now:
- Photonic writes extra G-buffer data (`oldAlbedo` / normals) into extra render targets (`colortex10/11`) in patched gbuffer programs.
- That proves the RT data path is being produced.

What this means visually:
- You may not see a dramatic "before/after path tracing" image by default in normal gameplay.
- Verification should be done by inspecting buffers (`colortex10/11`) or temporarily visualizing those buffers.

## Automated frame-capture approach

### Option A (recommended): Fabric Client GameTest + GFX Debuggers + RenderDoc

1. Add a client gametest that waits until a world is loaded.
2. Use test input to trigger the capture key:
   - `testContext.getInput().pressKey(GLFW.GLFW_KEY_F12);`
3. Wait for capture output (`.rdc`) to appear.
4. Open the frame in RenderDoc and inspect attachments (`colortex10`, `colortex11`).

Why this is automatable:
- Fabric API exposes client-side test context and input simulation (`ClientGameTestContext`, `TestInput`).
- GFX Debuggers integrates RenderDoc capture into Minecraft (F12 trigger).

### Option B: Scripted local capture trigger

If you do not want client gametest plumbing yet:
1. Launch `.\gradlew.bat runClient`.
2. Auto-enter/load a known world.
3. Trigger F12 from a local automation script (window-focused key send).
4. Assert latest capture exists and archive it as CI/dev artifact.

This is less deterministic than client gametests, but quick to set up.

## Minimal verification checklist per capture

1. `run/logs/latest.log` has no patch-option or block-id-map parse warnings.
2. Frame contains expected RT targets (`colortex10`, `colortex11`).
3. `colortex10` shows pre-lit albedo-like data.
4. `colortex11` shows encoded normal-like data.
5. Optional: temporary debug composite displays one target on-screen for quick visual sanity check.

## References

- Fabric client testing context API:
  - https://maven.fabricmc.net/docs/fabric-api-0.129.0+1.21.7/net/fabricmc/fabric/api/client/gametest/v1/context/ClientGameTestContext.html
- Fabric test input API (`pressKey`, etc.):
  - https://maven.fabricmc.net/docs/fabric-api-0.129.0+1.21.7/net/fabricmc/fabric/api/client/gametest/v1/input/TestInput.html
- GFX Debuggers (RenderDoc capture integration mod):
  - https://modrinth.com/mod/gfx-debuggers
- RenderDoc project/site:
  - https://renderdoc.org/
