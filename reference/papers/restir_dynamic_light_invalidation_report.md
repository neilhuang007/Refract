# ReSTIR DI / RTXDI / ReGIR Dynamic-Light Invalidation Model

**Problem:** Many local lights exist. Some lights toggle on/off or change intensity/color, but their position, shape, and identity remain stable. Visible tiles sometimes flash in unrelated regions. The core question is how to separate **light activity/radiance changes** from **light sampling/topology changes**.

**Short conclusion:** A light changing intensity, color, or active state should usually be treated as a **radiometric change**, not a **sampling-topology change**. Keep the light's identity stable. Update current light data and sampling distributions. Do not globally reset reservoirs or reorder the light list. Only invalidate or reweight samples that actually reference the changed light, or structures whose probability model was built from stale power.

---

## 1. Key findings

### 1.1 Separate identity, topology, and radiometry

Use three independent state categories:

| State category | Examples | Typical consequence |
|---|---|---|
| **Identity** | Stable light ID, stable logical slot, generation counter | Needed for temporal reuse and previous/current index translation |
| **Sampling topology** | Position, shape, area, orientation, light type, spatial cell membership, mesh-emissive triangle identity | Can invalidate ReGIR cells, spatial light grids, light-index mappings, and reservoirs containing the light |
| **Radiometry/activity** | Intensity, color, active flag, emissive texture multiplier, IES scalar | Should update PDFs, RIS/presampling buffers, compact records, and sample weights, but should not reorder or globally reset the world |

The most important engineering rule is:

> **A toggled light is still the same light.**  
> If its position, shape, and identity did not change, do not treat it as a removed light and a new light.

### 1.2 Stable light indices matter

RTXDI's integration model explicitly includes:

- a **light data buffer**,
- a **light index mapping buffer** between previous and current frames,
- **PDF textures**,
- **RIS buffers**,
- optional **RIS light data buffers**,
- **reservoir buffers**.

It also keeps previous/current light data available for temporal resampling and uses a bridge function for light-index translation. This strongly implies that changing radiance should not silently change what a reservoir's stored index refers to.

Recommended practice:

```text
stableLightId never changes for the same logical light
physicalSlot stays stable when possible
if physicalSlot changes, previousToCurrent[oldSlot] must be valid
if light is removed, previousToCurrent[oldSlot] = INVALID
```

### 1.3 ReGIR specifically supports dynamic lights, but stale weights are dangerous

The ReGIR chapter states that reservoirs store a light ID so current light properties can be loaded at use time. This avoids stale **shading** data. However, temporal reuse can preserve stale **weights** when light properties change. The chapter suggests either excluding dynamic lights from temporal reuse or reweighting them during grid construction.

That distinction is critical:

```text
stale light color/intensity at shading time  -> fix by reloading current light data by ID
stale reservoir weight/probability          -> fix by reweighting or invalidating the sample
```

### 1.4 Most remote-light toggle flashing is a consistency bug

If toggling a remote light causes grid/tile flashing where the light contributes little, suspect one of these:

1. The light array is compacted or sorted by power, so old reservoir indices now point to different lights.
2. RIS/presampling tiles keep stale inverse source PDFs.
3. Compact records cache stale intensity/color.
4. ReGIR cell reservoirs keep old weights for dynamic lights.
5. A global CDF rebuild changes random mapping globally, and temporal reservoirs are not reweighted.
6. Temporal confidence is too high, so stale samples dominate new candidates.
7. Grid origin or cell indexing changes in camera-relative coordinates without preserving world-cell identity.

---

## 2. Recommended renderer state model

### 2.1 Light record

```cpp
struct LightRecord
{
    uint stableId;           // logical identity, never reused immediately
    uint physicalSlot;       // current buffer slot
    uint generation;         // increments on remove/recreate of the slot

    uint topologyVersion;    // increments on position/shape/type/area changes
    uint radianceVersion;    // increments on intensity/color/active changes

    bool active;             // active == false means power/radiance is 0
    LightType type;

    ShapeData shape;
    float3 position;
    float3 orientation;

    float3 color;
    float intensity;
};
```

### 2.2 Reservoir payload

For ReSTIR DI and ReGIR, prefer reservoir payloads that store a **sample reference**, not final baked lighting:

```cpp
struct LightSampleRef
{
    uint stableIdOrTranslatedIndex;
    uint generation;
    float2 sampleUv;           // for area/triangle/disk light point sampling
    uint randomSeedOrParams;   // if sample reconstruction needs it
};

struct Reservoir
{
    LightSampleRef y;          // selected sample
    float weightSum;           // sum of candidate weights
    float targetPdfAtY;        // optional, but must be current or revalidated
    uint M;                    // candidate count / confidence
    uint storedRadianceVersion;// optional debugging / invalidation aid
    uint storedTopologyVersion;// optional debugging / invalidation aid
};
```

Do **not** store only a baked final `Li * BRDF * visibility` and reuse it as if it were current. Final shading should reload the current light record by stable ID or translated current-frame index.

---

## 3. Event table

| Event | Global light array | CDF / alias / PDF texture | RIS / presampling tiles | ReGIR cells | ReSTIR DI reservoirs | Temporal history |
|---|---|---|---|---|---|---|
| **Light toggled off** | Keep stable ID and slot. Set emitted power to zero. | Rebuild or incrementally update the entry and mip/alias hierarchy. | Regenerate current-frame presamples. Old samples selecting this light evaluate to zero or are rejected. | New cell construction gives it zero target weight. Old cells containing it must be reweighted, dropped, or age-limited. | Do not globally reset. If selected light is this ID, re-evaluate target; if zero, invalidate or allow replacement. | Reduce confidence only for affected samples. |
| **Light toggled on** | Keep stable ID and slot. Restore current power. | Update the PDF so its selection probability is nonzero. | Regenerate current-frame presamples so the light can enter candidates quickly. | Rebuild or reweight relevant cells. Optionally force a small local refresh near the light. | No global reset. New canonical samples will introduce it. | Optionally reduce history cap in affected cells/tiles for faster response. |
| **Intensity change** | Keep stable ID and slot. Increment `radianceVersion`. | Update power-based PDF because source probabilities changed. | Regenerate presampling tiles or refresh compact records. | Reweight cell reservoirs containing this light; if ratio change is large, invalidate those samples. | Recompute target PDF/current contribution. Do not clear unrelated reservoirs. | Clamp confidence for affected samples. |
| **Color change** | Keep stable ID and slot. Increment `radianceVersion`. | If sampling power uses luminance and luminance changed, update. If only hue changed and luminance is equal, PDF may stay. | Refresh records if color is cached. | Same as intensity if importance changes. | Reload current color for shading. | Usually keep history unless change is visually large. |
| **Light moved** | Keep stable logical ID only if it is truly the same object. Increment `topologyVersion`. | Update if power/area changed. | Regenerate. | Rebuild/reweight affected spatial cells. Old cells containing the light are stale. | Invalidate or heavily reduce reservoirs containing this light unless correct shift/reweight is implemented. | Treat large movement as remove+add for reuse purposes. |
| **Light shape/type/area changed** | Same stable ID only if semantically same light; increment `topologyVersion`. | Update power and sampling-domain PDF. | Regenerate because sample UV/domain may no longer mean the same thing. | Rebuild/reweight cells. | Invalidate samples of this light if sample parameterization changed. | Reduce confidence or invalidate affected samples. |
| **Light added** | Allocate new stable ID. Prefer append/free-list slot; avoid global reorder. | Add entry and rebuild/update distribution. | Regenerate. | Rebuild/reweight relevant cells. | No previous sample exists for this light. | New light has no history. |
| **Light removed** | Prefer tombstone for a few frames, or map old slot to INVALID. Do not reuse ID immediately. | Remove or set power to zero, then rebuild/update. | Regenerate. | Drop cell reservoirs containing removed ID. | Reservoirs referencing removed ID are invalid. | Only affected samples invalid. |
| **Scene geometry changed** | No light-list change unless emissive geometry changed. | Only update if emissive light set/power changed. | Refresh if mesh light extraction changed. | Rebuild cells if emissive geometry or visibility assumptions changed. | Validate G-buffer reprojection, normals, depth, visibility, and previous-frame scene access. | Reset/reduce history in changed or disoccluded regions. |
| **Camera moved** | No light-list change. | No change. | No change unless camera-dependent tiling is used. | If grid is camera-centered, preserve matching world cells or invalidate shifted cells. | Normal temporal reprojection. | Reset where reprojection fails or disocclusion occurs. |
| **Grid origin moved** | No light-list change. | No change. | No change. | If a cell index now refers to a different world region, invalidate that cell history. If clipmap/scrolling grid preserves world identity, keep matching cells. | No direct effect. | Only ReGIR history affected. |

---

## 4. Specific recommendations by structure

### 4.1 Global light array

**Recommendation:** Keep stable logical IDs. Keep physical slots stable when possible.

Bad:

```text
Every frame:
  remove inactive lights
  compact active lights
  sort by power
  store reservoirs using physical index
```

This makes old reservoir index `17` mean light A last frame and light B this frame.

Good:

```text
Every frame:
  stableId persists
  physicalSlot persists when possible
  inactive light remains present with power = 0
  removed light maps to INVALID for temporal reuse
  if compaction is necessary, build previous/current index translation
```

### 4.2 CDFs, alias tables, and PDF textures

Update when the **sampling power** changes:

- intensity changed,
- active flag changed,
- emissive material multiplier changed,
- area/shape changed,
- environment map changed,
- mesh emissive set changed.

A power-based light PDF should use current power. For inactive lights, target sampling power should be `0`.

Do not use an epsilon power to hide correctness issues unless you also account for it in source PDFs and target PDFs. A small exploration floor can be valid, but it is an intentional variance/bias/performance decision, not a stability fix.

### 4.3 RIS / presampling tiles

Presampling tiles usually store something like:

```cpp
struct RISEntry
{
    uint lightIndex;
    float invSourcePdf;
};
```

Therefore, regenerate or patch RIS entries whenever the distribution used to compute `invSourcePdf` changes. If a remote light toggle globally changes a CDF, old `invSourcePdf` values can become inconsistent. That can produce weight spikes even when the remote light is visually irrelevant.

Minimum safe approach:

```text
if any local-light power distribution changed:
    rebuild local light PDF
    regenerate current-frame RIS/presampling buffer
    do not reuse stale RIS entries across the change unless they are reweighted
```

### 4.4 Compact light records

Compact records may be used for locality, but treat them as cache lines, not truth.

Safe options:

1. **Store only stable sample reference** and reload current light data from the main light buffer.
2. **Store compact snapshots**, but refresh them every frame or whenever `radianceVersion` or `topologyVersion` changes.
3. **Store version tags** and reject/reload if stale.

Bad:

```text
reservoir stores compactLight = { position, color, intensity }
later shading uses compactLight directly after light changed
```

Good:

```text
reservoir stores { stableLightId, sampleUv }
shading:
    light = LoadCurrentLight(stableLightId)
    sample point = ReconstructSample(light, sampleUv)
    evaluate current color/intensity
```

### 4.5 ReGIR cells

ReGIR cells are not permanent ownership lists. They are world-space reservoirs of sampled lights and weights.

Recommended dynamic-light policy:

```text
During ReGIR construction:
    use current light power and current geometry
    if candidate light radianceVersion changed:
        reweight candidate using current target PDF
        if reweight unavailable or change ratio is huge:
            do not merge old reservoir for this light
```

For toggles:

```text
toggle off:
    targetPdf = 0
    old cell reservoir selecting that light should become invalid or weight 0

toggle on:
    targetPdf > 0
    new cell construction must be allowed to sample it quickly
```

If ReGIR grid history is used:

```text
if cell world bounds changed:
    invalidate that cell history

if selected light topologyVersion changed:
    invalidate that selected sample

if selected light radianceVersion changed:
    reweight or reduce confidence

if selected light was removed:
    invalidate
```

### 4.6 ReSTIR DI temporal reservoirs

Temporal reservoirs should not be globally reset for a radiometric change. Use selective validation.

Recommended validation for a previous-frame reservoir:

```cpp
bool ValidateTemporalReservoir(Reservoir r, Surface currentSurface)
{
    LightRecord light = LoadCurrentLightByStableId(r.y.stableId);

    if (!light.exists) return false;
    if (light.generation != r.y.generation) return false;

    if (light.topologyVersion != r.storedTopologyVersion)
        return false; // or expensive revalidation if supported

    float currentTarget = EvaluateTargetPdf(light, r.y, currentSurface);

    if (currentTarget <= 0)
        return false;

    if (light.radianceVersion != r.storedRadianceVersion)
    {
        float oldTarget = max(r.targetPdfAtY, EPS);
        float ratio = currentTarget / oldTarget;

        if (ratio > LARGE_CHANGE || ratio < 1.0 / LARGE_CHANGE)
            r.M = min(r.M, SMALL_HISTORY_CAP);

        r.targetPdfAtY = currentTarget;
        r.storedRadianceVersion = light.radianceVersion;
    }

    return true;
}
```

For dynamic lighting, use confidence/history caps. Unbounded temporal confidence makes stale samples too hard to replace.

---

## 5. Practical anti-flashing model

### 5.1 Never let radiance changes reorder sampling identity

This is the most likely cause of remote-toggle tile flashes.

**Avoid:**

```text
activeLights = compact(allLights where active && power > 0)
sort(activeLights by power)
reservoir stores activeLights index
```

**Use:**

```text
allLights[stableSlot] exists even if inactive
sample distribution maps stableSlot -> probability
inactive slot probability = 0
reservoir stores stableSlot or stableId
```

### 5.2 Rebuild current source distributions, not history

When light power changes:

```text
update current light buffer
rebuild/patch light PDF
regenerate current RIS/presampling
rebuild/reweight current ReGIR cells
validate previous reservoirs lazily/selectively
```

Do not clear all screen reservoirs unless the entire light domain or scene representation changed.

### 5.3 Reweight stale weights

A reservoir that selected light `L` before an intensity change is not automatically wrong as a **sample**, but its **weight** may be wrong.

Use one of these policies:

| Policy | Cost | Quality | Use when |
|---|---:|---:|---|
| Invalidate affected samples | Low | Can pop locally | Simple implementation, rare changes |
| Clamp confidence for affected samples | Low-medium | Stable | Most real-time cases |
| Reweight affected samples | Medium | Best | You can recompute current and old target/source PDFs |
| Exclude dynamic lights from temporal reuse | Low | More noise | Highly unstable blinking lights |
| Full global reset | High visual disruption | Bad | Only for catastrophic domain changes |

### 5.4 Use local or per-light dirty regions

For remote toggles, do not assume all pixels are affected. Maintain:

```cpp
struct LightDirtyEvent
{
    uint stableId;
    DirtyType type;       // radiance, topology, add, remove
    AABB influenceBounds; // conservative sphere/cone/area bounds
    float oldPower;
    float newPower;
};
```

Then use dirty events to:

- refresh ReGIR cells overlapping influence bounds,
- reduce temporal confidence for reservoirs selecting that light,
- optionally reduce history in screen tiles whose visible points lie within the light's influence bounds,
- leave unrelated reservoirs alone.

### 5.5 Add diagnostic views

Implement debug views before tuning:

1. **Reservoir selected light ID**  
   Flashing random IDs in unrelated tiles means index instability or random-source instability.

2. **Selected light generation/version**  
   Old versions in final shading mean stale compact records.

3. **Target PDF before/after validation**  
   Huge spikes after toggles mean stale source PDF or stale weight.

4. **RIS `invSourcePdf` heatmap**  
   Tile-aligned changes after CDF update mean stale RIS buffers.

5. **ReGIR cell selected light ID**  
   Cell-shaped artifacts mean stale ReGIR reservoirs or unstable grid origin.

6. **History confidence / M**  
   High confidence in wrong areas means stale reservoirs cannot be replaced.

---

## 6. Common causes of visible tile flashing

| Cause | Why it flashes | Fix |
|---|---|---|
| Light array compaction after toggle | Previous reservoir index now references a different light | Stable IDs or previous/current index translation |
| Sorting lights by power every frame | Remote toggle globally changes index order | Keep sampling distribution separate from identity order |
| Stale RIS `invSourcePdf` | Weights no longer match current CDF | Regenerate or reweight presampling buffers |
| Compact records cache old radiance | Shading uses stale intensity/color | Reload current light data by ID or refresh compact records |
| ReGIR temporal history keeps old weight | Cell reservoir still believes old light is important | Reweight dynamic lights, invalidate affected cell samples, or exclude dynamic lights from grid temporal reuse |
| Grid origin changes without world-cell preservation | Same cell index points to different world space | Use scrolling/clipmap mapping or invalidate shifted cells |
| No lookup jitter in ReGIR | Cell boundaries become visible | Jitter lookup within cell size / stochastic trilinear-like cell selection |
| Excessive temporal confidence | New samples cannot replace old wrong samples | Cap `M`, clamp history, or decay confidence after dirty events |
| Inconsistent previous/current light data | Temporal normalization uses wrong old data | Keep previous light buffer and mapping |
| Missing previous scene/TLAS for validation | Bias or invalid visibility after dynamic geometry | Use previous scene data if possible, or conservative invalidation |

---

## 7. Recommended invalidation rules

### 7.1 ReSTIR reservoirs

Invalidate if:

- selected light no longer exists,
- selected light generation changed,
- light index translation fails,
- selected light topology changed significantly,
- sample domain changed and stored sample parameters are no longer meaningful,
- current target PDF is zero,
- surface reprojection fails,
- normal/depth/material dissimilarity exceeds threshold,
- visibility validation fails under the chosen biased/unbiased mode.

Do not invalidate globally for:

- intensity change,
- color change,
- active toggle of a different light,
- CDF rebuild alone.

Instead, reweight or confidence-clamp affected samples.

### 7.2 ReGIR cells

Invalidate or rebuild a cell if:

- its world-space bounds changed,
- its grid/clipmap level now maps to different world space,
- light topology changes inside or near the cell,
- many lights in its candidate set were added/removed,
- the cell was unused too long and its history is cold.

Reweight or confidence-clamp if:

- selected light intensity/color changed,
- selected light toggled active/inactive,
- light power distribution changed but cell bounds are stable.

### 7.3 Spatial light grids

Spatial acceleration/light assignment grids depend on topology. Rebuild/update when:

- light moved,
- light radius/range changed,
- light shape/area changed,
- light added/removed,
- grid origin/cell mapping changed,
- emissive mesh geometry changed.

Do not rebuild spatial topology merely because a light changed color unless the color change changes range or sampling importance.

### 7.4 CDF / alias / PDF tables

Update when:

- any light's sampling power changes,
- active flag changes,
- emissive texture/material changes,
- area/shape changes,
- environment map changes,
- light count/domain changes.

Keep identity order stable. The CDF/alias table maps stable entries to probabilities; it should not redefine what a light index means.

### 7.5 Temporal reuse history

Reset history locally when:

- reprojection fails,
- disocclusion occurs,
- surface/material changed,
- selected light became invalid,
- selected light topology changed,
- grid cell world identity changed.

Clamp history when:

- selected light radiance changed a lot,
- selected light toggled on/off,
- source distribution changed strongly,
- confidence is high and current target/source ratio is far from stored value.

Leave history intact when:

- unrelated light toggled,
- current reservoir target remains valid,
- source PDF was correctly reweighted.

---

## 8. Minimal implementation plan

### Phase 1: Stop global instability

1. Keep inactive lights in the global array with power `0`.
2. Stop sorting/compacting lights by activity or power.
3. Add stable `lightId`, `generation`, `topologyVersion`, `radianceVersion`.
4. Make reservoir shading reload current light data by stable ID.
5. Rebuild current light PDF and current RIS buffers when power changes.
6. Disable ReGIR temporal reuse for dynamic lights as a first safe baseline.

### Phase 2: Selective validation

1. Add previous/current index translation if physical slots can change.
2. Track dirty light events.
3. For temporal reservoirs, invalidate only if the selected light is dirty and cannot be reweighted.
4. For ReGIR cells, reweight or drop old reservoirs selecting dirty lights.
5. Add confidence clamping for radiance changes.

### Phase 3: Quality recovery

1. Reweight dynamic reservoirs instead of dropping them.
2. Keep grid cell history using world-stable clipmap/scrolling cells.
3. Add stochastic ReGIR cell lookup jitter.
4. Add local refresh around toggled-on lights so they appear quickly.
5. Add reservoir mutation/decorrelation if correlation artifacts remain.

---

## 9. Pseudocode for a robust dynamic-light update

```cpp
void ProcessLightEvent(LightEvent e)
{
    LightRecord& L = lights[e.stableId];

    switch (e.type)
    {
    case LightEventType::Toggle:
    case LightEventType::Intensity:
    case LightEventType::Color:
        L.radianceVersion++;
        UpdateCurrentLightBuffer(L);
        MarkLightPowerPdfDirty(L.stableId);
        MarkRISDirty(LocalLightDomain);
        MarkReGIRRadianceDirty(L.stableId, L.influenceBounds);
        MarkReservoirRadianceDirty(L.stableId);
        break;

    case LightEventType::Move:
    case LightEventType::Shape:
        L.topologyVersion++;
        UpdateCurrentLightBuffer(L);
        MarkSpatialGridDirty(L.oldBounds, L.newBounds);
        MarkLightPowerPdfDirty(L.stableId);
        MarkRISDirty(LocalLightDomain);
        MarkReGIRTopologyDirty(L.stableId, Union(L.oldBounds, L.newBounds));
        MarkReservoirTopologyDirty(L.stableId);
        break;

    case LightEventType::Add:
        AllocateStableLightIdAndSlot(e);
        MarkLightPowerPdfDirty(e.stableId);
        MarkRISDirty(LocalLightDomain);
        MarkSpatialGridDirty(e.bounds);
        MarkReGIRTopologyDirty(e.stableId, e.bounds);
        break;

    case LightEventType::Remove:
        TombstoneOrInvalidateMapping(e.stableId);
        MarkLightPowerPdfDirty(e.stableId);
        MarkRISDirty(LocalLightDomain);
        MarkSpatialGridDirty(e.bounds);
        MarkReGIRTopologyDirty(e.stableId, e.bounds);
        MarkReservoirRemovedLight(e.stableId);
        break;
    }
}
```

Temporal validation:

```cpp
bool TryReuseTemporalReservoir(Reservoir& r, Surface s)
{
    uint currentIndex = TranslatePreviousLightIndex(r.y.lightIndex);
    if (currentIndex == INVALID)
        return false;

    LightRecord L = LoadCurrentLight(currentIndex);

    if (L.generation != r.y.generation)
        return false;

    if (L.topologyVersion != r.storedTopologyVersion)
        return false;

    float currentTarget = EvaluateTargetPdf(L, r.y, s);
    if (currentTarget <= 0.0f)
        return false;

    if (L.radianceVersion != r.storedRadianceVersion)
    {
        float ratio = currentTarget / max(r.targetPdfAtY, 1e-8f);

        if (ratio > 4.0f || ratio < 0.25f)
            r.M = min(r.M, 2u);  // confidence clamp

        r.targetPdfAtY = currentTarget;
        r.storedRadianceVersion = L.radianceVersion;
    }

    return true;
}
```

---

## 10. Research papers, writeups, talks, and reference libraries

### 10.1 Core papers

1. **Bitterli et al., 2020 — _Spatiotemporal Reservoir Resampling for Real-Time Ray Tracing with Dynamic Direct Lighting_**  
   Use for the original ReSTIR DI estimator, temporal/spatial reuse, reservoirs, and many-light direct illumination.  
   Source: <https://research.nvidia.com/labs/rtr/publication/bitterli2020spatiotemporal/>

2. **Boksansky et al., 2021 — _Rendering Many Lights with Grid-Based Reservoirs_ / ReGIR**  
   Use for ReGIR cell construction, grid temporal reuse, dynamic-light caveats, and light-ID indirection.  
   Source: <https://research.nvidia.com/labs/rtr/publication/boksansky2021rendering/>  
   PDF mirror: <https://cwyman.org/papers/rtg2-manyLightReGIR.pdf>

3. **Wyman and Panteleev, 2021 — _Rearchitecting Spatiotemporal Resampling for Production_**  
   Use for production-oriented ReSTIR optimization, memory coherence, ray-budget reduction, and implementation tradeoffs.  
   Source: <https://research.nvidia.com/labs/rtr/publication/wyman2021rearchitecting/>

4. **Lin et al., 2022 — _Generalized Resampled Importance Sampling: Foundations of ReSTIR_ / GRIS**  
   Use for the theory behind correlated reuse, unknown PDFs, varied domains, and shift mappings.  
   Source: <https://research.nvidia.com/publication/2022-07_generalized-resampled-importance-sampling-foundations-restir>

5. **Ouyang et al., 2021 — _ReSTIR GI: Path Resampling for Real-Time Path Tracing_**  
   Less directly about direct-light toggles, but useful for understanding reuse of path samples and temporal/spatial validation patterns.  
   Source: <https://research.nvidia.com/publication/2021-06_restir-gi-path-resampling-real-time-path-tracing>

6. **Kettunen et al., 2023 — _Conditional Resampled Importance Sampling and ReSTIR_**  
   Use when the renderer starts mixing conditional domains, randomized domains, or complex reuse rules.  
   Source: <https://dqlin.xyz/pubs/2023-sa-CRIS/>

7. **Sawhney et al., 2024 — _Decorrelating ReSTIR Samplers via MCMC Mutations_**  
   Use when visible temporal/spatial correlation remains after basic invalidation is correct.  
   Source: <https://arxiv.org/abs/2211.00166>

8. **Zhang et al., 2024 — _Area ReSTIR: Resampling for Real-Time Defocus and Antialiasing_**  
   Use for subpixel/lens tracking and robust temporal reuse under high-frequency camera/sample domains.  
   Source: <https://research.nvidia.com/labs/rtr/publication/zhang2024area/>

### 10.2 Official docs and talks

1. **NVIDIA RTXDI SDK**  
   Best reference implementation for RTXDI/ReSTIR DI/ReGIR-style integration.  
   Source: <https://github.com/NVIDIA-RTX/RTXDI>

2. **RTXDI Integration Guide**  
   Important sections: resource allocation, light data buffer, light index mapping buffer, PDF textures, RIS buffer, ReGIR construction, final shading.  
   Source: <https://github.com/NVIDIA-RTX/RTXDI/blob/main/Doc/Integration.md>

3. **RTXDI Shader API / Application Bridge docs**  
   Important concepts: bridge callbacks, current/previous light loading, index translation, target PDF evaluation.  
   Source: <https://github.com/NVIDIA-RTX/RTXDI/tree/main/Doc>

4. **A Gentle Introduction to ReSTIR: Path Reuse in Real-Time — SIGGRAPH 2023 course**  
   Best learning document for RIS, WRS, ReSTIR, GRIS, bias traps, and integration intuition.  
   Source: <https://intro-to-restir.cwyman.org/>

5. **Cyberpunk 2077 RT: Overdrive ReSTIR integration slides**  
   Useful production warning: inconsistent light indices between frames require a light-index translation pass.  
   Source: <https://intro-to-restir.cwyman.org/presentations/2023ReSTIR_Course_Cyberpunk_2077_Integration.pdf>

6. **NVIDIA blog — _Lighting Scenes with Millions of Lights Using RTX Direct Illumination_**  
   Good high-level RTXDI motivation and integration overview.  
   Source: <https://developer.nvidia.com/blog/lighting-scenes-with-millions-of-lights-using-rtx-direct-illumination/>

7. **NVIDIA blog — _Render Millions of Direct Lights in Real-Time With RTX Direct Illumination_**  
   Good production-context overview for why every light should be treated uniformly, instead of hand-designing a small hero-light set.  
   Source: <https://developer.nvidia.com/blog/render-millions-of-direct-lights-in-real-time-with-rtx-direct-illumination-rtxdi/>

8. **Chris Wyman code and demos page**  
   Useful hub for ReSTIR/RTXDI/Falcor references.  
   Source: <https://cwyman.org/demos.html>

### 10.3 Reference libraries and codebases

Use these as references, not as blind copy-paste sources. Check license compatibility before copying code.

1. **NVIDIA RTXDI SDK**  
   Most important reference. Study `Libraries/Rtxdi`, `Samples/MinimalSample`, `Samples/FullSample`, `DI`, `GI`, `PT`, and ReGIR code paths.  
   Source: <https://github.com/NVIDIA-RTX/RTXDI>

2. **NVIDIA Falcor**  
   Research renderer/framework used by many NVIDIA real-time rendering prototypes. Good for scene loading, render graphs, ray tracing abstractions, and experimental passes.  
   Source: <https://github.com/NVIDIAGameWorks/Falcor>

3. **DQLin/ReSTIR_PT**  
   Source code for SIGGRAPH 2022 ReSTIR PT / GRIS. Useful for path reuse, shift mappings, and generalized reservoir logic.  
   Source: <https://github.com/DQLin/ReSTIR_PT>

4. **NVlabs/conditional-restir-prototype**  
   Source for Conditional RIS / ReSTIR. Useful for conditional-domain correctness and advanced resampling experiments.  
   Source: <https://github.com/NVlabs/conditional-restir-prototype>

5. **guiqi134/Area-ReSTIR**  
   Source for the direct-lighting portion of Area ReSTIR. Useful for subpixel/lens tracking ideas and high-frequency temporal reuse.  
   Source: <https://github.com/guiqi134/Area-ReSTIR>

6. **karel-tomanec/Falcor-ReSTIR**  
   Educational ReSTIR DI implementation in Falcor. Useful to compare a simpler implementation against RTXDI.  
   Source: <https://github.com/karel-tomanec/Falcor-ReSTIR>

7. **lukedan/ReSTIR-Vulkan**  
   Student Vulkan implementation of ReSTIR DI. Useful for a smaller codebase showing Vulkan ray-tracing integration.  
   Source: <https://github.com/lukedan/ReSTIR-Vulkan>

8. **shocker-0x15/GfxExp**  
   Graphics paper sandbox with ReGIR notes/code. Useful for comparing a non-RTXDI ReGIR implementation style.  
   Source: <https://github.com/shocker-0x15/GfxExp>

9. **Trylz/Restir_CPP**  
   Falcor 8 ReSTIR DI implementation. Useful as another implementation reference.  
   Source: <https://github.com/Trylz/Restir_CPP>

### 10.4 Writeups and learning references

1. **Tom Clabault — _ReGIR: An advanced implementation for many-lights sampling_**  
   Modern explanatory writeup on ReGIR and RIS concepts.  
   Source: <https://tomclabault.github.io/blog/2025/regir/>

2. **Interplay of Light — _A gentler introduction to ReSTIR_**  
   Qualitative ReSTIR explanation. Useful for sanity-checking intuition.  
   Source: <https://interplayoflight.wordpress.com/2023/12/17/a-gentler-introduction-to-restir/>

3. **GameHacker1999 — _Spatiotemporal Reservoir Resampling: Theory and Basic Implementation_**  
   Educational breakdown of the original paper.  
   Source: <https://gamehacker1999.github.io/posts/restir/>

4. **Jeremy Ong — _Much Ado About Sampling_**  
   Sampling theory context around RIS/GRIS.  
   Source: <https://jeremyong.com/math/monte%20carlo/2022/05/17/much-ado-about-sampling/>

---

## 11. Researcher task checklist

Give this to the researcher or implementation agent:

```text
1. Audit light identity:
   - Are inactive lights removed from the array?
   - Are lights sorted/compacted by power?
   - Do reservoirs store physical indices without translation?
   - Is there previous/current light-index mapping?

2. Audit stale data:
   - Does the final shade pass reload current light data?
   - Do compact RIS light records cache color/intensity?
   - Are compact records versioned or rebuilt?

3. Audit PDFs:
   - Is local-light PDF rebuilt when intensity/active state changes?
   - Are mip CDFs/alias tables rebuilt all the way to root?
   - Are RIS entries regenerated after source PDF changes?

4. Audit ReGIR:
   - Does grid history store light IDs?
   - Are dynamic-light weights reweighted?
   - Are dynamic lights excluded from temporal grid reuse as a baseline?
   - Is grid lookup jittered to avoid cell boundaries?
   - Does grid history preserve world-cell identity?

5. Audit reservoirs:
   - Is selected light removed/invalid translated properly?
   - Is current target PDF recomputed after light changes?
   - Is history confidence clamped after large radiance changes?
   - Are unrelated reservoirs left intact?

6. Add debug views:
   - selected light ID
   - selected light generation/version
   - target PDF
   - source PDF / invSourcePdf
   - reservoir M/confidence
   - ReGIR cell ID and selected light ID
```

---

## 12. Final guidance

For the described bug, start with these concrete changes:

1. **Keep toggled-off lights in the global light array.**
2. **Do not compact or reorder light indices when active state changes.**
3. **Set inactive light power to zero in the sampling PDF.**
4. **Regenerate current-frame PDF and RIS/presampling buffers after power changes.**
5. **Make final shading reload current light data by stable light ID.**
6. **For ReGIR temporal reuse, either disable dynamic-light reuse first, or reweight dynamic-light reservoirs during grid construction.**
7. **Clamp temporal confidence for reservoirs selecting a light whose radiance changed.**
8. **Invalidate only samples that reference removed/moved/topology-changed lights.**
9. **Do not reset unrelated screen reservoirs when a remote light toggles.**
10. **Add debug views to confirm that unrelated tiles are not changing selected light identity after the toggle.**

If these rules are followed, a remote light toggle should only affect:
- the PDF distribution,
- current-frame candidates,
- reservoirs that selected that light,
- ReGIR cells where that light was sampled,
- and pixels/surfaces where its contribution is non-negligible.

It should not cause unrelated tiles to flash.
