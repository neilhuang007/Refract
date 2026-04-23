#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_SHARED_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_SHARED_GLSL

#include "/photonics/lighttree/restir_di_temporal_buffer_bridge.glsl"

// Shared temporal-scatter payload and prototype surface.
// This keeps the stage ABI in one place while preserving the existing include
// order expected by reuse_bridge.glsl and the temporal stage modules.

struct LtScatterCurrentSample {
    bool                                  isValid;
    bool                                  hasPositivePHat;
    RTXDI_DIReservoir                     reservoir;
    ReservoirSplattingReconnectionData    reconnectionData;
    float                                 confidence;
};

float ScatterTemporalResampling_load_previous_reservoir_confidence(
    ivec2 neighborPixel);

RTXDI_DIReservoir lt_ScatterTemporalResampling_load_current_reservoir(
    ivec2 pixel);

LtScatterCurrentSample lt_ScatterTemporalResampling_load_current_sample(
    uint reservoirIdx,
    ivec2 pixel,
    RAB_Surface surface,
    RTXDI_DIReservoir currReservoir);

float ScatterTemporalResampling_compute_curr_sample_mis(
    LtScatterCurrentSample currSample,
    ivec2 pixel,
    RAB_Surface surface);

bool ScatterTemporalResampling_process_contributor(
    inout RTXDI_DIReservoir dstReservoir,
    inout ScatterReconnectionData dstReconnectionData,
    inout float newConfidence,
    ivec2 scatteredPixel,
    ivec2 pixel,
    RTXDI_DIReservoir currReservoir,
    ScatterReconnectionData currReconnectionData,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg);

float ScatterTemporalResampling_motion_vector_confidence(
    ivec2 pixel,
    float newConfidence);

#ifndef PH_LIGHTTREE_LT_SCATTER_SHIFTED_PATH_DECLARED
#define PH_LIGHTTREE_LT_SCATTER_SHIFTED_PATH_DECLARED
struct LtScatterShiftedPath {
    bool  valid;
    ReservoirSplattingHitInfo primaryHit;
    vec2  fractionalPixel;
    vec2  lensSample;
    vec3  firstRayDir;
    vec3  radiance;
    float subPixelJacobian;
    float secondaryPathJacobian;
    float lensVertexJacobian;
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE) || defined(PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE)
ShiftedPathData lt_temporal_empty_shifted_path();

struct LtTemporalGatherShiftedPathData {
    vec3 radiance;
    float secondaryPathJacobian;
    float lensVertexJacobian;
    float valid;
};

LtTemporalGatherShiftedPathData LtTemporalGatherShiftedPathData_init()
{
    LtTemporalGatherShiftedPathData shiftedPathData;
    shiftedPathData.radiance = vec3(0.0f);
    shiftedPathData.secondaryPathJacobian = 1.0f;
    shiftedPathData.lensVertexJacobian = 1.0f;
    shiftedPathData.valid = 0.0f;
    return shiftedPathData;
}

ShiftedPathData lt_temporal_load_shifted_path(ivec2 pixel, int offsetIndex)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();
    ShiftedPathStorageRecord shiftedPathRecord = shiftedPathRecords[
        lt_temporal_gather_shifted_path_record_index(pixel, offsetIndex)
    ];

    shiftedPath.primaryHit.worldPos = shiftedPathRecord.primaryHitData.xyz;
    shiftedPath.primaryHit.viewDepth = shiftedPathRecord.primaryHitData.w;
    shiftedPath.primaryHit.faceId = floatBitsToUint(
        shiftedPathRecord.primaryHitFaceFractionalPixelLensX.x
    );
    shiftedPath.fractionalPixel = shiftedPathRecord.primaryHitFaceFractionalPixelLensX.yz;
    shiftedPath.lensSample = vec2(
        shiftedPathRecord.primaryHitFaceFractionalPixelLensX.w,
        shiftedPathRecord.lensYFirstRayDir.x
    );
    shiftedPath.firstRayDir = shiftedPathRecord.lensYFirstRayDir.yzw;
    shiftedPath.subPixelJacobian = shiftedPathRecord.jacobianData.x;
    shiftedPath.lensVertexJacobian = shiftedPathRecord.jacobianData.y;
    shiftedPath.secondaryPathJacobian = shiftedPathRecord.jacobianData.z;
    shiftedPath.radiance = shiftedPathRecord.radianceData.xyz;
    return shiftedPath;
}

void lt_temporal_store_shifted_path(ivec2 pixel, int offsetIndex, ShiftedPathData shiftedPath)
{
    ShiftedPathStorageRecord shiftedPathRecord;
    shiftedPathRecord.primaryHitData = vec4(
        shiftedPath.primaryHit.worldPos,
        shiftedPath.primaryHit.viewDepth
    );
    shiftedPathRecord.primaryHitFaceFractionalPixelLensX = vec4(
        uintBitsToFloat(shiftedPath.primaryHit.faceId),
        shiftedPath.fractionalPixel,
        shiftedPath.lensSample.x
    );
    shiftedPathRecord.lensYFirstRayDir = vec4(shiftedPath.lensSample.y, shiftedPath.firstRayDir);
    shiftedPathRecord.jacobianData = vec4(
        shiftedPath.subPixelJacobian,
        shiftedPath.lensVertexJacobian,
        shiftedPath.secondaryPathJacobian,
        0.0f
    );
    shiftedPathRecord.radianceData = vec4(shiftedPath.radiance, 0.0f);
    shiftedPathRecords[
        lt_temporal_gather_shifted_path_record_index(pixel, offsetIndex)
    ] = shiftedPathRecord;
}

LtTemporalGatherShiftedPathData scatter_load_gather_shifted_path_data(ivec2 pixel, int offsetIndex)
{
    ShiftedPathData shiftedPath = lt_temporal_load_shifted_path(pixel, offsetIndex);
    LtTemporalGatherShiftedPathData packedShiftedPath = LtTemporalGatherShiftedPathData_init();
    packedShiftedPath.radiance = shiftedPath.radiance;
    packedShiftedPath.secondaryPathJacobian = shiftedPath.secondaryPathJacobian;
    packedShiftedPath.lensVertexJacobian = shiftedPath.lensVertexJacobian;
    packedShiftedPath.valid = all(greaterThanEqual(shiftedPath.fractionalPixel, vec2(0.0f))) ? 1.0f : 0.0f;
    return packedShiftedPath;
}

void scatter_store_gather_shifted_path_data(
    LtTemporalGatherShiftedPathData shiftedPathData,
    out vec4 shiftedPathData0,
    out vec4 shiftedPathData1)
{
    shiftedPathData0 = vec4(
        max(shiftedPathData.radiance, vec3(0.0f)),
        max(shiftedPathData.secondaryPathJacobian, 1e-10f)
    );
    shiftedPathData1 = vec4(max(shiftedPathData.lensVertexJacobian, 1e-10f), shiftedPathData.valid, 0.0f, 0.0f);
}
#endif

ShiftedPathData gatherLensVertexCopyShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir);

ShiftedPathData gatherPrimaryHitReconnectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    ReservoirSplattingHitInfo primaryHit,
    RTXDI_DIReservoir sourceReservoir);

ReservoirSplattingReconnectionData ReconnectionData_update(
    ReservoirSplattingReconnectionData reconnectionData,
    ShiftedPathData shiftedPathData);

float lt_scatter_reservoir_confidence(
    RTXDI_DIReservoir reservoir,
    ScatterReconnectionData reconnection);

float lt_scatter_radiance_phat(vec3 radiance);

float lt_scatter_compute_ucw(
    RTXDI_DIReservoir reservoir,
    vec3 integrand);

bool lt_scatter_add_sample_from_reservoir(
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    float sampleMIS,
    vec3 integrand,
    float jacobian,
    float ucw,
    float sampleConfidence,
    RTXDI_DIReservoir sampleReservoir,
    inout RTXDI_RandomSamplerState rng
);

bool lt_scatter_update_shifted_reservoir(
    ScatterReconnectionData sourceReconnection,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame,
    RAB_Surface targetSurface,
    ivec2 targetPixel,
    out LtScatterShiftedPath shifted,
    out RTXDI_DIReservoir shiftedReservoir,
    out ScatterReconnectionData shiftedReconnection,
    out float shiftedJacobian);

#endif
