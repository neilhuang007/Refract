#version 430

// RTXDI_PresampleLocalLightsForReGIR — ReGIR grid build compute shader.
// Each thread populates one light slot in a grid cell via RIS, drawing
// candidates from the presampled RIS tile buffer (regir_presample_tiles.glsl).
//
// Reference: PresamplingFunctions.hlsli, PresampleReGIR.hlsl
//
// Key RTXDI design: a "coherent RNG" (shared seed across nearby threads)
// selects ONE tile per thread; all numRegirBuildSamples proposals then draw
// from that same tile.  This keeps nearby threads reading the same tile → cache
// coherent.  A separate per-thread RNG picks the within-tile entry each
// iteration, giving independent samples.

layout(local_size_x = 256) in;

// ---------------------------------------------------------------------------
// SSBOs
// ---------------------------------------------------------------------------
const int light_size = 4; // 4 vec4s per light

// Light list (matches photonics.glsl)
// vec4[0]: position.xyz, blockId(w)
// vec4[1]: color.xyz, intensity(w)
// vec4[2]: attenuation.xy, falloff(z), block_radius(w)
// vec4[3]: emissionAxis.xyz, orientationSpread(w)
layout(std140, binding = 0) restrict readonly buffer ph_light_list {
    vec4 ph_lights_array[];
};

// Power CDF — kept for potential fallback; not used in the tile-based path.
layout(std430, binding = 1) restrict readonly buffer ph_global_light_cdf {
    float ph_global_light_cdf_data[];
};

// RTXDI: RTXDI_RIS_BUFFER — ReGIR output, written at fixed positions.
// Each cell has lightsPerCell slots.  Invalid entries = uvec2(~0u, 0u).
// Stored as uvec2 matching the RIS tile buffer format:
//   .x = lightIndex & RTXDI_LIGHT_INDEX_MASK  (bit 31 = 0 — no compact data)
//   .y = floatBitsToUint(invSourcePdf / weight)
// The per-pixel reader in light_tree.glsl unpacks the same way as a tile entry.
layout(std430, binding = 3) restrict writeonly buffer ph_regir_output_buffer {
    uvec2 ph_regir_output_data[];
};

// RTXDI: RTXDI_RIS_BUFFER — presampled tiles written by regir_presample_tiles.glsl
layout(std430, binding = 5) restrict readonly buffer ph_ris_tile_buffer {
    uvec2 ph_ris_tile_data[];
};

// ---------------------------------------------------------------------------
// RTXDI COMPACT_BIT / INDEX_MASK — same constants as regir_presample_tiles.glsl
const uint RTXDI_LIGHT_COMPACT_BIT = 0x80000000u;
const uint RTXDI_LIGHT_INDEX_MASK  = 0x7FFFFFFFu;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
// RTXDI: gridCenter = camera position; origin derived as:
//   gridOrigin = gridCenter - vec3(gridRes) * cellSize * 0.5
uniform vec3  ph_regir_grid_center;            // RTXDI: gridParams.center (world-space grid center)
uniform int   ph_regir_grid_resolution;        // RTXDI: gridParams.cellsX (uniform grid)
uniform int   ph_regir_lights_per_cell;        // RTXDI: commonParams.lightsPerCell
uniform float ph_regir_cell_size;              // RTXDI: commonParams.cellSize
uniform int   ph_light_count;
uniform uint  ph_ris_frame_index;              // RTXDI: g_Const.runtimeParams.frameIndex (raw frame count)
uniform int   ph_ris_tile_size;                // RTXDI: risBufferSegmentParams.tileSize
uniform int   ph_ris_tile_count;               // RTXDI: risBufferSegmentParams.tileCount
uniform uint  ph_regir_build_samples;          // RTXDI: ReGIR.h:141 default = 8
uniform float ph_regir_sampling_jitter;        // RTXDI: commonParams.samplingJitter (default 1.0)

// ---------------------------------------------------------------------------
// RTXDI RNG — exact port of RandomSamplerState.hlsli + Math.hlsli
// Same system as regir_presample_tiles.glsl.
// ---------------------------------------------------------------------------

uint RTXDI_IntegerExplode(uint x) {
    x = (x | (x << 8u)) & 0x00FF00FFu;
    x = (x | (x << 4u)) & 0x0F0F0F0Fu;
    x = (x | (x << 2u)) & 0x33333333u;
    x = (x | (x << 1u)) & 0x55555555u;
    return x;
}

uint RTXDI_ZCurveToLinearIndex(uvec2 xy) {
    return RTXDI_IntegerExplode(xy.x) | (RTXDI_IntegerExplode(xy.y) << 1u);
}

uint RTXDI_JenkinsHash(uint a) {
    a = (a + 0x7ed55d16u) + (a << 12u);
    a = (a ^ 0xc761c23cu) ^ (a >> 19u);
    a = (a + 0x165667b1u) + (a << 5u);
    a = (a + 0xd3a2646cu) ^ (a << 9u);
    a = (a + 0xfd7046c5u) + (a << 3u);
    a = (a ^ 0xb55a4f09u) ^ (a >> 16u);
    return a;
}

struct RTXDI_RandomSamplerState {
    uint seed;
    uint index;
};

const uint RTXDI_RANDOM_SAMPLER_PRIME_CONSTANT = 31u;

RTXDI_RandomSamplerState RTXDI_InitRandomSampler(uvec2 pixelPos, uint frameIndex, uint pass) {
    RTXDI_RandomSamplerState state;
    uint linearPixelIndex = RTXDI_ZCurveToLinearIndex(pixelPos);
    state.index = 1u;
    state.seed = RTXDI_JenkinsHash(linearPixelIndex) + frameIndex + (pass * RTXDI_RANDOM_SAMPLER_PRIME_CONSTANT);
    return state;
}

uint RTXDI_murmur3(inout RTXDI_RandomSamplerState r) {
    uint c1 = 0xcc9e2d51u;
    uint c2 = 0x1b873593u;
    uint hash = r.seed;
    uint k = r.index++;
    k *= c1;
    k = (k << 15u) | (k >> 17u);
    k *= c2;
    hash ^= k;
    hash = (hash << 13u) | (hash >> 19u);
    hash = hash * 5u + 0xe6546b64u;
    hash ^= 4u;
    hash ^= (hash >> 16u);
    hash *= 0x85ebca6bu;
    hash ^= (hash >> 13u);
    hash *= 0xc2b2ae35u;
    hash ^= (hash >> 16u);
    return hash;
}

float RTXDI_GetNextRandom(inout RTXDI_RandomSamplerState rng) {
    uint v = RTXDI_murmur3(rng);
    const uint one = 0x3f800000u;
    const uint mask = (1u << 23u) - 1u;
    return uintBitsToFloat((mask & v) | one) - 1.0;
}

// ---------------------------------------------------------------------------
// RTXDI_RandomlySelectRISTile — picks ONE tile using the coherent RNG.
// Called ONCE per thread, outside the RIS loop.
//
// Reference: RISBuffer.hlsli
//   RTXDI_RISTileInfo RTXDI_RandomlySelectRISTile(coherentRng, params)
//   {
//       float tileRnd = RTXDI_GetNextRandom(coherentRng);
//       uint tileIndex = uint(tileRnd * params.tileCount);
//       risTileInfo.risTileOffset = tileIndex * params.tileSize + params.bufferOffset;
//       risTileInfo.risTileSize = params.tileSize;
//   }
// ---------------------------------------------------------------------------
struct RISTileInfo {
    uint risTileOffset;
    uint risTileSize;
};

RISTileInfo RTXDI_RandomlySelectRISTile(inout RTXDI_RandomSamplerState coherentRng) {
    float tileRnd = RTXDI_GetNextRandom(coherentRng);
    // RTXDI: uint tileIndex = uint(tileRnd * params.tileCount)  — no min() clamp
    uint tileIndex = uint(tileRnd * float(ph_ris_tile_count));
    RISTileInfo info;
    info.risTileOffset = tileIndex * uint(ph_ris_tile_size);
    info.risTileSize   = uint(ph_ris_tile_size);
    return info;
}

// ---------------------------------------------------------------------------
// RTXDI_RandomlySelectLightDataFromRISTile — picks one entry from the tile.
// Called each iteration inside the RIS loop using the per-thread rng.
//
// Reference: RISBuffer.hlsli
//   void RTXDI_RandomlySelectLightDataFromRISTile(float rnd, RISTileInfo, out uint2, out uint)
//   {
//       uint risSample = min(uint(floor(rnd * bufferInfo.risTileSize)), risTileSize - 1);
//       uint risBufferPtr = risSample + bufferInfo.risTileOffset;
//       tileData = RTXDI_RIS_BUFFER[risBufferPtr];
//   }
// ---------------------------------------------------------------------------
void RTXDI_RandomlySelectLightDataFromRISTile(
    float rnd,
    RISTileInfo tileInfo,
    out int rndLight,
    out float invSourcePdf
) {
    uint risSample = min(uint(floor(rnd * float(tileInfo.risTileSize))), tileInfo.risTileSize - 1u);
    uint risBufferPtr = risSample + tileInfo.risTileOffset;
    uvec2 tileData = ph_ris_tile_data[risBufferPtr];
    // RTXDI: check COMPACT_BIT then load from compact or full buffer.
    // We never store compact data, so always load from full buffer.
    // Apply INDEX_MASK to strip the (always-zero) compact bit.
    bool hasCompactData = (tileData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u;
    rndLight     = int(tileData.x & RTXDI_LIGHT_INDEX_MASK);
    invSourcePdf = uintBitsToFloat(tileData.y);
    // If compact data bit was set (should never happen) invalidate the sample.
    if (hasCompactData) {
        rndLight     = -1;
        invSourcePdf = 0.0;
    }
}

// ---------------------------------------------------------------------------
// RAB_GetLightTargetPdfForVolume — full attenuation-model importance.
// Mirrors ph_compute_attenuation (attenuation.glsl):
//   result_color = color * intensity / dot(vec2(1, dist_sq * falloff), attenuation)
// Plus directional emission-cone shaping.
// ---------------------------------------------------------------------------
float RAB_GetLightTargetPdfForVolume(int lightIndex, vec3 cellCenter, float cellRadius) {
    int   base              = lightIndex * light_size;
    vec3  lightPos          = ph_lights_array[base + 0].xyz;
    vec3  lightColor        = ph_lights_array[base + 1].xyz;
    float intensity         = ph_lights_array[base + 1].w;
    vec2  attenuation       = ph_lights_array[base + 2].xy;
    float falloff           = ph_lights_array[base + 2].z;
    vec3  emissionAxis      = ph_lights_array[base + 3].xyz;
    float orientationSpread = ph_lights_array[base + 3].w;

    vec3  delta = cellCenter - lightPos;
    float dist  = length(delta);

    // regirAverageDistanceToVolume — nonlinear approximation
    float nonlinearFactor = 1.1547;
    float radiusSq        = cellRadius * cellRadius;
    float denom           = dist + cellRadius * nonlinearFactor;
    float averageDistance  = dist + cellRadius * radiusSq / max(denom * denom, 1e-4);
    float averageDistSq   = averageDistance * averageDistance;

    // Full attenuation model (attenuation.glsl)
    float attenuationDenom = dot(vec2(1.0, averageDistSq * falloff), attenuation);
    attenuationDenom = max(attenuationDenom, 1e-4);
    vec3  attenuatedColor = lightColor * intensity / attenuationDenom;
    float luminance = max(dot(attenuatedColor, vec3(0.299, 0.587, 0.114)), 0.0);

    // Directional emission shaping (attenuation.glsl)
    float shaping = 1.0;
    if (orientationSpread < 3.14159265) {
        vec3  dir       = (dist > 1e-4) ? (delta / dist) : vec3(0.0, 0.0, 1.0);
        float axisDot   = clamp(dot(emissionAxis, -dir), -1.0, 1.0);
        float axisAngle = acos(axisDot);
        shaping = max(cos(max(axisAngle - orientationSpread, 0.0)), 0.0);
    }
    if (shaping <= 0.0) return 0.0;

    return luminance * shaping;
}

// ---------------------------------------------------------------------------
// Main — RTXDI_PresampleLocalLightsForReGIR
// ---------------------------------------------------------------------------
void main() {
    // RTXDI: uint lightSlot = GlobalIndex
    uint lightSlot     = gl_GlobalInvocationID.x;
    int  lightsPerCell = ph_regir_lights_per_cell;
    int  gridRes       = ph_regir_grid_resolution;
    uint totalSlots    = uint(gridRes * gridRes * gridRes) * uint(lightsPerCell);

    if (lightSlot >= totalSlots) return;

    // RTXDI: cellIndex = lightSlot / lightsPerCell
    uint cellIndex = lightSlot / uint(lightsPerCell);

    // RTXDI: RTXDI_ReGIR_CellIndexToWorldPos → cellCenter, cellRadius
    uint cx = cellIndex % uint(gridRes);
    uint cy = (cellIndex / uint(gridRes)) % uint(gridRes);
    uint cz = cellIndex / uint(gridRes * gridRes);

    // RTXDI: gridOrigin = gridCenter - float3(gridCellCount) * (cellSize * 0.5)
    vec3 gridOrigin = ph_regir_grid_center - vec3(float(gridRes)) * (ph_regir_cell_size * 0.5);

    vec3  cellCenter = gridOrigin
                     + (vec3(float(cx), float(cy), float(cz)) + 0.5) * ph_regir_cell_size;
    float cellRadius = ph_regir_cell_size * sqrt(3.0);

    // RTXDI: cellRadius *= (regirParams.commonParams.samplingJitter + 1.0)
    cellRadius *= (ph_regir_sampling_jitter + 1.0);

    // RTXDI: rng = RTXDI_InitRandomSampler(uint2(GlobalIndex & 0xfff, GlobalIndex >> 12), frameIndex, 1)
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(lightSlot & 0xFFFu, lightSlot >> 12u),
        ph_ris_frame_index,
        1u  // pass = 1 for ReGIR build
    );

    // RTXDI: coherentRng = RTXDI_InitRandomSampler(uint2(GlobalIndex >> 8, 0), frameIndex, 1)
    // Every 256 threads share the same coherent seed → read from the same tile
    RTXDI_RandomSamplerState coherentRng = RTXDI_InitRandomSampler(
        uvec2(lightSlot >> 8u, 0u),
        ph_ris_frame_index,
        1u  // pass = 1 for ReGIR build
    );

    // RTXDI: ctx = RTXDI_InitializeLocalLightSelectionContextRIS(coherentRng, risBufferSegmentParams)
    // Tile selected ONCE per thread using coherentRng (all nearby threads pick the same tile)
    RISTileInfo risTileInfo = RTXDI_RandomlySelectRISTile(coherentRng);

    // RTXDI: if (numRegirBuildSamples == 0) write invalid entry and return (line 179-183)
    uint lightInCellEarly  = lightSlot % uint(lightsPerCell);
    uint risBufferPtrEarly = cellIndex * uint(lightsPerCell) + lightInCellEarly;
    if (ph_regir_build_samples == 0u) {
        ph_regir_output_data[risBufferPtrEarly] = uvec2(0u, 0u);
        return;
    }

    // RTXDI: float invNumSamples = 1.0 / float(numRegirBuildSamples)
    // numRegirBuildSamples comes from ph_regir_build_samples uniform (default 8 — RTXDI default)
    uint numBuildSamples = ph_regir_build_samples;
    float invNumSamples = 1.0 / float(numBuildSamples);

    // RTXDI: selectedLight, selectedTargetPdf, weightSum
    int   selectedLight     = -1;
    float selectedTargetPdf = 0.0;
    float weightSum         = 0.0;

    // RTXDI: for (uint i = 0; i < numRegirBuildSamples; i++)
    for (uint i = 0u; i < numBuildSamples; i++) {
        // RTXDI: float rand = RTXDI_GetNextRandom(rng)
        //        RTXDI_SelectNextLocalLight(ctx, rand, lightInfo, rndLight, invSourcePdf)
        // The rand value is used as the within-tile selection random number.
        float rand = RTXDI_GetNextRandom(rng);

        int   rndLight;
        float invSourcePdf;
        RTXDI_RandomlySelectLightDataFromRISTile(rand, risTileInfo, rndLight, invSourcePdf);

        // RTXDI: no early rejection — invalid entries produce zero risWeight naturally.
        // invSourcePdf *= invNumSamples
        invSourcePdf *= invNumSamples;

        // RTXDI: targetPdf = RAB_GetLightTargetPdfForVolume(lightInfo, cellCenter, cellRadius)
        float targetPdf = RAB_GetLightTargetPdfForVolume(rndLight, cellCenter, cellRadius);

        // RTXDI: risRnd = RTXDI_GetNextRandom(rng)
        float risRnd = RTXDI_GetNextRandom(rng);

        // RTXDI: risWeight = targetPdf * invSourcePdf
        float risWeight = targetPdf * invSourcePdf;
        weightSum += risWeight;

        // RTXDI: if (risRnd * weightSum < risWeight) → accept
        if (risRnd * weightSum < risWeight) {
            selectedLight     = rndLight;
            selectedTargetPdf = targetPdf;
        }
    }

    // RTXDI: weight = (selectedTargetPdf > 0) ? weightSum / selectedTargetPdf : 0
    float weight = (selectedTargetPdf > 0.0)
        ? (weightSum / selectedTargetPdf)
        : 0.0;

    // RTXDI: RTXDI_RIS_BUFFER[risBufferPtr] = uint2(lightIndex, asuint(weight))
    // Stored as uvec2 matching the RIS tile buffer format.
    // Invalid entries: selectedLight = -1 → stored as uvec2(0u, 0u) matching RTXDI convention.
    // Fixed-position write — each thread owns its slot.
    uint lightInCell  = lightSlot % uint(lightsPerCell);
    uint risBufferPtr = cellIndex * uint(lightsPerCell) + lightInCell;
    uint packedIndex  = (selectedLight >= 0)
        ? (uint(selectedLight) & RTXDI_LIGHT_INDEX_MASK)
        : 0u;  // RTXDI invalid sentinel: lightIndex=0, weight=0
    ph_regir_output_data[risBufferPtr] = uvec2(packedIndex, floatBitsToUint(weight));
}
