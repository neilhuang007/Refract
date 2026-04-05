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

// RTXDI: RTXDI_RIS_BUFFER — unified buffer for both presample tiles and ReGIR output.
// Presample tiles occupy [ph_ris_tile_buffer_offset, ph_ris_tile_buffer_offset + tileCount*tileSize).
// ReGIR output occupies [ph_regir_ris_buffer_offset, ph_regir_ris_buffer_offset + gridRes^3*lightsPerCell).
// Must be restrict (not readonly/writeonly) since this pass reads tiles and writes ReGIR in different regions.
layout(std430, binding = 5) restrict buffer ph_ris_buffer {
    uvec2 ph_ris_data[];
};

// RTXDI companion buffer: packed light data stored alongside each RIS entry.
// Each entry occupies 4 uvec4 (64 bytes), carrying the full 4xvec4 light record.
// Indexing: risBufferPtr * ph_compact_light_stride + [0..3].
layout(std430, binding = 6) restrict buffer ph_ris_compact_light_data {
    uvec4 ph_compact_light_data[];
};

const uint ph_compact_light_stride = 4u;

// ---------------------------------------------------------------------------
// RTXDI COMPACT_BIT / INDEX_MASK — same constants as regir_presample_tiles.glsl
const uint RTXDI_LIGHT_COMPACT_BIT = 0x80000000u;
const uint RTXDI_LIGHT_INDEX_MASK  = 0x7FFFFFFFu;

// ---------------------------------------------------------------------------
// RAB_StoreCompactLightInfo — stores the compact-light payload for
// light[lightIndex] into ph_compact_light_data at risBufferPtr*ph_compact_light_stride.
// Stores the full 4xvec4 light record so compact reload is self-contained.
// Returns true so the caller sets RTXDI_LIGHT_COMPACT_BIT on the stored index.
// ---------------------------------------------------------------------------
bool RAB_StoreCompactLightInfo(uint risBufferPtr, int lightIndex) {
    if (lightIndex < 0 || lightIndex * light_size + 3 >= ph_lights_array.length()) return false;
    int base = lightIndex * light_size;
    uint dst = risBufferPtr * ph_compact_light_stride;
    ph_compact_light_data[dst + 0u] = floatBitsToUint(ph_lights_array[base + 0]);
    ph_compact_light_data[dst + 1u] = floatBitsToUint(ph_lights_array[base + 1]);
    ph_compact_light_data[dst + 2u] = floatBitsToUint(ph_lights_array[base + 2]);
    ph_compact_light_data[dst + 3u] = floatBitsToUint(ph_lights_array[base + 3]);
    return true;
}

// ---------------------------------------------------------------------------
// RAB_LoadCompactLightData — loads the compact-light payload into in-register
// light state needed by ReGIR importance evaluation.
// ---------------------------------------------------------------------------
void RAB_LoadCompactLightData(uint risBufferPtr,
    out vec3 lightPos, out uint blockIdBits,
    out vec3 lightColor, out float intensity,
    out vec2 attenuation, out float falloff,
    out vec3 emissionAxis, out float orientationSpread) {
    uint src = risBufferPtr * ph_compact_light_stride;
    vec4 ld0 = uintBitsToFloat(ph_compact_light_data[src + 0u]);
    vec4 ld1 = uintBitsToFloat(ph_compact_light_data[src + 1u]);
    vec4 ld2 = uintBitsToFloat(ph_compact_light_data[src + 2u]);
    vec4 ld3 = uintBitsToFloat(ph_compact_light_data[src + 3u]);
    lightPos = ld0.xyz;
    blockIdBits = floatBitsToUint(ld0.w);
    lightColor = ld1.xyz;
    intensity = ld1.w;
    attenuation = ld2.xy;
    falloff = ld2.z;
    emissionAxis = normalize(ld3.xyz + vec3(1e-6));
    orientationSpread = ld3.w;
}

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
// RTXDI: gridCenter = camera position; origin derived as:
//   gridOrigin = gridCenter - vec3(gridRes) * cellSize * 0.5
uniform vec3  ph_regir_grid_center;            // RTXDI: gridParams.center (world-space grid center)
uniform ivec3 ph_regir_grid_cells;             // RTXDI: int3 gridCellCount = int3(cellsX, cellsY, cellsZ)
uniform int   ph_regir_lights_per_cell;        // RTXDI: commonParams.lightsPerCell
uniform float ph_regir_cell_size;              // RTXDI: commonParams.cellSize
uniform int   ph_light_count;
uniform uint  ph_ris_frame_index;              // RTXDI: g_Const.runtimeParams.frameIndex (raw frame count)
uniform int   ph_ris_tile_size;                // RTXDI: risBufferSegmentParams.tileSize
uniform int   ph_ris_tile_count;               // RTXDI: risBufferSegmentParams.tileCount
uniform uint  ph_regir_build_samples;          // RTXDI: ReGIR.h:141 default = 8
uniform float ph_regir_sampling_jitter;        // RTXDI ReGIR jitter in grid-cell units; 1.0 = +/- one cell
uniform uint  ph_ris_tile_buffer_offset;       // RTXDI: risBufferSegmentParams.bufferOffset (typically 0)
uniform uint  ph_regir_ris_buffer_offset;      // RTXDI: offset into unified RIS buffer where ReGIR data starts

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

// Grid origin: continuous, matching RTXDI_ReGIR_WorldPosToCellIndex.
vec3 regir_grid_origin() {
    return ph_regir_grid_center - vec3(ph_regir_grid_cells) * (ph_regir_cell_size * 0.5);
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
    info.risTileOffset = ph_ris_tile_buffer_offset + tileIndex * uint(ph_ris_tile_size);
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
    out float invSourcePdf,
    out bool hasCompact,
    out uint outRisBufferPtr
) {
    uint risSample = min(uint(floor(rnd * float(tileInfo.risTileSize))), tileInfo.risTileSize - 1u);
    outRisBufferPtr = risSample + tileInfo.risTileOffset;
    uvec2 tileData = ph_ris_data[outRisBufferPtr];
    // RTXDI: check COMPACT_BIT — if set, compact data is available in ph_compact_light_data.
    hasCompact   = (tileData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u;
    rndLight     = int(tileData.x & RTXDI_LIGHT_INDEX_MASK);
    invSourcePdf = uintBitsToFloat(tileData.y);

    // Empty RIS entries are stored as uint2(0, 0). In Photonics, the ReGIR build path
    // evaluates target PDFs from the decoded light index directly, so aliasing an empty
    // entry to light 0 would manufacture bogus positive weights and poison whole cells.
    bool invalidEntry = (tileData.x == 0u && tileData.y == 0u) || invSourcePdf <= 0.0;
    if (invalidEntry) {
        rndLight = -1;
        invSourcePdf = 0.0;
        hasCompact = false;
    }
}

// ---------------------------------------------------------------------------
// RAB_GetLightTargetPdfForVolume — full attenuation-model importance.
// Mirrors ph_compute_attenuation (attenuation.glsl):
//   result_color = color * intensity / dot(vec2(1, dist_sq * falloff), attenuation)
// Plus directional emission-cone shaping.
// hasCompact / risBufferPtr: when the tile entry had COMPACT_BIT set, load the
// 4 vec4s from the companion buffer instead of the main light array.
// ---------------------------------------------------------------------------
float RAB_GetLightTargetPdfForVolume(int lightIndex, bool hasCompact, uint risBufferPtr, vec3 cellCenter, float cellRadius) {
    vec3  lightPos;
    vec3  lightColor;
    float intensity;
    vec2  attenuation;
    float falloff;
    vec3  emissionAxis;
    float orientationSpread;
    if (hasCompact) {
        uint blockIdBits;
        RAB_LoadCompactLightData(
            risBufferPtr,
            lightPos,
            blockIdBits,
            lightColor,
            intensity,
            attenuation,
            falloff,
            emissionAxis,
            orientationSpread
        );
    } else {
        int base = lightIndex * light_size;
        vec4 ld0 = ph_lights_array[base + 0];
        vec4 ld1 = ph_lights_array[base + 1];
        vec4 ld2 = ph_lights_array[base + 2];
        vec4 ld3 = ph_lights_array[base + 3];
        lightPos          = ld0.xyz;
        lightColor        = ld1.xyz;
        intensity         = ld1.w;
        attenuation       = ld2.xy;
        falloff           = ld2.z;
        emissionAxis      = normalize(ld3.xyz + vec3(1e-6));
        orientationSpread = ld3.w;
    }

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
    float luminance = max(dot(attenuatedColor, vec3(0.2126, 0.7152, 0.0722)), 0.0);

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
    uint totalSlots    = uint(ph_regir_grid_cells.x * ph_regir_grid_cells.y * ph_regir_grid_cells.z) * uint(lightsPerCell);

    // Over-dispatch safety guard (RTXDI assumes exact dispatch sizing).
    if (lightSlot >= totalSlots) {
        return;
    }

    // RTXDI: risBufferPtr = regirParams.commonParams.risBufferOffset + lightSlot
    // Compute write position FIRST, then check numBuildSamples==0 (matching RTXDI line 177-183).
    uint lightInCell  = lightSlot % uint(lightsPerCell);
    uint cellIndex    = lightSlot / uint(lightsPerCell);
    uint risBufferPtr = ph_regir_ris_buffer_offset + cellIndex * uint(lightsPerCell) + lightInCell;

    // RTXDI: if (numRegirBuildSamples == 0) { RIS_BUFFER[risBufferPtr] = uint2(0, 0); return; }
    if (ph_regir_build_samples == 0u) {
        ph_ris_data[risBufferPtr] = uvec2(0u, 0u);
        return;
    }

    // RTXDI: RTXDI_ReGIR_CellIndexToWorldPos → cellCenter, cellRadius
    uint cx = cellIndex % uint(ph_regir_grid_cells.x);
    uint cy = (cellIndex / uint(ph_regir_grid_cells.x)) % uint(ph_regir_grid_cells.y);
    uint cz = cellIndex / uint(ph_regir_grid_cells.x * ph_regir_grid_cells.y);

    // RTXDI ReGIRSampling.hlsli: bounds check — reject over-dispatched threads
    if (cz >= uint(ph_regir_grid_cells.z)) {
        ph_ris_data[risBufferPtr] = uvec2(0u, 0u);
        return;
    }

    vec3 gridOrigin = regir_grid_origin();

    vec3  cellCenter = gridOrigin
                     + (vec3(float(cx), float(cy), float(cz)) + 0.5) * ph_regir_cell_size;
    float cellRadius = ph_regir_cell_size * sqrt(3.0);

    // RTXDI: cellRadius *= (regirParams.commonParams.samplingJitter + 1.0)
    cellRadius *= (ph_regir_sampling_jitter + 1.0);

    // RTXDI: rng = RTXDI_InitRandomSampler(uint2(GlobalIndex & 0xfff, GlobalIndex >> 12), frameIndex, 1)
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(lightSlot & 0xFFFu, lightSlot >> 12u),
        ph_ris_frame_index,
        1u
    );

    // RTXDI: coherentRng = RTXDI_InitRandomSampler(uint2(GlobalIndex >> 8, 0), frameIndex, 1)
    RTXDI_RandomSamplerState coherentRng = RTXDI_InitRandomSampler(
        uvec2(lightSlot >> 8u, 0u),
        ph_ris_frame_index,
        1u
    );

    // RTXDI: ctx = RTXDI_InitializeLocalLightSelectionContextRIS(coherentRng, risBufferSegmentParams)
    RISTileInfo risTileInfo = RTXDI_RandomlySelectRISTile(coherentRng);

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
        bool  tileHasCompact;
        uint  tileRisBufferPtr;
        RTXDI_RandomlySelectLightDataFromRISTile(rand, risTileInfo, rndLight, invSourcePdf, tileHasCompact, tileRisBufferPtr);

        if (rndLight < 0 || invSourcePdf <= 0.0) {
            continue;
        }

        // RTXDI: no early rejection — invalid entries produce zero risWeight naturally.
        // invSourcePdf *= invNumSamples
        invSourcePdf *= invNumSamples;

        // RTXDI: targetPdf = RAB_GetLightTargetPdfForVolume(lightInfo, cellCenter, cellRadius)
        // When the tile entry carries compact data, use it to avoid a random-access into ph_lights_array.
        float targetPdf = RAB_GetLightTargetPdfForVolume(rndLight, tileHasCompact, tileRisBufferPtr, cellCenter, cellRadius);

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

    // RTXDI: store compact data for the selected light in the ReGIR output slot.
    // If storage succeeds, set COMPACT_BIT on the stored index.
    // When no candidate had positive weight, store the exact RTXDI invalid entry: uint2(0, 0).
    // risBufferPtr was pre-computed at the top of main() as ph_regir_ris_buffer_offset + cellIndex * lightsPerCell + lightInCell.
    uint packedIndex = 0u;
    if (weight > 0.0 && selectedLight >= 0) {
        packedIndex = uint(selectedLight) & RTXDI_LIGHT_INDEX_MASK;
        if (RAB_StoreCompactLightInfo(risBufferPtr, selectedLight)) {
            packedIndex |= RTXDI_LIGHT_COMPACT_BIT;
        }
    }
    ph_ris_data[risBufferPtr] = uvec2(packedIndex, floatBitsToUint(weight));
}
