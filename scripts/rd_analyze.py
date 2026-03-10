"""
RenderDoc analysis script - run inside qrenderdoc Python console.
Analyzes the capture to find photonics-related draw calls and check for
texture feedback loops or wrong color data.
"""
import renderdoc as rd
import struct

def analyze(controller):
    actions = controller.GetRootActions()
    all_draws = []

    def collect(action_list, depth=0):
        for action in action_list:
            if action.flags & rd.ActionFlags.Drawcall:
                all_draws.append((action, depth))
            if len(action.children) > 0:
                collect(action.children, depth + 1)

    collect(actions)
    print(f"Total draw calls: {len(all_draws)}")

    # Find photonics-related draws
    photonics_draws = []
    for action, depth in all_draws:
        controller.SetFrameEvent(action.eventId, True)
        state = controller.GetPipelineState()
        fs_refl = state.GetShaderReflection(rd.ShaderStage.Fragment)

        if fs_refl is None:
            continue

        is_photonics = False
        has_radiosity = False
        resource_names = []
        for res in fs_refl.readOnlyResources:
            resource_names.append(res.name)
            if "radiosity" in res.name:
                has_radiosity = True
                is_photonics = True
        for res in fs_refl.readWriteResources:
            resource_names.append(res.name)
            if "gi_" in res.name:
                is_photonics = True
        for cb in fs_refl.constantBlocks:
            if "root_uniform" in cb.name or "cb_block" in cb.name or "light_registry" in cb.name or "lights_uniform" in cb.name:
                is_photonics = True

        if is_photonics:
            photonics_draws.append((action, fs_refl, has_radiosity, resource_names))

    print(f"\nPhotonics draws: {len(photonics_draws)}")

    for i, (action, fs_refl, has_radiosity, resource_names) in enumerate(photonics_draws):
        controller.SetFrameEvent(action.eventId, True)
        state = controller.GetPipelineState()
        om = state.GetOutputMerger()

        print(f"\n=== Photonics Draw {i} (EID {action.eventId}) ===")

        # Print outputs
        print("  Outputs:")
        for out in fs_refl.outputSignature:
            print(f"    loc[{out.regIndex}]: {out.varName}")

        # Print RTs
        rt_ids = set()
        print("  Render Targets:")
        for j, rt in enumerate(om.renderTargets):
            if rt.resourceId != rd.ResourceId.Null():
                tex = controller.GetTexture(rt.resourceId)
                fmt = str(tex.format.Name()) if tex else "?"
                w = tex.width if tex else 0
                h = tex.height if tex else 0
                print(f"    RT[{j}]: {rt.resourceId} {fmt} {w}x{h}")
                rt_ids.add(rt.resourceId)

        # Print bound textures
        tex_slots = state.GetReadOnlyResources(rd.ShaderStage.Fragment)
        print("  Bound Textures:")
        for slot in tex_slots:
            for bind in slot.resources:
                if bind.resourceId != rd.ResourceId.Null():
                    tex = controller.GetTexture(bind.resourceId)
                    if tex:
                        label = " *** FEEDBACK ***" if bind.resourceId in rt_ids else ""
                        print(f"    slot[{slot.bindPoint.bind}]: {bind.resourceId} {tex.format.Name()} {tex.width}x{tex.height}{label}")

        # Print SSBOs
        rw_res = state.GetReadWriteResources(rd.ShaderStage.Fragment)
        if rw_res:
            print("  Read-Write Resources:")
            for slot in rw_res:
                for bind in slot.resources:
                    if bind.resourceId != rd.ResourceId.Null():
                        print(f"    slot[{slot.bindPoint.bind}]: {bind.resourceId}")

        # Check for feedback loops
        for slot in tex_slots:
            for bind in slot.resources:
                if bind.resourceId in rt_ids:
                    print(f"\n  !!! TEXTURE FEEDBACK LOOP DETECTED !!!")
                    print(f"      Resource {bind.resourceId} is BOTH a render target and a sampler input")

        # Print relevant resource names
        print(f"  Resources: {', '.join(resource_names[:10])}")

    print("\n=== ANALYSIS COMPLETE ===")


# Entry point for qrenderdoc
pyrenderdoc.Replay().BlockInvoke(analyze)
