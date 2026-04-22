#version 430

// Reference stage 7 -- ResolveReSTIR::execute

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_resolve.glsl"

void storeEmptyResolveReSTIROutputs()
{
    direct_diffuse_frag_out = vec4(0.0f);
    direct_specular_frag_out = vec4(0.0f);
}

void main()
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 pixel = lt_fragment_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        storeEmptyResolveReSTIROutputs();
        return;
    }

    bool isActiveCheckerboardPixel = RTXDI_IsActiveCheckerboardPixel(
        pixel, false, int(runtimeParameters.activeCheckerboardField));
    if (!isActiveCheckerboardPixel) {
        storeEmptyResolveReSTIROutputs();
        return;
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface)) {
        storeEmptyResolveReSTIROutputs();
        return;
    }

    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(
        pixel, int(runtimeParameters.activeCheckerboardField));

    RTXDI_DIReservoir currReservoir;
    ResolveReSTIR_load_curr_reservoir(reservoirPosition, currReservoir);

    float shadingHitDistance = max(surface.viewDepth, 0.0f);
    vec3 color = ResolveReSTIR(currReservoir);

    if (lt_build_restir_di_parameters().shadingParams.enableDenoiserInputPacking != 0u) {
        direct_diffuse_frag_out = nrd_pack_direct_signal(color, shadingHitDistance);
        direct_specular_frag_out = nrd_pack_direct_signal(vec3(0.0f), shadingHitDistance);
    } else {
        direct_diffuse_frag_out = vec4(color, shadingHitDistance);
        direct_specular_frag_out = vec4(0.0f, 0.0f, 0.0f, shadingHitDistance);
    }
}
