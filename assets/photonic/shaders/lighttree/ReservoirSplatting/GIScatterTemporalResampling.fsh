#version 430
#define PH_GI_TEMPORAL_CELL_COUNTER_BUFFER 1
#define PH_GI_TEMPORAL_SORT_BUFFERS 1

in vec4 direction_vert_out;

layout(location = 0) out vec4 temporal_position_frag_out;
layout(location = 1) out vec4 temporal_normal_frag_out;
layout(location = 2) out vec4 temporal_radiance_frag_out;
layout(location = 3) out vec4 temporal_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"
#include "/photonics/lighttree/ReservoirSplatting/GITemporalSplatting.glsl"

bool gi_temporal_splat_combine(
    inout RTXDI_GIReservoir state,
    inout float selectedTargetPdf,
    RTXDI_GIReservoir candidateReservoir,
    RAB_Surface currentSurface,
    float jacobian,
    float misWeight,
    float randomValue)
{
    if (!RTXDI_IsValidGIReservoir(candidateReservoir) || jacobian <= 0.0f || misWeight <= 0.0f) {
        return false;
    }

    float targetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, candidateReservoir.selected);
    if (targetPdf <= 0.0f) {
        return false;
    }

    bool selected = RTXDI_CombineGIReservoirs(
        state,
        candidateReservoir,
        randomValue,
        targetPdf * jacobian * misWeight
    );
    if (selected) {
        selectedTargetPdf = targetPdf;
    }
    return true;
}

void gi_temporal_splat_store(RTXDI_GIReservoir reservoir)
{
    RTXDI_GIReservoirStore store = gi_make_reservoir_store(reservoir);
    temporal_position_frag_out = store.positionData;
    temporal_normal_frag_out = store.normalData;
    temporal_radiance_frag_out = store.radianceData;
    temporal_meta_frag_out = store.metaData;
}

void gi_temporal_splat_store_invalid()
{
    RTXDI_GIReservoirStore store = gi_make_invalid_reservoir_store();
    temporal_position_frag_out = store.positionData;
    temporal_normal_frag_out = store.normalData;
    temporal_radiance_frag_out = store.radianceData;
    temporal_meta_frag_out = store.metaData;
}

void main()
{
    gi_temporal_splat_store_invalid();

    int activeCheckerboardField = int(ph_restir_active_checkerboard_field);
    ivec2 currentReservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(currentReservoirPos)) {
        return;
    }

    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(currentReservoirPos, activeCheckerboardField);
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        return;
    }

    RAB_Surface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        return;
    }

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(currentReservoirPos),
        uint(frameCounter),
        RTXDI_GI_SPATIAL_RESAMPLING_RANDOM_SEED + 17u
    );

    RTXDI_GIReservoir state = RTXDI_EmptyGIReservoir();
    float selectedTargetPdf = 0.0f;

    uint cellIndex = gi_temporal_splat_linear_index(currentReservoirPos);
    uint splatCount = min(
        gi_temporal_splat_cell_counter_value(cellIndex),
        uint(gi_runtime_temporal_max_splats())
    );
    uint cellOffset = gi_temporal_splat_cell_offset_value(cellIndex);
    int previousCheckerboardField = lt_previous_checkerboard_field(activeCheckerboardField);
    float temporalMisWeight = 1.0f / (1.0f + float(splatCount));

    RTXDI_GIReservoir canonicalReservoir = RTXDI_LoadCanonicalGIReservoir(currentReservoirPos, activeCheckerboardField);
    gi_temporal_splat_combine(
        state,
        selectedTargetPdf,
        canonicalReservoir,
        currentSurface,
        1.0f,
        temporalMisWeight,
        0.5f
    );

    for (uint i = 0u; i < splatCount; ++i) {
        ivec2 sourcePixel = ivec2(gi_temporal_splat_load_sorted_source(cellOffset + i));
        if (!lt_is_viewport_uv_in_bounds(sourcePixel)) {
            continue;
        }

        RAB_Surface sourceSurface = lt_load_previous_surface(sourcePixel);
        if (!lt_is_valid_surface(sourceSurface)) {
            continue;
        }

        ivec2 sourceReservoirPos = RTXDI_PixelPosToReservoirPos(sourcePixel, previousCheckerboardField);
        RTXDI_GIReservoir previousReservoir = RTXDI_LoadPreviousGIReservoir(sourceReservoirPos, previousCheckerboardField);
        if (!RTXDI_IsValidGIReservoir(previousReservoir)) {
            continue;
        }

        if (!gi_sample_is_skylight(previousReservoir, currentSurface)
            && !lt_materials_similar(currentSurface, sourceSurface)) {
            continue;
        }

        float jacobian = RTXDI_GICalculateJacobian(currentSurface, sourceSurface, previousReservoir.selected);
        gi_temporal_splat_combine(
            state,
            selectedTargetPdf,
            previousReservoir,
            currentSurface,
            jacobian,
            temporalMisWeight,
            RTXDI_GetNextRandom(rng)
        );
    }

    if (!RTXDI_IsValidGIReservoir(state) || selectedTargetPdf <= 0.0f) {
        return;
    }

    RTXDI_FinalizeGIResampling(state, 1.0f, state.samples * selectedTargetPdf);
    if (!RTXDI_IsValidGIReservoir(state)) {
        return;
    }

    gi_temporal_splat_store(state);
}
