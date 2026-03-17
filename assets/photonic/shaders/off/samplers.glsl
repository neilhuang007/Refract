uniform float ph_debug_show_direct;
uniform float ph_debug_show_indirect;
uniform float ph_debug_show_handheld;
uniform float ph_debug_show_denoiser;

vec3 sample_photonics_direct(vec2 tex_coord) {
    return vec3(0f);
}

vec3 sample_photonics_handheld(vec2 tex_coord) {
    return vec3(0f);
}

vec3 sample_photonics_indirect(vec2 tex_coord) {
    return vec3(0f);
}
