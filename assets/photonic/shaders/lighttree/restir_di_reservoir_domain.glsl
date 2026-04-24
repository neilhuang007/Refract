vec2 scatter_resolve_reservoir_subpixel(RTXDI_DIReservoir reservoir, ivec2 pixelPosition);
ivec2 lt_area_pixel_from_sample_uv(vec2 pixelSampleUV);
bool lt_area_has_valid_domain(RTXDI_DIReservoir reservoir);
vec2 lt_area_clamp_pixel_sample_uv(vec2 pixelSampleUV);
vec2 lt_area_pixel_sample_from_subpixel(ivec2 pixelPosition, vec2 subPixel);

vec2 lt_area_default_pixel_sample(ivec2 pixelPosition) {
    return (vec2(pixelPosition) + vec2(0.5f)) / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
}

vec2 PathReservoir_getSubPixel(RTXDI_DIReservoir reservoir, ivec2 pixelPosition) {
    vec2 pixelSampleUV = lt_area_has_valid_domain(reservoir)
        ? lt_area_clamp_pixel_sample_uv(reservoir.pixelSampleUV)
        : lt_area_default_pixel_sample(pixelPosition);
    vec2 samplePixel = pixelSampleUV * vec2(viewWidth, viewHeight) - vec2(0.5f);
    return clamp(fract(samplePixel), vec2(0.0f), vec2(1.0f));
}

vec2 lt_area_random_pixel_sample(inout RTXDI_RandomSamplerState rng, ivec2 pixelPosition) {
    vec2 jitter = vec2(lt_next_random(rng), lt_next_random(rng));
    return (vec2(pixelPosition) + jitter) / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
}

vec2 lt_area_default_lens_sample() {
    return vec2(0.0f);
}

vec2 lt_area_sample_lens_sample(inout RTXDI_RandomSamplerState rng) {
    return lt_area_default_lens_sample();
}

const uint LT_PATH_SAMPLE_MASK = 0xFFu;
const uint LT_PATH_SAMPLE_PROPOSAL_SHIFT = 8u;
const uint LT_PATH_SAMPLE_PROPOSAL_MASK = 0xFu;
const uint LT_PATH_SAMPLE_TIME_SHIFT = 12u;
const uint LT_PATH_SAMPLE_TIME_MASK = 0x1FFu;
const uint LT_PROPOSAL_FAMILY_UNKNOWN = 0u;
const uint LT_PROPOSAL_FAMILY_UNIFORM = 1u;
const uint LT_PROPOSAL_FAMILY_POWER_RIS = 2u;
const uint LT_PROPOSAL_FAMILY_REGIR_RIS = 3u;
const uint LT_PROPOSAL_FAMILY_REGIR_FALLBACK = 4u;
const uint LT_PROPOSAL_FAMILY_BRDF = 5u;
const uint LT_PROPOSAL_FAMILY_FAST_RANDOM = 6u;

uint lt_make_path_sample(uint basePathSample, uint proposalFamily) {
    return (basePathSample & LT_PATH_SAMPLE_MASK)
        | ((proposalFamily & LT_PATH_SAMPLE_PROPOSAL_MASK) << LT_PATH_SAMPLE_PROPOSAL_SHIFT);
}

uint lt_make_path_sample_with_time(uint basePathSample, uint proposalFamily, float time) {
    uint packedTime = min(
        uint(round(clamp(time, 0.0f, 1.0f) * float(LT_PATH_SAMPLE_TIME_MASK))),
        LT_PATH_SAMPLE_TIME_MASK
    );
    return lt_make_path_sample(basePathSample, proposalFamily)
        | (packedTime << LT_PATH_SAMPLE_TIME_SHIFT);
}

uint lt_path_sample_base(uint pathSample) {
    return pathSample & LT_PATH_SAMPLE_MASK;
}

uint lt_path_sample_proposal_family(uint pathSample) {
    return (pathSample >> LT_PATH_SAMPLE_PROPOSAL_SHIFT) & LT_PATH_SAMPLE_PROPOSAL_MASK;
}

float lt_path_sample_time(uint pathSample) {
    return float((pathSample >> LT_PATH_SAMPLE_TIME_SHIFT) & LT_PATH_SAMPLE_TIME_MASK)
        / float(LT_PATH_SAMPLE_TIME_MASK);
}

bool lt_area_has_valid_domain(RTXDI_DIReservoir reservoir) {
    return all(greaterThanEqual(reservoir.pixelSampleUV, vec2(0.0f)))
        && all(greaterThanEqual(reservoir.lensSampleUV, vec2(0.0f)));
}

void lt_area_set_domain_samples(inout RTXDI_DIReservoir reservoir, vec2 pixelSampleUV, vec2 lensSampleUV, uint pathSample) {
    reservoir.pixelSampleUV = clamp(pixelSampleUV, vec2(0.0f), vec2(1.0f));
    reservoir.lensSampleUV = clamp(lensSampleUV, vec2(0.0f), vec2(1.0f));
    reservoir.pathSample = pathSample;
}

void PathReservoir_setSubPixel(inout RTXDI_DIReservoir reservoir, ivec2 pixelPosition, vec2 subPixel) {
    vec2 lensSampleUV = lt_area_has_valid_domain(reservoir)
        ? clamp(reservoir.lensSampleUV, vec2(0.0f), vec2(1.0f))
        : lt_area_default_lens_sample();
    lt_area_set_domain_samples(
        reservoir,
        lt_area_pixel_sample_from_subpixel(pixelPosition, subPixel),
        lensSampleUV,
        reservoir.pathSample
    );
}

void PathReservoir_copyDomainAtPixel(
    inout RTXDI_DIReservoir dstReservoir,
    ivec2 dstPixel,
    RTXDI_DIReservoir srcReservoir,
    ivec2 srcPixel)
{
    vec2 srcSubPixel = PathReservoir_getSubPixel(srcReservoir, srcPixel);
    vec2 srcLensSample = lt_area_has_valid_domain(srcReservoir)
        ? clamp(srcReservoir.lensSampleUV, vec2(0.0f), vec2(1.0f))
        : lt_area_default_lens_sample();
    lt_area_set_domain_samples(
        dstReservoir,
        lt_area_pixel_sample_from_subpixel(dstPixel, srcSubPixel),
        srcLensSample,
        srcReservoir.pathSample
    );
}

void lt_area_finalize_candidate(inout RTXDI_DIReservoir reservoir, ivec2 pixelPosition, uint pathSample) {
    if (!lt_area_has_valid_domain(reservoir)) {
        lt_area_set_domain_samples(
            reservoir,
            lt_area_default_pixel_sample(pixelPosition),
            lt_area_default_lens_sample(),
            pathSample
        );
    } else {
        reservoir.pathSample = pathSample;
    }
}

float lt_area_effective_target_pdf(
    RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    ivec2 referencePixelPosition,
    bool reservoirPreviousFrame,
    bool targetPreviousFrame)
{
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return 0.0f;
    }

    RAB_LightSample smple = lt_decode_reservoir_sample_for_frame(
        reservoir,
        surface,
        reservoirPreviousFrame,
        targetPreviousFrame
    );
    if (smple.index < 0 || smple.solidAnglePdf <= 0.0f) {
        return 0.0f;
    }

    float shiftedTarget = lt_surface_target_pdf(surface, smple);
    vec2 referencePixelSample = lt_area_default_pixel_sample(referencePixelPosition);
    float pixelJacobian = lt_area_has_valid_domain(reservoir)
        ? max(0.25f, 1.0f - length((reservoir.pixelSampleUV - referencePixelSample) * vec2(viewWidth, viewHeight)) / 4.0f)
        : 1.0f;
    float lensJacobian = lt_area_has_valid_domain(reservoir)
        ? max(0.25f, 1.0f - length(reservoir.lensSampleUV - lt_area_default_lens_sample()) * 2.0f)
        : 1.0f;
    return shiftedTarget * pixelJacobian * lensJacobian;
}

float lt_area_effective_target_pdf(RTXDI_DIReservoir reservoir, RAB_Surface surface) {
    return lt_area_effective_target_pdf(
        reservoir,
        surface,
        lt_fragment_pixel_pos(),
        false,
        false
    );
}

vec2 lt_area_clamp_pixel_sample_uv(vec2 pixelSampleUV) {
    vec2 pixelSize = vec2(1.0f / max(viewWidth, 1.0), 1.0f / max(viewHeight, 1.0));
    return clamp(pixelSampleUV, pixelSize * 0.5f, vec2(1.0f) - pixelSize * 0.5f);
}

vec2 lt_area_pixel_sample_from_subpixel(ivec2 pixelPosition, vec2 subPixel) {
    return lt_area_clamp_pixel_sample_uv(
        (vec2(pixelPosition) + clamp(subPixel, vec2(0.0f), vec2(1.0f))) / vec2(viewWidth, viewHeight)
    );
}

bool lt_area_try_shift_temporal_domain(
    inout RTXDI_DIReservoir reservoir,
    ivec2 sourcePixel,
    ivec2 targetPixel,
    vec2 previousFloatingPixel)
{
    const float overlapEpsilon = 1e-4f;
    vec2 prevSubPixel = scatter_resolve_reservoir_subpixel(reservoir, sourcePixel);
    vec2 shiftedSubPixel = (vec2(sourcePixel) + prevSubPixel) - previousFloatingPixel;
    if (any(lessThan(shiftedSubPixel, vec2(-overlapEpsilon)))
        || any(greaterThan(shiftedSubPixel, vec2(1.0f + overlapEpsilon))))
    {
        return false;
    }

    shiftedSubPixel = clamp(shiftedSubPixel, vec2(0.0f), vec2(1.0f - 1e-5f));

    vec2 lensSampleUV = lt_area_has_valid_domain(reservoir)
        ? clamp(reservoir.lensSampleUV, vec2(0.0f), vec2(1.0f))
        : lt_area_default_lens_sample();
    lt_area_set_domain_samples(
        reservoir,
        lt_area_pixel_sample_from_subpixel(targetPixel, shiftedSubPixel),
        lensSampleUV,
        reservoir.pathSample
    );
    return lt_area_pixel_from_sample_uv(reservoir.pixelSampleUV) == targetPixel;
}

ivec2 lt_area_pixel_from_sample_uv(vec2 pixelSampleUV) {
    vec2 scaled = lt_area_clamp_pixel_sample_uv(pixelSampleUV) * vec2(viewWidth, viewHeight) - vec2(0.5f);
    return clamp(ivec2(floor(scaled)), ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));
}

vec2 lt_area_jitter_domain_sample(vec2 sampleUv, vec2 jitter, vec2 scale) {
    return clamp(sampleUv + jitter * scale, vec2(0.0f), vec2(1.0f));
}

void lt_area_seed_domain_samples(inout RTXDI_DIReservoir reservoir, ivec2 pixelPosition, uint pathSample) {
    lt_area_set_domain_samples(
        reservoir,
        lt_area_default_pixel_sample(pixelPosition),
        lt_area_default_lens_sample(),
        pathSample
    );
}

void lt_area_seed_domain_samples(
    inout RTXDI_DIReservoir reservoir,
    inout RTXDI_RandomSamplerState rng,
    ivec2 pixelPosition,
    uint pathSample)
{
    lt_area_set_domain_samples(
        reservoir,
        lt_area_random_pixel_sample(rng, pixelPosition),
        lt_area_sample_lens_sample(rng),
        pathSample
    );
}

float lt_area_confidence_from_samples(float sampleCount) {
    // Reference: Reservoir.slang:75 -- PathReservoir::confidenceCap = 20
    return clamp(sampleCount, 0.0f, 20.0f);
}

float lt_scatter_bilinear_weight(vec2 fracOffset, int dx, int dy) {
    return ((dx == 0) ? (1.0f - fracOffset.x) : fracOffset.x)
         * ((dy == 0) ? (1.0f - fracOffset.y) : fracOffset.y);
}

vec2 lt_temporal_previous_pixel_center(ivec2 pixelPosition) {
    vec4 motionSample = texelFetch(radiosity_motion, pixelPosition, 0);
    if (motionSample.w <= 0.0f) {
        return vec2(pixelPosition) + vec2(0.5f);
    }

    // ph_compute_temporal_motion() already stores pixel-space motion as:
    //   previousPixel - currentPixelCenter
    // so temporal reuse must add that delta directly instead of scaling by the
    // viewport again or flipping the sign.
    return vec2(pixelPosition) + vec2(0.5f) + motionSample.xy;
}

ivec2 lt_temporal_previous_checkerboard_pixel(ivec2 pixelPosition, int previousCheckerboardField) {
    ivec2 previousPixel = pixelPosition;
    RTXDI_ActivateCheckerboardPixel(previousPixel, true, previousCheckerboardField);
    return previousPixel;
}

float lt_scatter_compute_history_confidence(ivec2 pixelPosition, RAB_Surface currentSurface, RTXDI_DIReservoir reservoir) {
    float currentConfidence = lt_area_confidence_from_samples(reservoir.M);
    if (!RAB_IsSurfaceValid(currentSurface)) {
        return currentConfidence;
    }

    vec2 backprojF = lt_temporal_previous_pixel_center(pixelPosition);
    ivec2 basePixel = ivec2(floor(backprojF));
    vec2 fracOffset = backprojF - vec2(basePixel);
    int previousCheckerboardField = lt_previous_checkerboard_field(int(ph_restir_active_checkerboard_field));

    float bilinearConfidence = 0.0f;
    float totalWeight = 0.0f;
    for (int dy = 0; dy <= 1; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 samplePixel = basePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(samplePixel)) {
                continue;
            }

            ivec2 previousSamplePixel = lt_temporal_previous_checkerboard_pixel(samplePixel, previousCheckerboardField);
            if (!lt_is_viewport_uv_in_bounds(previousSamplePixel)) {
                continue;
            }

            ScatterReconnectionData neighborReconn;
            scatter_load_prev_reconnection(previousSamplePixel, neighborReconn);
            float weight = lt_scatter_bilinear_weight(fracOffset, dx, dy);
            if (weight <= 0.0f) {
                continue;
            }

            if (!scatter_reconnection_matches_surface(neighborReconn, pixelPosition, currentSurface)) {
                continue;
            }

            bilinearConfidence += weight * RTXDI_LoadPreviousDIReservoir(
                lt_build_restir_di_parameters().reservoirBufferParams,
                uvec2(previousSamplePixel)
            ).M;
            totalWeight += weight;
        }
    }

    float prevConfidence = (totalWeight > 0.0f) ? (bilinearConfidence / totalWeight) : 0.0f;
    return min(max(currentConfidence, prevConfidence + 1.0f), 20.0f);
}

bool lt_area_is_surface_neighbor_valid(RAB_Surface currentSurface, RAB_Surface prevSurface) {
    if (!RAB_IsSurfaceValid(currentSurface) || !RAB_IsSurfaceValid(prevSurface)) {
        return false;
    }

    return RTXDI_IsValidNeighbor(
        RAB_GetSurfaceNormal(currentSurface),
        RAB_GetSurfaceNormal(prevSurface),
        RAB_GetSurfaceLinearDepth(currentSurface),
        RAB_GetSurfaceLinearDepth(prevSurface),
        ph_restir_normal_threshold,
        ph_restir_depth_threshold
    );
}

bool lt_area_is_temporal_neighbor_valid(
    RAB_Surface currentSurface,
    RAB_Surface prevSurface,
    ScatterReconnectionData prevReconnection,
    ivec2 currentPixel)
{
    return lt_area_is_surface_neighbor_valid(currentSurface, prevSurface);
}

ivec2 lt_area_reproject_pixel(ivec2 pixelPosition) {
    ivec2 prevPixel = ivec2(floor(lt_temporal_previous_pixel_center(pixelPosition)));
    return clamp(prevPixel, ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));
}
