#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;
layout(location = 5) out vec4 initial_debug_frag_out;

#include "/photonics/common/header.glsl"
 #include "/photonics/lighttree/restir_di_bridge.glsl"

void storeDIReservoir(RTXDI_DIReservoir reservoir, ScatterReconnectionData reconnection) {
    scatter_pack_reconnection(
        reconnection,
        reservoir.transportAux0,
        reservoir.transportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out
    );
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

const int LT_INITIAL_DEBUG_INVALID_SURFACE = 0;
const int LT_INITIAL_DEBUG_NO_LIGHTS = 1;
const int LT_INITIAL_DEBUG_NO_LOCAL_SAMPLES = 2;
const int LT_INITIAL_DEBUG_INVALID_LIGHT_SELECTION = 3;
const int LT_INITIAL_DEBUG_INVALID_LIGHT_SAMPLE = 4;
const int LT_INITIAL_DEBUG_ZERO_RADIANCE = 5;
const int LT_INITIAL_DEBUG_ZERO_SOURCE_PDF = 6;
const int LT_INITIAL_DEBUG_ZERO_TARGET_PDF = 7;
const int LT_INITIAL_DEBUG_NONFINITE_SOURCE_PDF = 8;
const int LT_INITIAL_DEBUG_NONFINITE_TARGET_PDF = 9;
const int LT_INITIAL_DEBUG_SUCCESS = 10;

struct LtInitialSamplingDebugInfo {
    int reason;
    float positiveCandidateFraction;
    float proposalValid;
    float proposalWeight;
};

bool lt_is_finite_float(float value) {
    return value == value && abs(value) < 3.402823466e+38f;
}

void storeDIReservoir(
    RTXDI_DIReservoir reservoir,
    ScatterReconnectionData reconnection,
    LtInitialSamplingDebugInfo debugInfo
) {
    storeDIReservoir(reservoir, reconnection);
    initial_debug_frag_out = vec4(
        float(debugInfo.reason),
        debugInfo.positiveCandidateFraction,
        debugInfo.proposalValid,
        debugInfo.proposalWeight
    );
}

LtInitialSamplingDebugInfo lt_debug_diagnose_initial_local_samples(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    RAB_Surface surface,
    ivec2 pixelPosition,
    RTXDI_DIInitialSamplingParameters initialSamplingParams)
{
    LtInitialSamplingDebugInfo debugInfo;
    debugInfo.reason = LT_INITIAL_DEBUG_INVALID_SURFACE;
    debugInfo.positiveCandidateFraction = 0.0f;
    debugInfo.proposalValid = 0.0f;
    debugInfo.proposalWeight = 0.0f;

    if (!RAB_IsSurfaceValid(surface)) {
        return debugInfo;
    }

    RTXDI_LightBufferRegion localLightBufferRegion = RTXDI_GetLocalLightBufferRegion();
    if (localLightBufferRegion.numLights == 0u) {
        debugInfo.reason = LT_INITIAL_DEBUG_NO_LIGHTS;
        return debugInfo;
    }

    if (initialSamplingParams.numLocalLightSamples == 0u) {
        debugInfo.reason = LT_INITIAL_DEBUG_NO_LOCAL_SAMPLES;
        return debugInfo;
    }

    debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SELECTION;
    return debugInfo;
}

void main() {
    ivec2 GlobalIndex = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(GlobalIndex)) {
        storeDIReservoir(
            RTXDI_EmptyDIReservoir(),
            scatter_empty_reconnection(),
            LtInitialSamplingDebugInfo(LT_INITIAL_DEBUG_INVALID_SURFACE, 0.0f, 0.0f, 0.0f)
        );
        return;
    }

    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, int(params.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeDIReservoir(
            RTXDI_EmptyDIReservoir(),
            scatter_empty_reconnection(),
            LtInitialSamplingDebugInfo(LT_INITIAL_DEBUG_INVALID_SURFACE, 0.0f, 0.0f, 0.0f)
        );
        return;
    }

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(uvec2(pixelPosition), params.frameIndex, RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    RTXDI_RandomSamplerState tileRng = RTXDI_InitRandomSampler(uvec2(pixelPosition / RTXDI_TILE_SIZE_IN_PIXELS), 0u, RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    RTXDI_RandomSamplerState debugRng = rng;
    RTXDI_RandomSamplerState debugTileRng = tileRng;
    LtInitialSamplingDebugInfo debugInfo = lt_debug_diagnose_initial_local_samples(
        debugRng,
        debugTileRng,
        surface,
        pixelPosition,
        restirDI.initialSamplingParams
    );
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    ScatterReconnectionData reconnection = scatter_empty_reconnection();
    RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

    if (RAB_IsSurfaceValid(surface)) {
        reservoir = RTXDI_SampleLightsForSurface(
            rng,
            tileRng,
            surface,
            restirDI.initialSamplingParams,
            selectedLightSample
        );
        reservoir.spatialDistance = ivec2(0);
        // Seed the area-domain payload from the actual per-pixel stochastic sample state.
        // Area ReSTIR and future reservoir splatting both need stable pixel/lens payloads
        // that describe the selected proposal domain instead of a canonical placeholder.
        lt_area_seed_domain_samples(reservoir, rng, pixelPosition, reservoir.pathSample);

        vec3 currCameraPos = world_camera_position;
        vec3 currCameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
        float subPixelJacobian = scatter_compute_subpixel_jacobian(
            surface.worldPos,
            surface.geoNormal,
            currCameraPos,
            currCameraForward
        );
        reconnection = scatter_build_reconnection(
            surface,
            reservoir,
            selectedLightSample,
            pixelPosition,
            scatter_clamp_reconnection_confidence(lt_area_confidence_from_samples(reservoir.M)),
            subPixelJacobian
        );
    }

    debugInfo.proposalValid = RTXDI_IsValidDIReservoir(reservoir) ? 1.0f : 0.0f;
    debugInfo.proposalWeight = reservoir.weightSum;
    debugInfo.positiveCandidateFraction = debugInfo.proposalValid;
    if (RAB_IsSurfaceValid(surface)) {
        if (RTXDI_IsValidDIReservoir(reservoir)) {
            debugInfo.reason = LT_INITIAL_DEBUG_SUCCESS;
        } else if (selectedLightSample.index < 0) {
            debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SELECTION;
        } else if (!lt_is_finite_float(selectedLightSample.weight)) {
            debugInfo.reason = LT_INITIAL_DEBUG_NONFINITE_TARGET_PDF;
        } else if (selectedLightSample.weight <= 0.0f) {
            debugInfo.reason = LT_INITIAL_DEBUG_ZERO_TARGET_PDF;
        } else {
            debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SAMPLE;
        }
    }

    storeDIReservoir(reservoir, reconnection, debugInfo);
}
