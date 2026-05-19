#ifndef PHOTONICS_RESTIR_DI_SCATTER_IMPL_GLSL
#define PHOTONICS_RESTIR_DI_SCATTER_IMPL_GLSL

#include "/photonics/lighttree/restir_di_reconnection_scatter.glsl"

// ============================================================================
// This module contains the reusable helper functions that support the full
// Reservoir Splatting temporal stage family implemented by the active bridge:
//   * CollectTemporalSamples
//   * GatherTemporalResampling
//   * ReprojectTemporalSamples
//   * SortReprojectedReservoirs
//   * ScatterTemporalResampling
//   * MultiReprojectTemporalSamples
//   * MultiSortReprojectedReservoirs
//   * MultiScatterTemporalResampling
//   * ShiftMapping.slang::scatterReprojectionShift analogs
//
// The bridge exports the stage entry points directly and this file owns the
// shared shift mappings, MIS terms, and confidence bookkeeping used by those
// stages without introducing local behavioral adaptations.
// ============================================================================

// ===========================================================================
// Stage 2c (ScatterTemporalResampling.rt.slang) helpers.
//
// The reference's `run(pixel)` body is structurally simple:
//   1. Load the current reservoir/reconnection, compute currSampleMIS via a
//      current -> previous shift.
//   2. Seed the destination state with addSampleFromReservoir(currSampleMIS,
//      currReservoir).  Snapshot its confidence as newConfidence.
//   3. Walk sortedReservoirs[cellOffset + i], shift each prev -> current,
//      compute prevSampleMIS via m1/m2, and addSampleFromReservoir.
//   4. Overwrite dstReservoir.confidence with the motion-vector bilinear
//      accumulation against prevReservoirs[neighbor].
//
// The helpers below isolate each step so the entry point in reuse_bridge.glsl
// is a linear transliteration of ScatterTemporalResampling::run.
// ===========================================================================

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)

// ---------------------------------------------------------------------------
// Build the current-frame canonical sample for this pixel.
//
// Mirrors ScatterTemporalResampling.rt.slang:77-79 exactly:
//   currReservoir = currReservoirs[reservoirIdx]
//   currReconnection = currReconnectionData[reservoirIdx]
//
// The stage consumes the published Stage-1 sidecar snapshot directly through
// the shared current-stage reconnection samplers. No canonical rebuild is
// permitted here because the reference never resamples the current candidate
// in this pass, and doing so reintroduces pHat jitter / blur.
// Returns valid=false when the carried integrand is zero.
// ---------------------------------------------------------------------------
float ScatterTemporalResampling_load_previous_reservoir_confidence(
    ivec2 neighborPixel);

ivec2 ScatterTemporalResampling_previous_reservoir_pixel(
    ivec2 previousPixel);

RTXDI_DIReservoir lt_ScatterTemporalResampling_load_current_reservoir(
    ivec2 pixel);

LtScatterCurrentSample lt_ScatterTemporalResampling_load_current_sample(
    uint reservoirIdx,
    ivec2 pixel,
    RAB_Surface surface,
    RTXDI_DIReservoir currReservoir);

float ScatterTemporalResampling_compute_curr_sample_mis(
    LtScatterCurrentSample currSample,
    ivec2 pixel,
    RAB_Surface surface);

bool ScatterTemporalResampling_process_contributor(
    inout RTXDI_DIReservoir dstReservoir,
    inout ReconnectionData dstReconnectionData,
    inout float newConfidence,
    ivec2 scatteredPixel,
    ivec2 pixel,
    RTXDI_DIReservoir currReservoir,
    ReconnectionData currReconnectionData,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg);

float ScatterTemporalResampling_motion_vector_confidence(
    ivec2 pixel,
    float newConfidence);

RTXDI_DIReservoir lt_ScatterTemporalResampling_load_current_reservoir(
    ivec2 pixel)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    // The proposal reservoir textures are half-width when checkerboard is active.
    // Callers pass a full-res pixel; convert to the half-width address before
    // texelFetch or the right half of the screen reads OOB and gets an empty
    // reservoir. Reference: RTXDI Rtxdi/Include/Rtxdi/Utils/ReservoirAddressing.hlsli.
    ivec2 reservoirPos = RTXDI_PixelPosToReservoirPos(pixel, ph_restir_active_checkerboard_field);
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_proposal_reservoirs, reservoirPos, 0),
        texelFetch(radiosity_proposal_reservoir_samples, reservoirPos, 0),
        texelFetch(radiosity_proposal_reservoir_meta, reservoirPos, 0),
        RAB_EmptySurface(),
        false
    );
    return reservoir;
}

LtScatterCurrentSample lt_scatter_make_empty_current_sample() {
    LtScatterCurrentSample currentSample;
    currentSample.isValid = false;
    currentSample.hasPositivePHat = false;
    currentSample.reservoir = RTXDI_EmptyDIReservoir();
    currentSample.reconnectionData = ReconnectionData_init();
    currentSample.confidence = 0.0f;
    return currentSample;
}

float ScatterTemporalResampling_motion_vector_confidence(
    ivec2 pixel,
    float newConfidence)
{
    vec2 prevPixel = lt_temporal_previous_pixel_center(pixel) - vec2(0.5f);
    ivec2 topLeft = ivec2(floor(prevPixel));
    vec2 fractionalCoord = clamp(prevPixel - vec2(topLeft), vec2(0.0f), vec2(1.0f));

    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 neighborPixel = topLeft + ivec2(x, y);
            if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                continue;
            }

            float bilinearWeight =
                ((x == 0) ? (1.0f - fractionalCoord.x) : fractionalCoord.x) *
                ((y == 0) ? (1.0f - fractionalCoord.y) : fractionalCoord.y);
            newConfidence += bilinearWeight * lt_scatter_confidence_mis_weight(
                ScatterTemporalResampling_load_previous_reservoir_confidence(neighborPixel)
            );
        }
    }

    return min(newConfidence, SCATTER_RECONNECTION_CONFIDENCE_MAX);
}

LtScatterCurrentSample lt_ScatterTemporalResampling_load_current_sample(
    uint reservoirIdx,
    ivec2 pixel,
    RAB_Surface surface,
    RTXDI_DIReservoir currReservoir)
{
    LtScatterCurrentSample currentSample = lt_scatter_make_empty_current_sample();
    currentSample.reservoir = currReservoir;
    // Reference parity: load the Stage-1 current-frame reconnection snapshot
    // that was published by the Java pipeline before Stage 2c. This mirrors the
    // structured-buffer read of currReconnectionData[reservoirIdx] exactly.
    reservoirIdx = reservoirIdx;
    // scatter_reconnection* are half-width when checkerboard is active; halve x.
    ivec2 reservoirPos = RTXDI_PixelPosToReservoirPos(pixel, ph_restir_active_checkerboard_field);
    vec4 reconnection0 = texelFetch(scatter_reconnections, ivec3(reservoirPos, 0), 0);
    vec4 reconnection1 = texelFetch(scatter_reconnections, ivec3(reservoirPos, 1), 0);
    vec4 reconnection2 = texelFetch(scatter_reconnections, ivec3(reservoirPos, 2), 0);
    vec4 reconnection3 = texelFetch(scatter_reconnections, ivec3(reservoirPos, 3), 0);
    vec4 reconnection4 = texelFetch(scatter_reconnections, ivec3(reservoirPos, 4), 0);
    ReconnectionData storedReconnection;
    scatter_unpack_reconnection(
        reconnection0,
        reconnection1,
        reconnection2,
        reconnection3,
        reconnection4,
        0.0f,
        0.0f,
        storedReconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixel, false, currentSample.reservoir, storedReconnection);
    currentSample.confidence = PathReservoir_getConfidence(currentSample.reservoir);
    currentSample.isValid = true;
    currentSample.reconnectionData = storedReconnection;
    currentSample.hasPositivePHat = ph_luminance(PathReservoir_getIntegrand(currentSample.reservoir)) > 0.0f;
    return currentSample;
}

// ---------------------------------------------------------------------------
// Canonical current-sample MIS (Reference: ScatterTemporalResampling.rt.slang:80-104).
//
// Shifts the current reservoir/reconnection into the previous-frame domain,
// reads prevReservoirs[linearizePixel(floor(shiftedCurr.fractionalPixel))] for
// its confidence, and computes `currSampleMIS = m1 / (m1 + m2)`.
//
// Returns 1.0 when:
//   * the candidate is not valid (reference's `else`-branch)
//   * the current->previous reprojection falls off-screen
//     (reference's `validateIntegerPixelBounds(scatteredPixel) == false`
//      drops m2 to 0 -> MIS = m1/(m1+0) = 1 regardless of m1)
//   * the shift itself fails (shiftedCurr.valid=false -> radiance=0 -> m2=0)
// Returns 0.0 when m1 is 0 (integrand is zero or confidence is zero).
// ---------------------------------------------------------------------------
// Current-sample MIS in the shape used by ScatterTemporalResampling::run(pixel).
float ScatterTemporalResampling_compute_curr_sample_mis(
    LtScatterCurrentSample currSample,
    ivec2 pixel,
    RAB_Surface surface)
{
    if (!currSample.hasPositivePHat) {
        return 1.0f;
    }

    LtScatterShiftedPath shiftedCurr;
    RTXDI_DIReservoir shiftedReservoir;
    ReconnectionData shiftedReconnection;
    float shiftedJacobian;
    if (!lt_scatter_update_shifted_reservoir_to_previous_frame(
            currSample.reconnectionData,
            currSample.reservoir,
            false,
            shiftedCurr,
            shiftedReservoir,
            shiftedReconnection,
            shiftedJacobian)) {
        return 1.0f;
    }

    ivec2 scatteredPixel = ivec2(floor(shiftedCurr.fractionalPixel));
    if (!lt_is_viewport_uv_in_bounds(scatteredPixel)) {
        return 1.0f;
    }

    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);

    return lt_scatter_canonical_mis(
        lt_scatter_radiance_phat(PathReservoir_getIntegrand(currSample.reservoir)),
        lt_scatter_confidence_mis_weight(currSample.confidence),
        lt_scatter_radiance_phat(shiftedCurr.radiance),
        shiftedJacobian,
        lt_scatter_confidence_mis_weight(prevReservoirConfidence),
        true
    );
}

bool ScatterTemporalResampling_process_contributor(
    inout RTXDI_DIReservoir dstReservoir,
    inout ReconnectionData dstReconnectionData,
    inout float newConfidence,
    ivec2 scatteredPixel,
    ivec2 pixel,
    RTXDI_DIReservoir currReservoir,
    ReconnectionData currReconnectionData,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg)
{
    ivec2 previousReservoirPixel = ScatterTemporalResampling_previous_reservoir_pixel(scatteredPixel);
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(previousReservoirPixel)
    );
    ReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(previousReservoirPixel);
    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
    RAB_Surface targetSurface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(targetSurface)) {
        return false;
    }

    LtScatterShiftedPath shiftedPrev;
    RTXDI_DIReservoir shiftedReservoir;
    ReconnectionData shiftedPrevReconnectionData;
    float shiftedJacobian;
    if (!lt_scatter_update_shifted_reservoir(
            prevReconnectionData,
            prevReservoir,
            true,
            false,
            targetSurface,
            pixel,
            shiftedPrev,
            shiftedReservoir,
            shiftedPrevReconnectionData,
            shiftedJacobian)) {
        return false;
    }

    float prevSampleMIS = 0.0f;
    if (ph_luminance(PathReservoir_getIntegrand(prevReservoir)) > 0.0f) {
        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * lt_scatter_confidence_mis_weight(currReservoirConfidence);
        float m2 = lt_scatter_radiance_phat(PathReservoir_getIntegrand(prevReservoir))
            * lt_scatter_confidence_mis_weight(prevReservoirConfidence);
        float denominator = m1 + m2;
        prevSampleMIS = (denominator > 0.0f) ? (m2 / denominator) : 0.0f;
    }

    bool prevSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        newConfidence,
        prevSampleMIS,
        shiftedPrev.radiance,
        shiftedJacobian,
        lt_scatter_compute_ucw(prevReservoir, PathReservoir_getIntegrand(prevReservoir)),
        prevReservoirConfidence,
        shiftedReservoir,
        sg
    );
    if (prevSelected) {
        dstReconnectionData = shiftedPrevReconnectionData;
    }
    return prevSelected;
}
//   if (length(motionVector) < 1e-6) motionVector = 0
//   prevPixel = float2(pixel) + motionVector * float2(frameDim)
//   topLeft = int2(floor(prevPixel))
//   frac = saturate(prevPixel - float2(topLeft))
//   for (x,y in {0,1}):
//       bw = lerp(1-x, x, frac.x) * lerp(1-y, y, frac.y)
//       newConfidence += bw * prevReservoirs[neighbor].confidence
//   dstReservoir.confidence = min(confidenceCap, newConfidence)
//
// `lt_temporal_previous_pixel_center` already applies the motion-vector
// delta (returns `pixel + 0.5 + motionVector`).  Subtracting 0.5 recovers
// the reference's `prevPixel = pixel + motionVector * frameDim`.
// Returns the new confidence clamped to SCATTER_RECONNECTION_CONFIDENCE_MAX.
// ---------------------------------------------------------------------------
// Loads previous-frame confidence directly from the previous reservoir buffer,
// matching prevReservoirs[neighborIndex].confidence in the reference stage.
ivec2 ScatterTemporalResampling_previous_reservoir_pixel(
    ivec2 previousPixel)
{
    return previousPixel;
}

float ScatterTemporalResampling_load_previous_reservoir_confidence(
    ivec2 neighborPixel)
{
    if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
        return 0.0f;
    }

    ivec2 previousReservoirPixel = ScatterTemporalResampling_previous_reservoir_pixel(neighborPixel);
    if (!lt_is_viewport_uv_in_bounds(previousReservoirPixel)) {
        return 0.0f;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(previousReservoirPixel)
    );

    return PathReservoir_getConfidence(prevReservoir);
}


#endif // PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS

#endif // PHOTONICS_RESTIR_DI_SCATTER_IMPL_GLSL
