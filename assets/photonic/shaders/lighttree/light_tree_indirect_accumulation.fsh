#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_frag_out;
layout(location = 1) out vec4 indirect_variance_frag_out;
layout(location = 2) out vec4 handheld_frag_out;
layout(location = 3) out vec4 indirect_reservoir_position_frag_out;
layout(location = 4) out vec4 indirect_reservoir_normal_frag_out;
layout(location = 5) out vec4 indirect_reservoir_radiance_frag_out;
layout(location = 6) out vec4 indirect_reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

const int lt_gi_spatial_sample_count = 2;

void main() {
    handheld_frag_out = vec4(0.0f);
    gi_store_invalid(
        indirect_reservoir_position_frag_out,
        indirect_reservoir_normal_frag_out,
        indirect_reservoir_radiance_frag_out,
        indirect_reservoir_meta_frag_out
    );

    if (!is_in_world()) {
        indirect_frag_out = vec4(0.0f);
        indirect_variance_frag_out = vec4(0.0f);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    handheld_frag_out = lt_build_handheld_stage();

    DirectSurface currentSurface = lt_current_surface();
    RTXDI_GIReservoir initialReservoir = RTXDI_LoadInitialGIReservoir(tex_coord);
    if (!RTXDI_IsValidGIReservoir(initialReservoir)) {
        initialReservoir = gi_build_initial_reservoir(currentSurface);
    }

    RTXDI_GIReservoir currentReservoir = RTXDI_LoadGIReservoir(
        radiosity_indirect_temporal_position,
        radiosity_indirect_temporal_normal,
        radiosity_indirect_temporal_radiance,
        radiosity_indirect_temporal_meta,
        tex_coord
    );

    RTXDI_GIReservoir state = RTXDI_EmptyGIReservoir();
    float selectedTargetPdf = 0.0f;
    float inputM = 0.0f;
    if (RTXDI_IsValidGIReservoir(currentReservoir)) {
        selectedTargetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, currentReservoir.selected);
        RTXDI_CombineGIReservoirs(state, currentReservoir, 0.5f, selectedTargetPdf);
        inputM = currentReservoir.samples;
    }

    int acceptedMask = 0;
    int selectedNeighborIndex = -1;
    int neighborSampleStartIdx = int(rand_next_float() * float(lt_neighbor_offset_count));

    for (int i = 0; i < lt_gi_spatial_sample_count; i++) {
        ivec2 spatialOffset = lt_calculate_spatial_resampling_offset(
            neighborSampleStartIdx + i,
            lt_gi_spatial_reuse_radius()
        );
        ivec2 neighborUv = tex_coord + spatialOffset;
        neighborUv = clamp(neighborUv, ivec2(0), ivec2(viewWidth - 1, viewHeight - 1));

        DirectSurface neighborSurface = lt_load_surface(neighborUv);
        if (!lt_surface_matches(currentSurface, neighborSurface, lt_depth_threshold, lt_gi_normal_threshold)) {
            continue;
        }

        if (!lt_materials_similar(currentSurface, neighborSurface)) {
            continue;
        }

        RTXDI_GIReservoir neighborReservoir = RTXDI_LoadGIReservoir(
            radiosity_indirect_temporal_position,
            radiosity_indirect_temporal_normal,
            radiosity_indirect_temporal_radiance,
            radiosity_indirect_temporal_meta,
            neighborUv
        );
        if (!RTXDI_IsValidGIReservoir(neighborReservoir)) {
            continue;
        }

        float jacobian = RTXDI_GICalculateJacobian(currentSurface, neighborSurface, neighborReservoir.selected);
        if (jacobian <= 0.0f) {
            continue;
        }

        float targetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, neighborReservoir.selected);

        neighborReservoir.weight_sum *= jacobian;
        acceptedMask |= (1 << i);

        if (RTXDI_CombineGIReservoirs(state, neighborReservoir, rand_next_float(), targetPdf)) {
            selectedTargetPdf = targetPdf;
            selectedNeighborIndex = i;
        }
    }

    {
        float normalizationNumerator = 1.0f;
        float normalizationDenominator = state.samples * selectedTargetPdf;

        if (acceptedMask != 0) {
            float pi = selectedTargetPdf;
            float piSum = selectedTargetPdf * inputM;

            for (int i = 0; i < lt_gi_spatial_sample_count; i++) {
                if ((acceptedMask & (1 << i)) == 0) {
                    continue;
                }

                ivec2 spatialOffset = lt_calculate_spatial_resampling_offset(
                    neighborSampleStartIdx + i,
                    lt_gi_spatial_reuse_radius()
                );
                ivec2 neighborUv = tex_coord + spatialOffset;
                neighborUv = clamp(neighborUv, ivec2(0), ivec2(viewWidth - 1, viewHeight - 1));
                DirectSurface neighborSurface = lt_load_surface(neighborUv);
                RTXDI_GIReservoir neighborReservoir = RTXDI_LoadGIReservoir(
                    radiosity_indirect_temporal_position,
                    radiosity_indirect_temporal_normal,
                    radiosity_indirect_temporal_radiance,
                    radiosity_indirect_temporal_meta,
                    neighborUv
                );

                float ps = RAB_GetGISampleTargetPdfForSurface(neighborSurface, state.selected);
                if (selectedNeighborIndex == i) {
                    pi = ps;
                }
                piSum += ps * neighborReservoir.samples;
            }

            normalizationNumerator = pi;
            normalizationDenominator = piSum * selectedTargetPdf;
        }

        RTXDI_FinalizeGIResampling(state, normalizationNumerator, normalizationDenominator);
    }

    if (!RTXDI_IsValidGIReservoir(state)) {
        indirect_frag_out = vec4(0.0f);
        indirect_variance_frag_out = vec4(0.0f);
        return;
    }

    vec3 shadedDiffuse = vec3(0.0f);
    vec3 shadedSpecular = vec3(0.0f);
    gi_shade_reservoir(currentSurface, state, initialReservoir, shadedDiffuse, shadedSpecular);

    // Demodulate diffuse by albedo for NRD storage (matching RTXDI pattern)
    vec3 demodulatedDiffuse = nrd_safe_demodulate(
        shadedDiffuse * gi_surface_albedo(currentSurface),
        nrd_compute_diffuse_demodulation(gi_surface_albedo(currentSurface))
    );

    // Combined signal for current single-output pipeline
    vec3 demodulatedIndirect = demodulatedDiffuse + shadedSpecular;
    float history = min(state.age + 1.0f, lt_indirect_max_history);
    float luma = ph_luminance(max(demodulatedIndirect, vec3(0.0f)));
    float secondMoment = luma * luma;
    float variance = max(secondMoment / max(history, 1.0f), 1e-6f);
    float confidence = nrd_confidence_from_history(history, lt_indirect_max_history);

    indirect_frag_out = vec4(max(demodulatedIndirect, vec3(0.0f)), history);
    indirect_variance_frag_out = vec4(luma, secondMoment, variance, confidence);
    RTXDI_StoreGIReservoir(
        state,
        indirect_reservoir_position_frag_out,
        indirect_reservoir_normal_frag_out,
        indirect_reservoir_radiance_frag_out,
        indirect_reservoir_meta_frag_out
    );
}
