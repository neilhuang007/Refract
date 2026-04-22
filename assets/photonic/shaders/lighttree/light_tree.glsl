#ifndef PH_RESTIR_REGIR_INCLUDE
#define PH_RESTIR_REGIR_INCLUDE

// ReGIR output buffer -- each cell has lightsPerCell fixed-position slots.
// Stored as uvec2 matching the RIS tile buffer format:
//   .x = lightIndex & RTXDI_LIGHT_INDEX_MASK  (bit 31 = RTXDI_LIGHT_COMPACT_BIT when set by build pass)
//   .y = floatBitsToUint(weight), which the selection path reuses as the slot's invSourcePdf
//        exactly like RTXDI's ReGIR RIS mini-tile readback.
// Invalid entries: .x = RTXDI_LIGHT_INDEX_MASK (all lower bits set), .y = 0.
// Per-pixel code reads this exactly like a tile entry (same unpack path).

// RTXDI COMPACT_BIT / INDEX_MASK
const uint RTXDI_LIGHT_COMPACT_BIT = 0x80000000u;
const uint RTXDI_LIGHT_INDEX_MASK  = 0x7FFFFFFFu;

layout(std430, binding = 5) restrict buffer ph_ris_buffer {
    uvec2 ph_ris_data[];
};

// Shared compact-light decoder for RIS entries produced by either presample tiles or ReGIR.
// Each compact entry occupies 4 uvec4 (64 bytes), carrying the full 4xvec4 light record.
// Indexing: risBufferPtr * ph_compact_light_stride + [0..3].
layout(std430, binding = 6) restrict readonly buffer ph_ris_compact_light_data {
    uvec4 ph_compact_light_data[];
};

const uint ph_compact_light_stride = 4u;

Light load_compact_light(uint risBufferPtr, int lightIndex) {
    uint src = risBufferPtr * ph_compact_light_stride;
    vec4 ld0 = uintBitsToFloat(ph_compact_light_data[src + 0u]);
    vec4 ld1 = uintBitsToFloat(ph_compact_light_data[src + 1u]);
    vec4 ld2 = uintBitsToFloat(ph_compact_light_data[src + 2u]);
    vec4 ld3 = uintBitsToFloat(ph_compact_light_data[src + 3u]);
    return Light(
        lightIndex,
        floatBitsToInt(ld0.w),
        ld0.xyz - world_offset,
        ld1.xyz,
        ld1.w,
        ld2.xy,
        ld2.z,
        ld2.w,
        normalize(ld3.xyz + vec3(1e-6f)),
        ld3.w
    );
}

// ph_regir_grid_center: world-space center of the ReGIR grid (= camera position).
// gridOrigin derived as: origin = center - vec3(ph_regir_grid_cells) * cellSize * 0.5
uniform vec3  ph_regir_grid_center;
uniform ivec3 ph_regir_grid_cells;
uniform int   ph_regir_lights_per_cell;
uniform float ph_regir_cell_size;
uniform float ph_regir_sampling_jitter;
uniform int   ph_regir_ris_buffer_offset;  // RTXDI: offset into unified RIS buffer where ReGIR data starts

const uint RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED = 1u;
const uint RTXDI_DI_TEMPORAL_RESAMPLING_RANDOM_SEED = 2u;
const uint RTXDI_DI_SPATIAL_RESAMPLING_RANDOM_SEED = 3u;
const uint RTXDI_GI_TEMPORAL_RESAMPLING_RANDOM_SEED = 12u;
const uint RTXDI_GI_SPATIAL_RESAMPLING_RANDOM_SEED = 13u;
const uint RTXDI_GI_SPATIOTEMPORAL_RESAMPLING_RANDOM_SEED = 14u;
const uint RTXDI_RANDAOM_SAMPLER_PRIME_CONSTANT = 31u;
const uint RTXDI_TILE_SIZE_IN_PIXELS = 16u;

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

RTXDI_RandomSamplerState RTXDI_InitRandomSampler(uvec2 pixelPos, uint frameIndex, uint pass) {
    RTXDI_RandomSamplerState state;
    uint linearPixelIndex = RTXDI_ZCurveToLinearIndex(pixelPos);
    state.index = 1u;
    state.seed = RTXDI_JenkinsHash(linearPixelIndex) + frameIndex + (pass * RTXDI_RANDAOM_SAMPLER_PRIME_CONSTANT);
    return state;
}

uint RTXDI_murmur3(inout RTXDI_RandomSamplerState r) {
    uint c1 = 0xcc9e2d51u;
    uint c2 = 0x1b873593u;
    uint r1 = 15u;
    uint r2 = 13u;
    uint m = 5u;
    uint n = 0xe6546b64u;

    uint hash = r.seed;
    uint k = r.index++;
    k *= c1;
    k = (k << r1) | (k >> (32u - r1));
    k *= c2;

    hash ^= k;
    hash = ((hash << r2) | (hash >> (32u - r2))) * m + n;

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
    const uint one = floatBitsToUint(1.0f);
    const uint mask = (1u << 23u) - 1u;
    return uintBitsToFloat((mask & v) | one) - 1.0f;
}

// Grid origin: snapped to cell boundaries for frame-to-frame stability.
// When the camera moves less than one cell, the grid doesn't shift, which helps
// temporal reuse maintain stable reservoirs. The snap is applied identically
// in the GPU build shader so build and query always agree.
vec3 regir_grid_origin() {
    vec3 continuousOrigin = ph_regir_grid_center - vec3(ph_regir_grid_cells) * (ph_regir_cell_size * 0.5);
    return floor(continuousOrigin / ph_regir_cell_size) * ph_regir_cell_size;
}

// RTXDI: RTXDI_ReGIR_WorldPosToCellIndex -- maps world position to grid cell
// coords. Returns false when outside the grid.
bool regir_cell_in_bounds(ivec3 cellCoord);
bool regir_world_to_cell(vec3 shadingWorldPos, out ivec3 cellCoord) {
    vec3 gridOrigin = regir_grid_origin();
    vec3 relative   = shadingWorldPos - gridOrigin;
    cellCoord       = ivec3(floor(relative / ph_regir_cell_size));
    return regir_cell_in_bounds(cellCoord);
}

int regir_flatten_cell(ivec3 cellCoord) {
    return cellCoord.x + ph_regir_grid_cells.x * (cellCoord.y + ph_regir_grid_cells.y * cellCoord.z);
}

bool regir_cell_in_bounds(ivec3 cellCoord) {
    return all(greaterThanEqual(cellCoord, ivec3(0)))
        && all(lessThan(cellCoord, ph_regir_grid_cells));
}

// Unpack a ReGIR output slot -- same format as a RIS tile entry.
// Returns false if the slot is invalid (RTXDI invalid entry uint2(0,0) or a zero invSourcePdf payload).
// outHasCompact: true when RTXDI_LIGHT_COMPACT_BIT is set -- compact companion data is available
//   in ph_compact_light_data at outRisBufferPtr*ph_compact_light_stride + [0..3].
bool regir_unpack_slot(int flatCellIndex, int cellSlot,
    out int lightIndex, out float invSourcePdf,
    out bool outHasCompact, out uint outRisBufferPtr) {
    int  bufferIndex   = flatCellIndex * ph_regir_lights_per_cell + cellSlot;
    outRisBufferPtr    = uint(ph_regir_ris_buffer_offset) + uint(bufferIndex);
    uvec2 slotData     = ph_ris_data[outRisBufferPtr];
    outHasCompact      = (slotData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u;
    lightIndex         = int(slotData.x & RTXDI_LIGHT_INDEX_MASK);
    invSourcePdf       = uintBitsToFloat(slotData.y);

    // RTXDI writes invalid ReGIR entries as uint2(0, 0), not INDEX_MASK sentinel values.
    // Because light 0 is a legal light, validity must be derived from the stored weight/PDF,
    // not from the decoded light index alone.
    bool isInvalidEntry = (slotData.x == 0u && slotData.y == 0u) || invSourcePdf <= 0.0;
    if (isInvalidEntry) {
        lightIndex    = -1;
        invSourcePdf  = 0.0;
        outHasCompact = false;
        return false;
    }
    return true;
}

// RTXDI: RTXDI_CalculateReGIRCellIndex -- determines which cell this pixel falls in.
// Returns true if inside the grid, with flatCellIndex set.
// Match RTXDI by using the same sampling jitter parameter that the build path uses.
bool regir_resolve_cell(vec3 shadingWorldPos, inout RTXDI_RandomSamplerState rng, out int flatCellIndex) {
    flatCellIndex = -1;

    vec3 cellJitter = vec3(
        RTXDI_GetNextRandom(rng),
        RTXDI_GetNextRandom(rng),
        RTXDI_GetNextRandom(rng)
    ) - 0.5f;

    float jitterScale = max(ph_regir_sampling_jitter, 0.0f) * ph_regir_cell_size;
    vec3 samplingPos = shadingWorldPos + cellJitter * jitterScale;

    ivec3 cellCoord;
    if (!regir_world_to_cell(samplingPos, cellCoord)) {
        return false;
    }

    flatCellIndex = regir_flatten_cell(cellCoord);
    return true;
}


// RTXDI: RTXDI_SelectLocalLightReGIRRISTile -- creates a RISTileInfo from the cell and
// uses RTXDI_RandomlySelectLightDataFromRISTile, exactly matching the tile path.
// The ReGIR output buffer uses the same uvec2 format as the tile buffer so the
// unpack logic is identical.  Per-pixel code treats the cell's slots as a mini-tile.
// rnd: stratified random in [0,1) for slot selection (InitialSampling.hlsli:280 RTXDI_STRATIFY_LOCAL_SAMPLING).
// Caller computes: rnd = (rand_next_float() + float(i)) / float(numLocalSamples)
bool regir_pick_light(
    int flatCellIndex,
    float rnd,
    out int lightIndex,
    out float lightPdf,
    out bool hasCompact,
    out uint risBufferPtr
) {
    lightIndex = -1;
    lightPdf   = 0.0f;
    hasCompact = false;
    risBufferPtr = 0u;

    // RTXDI: RTXDI_RandomlySelectLightDataFromRISTile(rnd, tileInfo, tileData, risBufferPtr)
    // Pick uniformly from [0, lightsPerCell) using the caller-supplied stratified random.
    int cellSlot = clamp(int(floor(rnd * float(ph_regir_lights_per_cell))), 0, ph_regir_lights_per_cell - 1);

    float slotInvSourcePdf;
    if (!regir_unpack_slot(flatCellIndex, cellSlot, lightIndex, slotInvSourcePdf, hasCompact, risBufferPtr)) {
        lightIndex = -1;
        lightPdf   = 0.0f;
        hasCompact = false;
        risBufferPtr = 0u;
        return false;
    }

    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        lightIndex = -1;
        lightPdf   = 0.0f;
        return false;
    }

    // RTXDI carries invSourcePdf as-is without clamping; the reciprocal is taken later.
    lightPdf = 1.0f / slotInvSourcePdf;
    return true;
}

#endif
