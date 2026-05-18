#ifndef PH_RESTIR_REGIR_INCLUDE
#define PH_RESTIR_REGIR_INCLUDE

// ReGIR output buffer -- each cell has lightsPerCell fixed-position slots.
// Stored as uvec2 matching the RIS tile buffer format:
//   .x = lightIndex & RTXDI_LIGHT_INDEX_MASK  (ReGIR leaves RTXDI_LIGHT_COMPACT_BIT clear)
//   .y = floatBitsToUint(weight), which the selection path reuses as the slot's invSourcePdf
//        exactly like RTXDI's ReGIR RIS mini-tile readback.
// Invalid entries: .x = RTXDI_LIGHT_INDEX_MASK (all lower bits set), .y = 0.
// Per-pixel code reads this exactly like a tile entry (same unpack path).

// RTXDI COMPACT_BIT / INDEX_MASK
const uint RTXDI_LIGHT_COMPACT_BIT = 0x80000000u;
const uint RTXDI_LIGHT_INDEX_MASK  = 0x7FFFFFFFu;

#ifndef PH_LIGHTTREE_OMIT_REGIR_BUFFERS
layout(std430, binding = 5) restrict buffer ph_ris_buffer {
    uvec2 ph_ris_data[];
};

// Shared compact-light decoder for RIS entries produced by either presample tiles or ReGIR.
// Each compact entry occupies 4 uvec4 (64 bytes), carrying the full 4xvec4 light record.
// Indexing: risBufferPtr * ph_compact_light_stride + [0..3].
layout(std430, binding = 6) restrict readonly buffer ph_ris_compact_light_data {
    uvec4 ph_compact_light_data[];
};
#else
// Stubs: passes that don't sample ReGIR/RIS (e.g. temporal resampling) skip the
// SSBO bindings. Consumer helpers (load_compact_light, regir_unpack_slot, etc.)
// remain compilable but are unreachable from the gated entry point.
const uvec2 ph_ris_data[1] = uvec2[1](uvec2(0u));
const uvec4 ph_compact_light_data[1] = uvec4[1](uvec4(0u));
#endif

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

// ph_regir_grid_center: world-space center of the ReGIR build region.
// In the hash-grid variant, lookups hash the actual surface position.
uniform vec3  ph_regir_grid_center;
uniform ivec3 ph_regir_grid_cells;             // legacy uniform retained for diagnostic shaders
uniform int   ph_regir_lights_per_cell;
uniform float ph_regir_cell_size;              // legacy 32-block cell size (used by some debug paths)
uniform float ph_regir_sampling_jitter;
uniform int   ph_regir_ris_buffer_offset;      // offset into unified RIS buffer where the ReGIR region starts
uniform int   ph_regir_local_light_sampling_fallback_mode;
// Hash-grid uniforms (paper variant).
uniform int   ph_regir_hash_table_size;        // number of slots in the hash table
uniform float ph_regir_hash_cell_size;         // world units per hash cell side
uniform int   ph_regir_hash_normal_buckets;    // currently 6 (axis-aligned)
uniform int   ph_regir_build_region_cells;     // build cube side (cells)

// Hash-grid auxiliary buffers (read-only at lookup time; written by regir_build.glsl).
#ifndef PH_LIGHTTREE_OMIT_REGIR_BUFFERS
layout(std430, binding = 7) restrict readonly buffer ph_regir_cell_checksums {
    uint ph_regir_cell_checksum[];
};

layout(std430, binding = 8) restrict readonly buffer ph_regir_cell_keys {
    ivec4 ph_regir_cell_key[];
};
#else
// Stubs: regir_hash_lookup is unreachable from the gated entry point.
const uint ph_regir_cell_checksum[1] = uint[1](0u);
const ivec4 ph_regir_cell_key[1] = ivec4[1](ivec4(0));
#endif

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

// 16x16 tile-coherent jitter, matching RTXDI: all pixels in a tile share the
// same cell-jitter offset so ReGIR lookups inside the tile resolve to the same
// jittered cell. Tile size is RTXDI_TILE_SIZE_IN_PIXELS = 16 (>> 4).
RTXDI_RandomSamplerState RTXDI_InitReGIRLookupRandomSampler(uvec2 pixelPos, uint frameIndex) {
    return RTXDI_InitRandomSampler(
        uvec2(pixelPos >> 4u),
        frameIndex,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
    );
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

// Legacy origin helper kept for diagnostic shaders that still expect a "grid origin"
// (e.g. coverage debug views). Not used by the hash-grid lookup path.
vec3 regir_grid_origin() {
    return ph_regir_grid_center - vec3(ph_regir_grid_cells) * (ph_regir_cell_size * 0.5);
}

// ---------------------------------------------------------------------------
// Hash-grid helpers (paper variant). Mirrored from regir_build.glsl so both
// build and lookup walk the exact same hash + probe sequence for a given
// (cellCoord, bucket). KEEP IN SYNC.
// ---------------------------------------------------------------------------

uint regir_pcg_step(uint h) {
    h = h * 747796405u + 2891336453u;
    h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
    return (h >> 22u) ^ h;
}

uint regir_xxhash_step(uint h) {
    const uint PRIME32_2 = 2246822519u;
    const uint PRIME32_3 = 3266489917u;
    const uint PRIME32_4 = 668265263u;
    const uint PRIME32_5 = 374761393u;

    uint h32 = h + PRIME32_5;
    h32 = PRIME32_4 * ((h32 << 17u) | (h32 >> 15u));
    h32 = PRIME32_2 * (h32 ^ (h32 >> 15u));
    h32 = PRIME32_3 * (h32 ^ (h32 >> 13u));
    return h32 ^ (h32 >> 16u);
}

uint regir_hash_pcg_key(ivec3 cellCoord, int bucket) {
    return regir_pcg_step(uint(bucket) + regir_pcg_step(uint(cellCoord.z)
        + regir_pcg_step(uint(cellCoord.y) + regir_pcg_step(uint(cellCoord.x)))));
}

const uint REGIR_HASH_CLAIMED = 0xffffffffu;
const int REGIR_HASH_MAX_PROBES = 128;

uint regir_hash_xxhash_checksum(ivec3 cellCoord, int bucket) {
    uint h = regir_xxhash_step(uint(bucket) + regir_xxhash_step(uint(cellCoord.z)
        + regir_xxhash_step(uint(cellCoord.y) + regir_xxhash_step(uint(cellCoord.x)))));
    // Reserve 0 for empty and 0xffffffff for an in-progress claim.
    if (h == 0u) return 1u;
    if (h == REGIR_HASH_CLAIMED) return 0xfffffffeu;
    return h;
}

// Quantize surface normal to one of 6 axis-aligned buckets (+X,-X,+Y,-Y,+Z,-Z).
int regir_normal_to_bucket(vec3 n) {
    vec3 a = abs(n);
    if (a.x >= a.y && a.x >= a.z) return n.x >= 0.0 ? 0 : 1;
    if (a.y >= a.z)               return n.y >= 0.0 ? 2 : 3;
    return                                 n.z >= 0.0 ? 4 : 5;
}

int regir_clamp_normal_bucket(int bucket) {
    return clamp(bucket, 0, max(ph_regir_hash_normal_buckets - 1, 0));
}

// Hash lookup with bounded linear probing. Returns the slot containing the
// matching (cellCoord, bucket) key, or -1 if the cell wasn't built this frame.
int regir_hash_lookup(ivec3 cellCoord, int bucket) {
    if (ph_regir_hash_table_size <= 0 || ph_regir_hash_cell_size <= 0.0) {
        return -1;
    }

    bucket = regir_clamp_normal_bucket(bucket);
    uint checksum = regir_hash_xxhash_checksum(cellCoord, bucket);
    uint slot = regir_hash_pcg_key(cellCoord, bucket) % uint(ph_regir_hash_table_size);

    for (int probe = 0; probe < REGIR_HASH_MAX_PROBES; probe++) {
        uint stored = ph_regir_cell_checksum[slot];
        if (stored == 0u) return -1;        // empty -> cell missed; lookup fails fast
        if (stored == REGIR_HASH_CLAIMED) return -1;
        if (stored == checksum) {
            ivec4 key = ph_regir_cell_key[slot];
            if (key.x == cellCoord.x && key.y == cellCoord.y && key.z == cellCoord.z && key.w == bucket) {
                return int(slot);
            }
        }
        slot = (slot + 1u) % uint(ph_regir_hash_table_size);
    }
    return -1;
}

// RTXDI_CalculateReGIRCellIndex jitters the world-space lookup independently
// on each axis: (rand3 - 0.5) * samplingJitter * cellSize. Using the same
// support here keeps lookup jitter consistent with the build-time cell radius.
vec3 regir_jitter_world_cube(vec3 worldPos, float jitterScale, inout RTXDI_RandomSamplerState rng) {
    vec3 cellJitter = vec3(
        RTXDI_GetNextRandom(rng),
        RTXDI_GetNextRandom(rng),
        RTXDI_GetNextRandom(rng)
    ) - vec3(0.5);
    return worldPos + cellJitter * jitterScale;
}

// Unpack a ReGIR output slot. Slot is a hash-table slot index (NOT a linear cell
// index). The buffer offset within ph_ris_data is `regirRisOffset + slot*lightsPerCell + cellSlot`.
bool regir_unpack_slot(int hashSlot, int cellSlot,
    out int lightIndex, out float invSourcePdf,
    out bool outHasCompact, out uint outRisBufferPtr) {
    lightIndex = -1;
    invSourcePdf = 0.0f;
    outHasCompact = false;
    outRisBufferPtr = 0u;

    if (hashSlot < 0 || cellSlot < 0 || cellSlot >= ph_regir_lights_per_cell) {
        return false;
    }

    int  bufferIndex   = hashSlot * ph_regir_lights_per_cell + cellSlot;
    outRisBufferPtr    = uint(ph_regir_ris_buffer_offset) + uint(bufferIndex);
    uvec2 slotData     = ph_ris_data[outRisBufferPtr];
    if (slotData.y == 0u) {
        return false;
    }

    outHasCompact      = (slotData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u;
    lightIndex         = int(slotData.x & RTXDI_LIGHT_INDEX_MASK);
    invSourcePdf       = uintBitsToFloat(slotData.y);

    if (lightIndex < 0 || lightIndex >= ph_light_count
        || !(invSourcePdf > 0.0f)
        || isinf(invSourcePdf)
        || isnan(invSourcePdf)) {
        lightIndex = -1;
        invSourcePdf = 0.0f;
        outHasCompact = false;
        outRisBufferPtr = 0u;
        return false;
    }

    return true;
}

// Resolve the hash slot to query for (worldPos, normal). Returns true if the
// cell was built this frame and the caller can RIS over its lightsPerCell slots.
// On miss, the caller must fall back to POWER_RIS or uniform sampling.
//
// `flatCellIndex` (out) is the hash-table slot, kept as `int` for source-compat
// with existing call sites that called the old volumetric variant.
bool regir_resolve_cell(vec3 shadingWorldPos, vec3 shadingNormal, inout RTXDI_RandomSamplerState rng, out int flatCellIndex) {
    flatCellIndex = -1;

    float normalLengthSq = dot(shadingNormal, shadingNormal);
    if (!(normalLengthSq > 1.0e-8) || any(isnan(shadingNormal)) || any(isinf(shadingNormal))) {
        return false;
    }
    vec3 queryNormal = normalize(shadingNormal);

    // The cell binding is world-space: the RNG only jitters the world position
    // before lookup. Final ReGIR sampling passes Photonics' per-pixel lookup RNG
    // here; Power RIS fallback keeps using the tile-coherent RTXDI stream.
    float jitterScale = max(ph_regir_hash_cell_size * ph_regir_sampling_jitter, 0.0);
    vec3 jitteredPos = (jitterScale > 0.0)
        ? regir_jitter_world_cube(shadingWorldPos, jitterScale, rng)
        : shadingWorldPos;

    ivec3 cellCoord = ivec3(floor(jitteredPos / ph_regir_hash_cell_size));
    int   bucket    = regir_normal_to_bucket(queryNormal);

    int slot = regir_hash_lookup(cellCoord, bucket);
    if (slot < 0) return false;
    flatCellIndex = slot;
    return true;
}

// Stratified slot pick within a hash cell. Same shape as the volumetric variant.
bool regir_pick_light(
    int hashSlot,
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

    int cellSlot = min(int(floor(rnd * float(ph_regir_lights_per_cell))), ph_regir_lights_per_cell - 1);

    float slotInvSourcePdf;
    if (!regir_unpack_slot(hashSlot, cellSlot, lightIndex, slotInvSourcePdf, hasCompact, risBufferPtr)) {
        return false;
    }

    lightPdf = 1.0f / slotInvSourcePdf;
    return true;
}

// Cell occupancy probe. Returns true if at least one slot in the resolved cell
// holds a non-empty proposal. Empty slots (slotData.y == 0) are produced by
// regir_build.glsl when its RIS proposals all evaluate to zero target pdf for
// the cell volume (RAB_GetLightTargetPdfForVolume == 0 for every candidate light
// considered). When every slot is empty, the lookup-time RIS draws from the same
// pool the build sampled and would itself produce only zero-weight candidates,
// so the candidate-generation pipeline at any surface inside this cell collapses
// to an empty reservoir.
bool regir_cell_has_any_light(int hashSlot) {
    if (hashSlot < 0 || ph_regir_lights_per_cell <= 0) {
        return false;
    }
    uint baseIndex = uint(ph_regir_ris_buffer_offset)
                   + uint(hashSlot) * uint(ph_regir_lights_per_cell);
    for (int slot = 0; slot < ph_regir_lights_per_cell; slot++) {
        if (ph_ris_data[baseIndex + uint(slot)].y != 0u) {
            return true;
        }
    }
    return false;
}

#endif
