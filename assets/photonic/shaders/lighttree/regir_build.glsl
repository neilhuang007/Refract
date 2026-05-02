#version 430

// RTXDI_PresampleLocalLightsForReGIR -- ReGIR grid build compute shader.
// Each thread populates one light slot in a grid cell via RIS, drawing
// candidates from the presampled RIS tile buffer (regir_presample_tiles.glsl).
//
// Reference: PresamplingFunctions.hlsli, PresampleReGIR.hlsl
//
// Key RTXDI design: a "coherent RNG" (shared seed across nearby threads)
// selects ONE tile per thread; all numRegirBuildSamples proposals then draw
// from that same tile.  This keeps nearby threads reading the same tile -> cache
// coherent.  A separate per-thread RNG picks the within-tile entry each
// iteration, giving independent samples.

// One thread per world-space hash-grid light slot, matching RTXDI's
// RTXDI_PresampleLocalLightsForReGIR dispatch shape. Each thread owns one
// (cellCoord, normalBucket, lightInCell) slot.
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

// Power CDF -- kept for potential fallback; not used in the tile-based path.
layout(std430, binding = 1) restrict readonly buffer ph_global_light_cdf {
    float ph_global_light_cdf_data[];
};

// RTXDI: RTXDI_RIS_BUFFER -- unified buffer for both presample tiles and ReGIR output.
// Presample tiles occupy [ph_ris_tile_buffer_offset, ph_ris_tile_buffer_offset + tileCount*tileSize).
// Hash-grid ReGIR slots occupy [ph_regir_ris_buffer_offset, ph_regir_ris_buffer_offset + hashTableSize*lightsPerCell).
// Must be restrict (not readonly/writeonly) since this pass reads tiles and writes ReGIR in different regions.
layout(std430, binding = 5) coherent restrict buffer ph_ris_buffer {
    uvec2 ph_ris_data[];
};

// RTXDI companion buffer: packed light data stored alongside each RIS entry.
// Each entry occupies 4 uvec4 (64 bytes), carrying the full 4xvec4 light record.
// Indexing: risBufferPtr * ph_compact_light_stride + [0..3].
layout(std430, binding = 6) restrict buffer ph_ris_compact_light_data {
    uvec4 ph_compact_light_data[];
};

const uint ph_compact_light_stride = 4u;

// Hash-grid auxiliary buffers (paper variant).
// - ph_regir_cell_checksum[slot]  : 0 = empty, otherwise xxhash32 of (cellCoord, bucket).
//                                    Atomically claimed via atomicCompSwap.
// - ph_regir_cell_key[slot]       : ivec4(cellCoord.x, .y, .z, normalBucket) -- written
//                                    after a successful claim, read by the lookup path
//                                    to verify against the queried key.
layout(std430, binding = 7) coherent restrict buffer ph_regir_cell_checksums {
    uint ph_regir_cell_checksum[];
};

layout(std430, binding = 8) coherent restrict buffer ph_regir_cell_keys {
    ivec4 ph_regir_cell_key[];
};

uniform sampler2D stage_radiosity_position;
uniform sampler2D stage_radiosity_mapped_normal;
uniform int ph_regir_geometry_build_enabled;

// ---------------------------------------------------------------------------
// RTXDI COMPACT_BIT / INDEX_MASK -- same constants as regir_presample_tiles.glsl
const uint RTXDI_LIGHT_COMPACT_BIT = 0x80000000u;
const uint RTXDI_LIGHT_INDEX_MASK  = 0x7FFFFFFFu;

struct RAB_LightInfo {
    int index;
    uint blockIdBits;
    vec3 position;
    vec3 color;
    float intensity;
    vec2 attenuation;
    float falloff;
    float blockRadius;
    vec3 emissionAxis;
    float orientationSpread;
};

RAB_LightInfo RAB_EmptyLightInfo() {
    return RAB_LightInfo(
        0,
        0u,
        vec3(0.0),
        vec3(0.0),
        0.0,
        vec2(0.0),
        0.0,
        0.0,
        vec3(0.0, 1.0, 0.0),
        0.0
    );
}

RAB_LightInfo RAB_LoadLightInfo(int lightIndex, bool previousFrame) {
    int base = lightIndex * light_size;
    vec4 ld0 = ph_lights_array[base + 0];
    vec4 ld1 = ph_lights_array[base + 1];
    vec4 ld2 = ph_lights_array[base + 2];
    vec4 ld3 = ph_lights_array[base + 3];
    return RAB_LightInfo(
        lightIndex,
        floatBitsToUint(ld0.w),
        ld0.xyz,
        ld1.xyz,
        ld1.w,
        ld2.xy,
        ld2.z,
        ld2.w,
        normalize(ld3.xyz + vec3(1e-6)),
        ld3.w
    );
}

bool RAB_StoreCompactLightInfo(uint risBufferPtr, RAB_LightInfo lightInfo) {
    uint dst = risBufferPtr * ph_compact_light_stride;
    ph_compact_light_data[dst + 0u] = floatBitsToUint(vec4(lightInfo.position, uintBitsToFloat(lightInfo.blockIdBits)));
    ph_compact_light_data[dst + 1u] = floatBitsToUint(vec4(lightInfo.color, lightInfo.intensity));
    ph_compact_light_data[dst + 2u] = floatBitsToUint(vec4(lightInfo.attenuation, lightInfo.falloff, lightInfo.blockRadius));
    ph_compact_light_data[dst + 3u] = floatBitsToUint(vec4(lightInfo.emissionAxis, lightInfo.orientationSpread));
    return true;
}

RAB_LightInfo RAB_LoadCompactLightInfo(uint risBufferPtr, int lightIndex) {
    uint src = risBufferPtr * ph_compact_light_stride;
    vec4 ld0 = uintBitsToFloat(ph_compact_light_data[src + 0u]);
    vec4 ld1 = uintBitsToFloat(ph_compact_light_data[src + 1u]);
    vec4 ld2 = uintBitsToFloat(ph_compact_light_data[src + 2u]);
    vec4 ld3 = uintBitsToFloat(ph_compact_light_data[src + 3u]);
    return RAB_LightInfo(
        lightIndex,
        floatBitsToUint(ld0.w),
        ld0.xyz,
        ld1.xyz,
        ld1.w,
        ld2.xy,
        ld2.z,
        ld2.w,
        normalize(ld3.xyz + vec3(1e-6)),
        ld3.w
    );
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
uniform uint  ph_regir_local_light_presampling_mode; // RTXDI: REGIR_LOCAL_LIGHT_PRESAMPLING_MODE_*

// Hash-grid uniforms (paper variant).
uniform int   ph_regir_hash_table_size;        // Number of slots in the hash table.
uniform float ph_regir_hash_cell_size;         // World units per cell side.
uniform int   ph_regir_hash_normal_buckets;    // Quantization buckets for surface normal.
uniform int   ph_regir_build_region_cells;     // Cells per side in the build cube around the camera.

const uint REGIR_LOCAL_LIGHT_PRESAMPLING_MODE_UNIFORM = 0u;
const uint REGIR_LOCAL_LIGHT_PRESAMPLING_MODE_POWER_RIS = 1u;

// ---------------------------------------------------------------------------
// RTXDI RNG -- exact port of RandomSamplerState.hlsli + Math.hlsli
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
// Hash-grid helpers (paper: PCG for slot, xxhash32 for verification checksum,
// 32-step linear probe). Deterministic in (cellCoord, normalBucket) so every
// thread that owns the same (cellCoord, bucket) walks the same probe sequence
// and ends up at the same slot.
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

// Quantize surface normal to one of the 6 axis-aligned buckets (+X,-X,+Y,-Y,+Z,-Z).
// Buckets are indexed: 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z.
int regir_normal_to_bucket(vec3 n) {
    vec3 a = abs(n);
    if (a.x >= a.y && a.x >= a.z) return n.x >= 0.0 ? 0 : 1;
    if (a.y >= a.z)               return n.y >= 0.0 ? 2 : 3;
    return                                 n.z >= 0.0 ? 4 : 5;
}

int regir_clamp_normal_bucket(int bucket) {
    return clamp(bucket, 0, max(ph_regir_hash_normal_buckets - 1, 0));
}

vec3 regir_bucket_to_normal(int bucket) {
    if (bucket == 0) return vec3( 1.0,  0.0,  0.0);
    if (bucket == 1) return vec3(-1.0,  0.0,  0.0);
    if (bucket == 2) return vec3( 0.0,  1.0,  0.0);
    if (bucket == 3) return vec3( 0.0, -1.0,  0.0);
    if (bucket == 4) return vec3( 0.0,  0.0,  1.0);
    return            vec3( 0.0,  0.0, -1.0);
}

struct RegirHashInsertResult {
    int slot;
    bool inserted;
};

RegirHashInsertResult regir_hash_result(int slot, bool inserted) {
    RegirHashInsertResult result;
    result.slot = slot;
    result.inserted = inserted;
    return result;
}

uint regir_atomic_load_checksum(uint slot) {
    return atomicOr(ph_regir_cell_checksum[slot], 0u);
}

uint regir_wait_for_claimed_slot(uint slot) {
    uint stored = regir_atomic_load_checksum(slot);
    for (int wait = 0; wait < 256 && stored == REGIR_HASH_CLAIMED; wait++) {
        memoryBarrierBuffer();
        stored = regir_atomic_load_checksum(slot);
    }
    return stored;
}

// Insert (cellCoord, bucket) into the hash table or find the existing slot.
// Returns the slot index and whether this invocation won the representative
// insertion. Only the winner may write reservoirs for the cell.
//
// Race-safety: the checksum uses a CLAIMED sentinel while the verification key
// is being written. Other invocations wait for the ready checksum before
// comparing the key, preventing duplicate slots for the same surface cell.
RegirHashInsertResult regir_hash_insert(ivec3 cellCoord, int bucket) {
    uint checksum = regir_hash_xxhash_checksum(cellCoord, bucket);
    uint slot = regir_hash_pcg_key(cellCoord, bucket) % uint(ph_regir_hash_table_size);
    ivec4 insertKey = ivec4(cellCoord, bucket);

    for (int probe = 0; probe < REGIR_HASH_MAX_PROBES; probe++) {
        uint existing = atomicCompSwap(ph_regir_cell_checksum[slot], 0u, REGIR_HASH_CLAIMED);
        if (existing == 0u) {
            ph_regir_cell_key[slot] = insertKey;
            memoryBarrierBuffer();
            atomicExchange(ph_regir_cell_checksum[slot], checksum);
            return regir_hash_result(int(slot), true);
        }

        uint stored = existing;
        if (stored == REGIR_HASH_CLAIMED) {
            stored = regir_wait_for_claimed_slot(slot);
            if (stored == REGIR_HASH_CLAIMED) {
                return regir_hash_result(-1, false);
            }
        }

        if (stored == checksum) {
            ivec4 storedKey = ph_regir_cell_key[slot];
            if (storedKey.x == insertKey.x && storedKey.y == insertKey.y
                && storedKey.z == insertKey.z && storedKey.w == insertKey.w) {
                return regir_hash_result(int(slot), false);
            }
        }
        slot = (slot + 1u) % uint(ph_regir_hash_table_size);
    }
    return regir_hash_result(-1, false);
}

bool regir_try_claim_output_slot(uint risBufferPtr) {
    if (ph_regir_geometry_build_enabled == 0) {
        return true;
    }

    uint existing = atomicCompSwap(ph_ris_data[risBufferPtr].y, 0u, REGIR_HASH_CLAIMED);
    return existing == 0u;
}

void regir_store_output_slot(uint risBufferPtr, uint packedLight, uint packedWeight) {
    if (ph_regir_geometry_build_enabled != 0) {
        ph_ris_data[risBufferPtr].x = packedLight;
        memoryBarrierBuffer();
        ph_ris_data[risBufferPtr].y = packedWeight;
    } else {
        ph_ris_data[risBufferPtr] = uvec2(packedLight, packedWeight);
    }
}

// Legacy helper kept so downstream code that still expects a "grid origin" compiles.
vec3 regir_grid_origin() {
    return ph_regir_grid_center - vec3(ph_regir_grid_cells) * (ph_regir_cell_size * 0.5);
}

// ---------------------------------------------------------------------------
// RTXDI_RandomlySelectRISTile -- picks ONE tile using the coherent RNG.
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
    // RTXDI: uint tileIndex = uint(tileRnd * params.tileCount)  -- no min() clamp
    uint tileIndex = uint(tileRnd * float(ph_ris_tile_count));
    RISTileInfo info;
    info.risTileOffset = ph_ris_tile_buffer_offset + tileIndex * uint(ph_ris_tile_size);
    info.risTileSize   = uint(ph_ris_tile_size);
    return info;
}

// ---------------------------------------------------------------------------
// RTXDI_RandomlySelectLightDataFromRISTile -- picks one entry from the tile.
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
    out uvec2 tileData,
    out uint outRisBufferPtr
) {
    uint risSample = min(uint(floor(rnd * float(tileInfo.risTileSize))), tileInfo.risTileSize - 1u);
    outRisBufferPtr = risSample + tileInfo.risTileOffset;
    tileData = ph_ris_data[outRisBufferPtr];
}

void RTXDI_UnpackLocalLightFromRISLightData(
    uvec2 tileData,
    uint risBufferPtr,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    lightInfo = RAB_EmptyLightInfo();
    lightIndex = tileData.x & RTXDI_LIGHT_INDEX_MASK;
    invSourcePdf = uintBitsToFloat(tileData.y);

    if (tileData.y == 0u
        || lightIndex >= uint(max(ph_light_count, 0))
        || !(invSourcePdf > 0.0)
        || isinf(invSourcePdf)
        || isnan(invSourcePdf)) {
        lightIndex = 0u;
        invSourcePdf = 0.0;
        return;
    }

    if ((tileData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u) {
        lightInfo = RAB_LoadCompactLightInfo(risBufferPtr, int(lightIndex));
    } else {
        lightInfo = RAB_LoadLightInfo(int(lightIndex), false);
    }
}

void RTXDI_SelectNextLocalLight(
    RISTileInfo risTileInfo,
    float rnd,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    uvec2 risTileData;
    uint risBufferPtr;
    RTXDI_RandomlySelectLightDataFromRISTile(rnd, risTileInfo, risTileData, risBufferPtr);
    RTXDI_UnpackLocalLightFromRISLightData(risTileData, risBufferPtr, lightInfo, lightIndex, invSourcePdf);
}

void RTXDI_RandomlySelectLightUniformly(
    float rnd,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    invSourcePdf = float(ph_light_count);
    lightIndex = min(uint(floor(rnd * float(ph_light_count))), uint(ph_light_count - 1));
    lightInfo = RAB_LoadLightInfo(int(lightIndex), false);
}

// ---------------------------------------------------------------------------
// RAB_GetLightTargetPdfForCell -- hash-grid target function (paper variant).
//
// p_hat_C(x) = Le(x) / |P_c - x|^2
//
// where:
//   Le(x)         := luminance(light_color * intensity / attenuation(distance))
//                    -- the existing attenuation model already folds in 1/(1+d^2*falloff)
//                    so the explicit /r^2 from the paper is captured by attenuation.
//
// Keep the grid-fill target conservative: directional cosine terms are evaluated
// later against the actual shading point. Using a bucket normal and cell-center
// representative here makes hard per-cell decisions at light/geometry edges.
// For shaped lights, reject only cells whose conservative volume cannot intersect
// the light's non-zero emission cone, matching RTXDI's volume-weight support test.
// ---------------------------------------------------------------------------
bool regir_sphere_intersects_cone(vec3 coneVertex, vec3 coneAxis, float coneHalfAngle, vec3 sphereCenter, float sphereRadius) {
    if (coneHalfAngle >= 3.14159265) return true;

    vec3 vertexToSphere = sphereCenter - coneVertex;
    float distanceToSphere = length(vertexToSphere);
    if (distanceToSphere <= sphereRadius) return true;
    if (!(distanceToSphere > 1.0e-6)) return true;

    float invDistance = 1.0 / distanceToSphere;
    float axisAngle = acos(clamp(dot(vertexToSphere, coneAxis) * invDistance, -1.0, 1.0));
    float sphereHalfAngle = asin(clamp(sphereRadius * invDistance, 0.0, 1.0));
    return axisAngle <= sphereHalfAngle + coneHalfAngle;
}

vec3 regir_cone_vertex_for_spherical_source(vec3 sphereCenter, float sphereRadius, vec3 coneAxis, float coneHalfAngle) {
    float sinHalfAngle = sin(min(coneHalfAngle, 1.57079633));
    float offset = max(sphereRadius, 0.0) / max(sinHalfAngle, 1.0e-5);
    return sphereCenter - coneAxis * offset;
}

bool regir_cell_intersects_shaped_light(RAB_LightInfo lightInfo, vec3 cellCenter, float cellRadius) {
    if (lightInfo.orientationSpread >= 3.14159265) return true;

    vec3 axis = normalize(lightInfo.emissionAxis + vec3(1.0e-6));

    // Photonics' runtime radiance stays non-zero until axisAngle reaches
    // orientationSpread + pi/2. Use that non-zero cone as RTXDI's shaping cone.
    float coneHalfAngle = clamp(lightInfo.orientationSpread + 1.57079633, 0.0, 3.14159265);
    vec3 coneVertex = regir_cone_vertex_for_spherical_source(
        lightInfo.position,
        lightInfo.blockRadius,
        axis,
        coneHalfAngle);
    return regir_sphere_intersects_cone(coneVertex, axis, coneHalfAngle, cellCenter, cellRadius);
}

float RAB_GetLightTargetPdfForCell(RAB_LightInfo lightInfo, vec3 cellCenter, vec3 receiverNormal, float cellRadius) {
    if (!regir_cell_intersects_shaped_light(lightInfo, cellCenter, cellRadius)) {
        return 0.0;
    }

    vec3  delta = cellCenter - lightInfo.position;
    float dist  = length(delta);

    // regirAverageDistanceToVolume -- nonlinear approximation. Kept from the
    // volumetric variant because cellRadius>0 still matters: the cell is a
    // 3D box and approximating distance by "to-center" overestimates closeness.
    float nonlinearFactor = 1.1547;
    float radiusSq        = cellRadius * cellRadius;
    float denom           = dist + cellRadius * nonlinearFactor;
    float averageDistance  = dist + cellRadius * radiusSq / max(denom * denom, 1e-4);
    float averageDistSq   = averageDistance * averageDistance;

    // Le * 1/r^2 captured by the attenuation model.
    float attenuationDenom = dot(vec2(1.0, averageDistSq * lightInfo.falloff), lightInfo.attenuation);
    attenuationDenom = max(attenuationDenom, 1e-4);
    vec3  attenuatedColor = lightInfo.color * lightInfo.intensity / attenuationDenom;
    float luminance = max(dot(attenuatedColor, vec3(0.2126, 0.7152, 0.0722)), 0.0);
    if (luminance <= 0.0) return 0.0;

    return luminance;
}

// Backward-compat shim: legacy callers asked for a volumetric (no-normal) target.
// We keep it but degrade gracefully: equivalent to using the +Y bucket, i.e.
// a "neutral" upward-facing surface.
float RAB_GetLightTargetPdfForVolume(RAB_LightInfo lightInfo, vec3 cellCenter, float cellRadius) {
    return RAB_GetLightTargetPdfForCell(lightInfo, cellCenter, vec3(0.0, 1.0, 0.0), cellRadius);
}

ivec3 regir_build_region_min_cell() {
    int buildRegionCells = max(ph_regir_build_region_cells, 1);
    int halfRegionCells = buildRegionCells / 2;
    ivec3 centerCell = ivec3(floor(ph_regir_grid_center / ph_regir_hash_cell_size));
    return centerCell - ivec3(halfRegionCells);
}

bool regir_cell_in_build_region(ivec3 cellCoord) {
    int buildRegionCells = max(ph_regir_build_region_cells, 1);
    ivec3 minCell = regir_build_region_min_cell();
    ivec3 maxCell = minCell + ivec3(buildRegionCells);
    return all(greaterThanEqual(cellCoord, minCell)) && all(lessThan(cellCoord, maxCell));
}

// ---------------------------------------------------------------------------
// Hash-grid ReGIR build (paper variant).
// The default path builds the full camera-centered hash window so lookup jitter
// cannot request cells that were missing from the current screen. Geometry mode
// is retained as an opt-in diagnostic path and claims each output slot once so
// duplicate stage pixels for the same (cellCoord, normalBucket) key cannot race.
// ---------------------------------------------------------------------------
void main() {
    if (ph_regir_hash_table_size <= 0
        || ph_regir_lights_per_cell <= 0
        || ph_light_count <= 0
        || ph_regir_hash_cell_size <= 0.0
        || ph_regir_build_region_cells <= 0
        || ph_regir_hash_normal_buckets <= 0) {
        return;
    }

    uint lightsPerCell = uint(ph_regir_lights_per_cell);
    uint threadId = gl_GlobalInvocationID.x;
    uint lightInCell;
    ivec3 cellCoord;
    int bucket;
    uint rngThreadId = threadId;

    if (ph_regir_geometry_build_enabled != 0) {
        ivec2 geometrySize = textureSize(stage_radiosity_position, 0);
        if (geometrySize.x <= 0 || geometrySize.y <= 0) return;

        uint pixelCount = uint(geometrySize.x) * uint(geometrySize.y);
        uint totalThreads = pixelCount * lightsPerCell;
        if (threadId >= totalThreads) return;

        lightInCell = threadId % lightsPerCell;
        uint pixelIndex = threadId / lightsPerCell;
        ivec2 pixel = ivec2(int(pixelIndex % uint(geometrySize.x)), int(pixelIndex / uint(geometrySize.x)));

        vec4 positionData = texelFetch(stage_radiosity_position, pixel, 0);
        if (!(positionData.w > 0.0) || any(isnan(positionData.xyz)) || any(isinf(positionData.xyz))) {
            return;
        }

        vec3 surfaceNormal = texelFetch(stage_radiosity_mapped_normal, pixel, 0).xyz;
        float normalLengthSq = dot(surfaceNormal, surfaceNormal);
        if (!(normalLengthSq > 1.0e-8) || any(isnan(surfaceNormal)) || any(isinf(surfaceNormal))) {
            return;
        }

        cellCoord = ivec3(floor(positionData.xyz / ph_regir_hash_cell_size));
        if (!regir_cell_in_build_region(cellCoord)) return;
        bucket = regir_normal_to_bucket(normalize(surfaceNormal));

        rngThreadId = (regir_hash_pcg_key(cellCoord, bucket) ^ regir_hash_xxhash_checksum(cellCoord, bucket))
            * lightsPerCell + lightInCell;
    } else {
        int buildRegionCells = max(ph_regir_build_region_cells, 1);
        int bucketCount = max(ph_regir_hash_normal_buckets, 1);
        uint cellsPerSide = uint(buildRegionCells);
        uint worldCellCount = cellsPerSide * cellsPerSide * cellsPerSide;
        uint totalThreads = worldCellCount * uint(bucketCount) * lightsPerCell;
        if (threadId >= totalThreads) return;

        lightInCell = threadId % lightsPerCell;
        uint cellKeyIndex = threadId / lightsPerCell;

        uint cellLinearIndex = cellKeyIndex / uint(bucketCount);
        bucket = regir_clamp_normal_bucket(int(cellKeyIndex - cellLinearIndex * uint(bucketCount)));
        ivec3 localCell = ivec3(
            int(cellLinearIndex % cellsPerSide),
            int((cellLinearIndex / cellsPerSide) % cellsPerSide),
            int(cellLinearIndex / (cellsPerSide * cellsPerSide))
        );
        cellCoord = regir_build_region_min_cell() + localCell;
    }

    vec3 representativePos = (vec3(cellCoord) + vec3(0.5)) * ph_regir_hash_cell_size;
    vec3 representativeNormal = regir_bucket_to_normal(bucket);

    RegirHashInsertResult insert = regir_hash_insert(cellCoord, bucket);
    if (insert.slot < 0) return;
    int slot = insert.slot;

    uint risBufferPtr = ph_regir_ris_buffer_offset
                      + uint(slot) * lightsPerCell
                      + lightInCell;

    if (!regir_try_claim_output_slot(risBufferPtr)) return;

    // If build samples is zero, mark this slot empty and bail.
    if (ph_regir_build_samples == 0u) {
        regir_store_output_slot(risBufferPtr, 0u, 0u);
        return;
    }

    // RTXDI ReGIR uses the full cell diagonal as the conservative volume radius,
    // then expands it by sampling jitter. Using a half diagonal clips shaped and
    // near lights at cell edges.
    float cellRadius = ph_regir_hash_cell_size * sqrt(3.0)
        * (max(ph_regir_sampling_jitter, 0.0) + 1.0);

    bool usePowerRisPresampling = ph_regir_local_light_presampling_mode == REGIR_LOCAL_LIGHT_PRESAMPLING_MODE_POWER_RIS;

    uint numBuildSamples = ph_regir_build_samples;
    float invNumSamples = 1.0 / float(numBuildSamples);

    // Match RTXDI PresampleReGIR.hlsl RNGs:
    // rng         = RTXDI_InitRandomSampler(uint2(GlobalIndex & 0xfff, GlobalIndex >> 12), frameIndex, 1)
    // coherentRng = RTXDI_InitRandomSampler(uint2(GlobalIndex >> 8, 0), frameIndex, 1)
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(rngThreadId & 0xfffu, rngThreadId >> 12),
        ph_ris_frame_index,
        1u
    );
    RTXDI_RandomSamplerState coherentRng = RTXDI_InitRandomSampler(
        uvec2(rngThreadId >> 8, 0u),
        ph_ris_frame_index,
        1u
    );

    RISTileInfo risTileInfo;
    if (usePowerRisPresampling) {
        risTileInfo = RTXDI_RandomlySelectRISTile(coherentRng);
    }

    RAB_LightInfo selectedLightInfo = RAB_EmptyLightInfo();
    uint  selectedLight = 0u;
    float selectedTargetPdf = 0.0;
    float weightSum = 0.0;

    for (uint i = 0u; i < numBuildSamples; i++) {
        float rand = RTXDI_GetNextRandom(rng);

        uint rndLight;
        RAB_LightInfo lightInfo = RAB_EmptyLightInfo();
        float invSourcePdf;
        if (usePowerRisPresampling) {
            RTXDI_SelectNextLocalLight(risTileInfo, rand, lightInfo, rndLight, invSourcePdf);
            if (rndLight >= uint(max(ph_light_count, 0))
                || !(invSourcePdf > 0.0)
                || isinf(invSourcePdf)
                || isnan(invSourcePdf)) {
                RTXDI_RandomlySelectLightUniformly(rand, lightInfo, rndLight, invSourcePdf);
            }
        } else {
            RTXDI_RandomlySelectLightUniformly(rand, lightInfo, rndLight, invSourcePdf);
        }

        if (rndLight >= uint(max(ph_light_count, 0))
            || !(invSourcePdf > 0.0)
            || isinf(invSourcePdf)
            || isnan(invSourcePdf)) {
            continue;
        }

        invSourcePdf *= invNumSamples;

        float targetPdf = RAB_GetLightTargetPdfForCell(
            lightInfo,
            representativePos,
            representativeNormal,
            cellRadius);

        float risRnd = RTXDI_GetNextRandom(rng);
        float risWeight = targetPdf * invSourcePdf;
        weightSum += risWeight;

        if (risRnd * weightSum < risWeight) {
            selectedLightInfo = lightInfo;
            selectedLight     = rndLight;
            selectedTargetPdf = targetPdf;
        }
    }

    float weight = (selectedTargetPdf > 0.0)
        ? (weightSum / selectedTargetPdf)
        : 0.0;

    if (weight > 0.0) {
        // Keep ReGIR slots lean: the sampled path can reload the selected light
        // by index, while compact payloads stay reserved for Power RIS tiles.
        selectedLight &= RTXDI_LIGHT_INDEX_MASK;
    }
    regir_store_output_slot(risBufferPtr, selectedLight, floatBitsToUint(weight));
}
