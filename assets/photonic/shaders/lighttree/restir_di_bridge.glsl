#ifndef PHOTONICS_RESTIR_DI_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_BRIDGE_GLSL

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_temporal.glsl"
#include "/photonics/lighttree/restir_di_spatial.glsl"
#include "/photonics/lighttree/restir_di_spatial_impl.glsl"

RTXDI_DIReservoir lt_area_spatial_resampling(
    ivec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng)
{
    if (!RAB_IsSurfaceValid(centerSurface) || !RTXDI_IsValidDIReservoir(centerSample)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

    RTXDI_DIReservoir result = RTXDI_DISpatialResampling(
        uvec2(pixelPosition),
        centerSurface,
        centerSample,
        rng,
        params,
        restirDI.reservoirBufferParams,
        restirDI.bufferIndices.spatialResamplingInputBufferIndex,
        restirDI.spatialResamplingParams,
        selectedLightSample
    );

    if (!RTXDI_IsValidDIReservoir(result)) {
        return centerSample;
    }

    return result;
}

#endif

