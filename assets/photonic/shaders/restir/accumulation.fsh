#version 430

/*
    -- INPUT VARIABLES --
*/
in vec4 direction_vert_out;

/*
    -- OUTPUT VARIABLES --
*/
layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 lighting_frag_out;
layout(location = 2) out vec4 lighting_variance_frag_out;

#ifdef PH_ENABLE_HANDHELD_LIGHT
layout(location = 3) out vec4 handheld_frag_out;
#define PH_INDIRECT_OUT_LOCATION 4
#define PH_DIRECT_OUT_LOCATION 5
#define PH_INDIRECT_VARIANCE_OUT_LOCATION 6
#else
#define PH_INDIRECT_OUT_LOCATION 3
#define PH_DIRECT_OUT_LOCATION 4
#define PH_INDIRECT_VARIANCE_OUT_LOCATION 5
#endif

layout(location = PH_INDIRECT_OUT_LOCATION) out vec4 indirect_frag_out;
layout(location = PH_DIRECT_OUT_LOCATION) out vec4 direct_frag_out;
layout(location = PH_INDIRECT_VARIANCE_OUT_LOCATION) out vec4 indirect_variance_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/restir/restir.glsl"

uniform sampler2D stage_radiosity_reservoirs;
uniform sampler2D stage_radiosity_lighting;
uniform sampler2D stage_radiosity_indirect;

#ifdef PH_ENABLE_HANDHELD_LIGHT
uniform sampler2D stage_radiosity_handheld;
#endif

void main() {
    if (!is_in_world()) {
        reservoir_frag_out = vec4(0f);
        lighting_frag_out = vec4(0f);
        lighting_variance_frag_out = vec4(0f);
        indirect_frag_out = vec4(0f);
        direct_frag_out = vec4(0f);
        indirect_variance_frag_out = vec4(0f);
        #ifdef PH_ENABLE_HANDHELD_LIGHT
        handheld_frag_out = vec4(0f);
        #endif
        return;
    }

    reservoir_frag_out = texelFetch(stage_radiosity_reservoirs, tex_coord, 0);
    #ifdef PH_ENABLE_HANDHELD_LIGHT
    handheld_frag_out = texelFetch(stage_radiosity_handheld, tex_coord, 0);
    #endif

    if (ph_light_count == 0) {
        lighting_frag_out = vec4(0f);
        lighting_variance_frag_out = vec4(0f);
        direct_frag_out = vec4(0f);
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    // --- Indirect temporal accumulation ---
    vec4 currentIndirect = texelFetch(stage_radiosity_indirect, tex_coord, 0);
    if (currentIndirect.a > 0.0f) {
        vec2 reproj_uv = ph_reprojectf(
            previous_modelview_projection,
            world_pos + block_normal * 0.01f,
            vec2(viewWidth, viewHeight),
            get_taa_jitter()
        );
        ivec2 prev_uv = ivec2(reproj_uv);
        ivec2 ind_tex_size = textureSize(prev_radiosity_indirect, 0);
        bool canReuseIndirect = !light_reload
            && all(greaterThanEqual(prev_uv, ivec2(0)))
            && all(lessThan(prev_uv, ind_tex_size));

        if (canReuseIndirect) {
            vec3 prev_n = texelFetch(prev_radiosity_normal, prev_uv, 0).xyz;
            vec3 prev_pos = texelFetch(prev_radiosity_position, prev_uv, 0).xyz;
            canReuseIndirect = dot(prev_n, block_normal) > 0.975f
                && ph_surface_positions_compatible(world_pos, prev_pos, 0.2f);
        }

        if (canReuseIndirect) {
            vec4 prevIndirect = texelFetch(prev_radiosity_indirect, prev_uv, 0);
            vec4 prevVariance = texelFetch(prev_radiosity_indirect_variance, prev_uv, 0);
            float prevHistory = prevIndirect.a;

            if (prevHistory > 0.0f && !any(isnan(prevIndirect))) {
                float maxHistory = float(PH_RESTIR_ACCUMULATION_FRAMES);
                float history = min(prevHistory + 1.0f, maxHistory);
                float alpha = max(1.0f / history, 0.05f);

                vec3 blended = mix(prevIndirect.rgb, currentIndirect.rgb, alpha);
                indirect_frag_out = vec4(blended, history);

                // Variance moments
                float momentAlpha = clamp(1.0f / history, 0.05f, 1.0f);
                float currentLuma = dot(currentIndirect.rgb, PH_HISTORY_LUMA_COEFF);
                vec2 moments = vec2(currentLuma, currentLuma * currentLuma);
                vec2 blendedMoments = mix(prevVariance.xy, moments, momentAlpha);
                float variance = max(blendedMoments.y - blendedMoments.x * blendedMoments.x, 0.0f);
                float confidence = clamp((history - 1.0f) / max(maxHistory - 1.0f, 1.0f), 0.0f, 1.0f);
                indirect_variance_frag_out = vec4(blendedMoments.x, blendedMoments.y, variance, confidence);
            } else {
                indirect_frag_out = currentIndirect;
                float lum = dot(currentIndirect.rgb, PH_HISTORY_LUMA_COEFF);
                indirect_variance_frag_out = vec4(lum, lum * lum, 0.0f, 0.0f);
            }
        } else {
            indirect_frag_out = currentIndirect;
            float lum = dot(currentIndirect.rgb, PH_HISTORY_LUMA_COEFF);
            indirect_variance_frag_out = vec4(lum, lum * lum, 0.0f, 0.0f);
        }
    } else {
        indirect_frag_out = vec4(0f);
        indirect_variance_frag_out = vec4(0f);
    }

    if (ph_light_count == 0) {
        return;
    }

    // --- Direct temporal accumulation (existing logic) ---
    SampleHistory smple = SampleHistory(texelFetch(stage_radiosity_lighting, tex_coord, 0), vec4(0f));
    SampleHistory accumulator = SampleHistory(vec4(0f), vec4(0f));
    sample_history_reproject(accumulator);
    sample_history_combine_lighting(accumulator, smple);

    #if PH_RESTIR_DENOISER_PASSES != 0
    sample_history_combine_moment(accumulator, smple);
    sample_history_compute_variance(accumulator, smple);
    #endif

    lighting_frag_out = accumulator.lighting;
    lighting_variance_frag_out = accumulator.variance;
    direct_frag_out = vec4(accumulator.lighting.rgb, 1f);
}
