#ifndef PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL
#define PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

void storeEmptyRobustReuseOptimizationResult()
{
    shifted_path_data0_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data1_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
    shifted_path_data2_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data3_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
    shifted_path_data4_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data5_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
    shifted_path_data6_frag_out = vec4(0.0f, 0.0f, 0.0f, 1.0f);
    shifted_path_data7_frag_out = vec4(1.0f, 0.0f, 0.0f, 0.0f);
}

void storeRobustReuseOptimizationShiftedPath(int localOffsetIndex, LtTemporalGatherShiftedPathData shiftedPathData)
{
    vec4 shiftedPathData0;
    vec4 shiftedPathData1;
    scatter_store_gather_shifted_path_data(shiftedPathData, shiftedPathData0, shiftedPathData1);
    switch (localOffsetIndex)
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
    }
}

void run(ivec2 pixel)
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    ReservoirSplattingReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(pixel);
    if (!RTXDI_IsValidDIReservoir(prevReservoir)
        || ph_luminance(PathReservoir_getIntegrand(prevReservoir)) <= 0.0f)
    {
        return;
    }

    RTXDI_RandomSamplerState randomSampler = lt_init_random_sampler(uvec2(pixel), runtimeParameters.frameIndex, 1u);
    const ivec2 neighborOffsets[8] = ivec2[8](
        ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
        ivec2(-1, 0),                  ivec2(1, 0),
        ivec2(-1, 1),  ivec2(0, 1),  ivec2(1, 1)
    );
    vec2 prevSubPixel = PathReservoir_getSubPixel(prevReservoir, pixel);

    for (int localOffsetIndex = 0; localOffsetIndex < 4; ++localOffsetIndex)
    {
        int offsetIndex = PH_LIGHTTREE_ROBUST_REUSE_OFFSET_BASE + localOffsetIndex;
        ivec2 neighborPixel = pixel + neighborOffsets[offsetIndex];
        LtTemporalGatherShiftedPathData shiftedPathData = LtTemporalGatherShiftedPathData_init();
        if (lt_is_viewport_uv_in_bounds(neighborPixel))
        {
            ShiftedPathData shiftedPath = gatherLensVertexCopyShift(
                randomSampler,
                prevReconnectionData,
                prevReconnectionData.time,
                vec2(neighborPixel) + prevSubPixel,
                prevReconnectionData.lensSample,
                prevReservoir
            );
            shiftedPathData.radiance = shiftedPath.radiance;
            shiftedPathData.secondaryPathJacobian = max(shiftedPath.secondaryPathJacobian, 1e-10f);
            shiftedPathData.lensVertexJacobian = max(shiftedPath.lensVertexJacobian, 1e-10f);
            shiftedPathData.valid = (
                any(greaterThan(max(shiftedPath.radiance, vec3(0.0f)), vec3(0.0f)))
                || shiftedPath.primaryHit.viewDepth > 0.0f
            ) ? 1.0f : 0.0f;
        }
        storeRobustReuseOptimizationShiftedPath(localOffsetIndex, shiftedPathData);
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

#endif
