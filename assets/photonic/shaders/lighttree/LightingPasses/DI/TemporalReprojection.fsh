#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE 1
// The reprojection pass only writes the four scatter buffers and reads texture
// samplers + camera uniforms. Drop the six light-data SSBOs that the shared
// includes pull in to stay under the bindable storage buffer limit (error
// C5058). Consumer helpers that reference these symbols are unreachable from
// ReprojectTemporalSamples_run; the stubs in photonics.glsl / reuse_bridge.glsl
// keep them compilable without consuming SSBO slots.
#define PH_LIGHTTREE_OMIT_LIGHT_DATA_BUFFERS

in vec4 direction_vert_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/ReprojectTemporalSamples.glsl"

void main()
{
    ivec2 reservoirPos = ivec2(gl_FragCoord.xy);
    int activeField = int(ph_restir_active_checkerboard_field);
    ivec2 pixel = (activeField == 0)
        ? reservoirPos
        : RTXDI_ReservoirPosToPixelPos(reservoirPos, activeField);
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPosition))
    {
        return;
    }

    ReprojectTemporalSamples_run(pixel);
}
