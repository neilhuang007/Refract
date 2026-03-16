// Octray sampler interface.
// Mirrors the ReSTIR sampler declarations so shared composite passes,
// including denoising, remain compatible when PH_LIGHTING_MODE == 3.

uniform sampler2D radiosity_position;
uniform sampler2D radiosity_normal;
uniform sampler2D radiosity_direct;
uniform sampler2D radiosity_direct_soft;
uniform sampler2D radiosity_reservoirs;
uniform sampler2D radiosity_lighting;
uniform sampler2D radiosity_lighting_variance;
uniform sampler2D radiosity_handheld;
uniform sampler2D radiosity_indirect;
uniform sampler2D radiosity_indirect_variance;
uniform sampler2D radiosity_indirect_resolved;
uniform sampler2D radiosity_gi_reservoir_pos;
uniform sampler2D radiosity_gi_reservoir_normal;
uniform sampler2D radiosity_gi_reservoir_radiance;
uniform sampler2D radiosity_gi_reservoir_meta;

uniform sampler2D prev_radiosity_position;
uniform sampler2D prev_radiosity_normal;
uniform sampler2D prev_radiosity_direct;
uniform sampler2D prev_radiosity_direct_soft;
uniform sampler2D prev_radiosity_reservoirs;
uniform sampler2D prev_radiosity_lighting;
uniform sampler2D prev_radiosity_lighting_variance;
uniform sampler2D prev_radiosity_handheld;
uniform sampler2D prev_radiosity_indirect;
uniform sampler2D prev_radiosity_indirect_variance;
uniform sampler2D prev_radiosity_gi_reservoir_pos;
uniform sampler2D prev_radiosity_gi_reservoir_normal;
uniform sampler2D prev_radiosity_gi_reservoir_radiance;
uniform sampler2D prev_radiosity_gi_reservoir_meta;

#if PH_RESTIR_DENOISER_PASSES != 0
uniform sampler2D denoise_color;
uniform sampler2D denoise_variance;
uniform sampler2D indirect_denoise_color;
uniform sampler2D indirect_denoise_variance;

uniform sampler2D prev_denoise_color;
uniform sampler2D prev_denoise_variance;
uniform sampler2D prev_indirect_denoise_color;
uniform sampler2D prev_indirect_denoise_variance;
#endif

vec3 sample_photonics_direct(vec2 tex_coord) {
    return texture2D(radiosity_direct, tex_coord).rgb;
}

vec3 sample_photonics_handheld(vec2 tex_coord) {
    #ifdef PH_ENABLE_HANDHELD_LIGHT
    return texture2D(radiosity_handheld, tex_coord).rgb;
    #else
    return vec3(0f);
    #endif
}

vec3 sample_photonics_indirect(vec2 tex_coord) {
    return texture2D(radiosity_indirect_resolved, tex_coord).rgb;
}
