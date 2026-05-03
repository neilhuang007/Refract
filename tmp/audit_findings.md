# Reservoir-Splatting Photonics Audit Findings

Status legend:
- C = Critical (causes flashing tiles / temporal non-convergence)
- H = High
- M = Medium  
- L = Low

## Stage 1: InitialCandidates (audit complete)

| # | Severity | Issue | Required change |
|---|----------|-------|-----------------|
| F1 | C | Fragment shader vs reference compute (numthreads(8,16,1)) | Convert to compute shader |
| F2 | C | isFirstSample uses sampleIdx==0; reference uses kSamplesPerPixel-1 | Flip condition |
| F3 | C | currReconnectionData unconditionally written; reference only on selected | Gate write on selection |
| F4 | C | subPixel update never captures winning candidate | Conditional update from path.reconnection.subPixel |
| F5 | C | Missing multi-bounce path-tracer loop (single SampleLightsForSurface) | Replicate while(path.isActive()) bounce loop |
| F6 | C | path.reconnection reset before addCandidateReservoir | Remove ReconnectionData_init() reset |
| F10 | C | Post-loop targetRatio reweight mutates totalWeight | Remove finalize reweight |
| F18 | C | Double-baked visibility (state.targetPdf *= lumV) | Remove targetPdf mutation |
| F19 | C | Visibility traced twice (sampling + finalize) | Remove second trace |
| F7 | H | RNG seed formula: kNumRenderPasses*(frameCount+seed)+0 | Match exact formula |
| F11 | H | Confidence reset to 1.0 overwrites accumulated count | Only reset on isFirstSample |
| F13 | H | transportAux0/1 zeroed and discarded | Wire to reconnection.irradiance.g/.b |
| F14 | H | ReconnectionData fields inferred not from per-hit | Populate per-bounce |

## Stage 3: CollectTemporalSamples (audit complete)

| # | Severity | Issue | Required change |
|---|----------|-------|-----------------|
| F1 | H | Missing OOB integer-pixel guard at entry | Add bounds check before motion-vector fetch |
| F2 | M | RNG seeded after floating-bounds guard (drift) | Move RNG init earlier |
| F3 | M | GatherData_getMotionVector pre-divides + .w guard | Match reference: raw .xy, no .w guard, mul by exact frameDim |
| F7 | H | Confidence not committed on early-out paths | Fold confidence accumulation into reservoir per-call |
| F8 | H | NaN guard scoped to Robust branch only | Move guard outside switch (post-switch position) |
| F11 | L | Redundant jacobian field re-writes | Remove redundant assignments |
| F14 | H | MRT layout: verify reconnection field completeness | Audit packing matches reference store |
| F15 | M | Empty-result uses different pack function | Use PathReservoir_packMeta uniformly |

## Stage 12: ResolveReSTIR (audit complete)

| # | Severity | Issue | Required change |
|---|----------|-------|-----------------|
| F5 | C | Full BRDF re-evaluation; reference is just integrand*UCW | Strip ResolveReSTIR_shade — directly multiply |
| F1 | M | Fragment vs compute shader | Architectural — keep if needed for NRD outputs |
| F2 | M | Checkerboard gate not in reference | Remove if not used elsewhere |
| F3 | H | Buffer slot indirection via lt_get_final_shading_input_buffer_index | Verify slot is correct post-spatial |
| F4 | H | Checkerboard-adjusted reservoir position | Use plain linearizePixel |
| F8 | L | UCW guard short-circuits write | Remove (becomes dead code after F5) |

## Stages pending: 2 (Robust), 4 (Gather), 5 (Reproject), 6 (Sort), 7 (Scatter), 8 (Backup), 9-11 (Multi), 13 (Shared)

