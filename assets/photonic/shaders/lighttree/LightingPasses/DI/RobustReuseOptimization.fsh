#version 430
#define floating_coords_frag_out temporal_gather_floating_coords_frag_out
#define intermediate_reservoir_frag_out temporal_gather_intermediate_reservoir_frag_out
#define intermediate_reservoir_sample_frag_out temporal_gather_intermediate_reservoir_sample_frag_out
#define intermediate_reservoir_meta_frag_out temporal_gather_intermediate_reservoir_meta_frag_out
#define intermediate_reconnection0_frag_out temporal_gather_intermediate_reconnection0_frag_out
#define intermediate_reconnection1_frag_out temporal_gather_intermediate_reconnection1_frag_out
#define shifted_path_data0_frag_out temporal_gather_shifted_path_data0_frag_out
#define shifted_path_data1_frag_out temporal_gather_shifted_path_data1_frag_out
#define shifted_path_data2_frag_out temporal_gather_shifted_path_data2_frag_out
#define shifted_path_data3_frag_out temporal_gather_shifted_path_data3_frag_out
#define PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE 1

in vec4 direction_vert_out;

layout(location = 0) out vec2 temporal_gather_floating_coords_frag_out;
layout(location = 1) out vec4 temporal_gather_intermediate_reservoir_frag_out;
layout(location = 2) out vec4 temporal_gather_intermediate_reservoir_sample_frag_out;
layout(location = 3) out vec4 temporal_gather_intermediate_reservoir_meta_frag_out;
layout(location = 4) out vec4 temporal_gather_intermediate_reconnection0_frag_out;
layout(location = 5) out vec4 temporal_gather_intermediate_reconnection1_frag_out;
layout(location = 6) out vec4 temporal_gather_shifted_path_data0_frag_out;
layout(location = 7) out vec4 temporal_gather_shifted_path_data1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

void storeEmptyRobustReuseOptimizationResult()
{
    floating_coords_frag_out = vec2(-1.0f);
    intermediate_reservoir_frag_out = rtxdi_pack_reservoir(RTXDI_EmptyDIReservoir());
    intermediate_reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(RTXDI_EmptyDIReservoir());
    intermediate_reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(RTXDI_EmptyDIReservoir());
    intermediate_reconnection0_frag_out = vec4(0.0f);
    intermediate_reconnection1_frag_out = vec4(0.0f);
    shifted_path_data0_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data1_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
}

void storeRobustReuseOptimizationShiftedPath(int offsetIndex, LtTemporalGatherShiftedPathData shiftedPathData)
{
    vec4 shiftedPathData0;
    vec4 shiftedPathData1;
    scatter_store_gather_shifted_path_data(shiftedPathData, shiftedPathData0, shiftedPathData1);
    switch (offsetIndex)
    {
        case 0:
            shifted_path_data0_frag_out = shiftedPathData0;
            shifted_path_data1_frag_out = shiftedPathData1;
            break;
    }
}

void run(ivec2 pixel)
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    vec2 prevPixel = lt_temporal_previous_pixel_center(pixel) - vec2(0.5f);
    if (!lt_is_viewport_uv_in_bounds(ivec2(floor(prevPixel)))
        || any(lessThan(prevPixel, vec2(0.0f)))
        || any(greaterThanEqual(prevPixel, vec2(viewWidth, viewHeight)))) {
        return;
    }

    ivec2 roundedPrevPixel = ivec2(round(prevPixel));
    if (!lt_is_viewport_uv_in_bounds(roundedPrevPixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(roundedPrevPixel)
    );
    ReservoirSplattingReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(roundedPrevPixel);

    floating_coords_frag_out = prevPixel;
    float transportAux0;
    float transportAux1;
    scatter_pack_reconnection_fields(
        prevReconnectionData.firstHit.worldPos,
        prevReconnectionData.firstHit.viewDepth,
        prevReconnectionData.lightPdf,
        prevReconnectionData.time,
        prevReconnectionData.irradiance,
        prevReconnectionData.subPixel,
        prevReconnectionData.subPixelJacobian,
        prevReconnectionData.secondaryPathJacobian,
        prevReconnectionData.firstHit.faceId,
        prevReconnectionData.pathLength,
        prevReconnectionData.firstBSDFComponentType,
        prevReconnectionData.secondBSDFComponentType,
        prevReconnectionData.transmissionEvent,
        prevReconnectionData.lightIsNEE,
        prevReconnectionData.lightIsDistant,
        transportAux0,
        transportAux1,
        intermediate_reconnection0_frag_out,
        intermediate_reconnection1_frag_out
    );
    intermediate_reservoir_frag_out = rtxdi_pack_reservoir(prevReservoir);
    intermediate_reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(prevReservoir);
    intermediate_reservoir_meta_frag_out = PathReservoir_packMeta(prevReservoir);

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface) || !RTXDI_IsValidDIReservoir(prevReservoir) || prevReservoir.M <= 0.0f)
    {
        return;
    }

    RTXDI_RandomSamplerState randomSampler = lt_init_random_sampler(uvec2(pixel), runtimeParameters.frameIndex, 1u);
    const ivec2 neighborOffsets[8] = ivec2[8](
        ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
        ivec2(-1, 0),                  ivec2(1, 0),
        ivec2(-1, 1),  ivec2(0, 1),  ivec2(1, 1)
    );
    for (int offsetIndex = 0; offsetIndex < 1; ++offsetIndex)
    {
        ivec2 neighborPixel = pixel + neighborOffsets[offsetIndex];
        bool neighborIsValid = lt_is_viewport_uv_in_bounds(neighborPixel);
        LtTemporalGatherShiftedPathData shiftedPathData = LtTemporalGatherShiftedPathData_init();
        if (neighborIsValid)
        {
            shiftedPathData.valid = 0.0f;
            shiftedPathData.radiance = vec3(0.0f);
            shiftedPathData.secondaryPathJacobian = 1.0f;
            shiftedPathData.lensVertexJacobian = 1.0f;
        }
        storeRobustReuseOptimizationShiftedPath(offsetIndex, shiftedPathData);
    }
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    storeEmptyRobustReuseOptimizationResult();

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

    run(pixel);
}
