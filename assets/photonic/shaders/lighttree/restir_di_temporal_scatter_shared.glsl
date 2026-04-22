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

struct LtScatterShiftedPath {
    bool  valid;
    ReservoirSplattingHitInfo firstHit;
    vec2  fractionalPixel;
    vec2  lensSample;
    vec3  firstRayDir;
    vec3  radiance;
    float subPixelJacobian;
    float secondaryPathJacobian;
    float lensVertexJacobian;
};

#ifndef PH_LIGHTTREE_SHIFTED_PATH_DATA_DECLARED
#define PH_LIGHTTREE_SHIFTED_PATH_DATA_DECLARED
struct ShiftedPathData {
    ReservoirSplattingHitInfo primaryHit;
    vec2 fractionalPixel;
    vec2 lensSample;
    vec3 firstRayDir;
    float subPixelJacobian;
    float lensVertexJacobian;
    float secondaryPathJacobian;
    vec3 radiance;
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE) || defined(PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE)
ShiftedPathData lt_temporal_empty_shifted_path();

#ifndef PH_LIGHTTREE_TEMPORAL_GATHER_SHIFTED_PATH_BUFFER_DECLARED
#define PH_LIGHTTREE_TEMPORAL_GATHER_SHIFTED_PATH_BUFFER_DECLARED
layout(std430) restrict buffer ph_temporal_gather_shifted_paths {
    vec4 ph_temporal_gather_shifted_paths_data[];
};

const uint LT_TEMPORAL_GATHER_SHIFT_COUNT = 8u;
const uint LT_TEMPORAL_GATHER_SHIFTED_PATH_PACKED_VEC4_COUNT = 5u;

uint lt_temporal_gather_shifted_path_pixel_index(ivec2 pixel)
{
    return uint(pixel.y * viewWidth + pixel.x);
}

uint lt_temporal_gather_shifted_path_record_index(ivec2 pixel, int offsetIndex)
{
    return lt_temporal_gather_shifted_path_pixel_index(pixel) * LT_TEMPORAL_GATHER_SHIFT_COUNT + uint(offsetIndex);
}

uint lt_temporal_gather_shifted_path_vec4_index(ivec2 pixel, int offsetIndex, uint vec4Index)
{
    return lt_temporal_gather_shifted_path_record_index(pixel, offsetIndex)
        * LT_TEMPORAL_GATHER_SHIFTED_PATH_PACKED_VEC4_COUNT
        + vec4Index;
}
#endif

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
    vec4 packed0 = ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 0u)
    ];
    vec4 packed1 = ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 1u)
    ];
    vec4 packed2 = ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 2u)
    ];
    vec4 packed3 = ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 3u)
    ];
    vec4 packed4 = ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 4u)
    ];

    shiftedPath.primaryHit.worldPos = packed0.xyz;
    shiftedPath.primaryHit.viewDepth = packed0.w;
    shiftedPath.primaryHit.faceId = floatBitsToUint(packed1.x);
    shiftedPath.fractionalPixel = packed1.yz;
    shiftedPath.lensSample = vec2(packed1.w, packed2.x);
    shiftedPath.firstRayDir = packed2.yzw;
    shiftedPath.subPixelJacobian = packed3.x;
    shiftedPath.lensVertexJacobian = packed3.y;
    shiftedPath.secondaryPathJacobian = packed3.z;
    shiftedPath.radiance = packed4.xyz;
    return shiftedPath;
}

void lt_temporal_store_shifted_path(ivec2 pixel, int offsetIndex, ShiftedPathData shiftedPath)
{
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 0u)
    ] = vec4(shiftedPath.primaryHit.worldPos, shiftedPath.primaryHit.viewDepth);
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 1u)
    ] = vec4(
        uintBitsToFloat(shiftedPath.primaryHit.faceId),
        shiftedPath.fractionalPixel,
        shiftedPath.lensSample.x
    );
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 2u)
    ] = vec4(shiftedPath.lensSample.y, shiftedPath.firstRayDir);
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 3u)
    ] = vec4(
        shiftedPath.subPixelJacobian,
        shiftedPath.lensVertexJacobian,
        shiftedPath.secondaryPathJacobian,
        0.0f
    );
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 4u)
    ] = vec4(shiftedPath.radiance, 0.0f);
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
    ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 pixel,
    vec2 lensSample,
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
