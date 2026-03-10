"""
RenderDoc capture analyzer for Photonics mod debugging.
Extracts draw call info, texture states, and framebuffer data
to identify the source of red/green block artifacts.
"""
import sys
import os

# RenderDoc ships its own Python; add its path
RENDERDOC_PATH = r"C:\Program Files\RenderDoc"
sys.path.insert(0, RENDERDOC_PATH)
os.environ["PATH"] = RENDERDOC_PATH + ";" + os.environ.get("PATH", "")

import renderdoc as rd

def analyze_capture(capture_path):
    cap = rd.OpenCaptureFile()
    result = cap.OpenFile(capture_path, '', None)
    if result != rd.ResultCode.Succeeded:
        print(f"Failed to open capture: {result}")
        return

    if not cap.LocalReplaySupport():
        print("Local replay not supported")
        return

    status, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    if status != rd.ResultCode.Succeeded:
        print(f"Failed to open replay: {status}")
        return

    print("=== CAPTURE ANALYSIS ===")
    print()

    # Get the list of draw calls
    actions = controller.GetRootActions()

    print(f"Total root actions: {len(actions)}")
    print()

    # Find all draw calls and their associated programs/framebuffers
    all_draws = []
    def collect_draws(action_list, depth=0):
        for action in action_list:
            if action.flags & rd.ActionFlags.Drawcall:
                all_draws.append((action, depth))
            if len(action.children) > 0:
                collect_draws(action.children, depth + 1)

    collect_draws(actions)
    print(f"Total draw calls: {len(all_draws)}")
    print()

    # For each draw call, check the output
    photonics_draws = []
    for action, depth in all_draws:
        controller.SetFrameEvent(action.eventId, True)
        state = controller.GetPipelineState()

        # Get shader info
        fs = state.GetShader(rd.ShaderStage.Fragment)
        vs = state.GetShader(rd.ShaderStage.Vertex)

        # Get shader reflection for fragment shader
        fs_refl = state.GetShaderReflection(rd.ShaderStage.Fragment)

        shader_name = ""
        if fs_refl is not None:
            # Check if this is a photonics shader by looking at uniforms/outputs
            for res in fs_refl.readOnlyResources:
                if "radiosity" in res.name or "prev_radiosity" in res.name:
                    shader_name = "PHOTONICS"
                    break
            for res in fs_refl.readOnlyResources:
                if "root_uniform" in res.name or "cb_block" in res.name or "light_registry" in res.name:
                    if shader_name == "":
                        shader_name = "PHOTONICS_SSBO"
                    break

            # Check outputs
            output_names = []
            for out in fs_refl.outputSignature:
                output_names.append(out.varName)

        if shader_name:
            photonics_draws.append((action, state, fs_refl, shader_name))

    print(f"Photonics-related draw calls: {len(photonics_draws)}")
    print()

    for i, (action, state, fs_refl, shader_name) in enumerate(photonics_draws):
        controller.SetFrameEvent(action.eventId, True)
        state = controller.GetPipelineState()

        print(f"--- Draw {i}: EID={action.eventId} [{shader_name}] ---")
        print(f"  Action: {action.GetName(controller.GetStructuredFile())}")

        # Print fragment shader outputs
        if fs_refl:
            print(f"  Fragment outputs:")
            for out in fs_refl.outputSignature:
                print(f"    location {out.regIndex}: {out.varName} ({out.compType})")

            # Print bound textures/samplers
            print(f"  Read-only resources (samplers):")
            for res in fs_refl.readOnlyResources:
                print(f"    {res.name}")

            # Print SSBOs/UBOs
            print(f"  Constant blocks (UBOs):")
            for cb in fs_refl.constantBlocks:
                print(f"    {cb.name} (size={cb.byteSize})")

            print(f"  Read-write resources (SSBOs/images):")
            for res in fs_refl.readWriteResources:
                print(f"    {res.name}")

        # Get framebuffer state
        om = state.GetOutputMerger()
        print(f"  Framebuffer:")
        print(f"    Depth target: {om.depth.resourceId}")
        for j, rt in enumerate(om.renderTargets):
            if rt.resourceId != rd.ResourceId.Null():
                tex_desc = controller.GetTexture(rt.resourceId)
                fmt = str(tex_desc.format.Name()) if tex_desc else "?"
                w = tex_desc.width if tex_desc else 0
                h = tex_desc.height if tex_desc else 0
                print(f"    RT[{j}]: id={rt.resourceId} fmt={fmt} {w}x{h}")

        # Get bound textures
        tex_slots = state.GetReadOnlyResources(rd.ShaderStage.Fragment)
        print(f"  Bound textures:")
        for slot in tex_slots:
            for bind in slot.resources:
                if bind.resourceId != rd.ResourceId.Null():
                    tex_desc = controller.GetTexture(bind.resourceId)
                    if tex_desc:
                        fmt = str(tex_desc.format.Name())
                        print(f"    slot[{slot.bindPoint.bind}]: id={bind.resourceId} fmt={fmt} {tex_desc.width}x{tex_desc.height}")

        # Check if any render target texture is also bound as a sampler input (feedback loop!)
        rt_ids = set()
        for rt in om.renderTargets:
            if rt.resourceId != rd.ResourceId.Null():
                rt_ids.add(rt.resourceId)

        for slot in tex_slots:
            for bind in slot.resources:
                if bind.resourceId in rt_ids:
                    print(f"  *** FEEDBACK LOOP: texture {bind.resourceId} bound as BOTH render target AND sampler input! ***")

        print()

    # Also look for any draw calls with very bright red/green output
    # by sampling the output textures
    print("=== CHECKING FOR RED/GREEN ARTIFACTS IN OUTPUTS ===")
    for i, (action, state, fs_refl, shader_name) in enumerate(photonics_draws):
        controller.SetFrameEvent(action.eventId, False)  # before draw
        state_before = controller.GetPipelineState()

        controller.SetFrameEvent(action.eventId, True)  # after draw
        state_after = controller.GetPipelineState()

        om = state_after.GetOutputMerger()
        for j, rt in enumerate(om.renderTargets):
            if rt.resourceId != rd.ResourceId.Null():
                # Try to get texture data
                try:
                    tex_data = controller.GetTextureData(rt.resourceId, rd.Subresource(0, 0, 0))
                    if tex_data and len(tex_data) > 0:
                        # Check first few pixels for pure red/green
                        # Format depends on texture type
                        print(f"  Draw {i} RT[{j}]: got {len(tex_data)} bytes of texture data")
                except:
                    pass

    controller.Shutdown()
    cap.Shutdown()

if __name__ == "__main__":
    capture = sys.argv[1] if len(sys.argv) > 1 else r"E:\RE\photonics\build\renderdoc\captures\runShaderGameTestClient_frame6651.rdc"
    analyze_capture(capture)
