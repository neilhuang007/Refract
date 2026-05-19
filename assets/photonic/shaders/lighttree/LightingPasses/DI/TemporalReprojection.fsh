#version 430
#include "/photonics/lighttree/lt_feature_flags.glsl"
#define PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE 1
// SSBO/sampler inclusion is driven by lt_buffer_features.glsl based on the
// PH_LIGHTTREE_ENABLE_*_STAGE flag above. Reprojection opts in to REGIR +
// FLOATING_COORDS centrally — no per-shader overrides.

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
