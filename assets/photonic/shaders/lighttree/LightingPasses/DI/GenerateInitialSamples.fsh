#version 430

// Reference-aligned Stage 1 wrapper for Reservoir Splatting.
// Mirrors InitialCandidates::run() entry structure while keeping the DI
// candidate construction explicit in this stage.

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_gi_initial_sampling_impl.glsl"

void storeInitialCandidatesResult(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    float sidecarTransportAux0;
    float sidecarTransportAux1;
    scatter_pack_reconnection(
        reconnectionData,
        sidecarTransportAux0,
        sidecarTransportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out
    );

    reservoir.transportAux0 = sidecarTransportAux0;
    reservoir.transportAux1 = sidecarTransportAux1;
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void storeEmptyInitialCandidatesResult()
{
    storeInitialCandidatesResult(
        RTXDI_EmptyDIReservoir(),
        ReservoirSplattingReconnectionData_init()
    );
}

float computeCurrentSubPixelJacobian(RAB_Surface surface)
{
    vec3 currCameraPos = world_camera_position;
    vec3 currCameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    return scatter_compute_subpixel_jacobian(
        surface.worldPos,
        surface.geoNormal,
        currCameraPos,
        currCameraForward
    );
}

ReservoirSplattingReconnectionData buildInitialSelectedReconnection(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel,
    vec3 visibilityRgb)
{
    float subPixelJacobian = computeCurrentSubPixelJacobian(surface);
    ReservoirSplattingReconnectionData reconnectionData = scatter_build_reconnection(
        surface,
        reservoir,
        selectedLightSample,
        pixel,
        1.0f,
        subPixelJacobian
    );
    reconnectionData.irradiance = visibilityRgb;
    reconnectionData.earlyThroughput = visibilityRgb;
    return reconnectionData;
}

RTXDI_DIReservoir buildInitialCandidatesReservoir(
    RAB_Surface surface,
    ivec2 pixel,
    RTXDI_Parameters restirDI,
    RTXDI_RuntimeParameters runtimeParams,
    out ReservoirSplattingReconnectionData reconnectionData)
{
    const uint sampleIdx = 0u;
    RTXDI_RandomSamplerState sg = RTXDI_InitRandomSampler(
        uvec2(pixel),
        runtimeParams.frameIndex,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED + sampleIdx * 0x9e3779b9u
    );
    RTXDI_RandomSamplerState coherentSg = RTXDI_InitRandomSampler(
        uvec2(pixel / RTXDI_TILE_SIZE_IN_PIXELS),
        sampleIdx,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
    );

    RAB_LightSample selectedLightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir reservoir = RTXDI_SampleLightsForSurface(
        sg,
        coherentSg,
        surface,
        restirDI.initialSamplingParams,
        selectedLightSample
    );

    if (!RTXDI_IsValidDIReservoir(reservoir))
    {
        reconnectionData = ReservoirSplattingReconnectionData_init();
        return RTXDI_EmptyDIReservoir();
    }

    vec3 visibilityRgb = max(rtxdi_unpack_visibility(reservoir.packedVisibility), vec3(0.0f));
    reconnectionData = buildInitialSelectedReconnection(
        surface,
        reservoir,
        selectedLightSample,
        pixel,
        visibilityRgb
    );

    reservoir.M = 1.0f;
    return reservoir;
}

void main()
{
    ivec2 reservoirPos = lt_current_reservoir_pos();
    storeEmptyInitialCandidatesResult();

    if (!lt_is_active_reservoir_lane(reservoirPos))
    {
        return;
    }

    const RTXDI_RuntimeParameters runtimeParams = lt_build_runtime_parameters();
    ivec2 pixel = RTXDI_ReservoirPosToPixelPos(
        reservoirPos,
        int(runtimeParams.activeCheckerboardField)
    );
    if (!lt_is_viewport_uv_in_bounds(pixel) || !is_in_world())
    {
        return;
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface))
    {
        return;
    }

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    ReservoirSplattingReconnectionData reconnectionData = ReservoirSplattingReconnectionData_init();
    RTXDI_DIReservoir reservoir = buildInitialCandidatesReservoir(
        surface,
        pixel,
        restirDI,
        runtimeParams,
        reconnectionData
    );
    storeInitialCandidatesResult(reservoir, reconnectionData);
}
