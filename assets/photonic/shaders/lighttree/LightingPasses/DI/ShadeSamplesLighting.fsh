#version 430

// Reference stage module -- ResolveReSTIR.cs.slang

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;
layout(location = 2) out vec4 direct_combined_frag_out;

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
    direct_combined_frag_out = vec4(0.0f);
}

void main()
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 pixel = lt_fragment_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        storeEmptyResolveReSTIROutputs();
        return;
    }

    // Lighting writes to a full-res FBO; the reservoir buffer is half-width when
    // checkerboard is active. RTXDI's reference dispatches over the half-res reservoir
    // grid (one thread per reservoir => one shaded pixel per pair), but we dispatch at
    // full-res via gl_FragCoord. So both checkerboard mates load the shared reservoir
    // at (x>>1, y) and shade against their own gbuffer surface. Zeroing inactive pixels
    // here would leave half the screen black because there is no reconstruction pass.
    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface)) {
        storeEmptyResolveReSTIROutputs();
        return;
    }

    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(
        pixel, int(runtimeParameters.activeCheckerboardField));

    RTXDI_DIReservoir currReservoir;
    ResolveReSTIRShading shading;
    if (!ResolveReSTIR_execute(reservoirPosition, surface, currReservoir, shading)) {
        storeEmptyResolveReSTIROutputs();
        return;
    }

    vec3 demodulatedSpecular = shading.specular / max(lt_surface_f0(surface), vec3(0.01f));
    demodulatedSpecular = ph_clamp_specular_for_relax(demodulatedSpecular);

    vec3 diffuseSignal = nrd_clamp_direct_firefly(shading.diffuse);
    vec3 specularSignal = nrd_clamp_direct_firefly(demodulatedSpecular);
    vec3 combinedDirect =
        nrd_safe_remodulate(diffuseSignal, nrd_compute_diffuse_demodulation(surface.material.diffuseAlbedo)) +
        nrd_safe_remodulate(specularSignal, max(lt_surface_f0(surface), vec3(0.01f)));

    direct_diffuse_frag_out = nrd_pack_direct_signal(diffuseSignal, shading.hitDistance);
    direct_specular_frag_out = nrd_pack_direct_signal(specularSignal, shading.hitDistance);
    direct_combined_frag_out = vec4(clamp(combinedDirect, vec3(0.0f), vec3(NRD_FP16_MAX)), shading.hitDistance);
}
