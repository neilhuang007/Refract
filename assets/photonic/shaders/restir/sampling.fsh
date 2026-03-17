#version 430

/*
    -- INPUT VARIABLES --
*/
in vec4 direction_vert_out;

/*
    -- OUTPUT VARIABLES --
*/
layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 reservoir_frag_out;
layout(location = 4) out vec4 gi_reservoir_pos_frag_out;
layout(location = 5) out vec4 gi_reservoir_normal_frag_out;
layout(location = 6) out vec4 gi_reservoir_radiance_frag_out;
layout(location = 7) out vec4 gi_reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
vec3 ph_sun_direction = ph_signed_nudge(sun_direction);
#include "/photonics/restir/restir.glsl"
#include "/photonics/common/lighting.glsl"

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0f);
        normal_frag_out = vec4(0f);
        mapped_normal_frag_out = vec4(0f);
        reservoir_frag_out = vec4(0f);
        gi_reservoir_pos_frag_out = vec4(0f);
        gi_reservoir_normal_frag_out = vec4(0f);
        gi_reservoir_radiance_frag_out = vec4(0f);
        gi_reservoir_meta_frag_out = vec4(0f);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    position_frag_out = vec4(world_pos, 1f);
    normal_frag_out = vec4(block_normal, 1f);
    mapped_normal_frag_out = vec4(normal, 1f);

    Reservoir reservoir = reservoir_new();
    if (ph_light_count > 0) {
        reservoir_init(reservoir);
    }

    Reservoir previous_reservoir = reservoir_new();
    bool canReuseTemporal = !light_reload && reservoir_reproject(previous_reservoir);

    if (canReuseTemporal) {
        Reservoir temporal_reservoir = reservoir_new();

        if (reservoir_is_valid(reservoir)) {
            reservoir_compute_weight(reservoir);

            reservoir_update(
                temporal_reservoir,
                reservoir.light,
                reservoir.light.weight * reservoir.weight * reservoir.samples,
                reservoir.samples
            );
        }

        // Dirty regions keep some temporal reuse instead of hard-resetting to
        // a single frame, which avoids the bright speckle burst after edits.
        float temporalCap = 20.0f;
        float capped_samples = min(temporalCap * reservoir.samples, previous_reservoir.samples);
        if (previous_reservoir.samples > 0f && capped_samples < previous_reservoir.samples) {
            previous_reservoir.weight_sum *= capped_samples / previous_reservoir.samples;
        }
        previous_reservoir.samples = capped_samples;

        reservoir_update(
            temporal_reservoir,
            previous_reservoir.light,
            previous_reservoir.light.weight * previous_reservoir.weight * previous_reservoir.samples,
            previous_reservoir.samples
        );

        reservoir = temporal_reservoir;
    }

    reservoir_compute_weight(reservoir);
    reservoir_frag_out = reservoir_encode(reservoir);

    GIReservoir giReservoir = gi_reservoir_new();
    gi_reservoir_init(giReservoir);
    gi_reservoir_compute_weight(giReservoir);

    GIReservoir previousGiReservoir = gi_reservoir_new();
    vec3 previousGiSourcePosition = vec3(0.0f);
    vec3 previousGiSourceNormal = vec3(0.0f);
    bool canReuseIndirectTemporal = !light_reload
        && gi_reservoir_reproject(previousGiReservoir, previousGiSourcePosition, previousGiSourceNormal);

    if (canReuseIndirectTemporal) {
        GIReservoir temporalGiReservoir = gi_reservoir_new();
        float currentGiSamples = giReservoir.samples;
        bool currentGiContributed = false;
        if (gi_reservoir_is_valid(giReservoir)) {
            currentGiContributed = true;
            gi_reservoir_update(
                temporalGiReservoir,
                giReservoir.giSample,
                gi_sample_target(giReservoir.giSample) * giReservoir.weight * giReservoir.samples,
                giReservoir.samples,
                0.0f
            );
        }

        float previousGiSamples = 0.0f;
        bool previousGiContributed = false;
        if (gi_reservoir_is_valid(previousGiReservoir)
            && gi_sample_has_conservative_visibility_from_surface(
                previousGiReservoir.giSample,
                previousGiSourcePosition,
                previousGiSourceNormal
            )) {
            float candidateJacobian = gi_jacobian(previousGiSourcePosition, previousGiReservoir.giSample);
            if (gi_validate_jacobian(candidateJacobian)) {
                float currentSamples = max(giReservoir.samples, 1.0f);
                previousGiReservoir.samples = min(previousGiReservoir.samples, PH_RESTIR_GI_MAX_HISTORY * currentSamples);
                previousGiSamples = previousGiReservoir.samples;
                previousGiContributed = previousGiSamples > 0.0f;
                gi_reservoir_update(
                    temporalGiReservoir,
                    previousGiReservoir.giSample,
                    gi_sample_target(previousGiReservoir.giSample) * previousGiReservoir.weight * previousGiReservoir.samples / candidateJacobian,
                    previousGiReservoir.samples,
                    min(previousGiReservoir.age + 1.0f, PH_RESTIR_GI_MAX_HISTORY)
                );
            }
        }

        giReservoir = temporalGiReservoir;
        float normalizationDenominator = 0.0f;
        if (gi_sample_is_valid(giReservoir.giSample)) {
            if (currentGiContributed) {
                normalizationDenominator += currentGiSamples * gi_sample_target(giReservoir.giSample);
            }

            if (previousGiContributed) {
                normalizationDenominator += previousGiSamples * gi_sample_target_from_source_surface(
                    giReservoir.giSample,
                    previousGiSourcePosition,
                    previousGiSourceNormal
                );
            }
        }

        gi_reservoir_finalize(giReservoir, normalizationDenominator);
    }

    gi_reservoir_encode(
        giReservoir,
        gi_reservoir_pos_frag_out,
        gi_reservoir_normal_frag_out,
        gi_reservoir_radiance_frag_out,
        gi_reservoir_meta_frag_out
    );
}
