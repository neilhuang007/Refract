#ifndef PHOTONICS_RESTIR_DI_RESOLVE_GLSL
#define PHOTONICS_RESTIR_DI_RESOLVE_GLSL

// Reference stage 4 helper surface for ResolveReSTIR::execute.

#include "/photonics/lighttree/restir_di_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void ResolveReSTIR_load_curr_reservoir(
    ivec2 reservoirPosition,
    out RTXDI_DIReservoir currReservoir,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    currReservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPosition),
        lt_get_final_shading_input_buffer_index()
    );

    vec4 reconnection0 = texelFetch(current_stage_reconnection0, reservoirPosition, 0);
    vec4 reconnection1 = texelFetch(current_stage_reconnection1, reservoirPosition, 0);
    vec4 sampleData = texelFetch(radiosity_spatial_reservoir_samples, reservoirPosition, 0);

    currReconnectionData = scatter_unpack_reconnection(
        reconnection0,
        reconnection1,
        sampleData,
        currReservoir.transportAux0,
        currReservoir.transportAux1
    );
}

float ResolveReSTIR_computeUCW(
    RTXDI_DIReservoir currReservoir,
    ReservoirSplattingReconnectionData currReconnectionData)
{
    float pHat = ph_luminance(max(currReconnectionData.integrand, vec3(0.0f)));
    return (pHat == 0.0f) ? 0.0f : max(currReservoir.weightSum, 0.0f) / pHat;
}

vec3 ResolveReSTIR(
    RTXDI_DIReservoir currReservoir,
    ReservoirSplattingReconnectionData currReconnectionData)
{
    if (!RTXDI_IsValidDIReservoir(currReservoir)) {
        return vec3(0.0f);
    }

    vec3 integrand = max(currReconnectionData.integrand, vec3(0.0f));
    return integrand * ResolveReSTIR_computeUCW(currReservoir, currReconnectionData);
}

#endif
