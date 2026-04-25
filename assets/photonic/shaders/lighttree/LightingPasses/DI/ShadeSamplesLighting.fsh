#version 430

// Reference stage 7 -- ResolveReSTIR::execute

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_resolve.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

const float ph_nrd_spec_fp16_safe_luma = 248.0;

vec3 ph_clamp_specular_for_relax(vec3 demodulatedSpecular) {
    demodulatedSpecular = max(demodulatedSpecular, vec3(0.0));
    float specularLuma = nrd_luminance(demodulatedSpecular);
    if (specularLuma > ph_nrd_spec_fp16_safe_luma) {
        demodulatedSpecular *= ph_nrd_spec_fp16_safe_luma / max(specularLuma, 1e-6);
    }
    return demodulatedSpecular;
}

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

    ResolveReSTIRShading shading;
    if (!ResolveReSTIR_shade(currReservoir, surface, shading)) {
        storeEmptyResolveReSTIROutputs();
        return;
    }

    vec3 demodulatedSpecular = shading.specular / max(lt_surface_f0(surface), vec3(0.01f));
    demodulatedSpecular = ph_clamp_specular_for_relax(demodulatedSpecular);

    direct_diffuse_frag_out = nrd_pack_direct_signal(shading.diffuse, shading.hitDistance);
    direct_specular_frag_out = nrd_pack_direct_signal(demodulatedSpecular, shading.hitDistance);
}
