#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_bridge.glsl"

void storeReservoirOutputs(RTXDI_DIReservoir reservoir)
{
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
}

void execute(ivec2 pixel)
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_DIReservoir currReservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPosition),
        restirDI.bufferIndices.shadingInputBufferIndex
    );

    if (!RTXDI_IsValidDIReservoir(currReservoir))
    {
        storeReservoirOutputs(RTXDI_EmptyDIReservoir());
        return;
    }

    storeReservoirOutputs(currReservoir);
}

void main()
{
    ivec2 pixel = lt_fragment_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        storeReservoirOutputs(RTXDI_EmptyDIReservoir());
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPosition))
    {
        storeReservoirOutputs(RTXDI_EmptyDIReservoir());
        return;
    }

    execute(pixel);
}
