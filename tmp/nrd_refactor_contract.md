# NRD RELAX_DiffuseSpecular Refactor — Interface Contract

This document is the **single source of truth** for the rewritten Photonics NRD denoiser pipeline. All sub-agents MUST conform to these names, layouts, and contracts so the Java layer can wire them up without conflicts.

The target reference is `reference/repos/NRD/Source/Denoisers/Relax_DiffuseSpecular.hpp` and the corresponding `RELAX_*.cs.hlsl` shaders. **Match the reference exactly. No simplifications.**

---

## 1. Pipeline order (after sampling/ReSTIR DI is done)

1. **ClassifyTiles** (new)
2. **HitDistReconstruction** (new, optional — produce shader but disabled by default uniform gate)
3. **PrePass** (new) — fused diff+spec
4. **TemporalAccumulation** (rewrite, fused diff+spec)
5. **HistoryFix** (rewrite, fused diff+spec)
6. **HistoryClamping** (rewrite, fused diff+spec)
7. **Copy** (new, fused diff+spec)
8. **AntiFirefly** (rewrite, fused diff+spec)
9. **AtrousSmem** (new, 1st A-trous pass at stride 1, fused)
10. **Atrous** (rewrite, 4 more passes at strides 2,4,8,16, fused)

A-trous step sizes are HARD-CODED to `{1, 2, 4, 8, 16}` (5 passes total, matching reference). Drop the configurable `getNrdAtrousPasses()` knob. The first pass is `AtrousSmem` (writes permanent NRD outputs); the next 4 passes are `Atrous`.

---

## 2. Files to create

```
assets/photonic/shaders/lighttree/nrd_classify_tiles.fsh
assets/photonic/shaders/lighttree/nrd_hitdist_reconstruction.fsh
assets/photonic/shaders/lighttree/nrd_prepass.fsh
assets/photonic/shaders/lighttree/nrd_copy.fsh
assets/photonic/shaders/lighttree/nrd_atrous_smem.fsh
```

## 3. Files to rewrite (fused diff+spec)

```
assets/photonic/shaders/lighttree/nrd_temporal_accumulation.fsh
assets/photonic/shaders/lighttree/nrd_history_fix.fsh
assets/photonic/shaders/lighttree/nrd_history_clamping.fsh
assets/photonic/shaders/lighttree/nrd_anti_firefly.fsh
assets/photonic/shaders/lighttree/nrd_atrous.fsh
```

## 4. Files to delete

```
assets/photonic/shaders/lighttree/nrd_spec_temporal_accumulation.fsh
assets/photonic/shaders/lighttree/nrd_spec_history_fix.fsh
assets/photonic/shaders/lighttree/nrd_spec_history_clamping.fsh
assets/photonic/shaders/lighttree/nrd_spec_anti_firefly.fsh
assets/photonic/shaders/lighttree/nrd_spec_atrous.fsh
assets/photonic/shaders/lighttree/direct_feature_extract.fsh
```

## 5. Files to modify

`assets/photonic/shaders/lighttree/light_tree_sampling_stage.fsh` — make it write **NRD-format material** directly into the material MRT (`nrd_pack_surface_material(...)`) and write **packed RELAX_FrontEnd radiance+hitDist** into the direct/direct_specular MRTs. After this, `direct_feature_extract.fsh` is deletable.

---

## 6. Sampler names (uniform sampler2D, must match Java sampler registration)

### Geometry / G-buffer (existing — keep)
```
radiosity_position, radiosity_normal, radiosity_mapped_normal, radiosity_material
prev_radiosity_position, prev_radiosity_normal, prev_radiosity_mapped_normal, prev_radiosity_material
radiosity_motion
stage_radiosity_*
```

### NRD pipeline samplers (new naming convention: `nrd_*`)

Per-pass inputs (only listed where ambiguous):
| Sampler name | Source FBO (write side) | Format |
|---|---|---|
| `nrd_in_tiles` | `nrdTilesFb` | R8 |
| `nrd_in_diff_radiance_hitdist` | written by sampling stage to `lightingStageBuffer.direct` (NRD-packed) | RGBA16F |
| `nrd_in_spec_radiance_hitdist` | written by sampling stage to `lightingStageBuffer.direct_specular` (NRD-packed) | RGBA16F |
| `nrd_diff_illum_ping` | `nrdDiffIllumPingFb` (transient) | RGBA16F |
| `nrd_diff_illum_pong` | `nrdDiffIllumPongFb` (transient) | RGBA16F |
| `nrd_spec_illum_ping` | `nrdSpecIllumPingFb` (transient) | RGBA16F |
| `nrd_spec_illum_pong` | `nrdSpecIllumPongFb` (transient) | RGBA16F |
| `nrd_history_length` | `nrdHistoryLengthFb` (transient, current frame) | R8 |
| `nrd_spec_reprojection_confidence` | `nrdSpecReprojectionConfidenceFb` (transient) | R8 |
| `nrd_diff_illum_prev` | `nrdDiffIllumPrevFb.read` (last frame) | RGBA16F |
| `nrd_diff_illum_responsive_prev` | `nrdDiffIllumResponsivePrevFb.read` (last frame) | RGBA16F |
| `nrd_spec_illum_prev` | `nrdSpecIllumPrevFb.read` (last frame) | RGBA16F |
| `nrd_spec_illum_responsive_prev` | `nrdSpecIllumResponsivePrevFb.read` (last frame) | RGBA16F |
| `nrd_history_length_prev` | `nrdHistoryLengthPrevFb.read` (last frame) | R8 |
| `nrd_reflection_hit_t_curr` | `nrdReflectionHitTCurrFb` | R16F |
| `nrd_reflection_hit_t_prev` | `nrdReflectionHitTPrevFb.read` | R16F |
| `nrd_out_diff_radiance_hitdist` | `nrdOutDiffRadianceHitDistFb` (final atrous result) | RGBA16F |
| `nrd_out_spec_radiance_hitdist` | `nrdOutSpecRadianceHitDistFb` (final atrous result) | RGBA16F |

### Uniforms (float)
```
ph_nrd_max_accumulated_frame_num         // gDiffMaxAccumulatedFrameNum / gSpecMaxAccumulatedFrameNum
ph_nrd_max_fast_accumulated_frame_num    // gDiffMaxFastAccumulatedFrameNum / gSpecMaxFastAccumulatedFrameNum
ph_nrd_depth_threshold                   // gDepthThreshold
ph_nrd_disocclusion_threshold            // gDisocclusionThreshold (default 0.005, world-space unit)
ph_nrd_disocclusion_threshold_alt        // gDisocclusionThresholdAlternate
ph_nrd_denoising_range                   // gDenoisingRange (max viewZ to denoise)
ph_nrd_phi_luminance_diff                // gDiffPhiLuminance (default 1.0)
ph_nrd_phi_luminance_spec                // gSpecPhiLuminance (default 1.5)
ph_nrd_lobe_angle_fraction               // gLobeAngleFraction (default 0.5)
ph_nrd_roughness_fraction                // gRoughnessFraction (default 0.15)
ph_nrd_spec_lobe_angle_slack             // gSpecLobeAngleSlack (default 0.0)
ph_nrd_history_fix_frame_num             // gHistoryFixFrameNum (default 3)
ph_nrd_history_fix_base_stride           // gHistoryFixBasePixelStride (default 14)
ph_nrd_history_fix_normal_power          // gHistoryFixEdgeStoppingNormalPower (default 8)
ph_nrd_anti_firefly                      // 1.0 if anti-firefly enabled, 0.0 to skip
ph_nrd_hitdist_reconstruction            // 0.0 disabled, 1.0 = 3x3, 2.0 = 5x5
ph_nrd_history_clamping_color_box_sigma_scale       // gFastHistoryClampingSigmaScale (default 2.0)
ph_nrd_history_acceleration_amount       // gHistoryAccelerationAmount (default 0.3)
ph_nrd_history_reset_temporal_sigma_scale // gHistoryResetTemporalSigmaScale (default 0.5)
ph_nrd_history_reset_spatial_sigma_scale  // gHistoryResetSpatialSigmaScale (default 4.5)
ph_nrd_history_reset_amount              // gHistoryResetAmount (default 0.5)
ph_nrd_diff_prepass_blur_radius          // gDiffuseBlurRadius (default 30)
ph_nrd_spec_prepass_blur_radius          // gSpecularBlurRadius (default 50)
direct_atrous_step_size                  // existing — keep, drives atrous stride per pass
direct_atrous_is_last_pass               // existing — keep, 1 if final pass
ph_debug_disable_temporal_reset
```

The Java agent will register these uniforms; shader agents simply `uniform float ph_nrd_*;` and use them.

---

## 7. Per-pass MRT layout (output attachment index, output variable name, target FBO attachment)

### ClassifyTiles (`nrd_classify_tiles.fsh`)
```glsl
layout(location = 0) out vec4 nrd_tiles_out;     // .r in [0,1], 1.0 if any pixel in 16x16 tile is sky/out-of-range
```
**Note:** Photonics renders this at FULL resolution (one tile per pixel of the tiles FBO). The Java agent will create `nrdTilesFb` as a small R8 buffer of `ceil(viewWidth/16) x ceil(viewHeight/16)`. The shader writes the 16x16 OR-reduce of `is_in_world() && viewZ < ph_nrd_denoising_range`.

### HitDistReconstruction (`nrd_hitdist_reconstruction.fsh`)
```glsl
layout(location = 0) out vec4 nrd_diff_recon_out;   // RGBA16F, fed into prepass diff input
layout(location = 1) out vec4 nrd_spec_recon_out;   // RGBA16F, fed into prepass spec input
```
Reads `nrd_in_diff_radiance_hitdist`, `nrd_in_spec_radiance_hitdist`. If `ph_nrd_hitdist_reconstruction == 0.0`, this pass should be SKIPPED at the Java level (don't even render). Mirror logic of `RELAX_HitDistReconstruction.cs.hlsl`.

### PrePass (`nrd_prepass.fsh`)
```glsl
layout(location = 0) out vec4 nrd_diff_prepass_out;   // RGBA16F → nrdOutDiffRadianceHitDistFb
layout(location = 1) out vec4 nrd_spec_prepass_out;   // RGBA16F → nrdOutSpecRadianceHitDistFb
```
Mirror `RELAX_PrePass.cs.hlsl`. Spatial pre-blur using hit distance and material gate. Output is the `OUT_*_RADIANCE_HITDIST` for the temporal pass to consume.

### TemporalAccumulation (`nrd_temporal_accumulation.fsh`, REWRITE)
```glsl
layout(location = 0) out vec4 nrd_history_length_out;       // R8 → nrdHistoryLengthFb (only .r used)
layout(location = 1) out vec4 nrd_diff_illum_ping_out;       // RGBA16F → nrdDiffIllumPingFb (slow signal: rgb + 2nd moment)
layout(location = 2) out vec4 nrd_spec_illum_ping_out;       // RGBA16F → nrdSpecIllumPingFb (slow signal: rgb + 2nd moment)
layout(location = 3) out vec4 nrd_diff_illum_pong_out;       // RGBA16F → nrdDiffIllumPongFb (responsive signal: rgb + 0)
layout(location = 4) out vec4 nrd_spec_illum_pong_out;       // RGBA16F → nrdSpecIllumPongFb (responsive signal: rgb + hitDist)
layout(location = 5) out vec4 nrd_reflection_hit_t_curr_out; // R16F  → nrdReflectionHitTCurrFb (only .r used)
layout(location = 6) out vec4 nrd_spec_reproj_confidence_out;// R8    → nrdSpecReprojectionConfidenceFb (only .r used)
```
Reads: `nrd_in_tiles`, `radiosity_motion`, `radiosity_normal`, `radiosity_mapped_normal`, `radiosity_position`, `radiosity_material`, `prev_radiosity_*`, `nrd_history_length_prev`, `nrd_diff_illum_prev`, `nrd_diff_illum_responsive_prev`, `nrd_spec_illum_prev`, `nrd_spec_illum_responsive_prev`, `nrd_reflection_hit_t_prev`, `nrd_out_diff_radiance_hitdist` (= prepass output), `nrd_out_spec_radiance_hitdist` (= prepass output).

Mirror `RELAX_TemporalAccumulation.cs.hlsl` end to end including SMB + VMB reprojection for spec, curvature estimation, virtual-history confidence.

**Tile early-out:** `if (texelFetch(nrd_in_tiles, tex_coord >> 4, 0).r > 0.5) { discard; }` at the start of `main()`.

### HistoryFix (`nrd_history_fix.fsh`, REWRITE)
```glsl
layout(location = 0) out vec4 nrd_diff_pong_fixed_out;  // RGBA16F → nrdDiffIllumPongFb (overwrites only at young pixels)
layout(location = 1) out vec4 nrd_spec_pong_fixed_out;  // RGBA16F → nrdSpecIllumPongFb
```
Reads: `nrd_in_tiles`, `nrd_history_length`, `nrd_diff_illum_ping` (= slow from temporal), `nrd_spec_illum_ping` (= slow from temporal), G-buffer, prev G-buffer.

Mirror `RELAX_HistoryFix.cs.hlsl`. Sparse cross-bilateral 5×5. Early-out `if (historyLength > gHistoryFixFrameNum)` → output the existing PONG content unchanged (sample `nrd_diff_illum_pong` and pass through).

### HistoryClamping (`nrd_history_clamping.fsh`, REWRITE)
```glsl
layout(location = 0) out vec4 nrd_diff_illum_prev_out;             // RGBA16F → nrdDiffIllumPrevFb (permanent, swappable)
layout(location = 1) out vec4 nrd_diff_illum_responsive_prev_out;  // RGBA16F → nrdDiffIllumResponsivePrevFb
layout(location = 2) out vec4 nrd_spec_illum_prev_out;             // RGBA16F → nrdSpecIllumPrevFb
layout(location = 3) out vec4 nrd_spec_illum_responsive_prev_out;  // RGBA16F → nrdSpecIllumResponsivePrevFb
layout(location = 4) out vec4 nrd_history_length_prev_out;         // R8     → nrdHistoryLengthPrevFb
```
Reads: `nrd_in_tiles`, `nrd_history_length`, `nrd_out_diff_radiance_hitdist` (noisy = prepass output), `nrd_out_spec_radiance_hitdist`, `nrd_diff_illum_ping` (slow), `nrd_spec_illum_ping`, `nrd_diff_illum_pong` (responsive, post-history-fix), `nrd_spec_illum_pong`, G-buffer.

Mirror `RELAX_HistoryClamping.cs.hlsl`. YCoCg 5×5 bbox from PONG, clamp PING toward bbox, write to permanent prev buffers. History acceleration + reset logic exactly per reference.

### Copy (`nrd_copy.fsh`)
```glsl
layout(location = 0) out vec4 nrd_out_diff_radiance_hitdist_out;  // RGBA16F → nrdOutDiffRadianceHitDistFb
layout(location = 1) out vec4 nrd_out_spec_radiance_hitdist_out;  // RGBA16F → nrdOutSpecRadianceHitDistFb
```
Trivial copy of `nrd_diff_illum_prev_out` (just written by clamping) to `nrd_out_diff_radiance_hitdist`. Mirror `RELAX_Copy.cs.hlsl`. Same pattern for spec.

### AntiFirefly (`nrd_anti_firefly.fsh`, REWRITE)
```glsl
layout(location = 0) out vec4 nrd_diff_illum_prev_firefly_out;  // RGBA16F → nrdDiffIllumPrevFb (in-place rewrite)
layout(location = 1) out vec4 nrd_spec_illum_prev_firefly_out;  // RGBA16F → nrdSpecIllumPrevFb (in-place rewrite)
```
**Important:** anti-firefly outputs to the SAME permanent buffer as clamping. The Java agent must:
1. Copy clamping output to public `nrd_out_*_radiance_hitdist` (via `nrd_copy.fsh`).
2. Then run anti-firefly which reads `nrd_out_*_radiance_hitdist` and writes back into `nrd_*_illum_prev_*` (the permanent slow). This breaks the same-pixel feedback hazard because anti-firefly's input and output are different buffers.

Reads: `nrd_in_tiles`, `nrd_out_diff_radiance_hitdist`, `nrd_out_spec_radiance_hitdist`, G-buffer.

Mirror `RELAX_AntiFirefly.cs.hlsl`. RCRS 3×3 with material gate. Center 2nd-moment preserved.

### AtrousSmem (`nrd_atrous_smem.fsh`, NEW — first A-trous pass)
```glsl
layout(location = 0) out vec4 nrd_diff_atrous_out;                 // RGBA16F → nrdDiffIllumPongFb (or PING — Java decides)
layout(location = 1) out vec4 nrd_spec_atrous_out;                 // RGBA16F → nrdSpecIllumPongFb
layout(location = 2) out vec4 nrd_normal_roughness_prev_out;       // RGBA16F → nrdNormalRoughnessPrevFb (write current G-buffer for next-frame temporal read)
layout(location = 3) out vec4 nrd_material_id_prev_out;            // R8     → nrdMaterialIdPrevFb (already exists as radiosity_material's .w?)
layout(location = 4) out vec4 nrd_viewz_prev_out;                  // R32F   → nrdViewZPrevFb
```
Note: in Photonics, `prev_radiosity_*` is already a swap-buffer of the live G-buffer, so the additional permanent G-buffer outputs in the SMEM pass are NOT needed (existing prev_radiosity_position etc. handles this). **Skip outputs 2-4** in Photonics; only output diff and spec atrous results. Reads `nrd_diff_illum_prev` (= post-anti-firefly slow), `nrd_spec_illum_prev`. Stride is HARD-CODED to 1 (this is the SMEM pass).

### Atrous (`nrd_atrous.fsh`, REWRITE)
```glsl
layout(location = 0) out vec4 nrd_diff_atrous_out;   // RGBA16F → nrdDiffIllumPing or Pong (Java picks via ping-pong)
layout(location = 1) out vec4 nrd_spec_atrous_out;   // RGBA16F → nrdSpecIllumPing or Pong
```
Reads `nrd_diff_illum_ping` or `nrd_diff_illum_pong` (whichever holds previous pass output), same for spec. **CRITICAL FIX:** keep `.a = 2nd moment of luminance` invariant ACROSS A-trous passes. Do NOT write variance into `.a`. Compute variance internally as `secondMoment - luma*luma`, write back the filtered second moment using the same w² weighting used in reference.

Stride is `direct_atrous_step_size` uniform: 2, 4, 8, 16 across the 4 A-trous passes (after the SMEM pass at stride 1).

Last pass (`direct_atrous_is_last_pass == 1`) writes to `nrdOutDiffRadianceHitDistFb` and `nrdOutSpecRadianceHitDistFb` (the public outputs). Java handles this routing via framebuffer choice; shader is the same.

---

## 8. Buffer FBO names (Java side, ColorFramebuffer)

### Permanent (swap-buffered, double-buffered for read-prev / write-curr)
- `nrdDiffIllumPrevFb`         — RGBA16F
- `nrdDiffIllumResponsivePrevFb` — RGBA16F
- `nrdSpecIllumPrevFb`         — RGBA16F
- `nrdSpecIllumResponsivePrevFb` — RGBA16F
- `nrdHistoryLengthPrevFb`     — R8
- `nrdReflectionHitTPrevFb`    — R16F

### Transient (single-buffered)
- `nrdTilesFb`                  — R8 (resolution `ceil(width/16) x ceil(height/16)`)
- `nrdDiffIllumPingFb`          — RGBA16F (full res)
- `nrdDiffIllumPongFb`          — RGBA16F
- `nrdSpecIllumPingFb`          — RGBA16F
- `nrdSpecIllumPongFb`          — RGBA16F
- `nrdHistoryLengthFb`          — R8
- `nrdSpecReprojectionConfidenceFb` — R8
- `nrdReflectionHitTCurrFb`     — R16F
- `nrdOutDiffRadianceHitDistFb` — RGBA16F
- `nrdOutSpecRadianceHitDistFb` — RGBA16F

### Buffers to DELETE (Java agent removes them)
- `directNoisyBuffer` (replaced by `nrdOutDiffRadianceHitDistFb` after PrePass)
- `directResponsiveBuffer` (alias of fast — was redundant)
- `directSlowBuffer` (replaced by `nrdDiffIllumPingFb`)
- `directFastBuffer` (replaced by `nrdDiffIllumPongFb`)
- `directAntiFireflyBuffer` (replaced by `nrdDiffIllumPrevFb` post-firefly)
- `directClampedSlowBuffer` (replaced by `nrdDiffIllumPrevFb`)
- `directClampedFastBuffer` (replaced by `nrdDiffIllumResponsivePrevFb`)
- `directDenoisedBuffer` (replaced by `nrdOutDiffRadianceHitDistFb`)
- `directAtrousPingBuffer` (replaced by `nrdDiffIllumPing/Pong`)
- `directConfidenceBuffer` (deleted entirely — confidence pipeline removed)
- `directHistoryLengthBuffer` (replaced by `nrdHistoryLengthFb` + `nrdHistoryLengthPrevFb`)
- `specularNoisyBuffer`, `specularResponsiveBuffer`, `specularSlowBuffer`, `specularFastBuffer`, `specularAntiFireflyBuffer`, `specularClampedSlowBuffer`, `specularClampedFastBuffer`, `specularDenoisedBuffer`, `specularAtrousPingBuffer`, `specularHistoryLengthBuffer` — all deleted (fused into diff pipeline buffers)

---

## 9. Renderers in LightTreeRenderer.java

### Create
- `nrdClassifyTilesRenderer`
- `nrdHitDistReconstructionRenderer`
- `nrdPrepassRenderer`
- `nrdCopyRenderer`
- `nrdAtrousSmemRenderer`

### Rewire (existing renderer, new framebuffer + shader)
- `directTemporalRenderer` (now fused) → reads new shader, writes 7 outputs
- `directHistoryFixRenderer` (now fused) → 2 outputs
- `directHistoryClampingRenderer` (now fused) → 5 outputs
- `directAntiFireflyRenderer` (now fused) → 2 outputs
- `directAtrousRenderer` (now fused) → 2 outputs

### Delete
- `directFeatureRenderer` (its work is now in sampling stage)
- `specTemporalRenderer`, `specHistoryFixRenderer`, `specHistoryClampingRenderer`, `specAntiFireflyRenderer`, `specAtrousRenderer` (all fused into diff renderers)

### Pipeline order in `render()` (replaces lines 1402-1422 of LightTreeRenderer.java):
```java
this.renderProfiled(nrdClassifyTilesRegionIndex, this.nrdClassifyTilesRenderer);
if (this.shouldRunHitDistReconstruction()) {
    this.renderProfiled(nrdHitDistReconstructionRegionIndex, this.nrdHitDistReconstructionRenderer);
}
this.renderProfiled(nrdPrepassRegionIndex, this.nrdPrepassRenderer);
this.renderProfiled(relaxTemporalAccumulationRegionIndex, this.directTemporalRenderer);
this.renderProfiled(relaxHistoryFixRegionIndex, this.directHistoryFixRenderer);
this.renderProfiled(relaxHistoryClampingRegionIndex, this.directHistoryClampingRenderer);
this.renderProfiled(nrdCopyRegionIndex, this.nrdCopyRenderer);
this.renderProfiled(relaxAntiFireflyRegionIndex, this.directAntiFireflyRenderer);

// A-trous: 1 SMEM pass (stride 1) + 4 regular passes (strides 2,4,8,16)
this.renderProfiled(relaxAtrousSmemRegionIndex, this.nrdAtrousSmemRenderer);
for (int i = 1; i < 5; i++) {
    this.directAtrousIteration = i;  // step size = {1,2,4,8,16}[i]
    this.renderProfiled(relaxAtrousRegionIndex, this.directAtrousRenderer);
}
```

### Atrous ping-pong routing
Use `nrdDiffIllumPingFb` and `nrdDiffIllumPongFb` (and spec equivalents). The SMEM pass reads `nrd_diff_illum_prev` (post-anti-firefly), writes to PONG. Pass i (for i=1..3) reads PONG/PING based on parity, writes the other. Pass 4 (final) writes to `nrdOutDiffRadianceHitDistFb`. Same logic for spec.

---

## 10. Sampling stage modification (`light_tree_sampling_stage.fsh`)

The sampling stage currently writes:
- `lightingStageBuffer.material` — raw `specular` deferred sample
- `lightingStageBuffer.direct` — diffuse irradiance (not packed)
- `lightingStageBuffer.direct_specular` — spec irradiance (not packed)

After refactor it must write:
- `lightingStageBuffer.material` — `nrd_pack_surface_material(specularSample)` directly (= `(roughness, metallic, emission, encodedMaterialId)`)
- `lightingStageBuffer.direct` — `nrd_pack_direct_signal(diffuseRadiance, hitDistance)` (RELAX-front-end packed)
- `lightingStageBuffer.direct_specular` — `nrd_pack_direct_signal(specRadiance, hitDistance)`

The `direct_feature_extract.fsh` pass becomes redundant and is deleted.

---

## 11. Behavioural rules (apply to all agents)

1. **Match reference exactly.** Do not simplify or shortcut. If the reference has a curvature estimation block of 50 lines, write all 50 lines. If the reference uses a specific NRD utility from `RELAX_Common.hlsli` or `NRD.hlsli`, port it (or use existing port in `nrd_common.glsl`).
2. **Comments must accurately describe what the code is doing.** Remove any stale or misleading comment from the previous implementation. Where you cite a reference line, cite the correct file (e.g. `RELAX_TemporalAccumulation.cs.hlsl:439-457` for the 3×3 normal averaging).
3. **No debug toggles** (`ph_debug_enable_*`, `ph_debug_disable_*`) unless they exist in the reference. Remove existing Photonics-only debug gates that do not have a reference equivalent.
4. **No "convenience" Photonics-only logic.** Remove any `ph_*` heuristic that does not have a 1:1 reference counterpart.
5. **Keep checkerboard owner-pixel remap support** because it is a Photonics ReSTIR-DI integration concern, not an NRD concern. Use `nrd_get_checkerboard_owner_pixel(...)` from `nrd_common.glsl` for current/prev tap remapping. **However**, when checkerboard is OFF (`ph_restir_active_checkerboard_field == 0`), the helpers must be no-ops — verify in `nrd_common.glsl`.
6. **A-trous .a invariant:** `.a` channel is always the 2nd moment of luminance. Variance is `max(.a - luma*luma, 0)`. Write `(rgb, secondMoment)` not `(rgb, variance)`.
7. **Use `discard` (or early-out via `gl_FragCoord` check) when the tile is sky** based on `nrd_in_tiles`.
8. **Preserve existing helpers in `nrd_common.glsl`.** If you need a new helper, add it there. Do not duplicate code across shaders.

---

## 12. Reference files (read these for parity)

- `reference/repos/NRD/Source/Denoisers/Relax_DiffuseSpecular.hpp` — pipeline graph
- `reference/repos/NRD/Shaders/RELAX_ClassifyTiles.cs.hlsl` — for ClassifyTiles
- `reference/repos/NRD/Shaders/RELAX_HitDistReconstruction.cs.hlsl` — for HitDistReconstruction
- `reference/repos/NRD/Shaders/RELAX_PrePass.cs.hlsl` — for PrePass
- `reference/repos/NRD/Shaders/RELAX_TemporalAccumulation.cs.hlsl` — for Temporal (the BIG one — has SMB and VMB, virtual reprojection, curvature, etc.)
- `reference/repos/NRD/Shaders/RELAX_HistoryFix.cs.hlsl` — for HistoryFix
- `reference/repos/NRD/Shaders/RELAX_HistoryClamping.cs.hlsl` — for HistoryClamping
- `reference/repos/NRD/Shaders/RELAX_Copy.cs.hlsl` — for Copy
- `reference/repos/NRD/Shaders/RELAX_AntiFirefly.cs.hlsl` — for AntiFirefly
- `reference/repos/NRD/Shaders/RELAX_AtrousSmem.cs.hlsl` — for AtrousSmem (1st pass)
- `reference/repos/NRD/Shaders/RELAX_Atrous.cs.hlsl` — for Atrous (passes 2-5)
- `reference/repos/NRD/Shaders/RELAX_Common.hlsli` — utility functions
- `reference/repos/NRD/Shaders/Common.hlsli` — utility functions
- `reference/repos/NRD/Shaders/NRD.hlsli` — packing/unpacking helpers

---

## 13. Test plan

After all agents complete and Java integration is done, the master process runs the codex shader game test:

```
.\.codex-run-shader-test.ps1
```

(working directory: `E:\RE\photonics`).
