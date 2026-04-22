#ifndef PHOTONICS_RESTIR_DI_RESOLVE_GLSL
#define PHOTONICS_RESTIR_DI_RESOLVE_GLSL

// Reference stage 4 helper surface for ResolveReSTIR::execute.

#include "/photonics/lighttree/restir_di_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void ResolveReSTIR_load_curr_reservoir(
    ivec2 reservoirPosition,
    out RTXDI_DIReservoir currReservoir)
{
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    currReservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPosition),
        lt_get_final_shading_input_buffer_index()
    );
}

float ResolveReSTIR_computeUCW(
    RTXDI_DIReservoir currReservoir)
{
    return PathReservoir_computeStoredUCW(currReservoir);
}

vec3 ResolveReSTIR(
    RTXDI_DIReservoir currReservoir)
{
    if (!RTXDI_IsValidDIReservoir(currReservoir)) {
        return vec3(0.0f);
    }

    return PathReservoir_getIntegrand(currReservoir)
        * ResolveReSTIR_computeUCW(currReservoir);
}

#endif
