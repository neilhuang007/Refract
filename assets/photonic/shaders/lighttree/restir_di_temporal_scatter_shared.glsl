#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_SHARED_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_SHARED_GLSL

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

struct ShiftedPathData {
    vec3 primaryHit;
    vec3 firstRayDir;
    vec3 radiance;
    vec2 fractionalPixel;
    vec2 subPixel;
    vec2 lensSample;
    float subPixelJacobian;
    float secondaryPathJacobian;
    float lensVertexJacobian;
};

ShiftedPathData gatherLensVertexCopyShift(
    RTXDI_RandomSamplerState rng,
    ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 pixel,
    vec2 lensSample);

ReservoirSplattingReconnectionData ScatterTemporalReconnectionData_update(
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
