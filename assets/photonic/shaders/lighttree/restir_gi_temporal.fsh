#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_temporal_position_frag_out;
layout(location = 1) out vec4 indirect_temporal_normal_frag_out;
layout(location = 2) out vec4 indirect_temporal_radiance_frag_out;
layout(location = 3) out vec4 indirect_temporal_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

const int lt_gi_temporal_search_radius = 1;

// RTXDI_JenkinsHash (Math.hlsli:82) — used for permutation sampling
uint RTXDI_JenkinsHash(uint a) {
    a = (a + 0x7ed55d16u) + (a << 12u);
    a = (a ^ 0xc761c23cu) ^ (a >> 19u);
    a = (a + 0x165667b1u) + (a << 5u);
    a = (a + 0xd3a2646cu) ^ (a << 9u);
    a = (a + 0xfd7046c5u) + (a << 3u);
    a = (a ^ 0xb55a4f09u) ^ (a >> 16u);
    return a;
}

// RTXDI_ApplyPermutationSampling (ReservoirAddressing.hlsli:50)
void RTXDI_ApplyPermutationSampling(inout ivec2 prevPixelPos, uint uniformRandomNumber) {
    ivec2 offset = ivec2(uniformRandomNumber & 3u, (uniformRandomNumber >> 2u) & 3u);
    prevPixelPos += offset;
    prevPixelPos.x ^= 3;
    prevPixelPos.y ^= 3;
    prevPixelPos -= offset;
}

void main() {
    if (!is_in_world()) {
        gi_store_invalid(
            indirect_temporal_position_frag_out,
            indirect_temporal_normal_frag_out,
            indirect_temporal_radiance_frag_out,
            indirect_temporal_meta_frag_out
        );
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    DirectSurface currentSurface = lt_current_surface();
    RTXDI_GIReservoir inputReservoir = RTXDI_LoadInitialGIReservoir(tex_coord);

    // Start with empty reservoir
    RTXDI_GIReservoir state = RTXDI_EmptyGIReservoir();
    float selectedTargetPdf = 0.0f;

    // Combine input reservoir (RTXDI always combines, even with targetPdf=0)
    if (RTXDI_IsValidGIReservoir(inputReservoir)) {
        selectedTargetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, inputReservoir.selected);
        RTXDI_CombineGIReservoirs(state, inputReservoir, 0.5f, selectedTargetPdf);
    }

    // Temporal search with RTXDI-style motion vector
    vec4 motionVector = texelFetch(radiosity_motion, tex_coord, 0);
    bool hasMotion = motionVector.a > 0.5f;

    ivec2 prevPos;
    float expectedPrevLinearDepth;
    if (hasMotion) {
        prevPos = ivec2(round(vec2(tex_coord) + motionVector.xy));
        float currentLinearDepth = length(currentSurface.worldPos - world_camera_position);
        expectedPrevLinearDepth = currentLinearDepth + motionVector.z;
    } else {
        vec2 previousBasePixel = ph_reprojectf(
            previous_modelview_projection,
            currentSurface.worldPos + currentSurface.geometryNormal * 0.01f,
            vec2(viewWidth, viewHeight),
            get_taa_jitter()
        );
        prevPos = ivec2(round(previousBasePixel));
        expectedPrevLinearDepth = length(currentSurface.worldPos - previous_world_camera_position);
    }

    float maxAge = lt_indirect_max_age * (0.5f + rand_next_float() * 0.5f);
    int temporalSampleStartIdx = int(rand_next_float() * 8.0f);
    uint uniformRandomNumber = RTXDI_JenkinsHash(uint(frameCounter));

    RTXDI_GIReservoir temporalReservoir = RTXDI_EmptyGIReservoir();
    DirectSurface temporalSurface = currentSurface;
    bool foundTemporalReservoir = false;

    // Search 5 temporal taps + 1 fallback = 6 total
    for (int i = 0; i < 6; i++) {
        bool isFirstSample = (i == 0);
        bool isFallbackSample = (i == 5);

        ivec2 sampleUv;
        if (isFallbackSample) {
            sampleUv = tex_coord;
            RTXDI_ApplyPermutationSampling(sampleUv, uniformRandomNumber);
        } else if (isFirstSample) {
            sampleUv = prevPos;
        } else {
            sampleUv = prevPos + lt_calculate_temporal_resampling_offset(temporalSampleStartIdx + i, lt_gi_temporal_search_radius);
        }

        if (!lt_is_viewport_uv_in_bounds(sampleUv)) continue;

        DirectSurface candidateSurface = lt_load_previous_surface(sampleUv);
        if (!lt_is_valid_surface(candidateSurface)) {
            continue;
        }

        // Surface similarity test (skip geometric test for fallback, but use RTXDI depth matching)
        if (!isFallbackSample) {
            if (hasMotion) {
                // Use RTXDI-style expected depth matching
                if (!RTXDI_IsValidTemporalNeighbor(currentSurface, candidateSurface, expectedPrevLinearDepth, lt_gi_normal_threshold, lt_depth_threshold)) {
                    continue;
                }
            } else {
                if (!lt_surface_matches_temporal(currentSurface, candidateSurface, lt_depth_threshold, lt_gi_normal_threshold)) {
                    continue;
                }
            }
        }

        if (!lt_materials_similar(currentSurface, candidateSurface)) {
            continue;
        }

        RTXDI_GIReservoir candidateReservoir = RTXDI_LoadGIReservoir(
            prev_radiosity_indirect_reservoir_position,
            prev_radiosity_indirect_reservoir_normal,
            prev_radiosity_indirect_reservoir_radiance,
            prev_radiosity_indirect_reservoir_meta,
            sampleUv
        );

        if (!RTXDI_IsValidGIReservoir(candidateReservoir)) continue;

        temporalReservoir = candidateReservoir;
        temporalSurface = candidateSurface;
        foundTemporalReservoir = true;
        break;
    }

    // Post-loop: apply Jacobian, clamp M, increment age, check age limit
    bool selectedPreviousSample = false;

    if (foundTemporalReservoir) {
        float jacobian = RTXDI_GICalculateJacobian(currentSurface, temporalSurface, temporalReservoir.selected);
        if (jacobian <= 0.0f) {
            foundTemporalReservoir = false;
        } else {
            temporalReservoir.weight_sum *= jacobian;
            temporalReservoir.samples = min(temporalReservoir.samples, lt_indirect_max_history);
            temporalReservoir.age += 1.0f;
            if (temporalReservoir.age > maxAge) {
                foundTemporalReservoir = false;
            }
        }
    }

    if (foundTemporalReservoir) {
        float targetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, temporalReservoir.selected);
        selectedPreviousSample = RTXDI_CombineGIReservoirs(state, temporalReservoir, rand_next_float(), targetPdf);
        if (selectedPreviousSample) {
            selectedTargetPdf = targetPdf;
        }
    }

    // BASIC bias correction normalization (always applied)
    if (RTXDI_IsValidGIReservoir(state) && foundTemporalReservoir) {
        float pi = selectedTargetPdf;
        float piSum = selectedTargetPdf * inputReservoir.samples;

        float temporalP = RAB_GetGISampleTargetPdfForSurface(temporalSurface, state.selected);
        pi = selectedPreviousSample ? temporalP : pi;
        piSum += temporalP * temporalReservoir.samples;

        RTXDI_FinalizeGIResampling(state, pi, piSum * selectedTargetPdf);
    } else {
        RTXDI_FinalizeGIResampling(state, 1.0f, selectedTargetPdf * state.samples);
    }

    // Output (no fallback - RTXDI always returns the resampled result)
    RTXDI_StoreGIReservoir(
        state,
        indirect_temporal_position_frag_out,
        indirect_temporal_normal_frag_out,
        indirect_temporal_radiance_frag_out,
        indirect_temporal_meta_frag_out
    );
}
