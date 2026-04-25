struct RTXDI_RuntimeParameters
{
    uint neighborOffsetMask;
    uint activeCheckerboardField;
    uint frameIndex;
    uint pad2;
};

struct RTXDI_ReservoirBufferParameters
{
    uint reservoirBlockRowPitch;
    uint reservoirArrayPitch;
    uint pad1;
    uint pad2;
};

struct RTXDI_BoilingFilterParameters
{
    uint enableBoilingFilter;
    float boilingFilterStrength;
    uint pad1;
    uint pad2;
};

struct RTXDI_DIInitialSamplingParameters
{
    uint numLocalLightSamples;
    uint numInfiniteLightSamples;
    uint numEnvironmentSamples;
    uint numBrdfSamples;
    float brdfCutoff;
    float brdfRayMinT;
    uint localLightSamplingMode;
    uint enableInitialVisibility;
    uint environmentMapImportanceSampling;
    uint pad1;
    uint pad2;
    uint pad3;
};

struct RTXDI_DISpatialResamplingParameters
{
    uint numSamples;
    uint numDisocclusionBoostSamples;
    float samplingRadius;
    uint biasCorrectionMode;
    float depthThreshold;
    float normalThreshold;
    uint targetHistoryLength;
    uint enableMaterialSimilarityTest;
    uint discountNaiveSamples;
    uint pad1;
    uint pad2;
    uint pad3;
};

struct RTXDI_ShadingParameters
{
    uint enableFinalVisibility;
    uint reuseFinalVisibility;
    uint finalVisibilityMaxAge;
    float finalVisibilityMaxDistance;
    uint enableDenoiserInputPacking;
    uint pad1;
    uint pad2;
    uint pad3;
};

struct RTXDI_VisibilityReuseParameters
{
    uint maxAge;
    float maxDistance;
};

struct RTXDI_DIBufferIndices
{
    uint initialSamplingOutputBufferIndex;
    uint spatialResamplingInputBufferIndex;
    uint spatialResamplingOutputBufferIndex;
    uint shadingInputBufferIndex;
    uint pad1;
    uint pad2;
    uint pad3;
    uint pad4;
};

struct RTXDI_Parameters
{
    RTXDI_ReservoirBufferParameters reservoirBufferParams;
    RTXDI_DIBufferIndices bufferIndices;
    RTXDI_DIInitialSamplingParameters initialSamplingParams;
    RTXDI_BoilingFilterParameters boilingFilterParams;
    RTXDI_DISpatialResamplingParameters spatialResamplingParams;
    RTXDI_ShadingParameters shadingParams;
};

const uint RTXDI_DI_BUFFER_INDEX_INITIAL_SAMPLING_OUTPUT = 0u;
const uint RTXDI_DI_BUFFER_INDEX_TEMPORAL_RESAMPLING_OUTPUT = 1u;
const uint RTXDI_DI_BUFFER_INDEX_SPATIAL_RESAMPLING_OUTPUT = 2u;
const uint RTXDI_DI_BUFFER_INDEX_SHADING_INPUT = 3u;

const uint LT_TEMPORAL_REUSE_GATHER_ONLY = 0u;
const uint LT_TEMPORAL_REUSE_SCATTER_ONLY = 1u;
const uint LT_TEMPORAL_REUSE_SCATTER_BACKUP = 2u;
const uint LT_TEMPORAL_REUSE_MULTI_SCATTER = 3u;

const uint LT_SCATTER_BACKUP_MIS_BALANCE = 0u;
const uint LT_SCATTER_BACKUP_MIS_PAIRWISE = 1u;

const uint LT_GATHER_MECHANISM_FAST = 0u;
const uint LT_GATHER_MECHANISM_CLAMPED = 1u;
const uint LT_GATHER_MECHANISM_ROBUST = 2u;

RTXDI_DIBufferIndices lt_build_di_buffer_indices()
{
    RTXDI_DIBufferIndices bufferIndices;
    bufferIndices.initialSamplingOutputBufferIndex = RTXDI_DI_BUFFER_INDEX_INITIAL_SAMPLING_OUTPUT;

    bool enableTemporalReuse = ph_debug_enable_direct_temporal_reuse >= 0.5f;
    uint temporalOutputBufferIndex = enableTemporalReuse
        ? RTXDI_DI_BUFFER_INDEX_TEMPORAL_RESAMPLING_OUTPUT
        : RTXDI_DI_BUFFER_INDEX_INITIAL_SAMPLING_OUTPUT;
    bool enableSpatialReuse = ph_debug_enable_direct_spatial_reuse >= 0.5f;

    bufferIndices.spatialResamplingInputBufferIndex = temporalOutputBufferIndex;
    bufferIndices.spatialResamplingOutputBufferIndex = enableSpatialReuse
        ? RTXDI_DI_BUFFER_INDEX_SPATIAL_RESAMPLING_OUTPUT
        : temporalOutputBufferIndex;
    bufferIndices.shadingInputBufferIndex = bufferIndices.spatialResamplingOutputBufferIndex;
    bufferIndices.pad1 = 0u;
    bufferIndices.pad2 = 0u;
    bufferIndices.pad3 = 0u;
    bufferIndices.pad4 = 0u;
    return bufferIndices;
}

RTXDI_DIBufferIndices RTXDI_GetDIBufferIndices()
{
    return lt_build_di_buffer_indices();
}

uint lt_restir_scatter_backup_mis_option()
{
    int misOption = int(round(ph_restir_scatter_backup_mis_mode));
    return uint(clamp(misOption, int(LT_SCATTER_BACKUP_MIS_BALANCE), int(LT_SCATTER_BACKUP_MIS_PAIRWISE)));
}

uint lt_restir_temporal_gather_option()
{
    int gatherOption = int(round(ph_restir_temporal_gather_mode));
    return uint(clamp(gatherOption, int(LT_GATHER_MECHANISM_FAST), int(LT_GATHER_MECHANISM_ROBUST)));
}

uint lt_get_final_shading_input_buffer_index()
{
    return lt_build_di_buffer_indices().shadingInputBufferIndex;
}

RTXDI_RuntimeParameters lt_build_runtime_parameters()
{
    RTXDI_RuntimeParameters params;
    params.neighborOffsetMask = uint(lt_neighbor_offset_count - 1);
    params.activeCheckerboardField = uint(ph_restir_active_checkerboard_field);
    params.frameIndex = uint(max(ph_restir_frame_index, 0));
    params.pad2 = 0u;
    return params;
}

RTXDI_ReservoirBufferParameters lt_build_reservoir_buffer_parameters()
{
    RTXDI_ReservoirBufferParameters reservoirParams;
    reservoirParams.reservoirBlockRowPitch = 0u;
    reservoirParams.reservoirArrayPitch = 0u;
    reservoirParams.pad1 = 0u;
    reservoirParams.pad2 = 0u;
    return reservoirParams;
}

RTXDI_DIInitialSamplingParameters lt_build_di_initial_sampling_parameters()
{
    RTXDI_DIInitialSamplingParameters initialSamplingParams;
    // Reservoir Splatting owns SPP in InitialCandidates_run(); the local-light
    // count is per path and must not default to the same SPP value again.
    initialSamplingParams.numLocalLightSamples = uint((ph_restir_initial_num_local_samples > 0.0)
        ? max(int(ph_restir_initial_num_local_samples), 1)
        : 1);
    initialSamplingParams.numInfiniteLightSamples = 0u;
    initialSamplingParams.numEnvironmentSamples = 0u;
    initialSamplingParams.numBrdfSamples = 0u;
    initialSamplingParams.brdfCutoff = (ph_restir_initial_brdf_cutoff > 0.0) ? ph_restir_initial_brdf_cutoff : 0.0001f;
    initialSamplingParams.brdfRayMinT = 0.001f;

    int requestedLocalLightSamplingMode = (ph_restir_local_light_sampling_mode <= 0.0)
        ? RTXDI_LOCAL_LIGHT_SAMPLING_UNIFORM
        : int(round(ph_restir_local_light_sampling_mode));

    initialSamplingParams.localLightSamplingMode = uint(requestedLocalLightSamplingMode);
    initialSamplingParams.enableInitialVisibility = (ph_restir_initial_enable_visibility > -0.5f) ? 1u : 0u;
    initialSamplingParams.environmentMapImportanceSampling = 0u;
    initialSamplingParams.pad1 = 0u;
    initialSamplingParams.pad2 = 0u;
    initialSamplingParams.pad3 = 0u;
    return initialSamplingParams;
}

RTXDI_DISpatialResamplingParameters lt_build_di_spatial_resampling_parameters()
{
    RTXDI_DISpatialResamplingParameters spatialResamplingParams;
    spatialResamplingParams.numSamples = uint((ph_restir_spatial_sample_count > 0.0)
        ? max(int(floor(ph_restir_spatial_sample_count)), 1)
        : max(PH_LIGHTTREE_SPATIAL_REUSE_SAMPLES, 1));
    spatialResamplingParams.numDisocclusionBoostSamples = uint((ph_restir_spatial_boost_samples > 0.0)
        ? max(int(floor(ph_restir_spatial_boost_samples)), int(spatialResamplingParams.numSamples))
        : 8);
    spatialResamplingParams.samplingRadius = ph_restir_spatial_radius > 0.0
        ? max(ph_restir_spatial_radius, 1.0f)
        : max(PH_LIGHTTREE_SPATIAL_REUSE_RADIUS, 1.0f);

    // Player/runtime default is pairwise MIS for spatial reuse, matching the RTXDI reference's
    // dedicated spatial resampling path. The explicit override still accepts Off/Basic/Pairwise/Ray-traced.
    if (ph_restir_spatial_bias_mode < -0.5f) {
        spatialResamplingParams.biasCorrectionMode = uint(RTXDI_BIAS_CORRECTION_PAIRWISE);
    } else {
        int resolvedMode = int(round(ph_restir_spatial_bias_mode));
        spatialResamplingParams.biasCorrectionMode = uint(
            (resolvedMode == RTXDI_BIAS_CORRECTION_OFF
                || resolvedMode == RTXDI_BIAS_CORRECTION_BASIC
                || resolvedMode == RTXDI_BIAS_CORRECTION_PAIRWISE
                || resolvedMode == RTXDI_BIAS_CORRECTION_RAY_TRACED)
                ? resolvedMode
                : RTXDI_BIAS_CORRECTION_BASIC
        );
    }

    spatialResamplingParams.depthThreshold = ph_restir_spatial_depth_threshold > 0.0
        ? ph_restir_spatial_depth_threshold
        : lt_depth_threshold;
    spatialResamplingParams.normalThreshold = ph_restir_spatial_normal_threshold > 0.0
        ? ph_restir_spatial_normal_threshold
        : lt_surface_normal_threshold;
    spatialResamplingParams.targetHistoryLength = uint(max(int(floor(ph_restir_spatial_target_history)), 0));
    spatialResamplingParams.enableMaterialSimilarityTest = (ph_restir_spatial_material_test < -1.5) ? 0u : 1u;
    spatialResamplingParams.discountNaiveSamples = (ph_restir_spatial_discount_naive < -1.5) ? 0u : 1u;
    spatialResamplingParams.pad1 = 0u;
    spatialResamplingParams.pad2 = 0u;
    spatialResamplingParams.pad3 = 0u;
    return spatialResamplingParams;
}

RTXDI_BoilingFilterParameters lt_build_di_boiling_filter_parameters()
{
    RTXDI_BoilingFilterParameters boilingFilterParams;
    boilingFilterParams.enableBoilingFilter = 1u;
    boilingFilterParams.boilingFilterStrength = 0.2f;
    boilingFilterParams.pad1 = 0u;
    boilingFilterParams.pad2 = 0u;
    return boilingFilterParams;
}

RTXDI_ShadingParameters lt_build_shading_parameters()
{
    RTXDI_ShadingParameters shadingParams;
    shadingParams.enableFinalVisibility = (ph_restir_enable_final_visibility >= 0.5f) ? 1u : 0u;
    shadingParams.reuseFinalVisibility = (ph_restir_reuse_final_visibility >= 0.5f) ? 1u : 0u;
    shadingParams.finalVisibilityMaxAge = uint((ph_restir_visibility_max_age > 0.0f) ? ph_restir_visibility_max_age : lt_visibility_reuse_max_age);
    shadingParams.finalVisibilityMaxDistance = (ph_restir_visibility_max_distance > 0.0f) ? ph_restir_visibility_max_distance : lt_visibility_reuse_max_distance;
    shadingParams.enableDenoiserInputPacking = (ph_restir_enable_denoiser_packing >= 0.5f) ? 1u : 0u;
    shadingParams.pad1 = 0u;
    shadingParams.pad2 = 0u;
    shadingParams.pad3 = 0u;
    return shadingParams;
}

RTXDI_VisibilityReuseParameters lt_build_visibility_reuse_parameters()
{
    RTXDI_VisibilityReuseParameters visibilityReuseParams;
    visibilityReuseParams.maxAge = uint((ph_restir_visibility_max_age > 0.0f) ? ph_restir_visibility_max_age : lt_visibility_reuse_max_age);
    visibilityReuseParams.maxDistance = (ph_restir_visibility_max_distance > 0.0f) ? ph_restir_visibility_max_distance : lt_visibility_reuse_max_distance;
    return visibilityReuseParams;
}

RTXDI_Parameters lt_build_restir_di_parameters()
{
    RTXDI_Parameters restirDI;
    restirDI.reservoirBufferParams = lt_build_reservoir_buffer_parameters();
    restirDI.bufferIndices = lt_build_di_buffer_indices();
    restirDI.initialSamplingParams = lt_build_di_initial_sampling_parameters();
    restirDI.boilingFilterParams = lt_build_di_boiling_filter_parameters();
    restirDI.spatialResamplingParams = lt_build_di_spatial_resampling_parameters();
    restirDI.shadingParams = lt_build_shading_parameters();
    return restirDI;
}
