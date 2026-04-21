#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
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
#define shifted_path_data4_frag_out temporal_gather_shifted_path_data4_frag_out
#define shifted_path_data5_frag_out temporal_gather_shifted_path_data5_frag_out
#define shifted_path_data6_frag_out temporal_gather_shifted_path_data6_frag_out
#define shifted_path_data7_frag_out temporal_gather_shifted_path_data7_frag_out
#define shifted_path_data8_frag_out temporal_gather_shifted_path_data8_frag_out
#define shifted_path_data9_frag_out temporal_gather_shifted_path_data9_frag_out

in vec4 direction_vert_out;

layout(location = 0) out vec2 temporal_gather_floating_coords_frag_out;
layout(location = 1) out vec4 temporal_gather_intermediate_reservoir_frag_out;
layout(location = 2) out vec4 temporal_gather_intermediate_reservoir_sample_frag_out;
layout(location = 3) out vec4 temporal_gather_intermediate_reservoir_meta_frag_out;
layout(location = 4) out vec4 temporal_gather_intermediate_reconnection0_frag_out;
layout(location = 5) out vec4 temporal_gather_intermediate_reconnection1_frag_out;
layout(location = 6) out vec4 temporal_gather_shifted_path_data0_frag_out;
layout(location = 7) out vec4 temporal_gather_shifted_path_data1_frag_out;
layout(location = 8) out vec4 temporal_gather_shifted_path_data2_frag_out;
layout(location = 9) out vec4 temporal_gather_shifted_path_data3_frag_out;
layout(location = 10) out vec4 temporal_gather_shifted_path_data4_frag_out;
layout(location = 11) out vec4 temporal_gather_shifted_path_data5_frag_out;
layout(location = 12) out vec4 temporal_gather_shifted_path_data6_frag_out;
layout(location = 13) out vec4 temporal_gather_shifted_path_data7_frag_out;
layout(location = 14) out vec4 temporal_gather_shifted_path_data8_frag_out;
layout(location = 15) out vec4 temporal_gather_shifted_path_data9_frag_out;

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
    shifted_path_data2_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data3_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
    shifted_path_data4_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data5_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
    shifted_path_data6_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data7_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
    shifted_path_data8_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data9_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
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
        case 1:
            shifted_path_data2_frag_out = shiftedPathData0;
            shifted_path_data3_frag_out = shiftedPathData1;
            break;
        case 2:
            shifted_path_data4_frag_out = shiftedPathData0;
            shifted_path_data5_frag_out = shiftedPathData1;
            break;
        case 3:
            shifted_path_data6_frag_out = shiftedPathData0;
            shifted_path_data7_frag_out = shiftedPathData1;
            break;
        case 4:
            shifted_path_data8_frag_out = shiftedPathData0;
            shifted_path_data9_frag_out = shiftedPathData1;
            break;
    }
}

void run(ivec2 pixel)
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface))
    {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    ReservoirSplattingReconnectionData prevReconnectionData = scatter_load_prev_reconnection(pixel);
    if (!RTXDI_IsValidDIReservoir(prevReservoir) || !any(greaterThan(prevReservoir.radiance, vec3(0.0f))))
    {
        return;
    }

    RTXDI_RandomSamplerState randomSampler = lt_init_random_sampler(uvec2(pixel), runtimeParameters.frameIndex, 1u);
    const ivec2 neighborOffsets[8] = ivec2[8](
        ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
        ivec2(-1, 0),                  ivec2(1, 0),
        ivec2(-1, 1),  ivec2(0, 1),  ivec2(1, 1)
    );
    for (int offsetIndex = 0; offsetIndex < 5; ++offsetIndex)
    {
        ivec2 neighborPixel = pixel + neighborOffsets[offsetIndex];
        bool neighborIsValid = lt_is_viewport_uv_in_bounds(neighborPixel);
        LtTemporalGatherShiftedPathData shiftedPathData = LtTemporalGatherShiftedPathData_init();
        if (neighborIsValid)
        {
            vec2 floatingCoord = vec2(neighborPixel) + prevReservoir.pixelSampleUV;
            SpatialShiftedPathData shiftedPath = gatherLensVertexCopyShift(
                randomSampler,
                prevReconnectionData,
                prevReconnectionData.time + float(frameTimeCounter),
                floatingCoord,
                prevReconnectionData.lensSample
            );
            shiftedPathData.radiance = max(shiftedPath.radiance, vec3(0.0f));
            shiftedPathData.secondaryPathJacobian = max(shiftedPath.secondaryPathJacobian, 1e-10f);
            shiftedPathData.lensVertexJacobian = max(shiftedPath.lensVertexJacobian, 1e-10f);
            shiftedPathData.valid = 1.0f;
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
