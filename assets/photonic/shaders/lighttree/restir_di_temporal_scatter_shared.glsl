#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_SHARED_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_SHARED_GLSL

#include "/photonics/lighttree/restir_di_temporal_buffer_bridge.glsl"

// Shared temporal scatter/gather ABI surface for the Reservoir Splatting
// reference pipeline. This header exists only to keep the GLSL port's include
// order stable while preserving the reference-stage payload layout and
// shifted-path buffer accessors.

struct LtScatterCurrentSample {
    bool                                  isValid;
    bool                                  hasPositivePHat;
    RTXDI_DIReservoir                     reservoir;
    ReconnectionData    reconnectionData;
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
    inout ReconnectionData dstReconnectionData,
    inout float newConfidence,
    ivec2 scatteredPixel,
    ivec2 pixel,
    RTXDI_DIReservoir currReservoir,
    ReconnectionData currReconnectionData,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg);

float ScatterTemporalResampling_motion_vector_confidence(
    ivec2 pixel,
    float newConfidence);

struct LtScatterShiftedPath {
    bool  valid;
    HitInfo primaryHit;
    vec2  fractionalPixel;
    vec2  lensSample;
    vec3  firstRayDir;
    vec3  radiance;
    float subPixelJacobian;
    float secondaryPathJacobian;
    float lensVertexJacobian;
};

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
    uint packedPrimaryHitIdentity = floatBitsToUint(
        shiftedPathRecord.primaryHitFaceFractionalPixelLensX.x
    );
    shiftedPath.primaryHit.faceId = packedPrimaryHitIdentity & 0x7u;
    shiftedPath.primaryHit.materialId = packedPrimaryHitIdentity >> 3u;
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
        uintBitsToFloat((shiftedPath.primaryHit.materialId << 3u) | (shiftedPath.primaryHit.faceId & 0x7u)),
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
        shiftedPathData.radiance,
        shiftedPathData.secondaryPathJacobian
    );
    shiftedPathData1 = vec4(shiftedPathData.lensVertexJacobian, shiftedPathData.valid, 0.0f, 0.0f);
}
#endif

ShiftedPathData gatherLensVertexCopyShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame);

ShiftedPathData gatherLensVertexCopyShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir);

ShiftedPathData gatherPrimaryHitReconnectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    HitInfo primaryHit,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame);

ShiftedPathData gatherPrimaryHitReconnectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    HitInfo primaryHit,
    RTXDI_DIReservoir sourceReservoir);

ReconnectionData ReconnectionData_update(
    ReconnectionData reconnectionData,
    ShiftedPathData shiftedPathData);

float lt_scatter_reservoir_confidence(
    RTXDI_DIReservoir reservoir,
    ReconnectionData reconnection);

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
    ReconnectionData sourceReconnection,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame,
    RAB_Surface targetSurface,
    ivec2 targetPixel,
    out LtScatterShiftedPath shifted,
    out RTXDI_DIReservoir shiftedReservoir,
    out ReconnectionData shiftedReconnection,
    out float shiftedJacobian);

bool lt_scatter_finalize_temporal_shifted_reservoir(
    ShiftedPathData shiftedPath,
    ReconnectionData sourceReconnection,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame,
    ivec2 targetPixel,
    RAB_Surface targetSurface,
    out RTXDI_DIReservoir shiftedReservoir,
    out ReconnectionData shiftedReconnection,
    out float shiftedJacobian)
{
    shiftedReservoir = RTXDI_EmptyDIReservoir();
    shiftedReconnection = ReconnectionData_init();
    shiftedJacobian = 0.0f;

    if (any(lessThan(shiftedPath.fractionalPixel, vec2(0.0f)))) {
        return false;
    }

    shiftedReservoir = lt_translate_reservoir_between_frames(
        sourceReservoir,
        sourcePreviousFrame,
        targetPreviousFrame
    );
    if (!RTXDI_IsValidDIReservoir(shiftedReservoir)) {
        return false;
    }

    vec2 shiftedSubPixel = fract(shiftedPath.fractionalPixel);
    PathReservoir_setSubPixel(shiftedReservoir, targetPixel, shiftedSubPixel);
    shiftedReservoir.lensSampleUV = sourceReconnection.lensSample;
    lt_area_finalize_candidate(shiftedReservoir, targetPixel, shiftedReservoir.pathSample);

    RAB_Surface shiftedSurface = targetSurface;
    shiftedSurface.worldPos = shiftedPath.primaryHit.worldPos;
    shiftedSurface.geoNormal = targetSurface.geoNormal;
    shiftedSurface.normal = targetSurface.geoNormal;
    shiftedSurface.viewDir = -shiftedPath.firstRayDir;
    shiftedSurface.viewDepth = shiftedPath.primaryHit.viewDepth;

    RAB_LightSample shiftedLight = lt_decode_reservoir_sample_for_frame(
        shiftedReservoir,
        shiftedSurface,
        sourcePreviousFrame,
        targetPreviousFrame
    );
    if (shiftedLight.index < 0 || shiftedLight.solidAnglePdf <= 0.0f) {
        return false;
    }

    float targetPdf = lt_surface_target_pdf(shiftedSurface, shiftedLight);
    if (targetPdf <= 0.0f) {
        return false;
    }

    shiftedReservoir.targetPdf = targetPdf;
    shiftedReconnection = ReconnectionData_update(sourceReconnection, shiftedPath);
    float baseJacobian = sourceReconnection.subPixelJacobian * sourceReconnection.secondaryPathJacobian;
    if (!(abs(baseJacobian) > 1e-20f) || isnan(baseJacobian)) {
        return false;
    }

    shiftedJacobian = (shiftedPath.subPixelJacobian * shiftedPath.secondaryPathJacobian) / baseJacobian;
    return !isnan(shiftedJacobian);
}

#endif
