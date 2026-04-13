# Combining Area ReSTIR and Reservoir Splatting

## Purpose and high-level synthesis

This document explains how the two reference systems can be combined into one temporal-spatial resampling pipeline for a real-time ray tracing renderer:

- **Area ReSTIR** contributes **fractional-domain reuse** over pixel area and lens area. Its main idea is that a reservoir should not only represent a light/path sample, but also the **subpixel sample** and optionally the **lens sample** that generated the primary ray. Reuse is then performed across a **continuous image/lens domain** using replay/reconnection shifts and MIS over alternative mappings. See the reservoir payload in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Reservoir.slang:16-29` and the area-sample payload utilities in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/PixelAreaSampleData.slang:23-32`.
- **Reservoir Splatting** contributes **many-to-one temporal reprojection/scatter**. Instead of only gathering one previous reservoir at the current pixel’s reprojected location, it can **scatter many previous-frame reservoirs** into current-frame pixels and then MIS-resample them. Its reservoir stores radiance plus geometric state for reconnection/reprojection shifts in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Reservoir.slang:73-132` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReconnectionData.slang:89-166`.

The most useful hybrid interpretation is:

1. Use **Area ReSTIR’s sample domain representation** for each reservoir: keep `(selected light/path sample, subpixel UV, lens UV, path sample type, target pdf)`.
2. Add **Reservoir Splatting’s reconnection metadata** so the same reservoir can also be reprojected/scattered between frames with correct Jacobians.
3. In temporal reuse, run **two complementary operators**:
   - **Gather-style fractional reuse** for the 2x2 previous-pixel footprint and lens/subpixel shifts.
   - **Scatter-style reprojection reuse** for previous reservoirs that would otherwise be missed or aliased under one-to-one motion-vector gathering.
4. Keep **Area ReSTIR’s shift-MIS logic** to combine random replay / lens copy / primary-hit reconnection alternatives.
5. Keep **Reservoir Splatting’s scatter cell binning** to accept multiple previous contributors per current pixel.

In short: **Area ReSTIR solves continuous-domain reuse inside a pixel/lens footprint; Reservoir Splatting solves many-to-one temporal transport of reservoirs across frames.** The hybrid should use splatting to decide **which previous reservoirs can contribute**, then use Area-ReSTIR-style shift evaluation to decide **how they are mapped and MIS-weighted** in the current domain.

---

## Paper intent summarized

### Area ReSTIR intent

The Area ReSTIR reference treats ReSTIR not as reuse of only a discrete light sample, but reuse of a **full primary-ray sample point** over:

- screen-space pixel area,
- lens area for depth of field,
- and optionally path class / emission sampling.

That is explicit in the reservoir payload fields `pixelSampleUV`, `lensSampleUV`, `pathSample`, and `targetPdf` in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Reservoir.slang:18-29`. The implementation maintains current and previous `EvalContext` values and retraces shifted primary rays with `retracePrimaryRay()` in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/PixelAreaSampleData.slang:72-108`.

The central goal is to make temporal/spatial reuse robust when the target domain is not a discrete pixel center, especially under **TAA-like subpixel jitter** and **DoF**.

### Reservoir Splatting intent

Reservoir Splatting addresses the limitation of strictly gather-based temporal reuse: a current pixel may correspond to a **fractional previous location** or may receive contributions from **multiple previous reservoirs**. The implementation therefore:

- generates initial path reservoirs,
- collects/gathers previous-frame candidates under several modes,
- or reprojects/scatters previous reservoirs into current pixels,
- sorts them into per-pixel bins,
- then merges current plus scattered reservoirs with MIS.

That is visible in the temporal scatter stages:

- reprojection/scatter indexing in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:50-175`,
- sorting in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SortReprojectedReservoirs.cs.slang:36-95`,
- temporal merge in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:44-173`.

Its core intent is therefore **reservoir transport by reprojection and splatting**, rather than only reservoir lookup by motion-vector gather.

---

## Recommended hybrid pipeline

A practical combined pipeline should be organized as follows.

### Stage 0. Persistent state and reservoir schema

You need one persistent per-pixel reservoir structure that merges both references.

### Area ReSTIR fields

From `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Reservoir.slang:16-29`:

- `lightSample`
- `M`
- `weight`
- `pixelSampleUV`
- `lensSampleUV`
- `pathSample`
- `targetPdf`

### Reservoir Splatting fields

From `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Reservoir.slang:73-132` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReconnectionData.slang:89-166`:

- reservoir accumulation: `confidence`, `totalWeight`, `integrand`, `subPixel`
- reconnection state: `subPixel`, `lensSample`, `time`, `pathLength`, `firstHit`, `firstWi`, `secondHit`, `secondWo`, `lightIsNEE`, `lightIsDistant`, `lightPdf`, `subPixelJacobian`, `lensVertexJacobian`, `secondaryPathJacobian`, `irradiance`, `earlyThroughput`

### Hybrid recommendation

Use one logical reservoir record with:

- **sample identity**: light/path sample selection from Area ReSTIR,
- **evaluation weight**: both `targetPdf`, `M`, `weight` and/or `integrand`, `totalWeight`,
- **continuous-domain coordinates**: `pixelSampleUV`, `lensSampleUV`, `subPixel`,
- **shift transport metadata**: all of `ReconnectionData`.

The hybrid reservoir should be able to do both:

- **RIS-style selection over target pdfs** like Area ReSTIR,
- **Jacobian-corrected sample transport** like Reservoir Splatting.

---

## Stage 1. Initial sample generation

### Area ReSTIR implementation

Initial sampling is in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:25-260`.

#### What it does

For each pixel, it:

1. loads surface state,
2. reads per-pixel subpixel and lens samples,
3. constructs an `EvalContext`,
4. samples from a light tile and optionally BRDF samples,
5. merges candidates into one reservoir,
6. stores the selected sample plus evaluation context.

Key code locations:

- input subpixel/lens reads: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:120-125`
- light-tile candidate generation: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:164-177`
- BRDF candidate generation: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:179-238`
- optional emission/path-sample candidate: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:242-247`
- reservoir writeback: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:249-260`

#### Data read

- `surfaceData`, `centerSurfaceData`, `normalDepth`, `viewDir`, `lightTileData`
- `pixelAreaSampleData.subPixelUV`, `pixelAreaSampleData.lensUV`
- scene/light state via `Lights`

#### Data written

- `reservoirs`
- `resEvalContext`
- `pixelCenterEvalContext`
- `debugOutput`

#### Relevant uniforms / parameters

From the stage struct in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:44-67`:

- `frameDim`, `frameIndex`
- `brdfCutoff`
- `resampleEmissionMode`
- `filterRadius`, `filterAlpha`, `filterNorm`
- `restirPassIdx`

#### Core equation

Streaming RIS update:

\[
w_i = m_i \frac{\hat p(x_i)}{p(x_i)}
\]

implemented as `sampleWeight = misWeight * targetPdf / sourcePdf` in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Resampling.slang:101-117`.

The reservoir update is:

\[
W \leftarrow W + w_i, \quad M \leftarrow M + 1,
\]

and selection probability is:

\[
P(\text{replace}) = \frac{w_i}{W}.
\]

This appears in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Resampling.slang:104-116` and `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Resampling.slang:121-137`.

### Reservoir Splatting implementation

Initial candidate generation is in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/InitialCandidates.cs.slang:46-156`.

#### What it does

It path traces one or more spp per pixel and accumulates them into one `PathReservoir`.

Key lines:

- path generation: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/InitialCandidates.cs.slang:80-115`
- reservoir update: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/InitialCandidates.cs.slang:52-75`
- write reservoir and reconnection data: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/InitialCandidates.cs.slang:57-66`

#### Data read

- `PathTracer` scene/path state

#### Data written

- `currReservoirs`
- `currReconnectionData`

#### Relevant uniforms / parameters

From the struct in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/InitialCandidates.cs.slang:46-50`:

- `params`
- `currReservoirs`
- `currReconnectionData`

and `PathTracerParams` in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Params.slang:81-139`.

#### Core equation

The initial candidate reservoir uses uniform per-sample MIS weight `1 / kSamplesPerPixel` in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/InitialCandidates.cs.slang:57-63`:

\[
m_i = \frac{1}{M}
\]

and then reservoir composition uses the selected candidate’s UCW.

### How to combine them in Stage 1

Use **Area ReSTIR’s initial candidate semantics** to store the selected sample’s:

- light/path choice,
- subpixel UV,
- lens UV,
- target pdf,
- selected eval context,

but additionally store **Reservoir Splatting reconnection data** for that selected sample. In practice, after the selected sample is known, you need to serialize the primary hit, lens sample, time, first/second-hit transport data, and Jacobian terms into a companion reconnection record.

That makes the initial reservoir ready for both:

- Area-style replay/reconnection,
- Splatting-style reprojection.

---

## Stage 2. Fractional temporal gather reuse

This is the stage where Area ReSTIR is strongest.

### Area ReSTIR implementation

There are two temporal passes:

- integer motion / simpler temporal pass: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling.cs.slang:24-170`
- fractional motion / 2RIS pass: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:27-690`

The fractional pass is the one that matters most for the hybrid.

#### What it does

It:

1. reprojects the current pixel to previous-frame floating coordinates,
2. identifies the 2x2 previous-pixel neighborhood,
3. computes bilinear overlap weights,
4. checks whether previous samples already lie in the target range,
5. if needed, retraces shifted samples using replay or reconnection,
6. combines them with MIS.

Important code locations:

- previous 2x2 neighbor setup: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:38-46`
- bilinear weights: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:132-149`
- target-range tests: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:100-130`
- process_2RIS entry: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:179-227`
- previous-neighbor reservoir loop: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:233-320`

#### Data read

- `motionVectors`
- `prevReservoirs`, `prevResEvalContext`, `prevPixelCenterEvalContext`
- `prevCameraData`
- precomputed temporal MIS buffers: `temporalMISPDFs`, `temporalMISJacobianData`, `temporalMISPrimHitNormals`, `temporalMISPrimaryHits`
- `pixelAreaSampleData`

#### Data written

- `reservoirs`
- `resEvalContext`
- `debugOutput`

#### Relevant uniforms / parameters

From `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:47-83`:

- `frameDim`, `frameIndex`
- `normalThreshold`, `depthThreshold`
- `useMFactor`
- `temporalReuseMode`
- `shiftMappingModeRIS1`, `shiftMappingModeRIS2`
- `optimizeShift2RIS`
- `shiftsPerPixel`
- `resampleEmissionMode`
- `restirPassIdx`
- `filterRadius`, `filterAlpha`, `filterNorm`
- `pixelAreaSampleData`

#### Core equations

Bilinear confidence / overlap weights:

\[
w_{00}=(1-x)(1-y),\quad
w_{10}=x(1-y),\quad
w_{01}=(1-x)y,\quad
w_{11}=xy
\]

implemented in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:132-149`.

Pairwise MIS helpers are defined in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Resampling.slang:192-219`, e.g.

\[
m = \frac{c_0 \hat p_i(T(y))}{(c_{sum}-c_1)\hat p_i(T(y)) + c_1 \hat p_c(y)}
\]

in the non-defensive non-canonical form at `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Resampling.slang:192-197`.

### Reservoir Splatting gather-side implementation

Reservoir Splatting has a gather-oriented temporal collection pass in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:43-257`.

#### What it does

It builds an intermediate previous-frame reservoir under three modes:

- `Fast`: bilinear 2x2 reuse if a previous sample naturally lands inside the current pixel support,
- `Clamped`: nearest-pixel reuse,
- `Robust`: shift neighbor samples so each can fit the floating reservoir and apply generalized balance MIS.

Key locations:

- motion vector to floating previous pixel: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:80-104`
- `Fast` branch: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:108-142`
- `Clamped` branch: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:143-156`
- `Robust` branch: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:157-240`

#### Data read

- `motionVectors`
- `shiftedPaths` for precomputed robust shifts
- `prevReservoirs`, `prevReconnectionData`

#### Data written

- `intermediateReservoirs`
- `intermediateReconnectionData`
- `floatingCoords`

#### Relevant uniforms / parameters

From `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:43-58`:

- `params`
- `useConfidenceWeights`
- `motionVectors`
- `gatherOption`
- `shiftedPaths`
- `floatingCoords`
- `prevReservoirs`, `intermediateReservoirs`
- `prevReconnectionData`, `intermediateReconnectionData`

#### Core equations

Relative shifted subpixel:

\[
\Delta u = o + u_{prev} - f
\]

where `o` is the 2x2 integer offset and `f` is the previous floating coordinate fraction. This is implemented at `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:127-135` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:176-186`.

Robust MIS accumulation uses:

\[
m_i = \frac{w_i \hat p_i}{\sum_j w_j \hat p_{i\rightarrow j} J_{i\rightarrow j}}
\]

which is built explicitly in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:199-227`.

### How to combine them in Stage 2

Use **Area ReSTIR’s fractional 2x2 gather logic as the primary temporal reuse path**, but replace or augment its candidate set with **Reservoir Splatting’s robust floating-domain candidates**.

Concretely:

1. Reproject current pixel to previous floating location.
2. Enumerate the 2x2 neighborhood.
3. For each previous neighbor reservoir:
   - if the sample already lies in the target range, reuse directly,
   - else evaluate one or more shifts:
     - random replay / lens vertex copy,
     - primary hit reconnection,
     - optional splatting reprojection shift.
4. MIS-weight these alternatives exactly as Area ReSTIR already does.

This stage should output:

- one temporally reused hybrid reservoir,
- updated `EvalContext` in the current domain,
- updated reconnection data in the current domain,
- floating coordinate / confidence metadata for future stages.

---

## Stage 3. Temporal splatting / scatter reuse

This is the stage contributed primarily by Reservoir Splatting.

### 3.1 Reproject previous reservoirs into current frame

Implementation: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:46-196`.

#### What it does

For each previous reservoir:

1. reconstruct the old sample’s first-hit geometry and lens state,
2. orient previous and current camera at the right shutter times,
3. form a current-frame ray corresponding to the old sample,
4. visibility-test that mapping,
5. project it into current NDC / pixel space,
6. append the source reservoir index into the target pixel’s scatter list.

#### Data read

- `prevReservoirs`
- `prevReconnectionData`
- scene camera and path tracer visibility

#### Data written

- `globalCounters`
- `cellCounters`
- `reservoirIndices`
- `scatteredReservoirs`

#### Relevant uniforms / parameters

From `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:46-58`:

- `params`
- `globalCounters`, `cellCounters`
- `reservoirIndices`, `scatteredReservoirs`
- `prevReservoirs`, `prevReconnectionData`

#### Core equations

Lens-world origin:

\[
\mathbf{o}' = \mathbf{c} + r_a (u_l \hat U + v_l \hat V)
\]

implemented in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:91-96`.

Film/NDC projection:

\[
\mathrm{film} = \mathbf{l}_{film} + |W| \frac{d_{xy}}{d_z},
\quad
\mathrm{ndc} = \frac{\mathrm{film}}{(|U|, |V|)}
\]

implemented in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:150-153`.

### 3.2 Sort scattered reservoirs into per-pixel bins

Implementation: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SortReprojectedReservoirs.cs.slang:36-95`.

#### What it does

It computes cell prefix sums and writes a dense sorted scatter list for each pixel.

#### Data read/write

- reads/writes `globalCounters`, `cellCounters`, `reservoirIndices`, `scatteredReservoirs`
- writes `cellOffsets`, `sortedReservoirs`

This stage is pure indexing infrastructure.

### 3.3 Merge current plus scattered reservoirs

Implementation: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:44-173`.

#### What it does

For each current pixel it:

1. starts from the current reservoir,
2. computes MIS between current-domain and reprojected-domain versions of the current sample,
3. iterates over all scattered previous reservoirs for that pixel,
4. shifts each previous reservoir into the current domain,
5. merges them with Jacobian-corrected UCW,
6. updates confidence using the 2x2 motion-vector footprint.

Key lines:

- current-sample MIS against scatter reprojection: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:77-107`
- scattered reservoir loop: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:112-148`
- confidence update using bilinear 2x2 previous footprint: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:150-171`

#### Data read

- `motionVectors`
- `cellCounters`, `cellOffsets`, `sortedReservoirs`
- `prevReservoirs`, `prevReconnectionData`
- `currReservoirs`, `currReconnectionData`

#### Data written

- `currReservoirs`
- `currReconnectionData`

#### Core equations

Reservoir merge weight:

\[
w = m \cdot \hat p \cdot W_{src} \cdot J
\]

implemented as `w = mis * pHat * other.computeUCW() * jacobian` in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Reservoir.slang:83-96`.

Current-vs-scatter MIS:

\[
m_{curr} = \frac{m_1}{m_1 + m_2}
\]

with `m1` from current-domain density and `m2` from shifted previous-domain density, implemented at `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:80-104`.

### How to combine them in Stage 3

This stage should happen **after** Stage 2 and should be treated as an **extra temporal candidate expansion** stage, not a replacement.

Recommended hybrid behavior:

1. Take the output reservoir from Stage 2 as the current canonical candidate.
2. Scatter all previous-frame reservoirs into current pixels using reprojection.
3. For each scattered reservoir, instead of only applying the splatting reprojection shift, also evaluate:
   - replay/lens-copy shift,
   - primary-hit reconnection shift,
   - scatter reprojection shift.
4. Combine these alternatives with Area ReSTIR-style pairwise or balance MIS.
5. Merge all resulting candidates into the current hybrid reservoir.

This is where the two methods are most complementary:

- splatting broadens the set of temporal candidates,
- area shifts improve how each candidate is mapped into the current domain.

---

## Stage 4. Spatial reuse

### Area ReSTIR implementation

Implementation: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:25-281`.

#### What it does

For each pixel it:

1. samples a set of spatial neighbors,
2. filters them by normal/depth/hit-type,
3. computes a confidence-weight sum,
4. resamples neighbors using pairwise MIS,
5. for area mode, optionally chooses replay vs reconnection shifts per neighbor.

Key lines:

- neighbor enumeration: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:97-124`
- point-reservoir spatial reuse: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:127-162`
- area-reservoir spatial reuse: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:163-267`

#### Data read

- `prevReservoirs`, `prevResEvalContext`, `pixelCenterEvalContext`
- `neighborOffsets`
- `normalDepth`

#### Data written

- `reservoirs`
- `resEvalContext`
- `debugOutput`

#### Relevant uniforms / parameters

From `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:37-66`:

- `frameDim`, `frameIndex`
- `normalThreshold`, `depthThreshold`
- `useMFactor`
- `neighborCount`, `gatherRadius`
- `shiftMappingMode`
- `randomReplaySampleWeight`
- `misSampleSelection`
- `rejectNeighborPixelForNormalDepth`
- `rejectNeighborPixelForHitType`
- `resampleEmissionMode`
- `restirPassIdx`, `spatialPassIdx`
- `pixelAreaSampleData`

### Reservoir Splatting implementation

Implementation: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang:45-184`.

#### What it does

It performs spatial GRIS between center and neighbors, splitting neighbor shifts between:

- lens vertex copy,
- primary hit reconnection.

It is structurally very close to Area ReSTIR’s spatial area reuse, but expressed with reconnection data and jacobians rather than `EvalContext`-centric target-pdf reevaluation.

Key lines:

- DoF split probabilities from CoC: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang:76-97`
- center-to-neighbor shift evaluation: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang:125-143`
- neighbor-to-center shift evaluation: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang:144-170`
- final normalization by `(validNeighbors + 1)`: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang:176-183`

#### Data read

- `prevReservoirs`, `prevReconnectionData`
- `neighborOffsets`, `vbuffer`

#### Data written

- `currReservoirs`, `currReconnectionData`

### How to combine them in Stage 4

Use Area ReSTIR’s **neighbor filtering policy and area-domain interpretation**, but use Reservoir Splatting’s **explicit Jacobian tracking** for each spatial shift.

Recommended rule:

- Keep Area ReSTIR’s valid-neighbor checks and confidence sums.
- For each neighbor, evaluate both:
  - replay / lens-copy shift,
  - reconnection shift,
  - optionally scatter-style subpixel reprojection if temporal splat data remains useful.
- Convert each into a common candidate weight representation:

\[
w_i = m_i \hat p_i W_i J_i
\]

then stream them into the same hybrid reservoir.

---

## Stage 5. Final resolve / shading

### Area ReSTIR implementation

The final selected reservoir is evaluated into a `FinalSample` in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvaluateFinalSamples.cs.slang:24-144`.

Important lines:

- path-length dependent evaluation: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvaluateFinalSamples.cs.slang:57-81`
- weighted incident radiance write: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvaluateFinalSamples.cs.slang:103-120`
- camera persistence for next frame: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvaluateFinalSamples.cs.slang:129-130`

Output payload is defined in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/FinalSample.slang:33-84`.

### Reservoir Splatting implementation

Resolve is simpler: it directly outputs

\[
L = f \cdot \mathrm{UCW}
\]

using `currReservoir.integrand * currReservoir.computeUCW()` in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ResolveReSTIR.cs.slang:55-63`.

### How to combine them in Stage 5

Use Area ReSTIR’s final shading path because it retains the semantic identity of the selected sample (`lightSample`, `pathSample`, subpixel/lens UV, per-pass MIS), but keep Reservoir Splatting’s UCW-style resolve available as a debugging cross-check.

Recommended hybrid finalization:

1. Selected hybrid reservoir provides:
   - chosen light/path sample,
   - selected current-domain `EvalContext`,
   - reconnection metadata.
2. Final shading evaluates the chosen sample exactly in current domain.
3. Store:
   - final radiance,
   - sampled direction and distance,
   - selected `pixelSampleUV`, `lensSampleUV`,
   - current primary hit / camera data for next frame.

---

## Shared math and how the two methods align

## 1. Streaming reservoir selection

Both methods rely on the same reservoir-selection principle:

\[
W_n = \sum_i w_i,
\qquad
P(\text{keep } x_i) = \frac{w_i}{W_n}
\]

This is explicit in:

- Area ReSTIR: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Resampling.slang:104-116`
- Reservoir Splatting: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Reservoir.slang:85-96`

## 2. Unbiased contribution weight

Both use the same UCW logic:

\[
W^{ucw} = \frac{W}{\hat p(x^*)}
\]

implemented in:

- Area ReSTIR reservoir conversion/final weight logic around `weight = weightSum / targetPdf` in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling.cs.slang:120-121`, `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:149-151`, and `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:254-255`
- Reservoir Splatting `computeUCW()` in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Reservoir.slang:112-116`

## 3. Jacobian-corrected shift transport

Reservoir Splatting makes this explicit:

\[
\hat p_y(T(x)) = \hat p_x(x) \, |J_T|
\]

where `J_T` may include:

- `subPixelJacobian`
- `lensVertexJacobian`
- `secondaryPathJacobian`

from `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReconnectionData.slang:119-123` and shift evaluation in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ShiftMapping.slang:90-180`.

Area ReSTIR uses the same idea, but often hides it inside target-pdf reevaluation and helper functions. The hybrid should standardize all shifts into explicit Jacobian-corrected candidate weights.

## 4. Bilinear fractional-motion weighting

Both methods use the same 2x2 overlap logic. Reservoir Splatting directly computes bilinear weights in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:129-130` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:166-167`; Area ReSTIR does so in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:132-149`.

---

## Exact implementation mapping by hybrid stage

## A. Reservoir/state representation

### Area ReSTIR files

- reservoir payload: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/Reservoir.slang:16-29`
- area-sample state and retracing helpers: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/PixelAreaSampleData.slang:23-108`
- evaluation context for target pdfs and BSDF/light evaluation: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvalContext.slang:28-316`

### Reservoir Splatting files

- path reservoir: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Reservoir.slang:73-132`
- shifted-path payload and reconnection state: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReconnectionData.slang:35-166`

## B. Initial generation

### Area ReSTIR

- `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:25-260`

### Reservoir Splatting

- `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/InitialCandidates.cs.slang:46-156`

## C. Temporal gather / fractional reuse

### Area ReSTIR

- integer temporal pass: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling.cs.slang:24-170`
- float-motion temporal pass: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:27-690`
- pretrace support for temporal MIS: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalMSAATracePrimaryRays.cs.slang:21-141`

### Reservoir Splatting

- gather collection: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:43-257`
- gather temporal merge: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/GatherTemporalResampling.rt.slang:46-235`
- floating coord helper: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/GatherHelper.slang:41-67`

## D. Temporal scatter / splatting

### Reservoir Splatting

- reprojection: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:46-196`
- sorting / prefix sums: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SortReprojectedReservoirs.cs.slang:36-95`
- merge scattered reservoirs: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterTemporalResampling.rt.slang:44-173`
- backup variant: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ScatterBackupTemporalResampling.rt.slang:46-282`
- multi-time partition reprojection: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/MultiReprojectTemporalSamples.rt.slang:46-167`
- multi-time partition merge: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/MultiScatterTemporalResampling.rt.slang:44-185`

## E. Spatial reuse

### Area ReSTIR

- `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:25-281`

### Reservoir Splatting

- `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang:45-184`

## F. Resolve/final shading

### Area ReSTIR

- final sample payload: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/FinalSample.slang:33-84`
- final evaluation: `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvaluateFinalSamples.cs.slang:24-144`

### Reservoir Splatting

- final resolve: `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ResolveReSTIR.cs.slang:35-63`

---

## Uniforms and resources you need in a true merged implementation

A combined pass set needs the union of both systems’ resources.

## Core per-frame uniforms

From Area ReSTIR and Reservoir Splatting parameter structs:

- `frameDim` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:57` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Params.slang:88-90`
- `frameIndex` / `frameCount` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:58` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Params.slang:92-94`
- random seed controls from `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Params.slang:81-87`

## Temporal reuse uniforms

- `motionVectors` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling.cs.slang:32` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:48`
- `prevCameraData` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling.cs.slang:39` and final persistence in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvaluateFinalSamples.cs.slang:44` and `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/EvaluateFinalSamples.cs.slang:129-130`
- `floatingCoords` from `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:52` and `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/GatherHelper.slang:45-48`
- `temporalReuseMode`, `shiftMappingModeRIS1`, `shiftMappingModeRIS2`, `shiftsPerPixel` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:71-77`
- `gatherOption` from `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:49`
- `useConfidenceWeights` from `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:45-46`

## Spatial reuse uniforms

- `neighborOffsets`, `neighborCount`, `gatherRadius` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:44` and `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:55-56`, and mirrored in `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang:50-55`
- `normalThreshold`, `depthThreshold` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:52-53`
- shift-selection controls such as `randomReplaySampleWeight`, `misSampleSelection`, `shiftMappingMode` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/SpatialResampling.cs.slang:58-66`

## Area/lens reuse uniforms

- `pixelAreaSampleData` with `subPixelUV`, `prevSubPixelUV`, `lensUV`, `prevLensUV` from `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/PixelAreaSampleData.slang:23-32`

## Scatter infrastructure buffers

- `globalCounters`, `cellCounters`, `reservoirIndices`, `scatteredReservoirs` from `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:50-58`
- `cellOffsets`, `sortedReservoirs` from `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SortReprojectedReservoirs.cs.slang:49-50`

## Per-pixel persistent buffers

- current/previous reservoirs
- current/previous evaluation contexts
- current/previous reconnection data
- optional temporal MIS helper buffers from Area ReSTIR: `temporalMISPDFs`, `temporalMISJacobianData`, `temporalMISPrimHitNormals`, `temporalMISPrimaryHits` in `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:55-60`

---

## Code snippets that best show the merge points

## 1. Area ReSTIR initial reservoir carries pixel/lens sample state

From `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/InitialResampling.cs.slang:120-125`:

```slang
SurfaceData sd = surfaceData[pixelIndex];
float2 subPixelUV = pixelAreaSampleData.subPixelUV[pixel];
float2 lensUV = pixelAreaSampleData.lensUV[pixel];
EvalContext evalContext = EvalContext::create(pixel, frameDim, sd, viewDir[pixel]);
```

This is the exact place where the hybrid should attach `ReconnectionData` construction for the selected sample.

## 2. Reservoir Splatting reservoir merge is already Jacobian-corrected

From `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/Reservoir.slang:83-96`:

```slang
float pHat = luminance(integrand);
float w = mis * pHat * other.computeUCW() * jacobian;
this.totalWeight = this.totalWeight + w;
this.confidence = min(this.confidence + other.confidence, PathReservoir::confidenceCap);
```

This is the cleanest generic merge formula for a hybrid implementation.

## 3. Area ReSTIR bilinear weights for fractional temporal reuse

From `reference/repos/Area-ReSTIR/Source/Modules/AreaReSTIR/TemporalResampling_FloatMotion.cs.slang:132-149`:

```slang
weights[0] = (1.0f - x0) * (1.0f - y0);
weights[1] = (reprojectedPixelSize.x - (1.0f - x0)) * (1.0f - y0);
weights[2] = (1.0f - x0) * (reprojectedPixelSize.y - (1.0f - y0));
weights[3] = (reprojectedPixelSize.x - (1.0f - x0)) * (reprojectedPixelSize.y - (1.0f - y0));
```

This should remain the confidence/source-domain weighting basis in the hybrid temporal gather stage.

## 4. Reservoir Splatting robust temporal gather evaluates all neighbor mappings

From `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/CollectTemporalSamples.cs.slang:199-227`:

```slang
float pHatSource = luminance(neighborReservoir.integrand);
float sourceWeight = bilinearWeight * pHatSource * (useConfidenceWeights ? neighborReservoir.confidence : 1.0f);
float totalPHat = sourceWeight;
...
float misWeight = (totalPHat > 0.0f) ? sourceWeight / totalPHat : 0.0f;
```

This is the reservoir-splatting analogue of Area ReSTIR’s pairwise/multi-shift MIS. In a unified design, this should be generalized to use Area-ReSTIR-style target-pdf evaluation where available.

## 5. Reservoir Splatting scatter indexing enables many-to-one temporal reuse

From `reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ReprojectTemporalSamples.rt.slang:167-175`:

```slang
uint index;
InterlockedAdd(globalCounters[kCounterIndexDataCount], 1, index);

uint cellIndex;
InterlockedAdd(cellCounters[linearizedIndex], 1, cellIndex);

reservoirIndices[index] = uint2(linearizedIndex, cellIndex);
scatteredReservoirs[index] = pixel;
```

This is the mechanism missing from plain Area ReSTIR temporal reuse and should be preserved almost as-is.

---

## Recommended final merged stage ordering

The most coherent execution order is:

1. **Generate primary samples / initial reservoirs**
   - Area-style initial RIS over light/BRDF/path candidates.
   - Store subpixel/lens sample and reconnection state.
2. **Optional pretrace for temporal shift MIS**
   - Area-style precomputed shifted p-hats/jacobians for neighboring previous pixels.
3. **Temporal gather reuse over 2x2 previous footprint**
   - Area-style fractional reuse.
   - Support replay, reconnection, and robust floating-domain shifts.
4. **Temporal scatter reuse**
   - Reproject all previous reservoirs.
   - Bin by current pixel.
   - Merge scattered candidates using the same hybrid shift MIS.
5. **Spatial reuse**
   - Reuse temporally improved reservoirs across neighbors.
   - Again allow replay/reconnection as alternative mappings.
6. **Final shading and persistence**
   - Evaluate selected sample in current domain.
   - Store current camera, current eval context, current reconnection data for next frame.

---

## Practical design conclusion

If you are implementing a combined renderer, the cleanest division of labor is:

- **Area ReSTIR owns the sample domain**:
  - subpixel sample,
  - lens sample,
  - target-pdf reevaluation,
  - shift-MIS between replay and reconnection mappings.
- **Reservoir Splatting owns temporal transport**:
  - reprojection of prior reservoirs,
  - visibility-checked scatter,
  - per-pixel binning of many previous contributors,
  - Jacobian-explicit merge of scattered samples.

The hybrid system therefore should treat **every temporal/spatial candidate as a transported area-sample reservoir**. For each candidate, you evaluate one or more mappings into the current domain, compute:

\[
w_i = m_i \hat p_i W_i J_i,
\]

stream it into the current reservoir, and preserve both:

- the selected sample identity needed for Area ReSTIR final shading,
- the selected reconnection state needed for future splatting/reprojection.

That is the most direct way to combine the two references without losing the strengths of either one.