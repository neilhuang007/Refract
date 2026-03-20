#ifndef PH_RESTIR_REGIR_INCLUDE
#define PH_RESTIR_REGIR_INCLUDE

// ReGIR output buffer — each cell has lightsPerCell fixed-position slots.
// Stored as uvec2 matching the RIS tile buffer format:
//   .x = lightIndex & RTXDI_LIGHT_INDEX_MASK  (bit 31 = RTXDI_LIGHT_COMPACT_BIT when set by build pass)
//   .y = floatBitsToUint(invSourcePdf / weight)
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
        int(floatBitsToUint(ld0.w)),
        ld0.xyz,
        ld1.xyz,
        ld1.w,
        ld2.xy,
        ld2.z,
        ld2.w,
        ld3.xyz,
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

// RTXDI: RTXDI_ReGIR_WorldPosToCellIndex — center-based origin derivation
bool regir_world_to_cell(vec3 shadingWorldPos, out ivec3 cellCoord) {
    vec3 gridOrigin = ph_regir_grid_center - vec3(ph_regir_grid_cells) * (ph_regir_cell_size * 0.5);
    vec3 relative   = shadingWorldPos - gridOrigin;
    cellCoord       = ivec3(floor(relative / ph_regir_cell_size));
    return all(greaterThanEqual(cellCoord, ivec3(0)))
        && all(lessThan(cellCoord, ph_regir_grid_cells));
}

int regir_flatten_cell(ivec3 cellCoord) {
    return cellCoord.x + ph_regir_grid_cells.x * (cellCoord.y + ph_regir_grid_cells.y * cellCoord.z);
}

// Unpack a ReGIR output slot — same format as a RIS tile entry.
// Returns false if the slot is invalid (lightIndex = sentinel or invSourcePdf = 0).
// outHasCompact: true when RTXDI_LIGHT_COMPACT_BIT is set — compact companion data is available
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
    // Sentinel for invalid: all INDEX_MASK bits set (== 0x7FFFFFFF)
    bool isSentinel = (slotData.x == RTXDI_LIGHT_INDEX_MASK);
    if (isSentinel || invSourcePdf <= 0.0) {
        lightIndex    = -1;
        invSourcePdf  = 0.0;
        outHasCompact = false;
        return false;
    }
    return true;
}

// RTXDI: RTXDI_CalculateReGIRCellIndex — determines which cell this pixel falls in.
// Returns true if inside the grid, with flatCellIndex set.
// Applies query-time jitter matching RTXDI_ReGIR_GetJitterScale (samplingJitter * cellSize).
bool regir_resolve_cell(vec3 shadingWorldPos, inout uint rng, out int flatCellIndex) {
    flatCellIndex = -1;

    // RTXDI: cellJitter = (rand3 - 0.5) * jitterScale
    // jitterScale = samplingJitter * cellSize (grid mode), samplingJitter = 1.0 default
    // Uses the passed coherentRng (not global rng_state) so neighboring pixels sharing the
    // same 8x8 block draw the same jitter, matching RTXDI_CalculateReGIRCellIndex(coherentRng).
    vec3 jitteredWorldPos = shadingWorldPos + (vec3(ph_RandomFloat01(rng), ph_RandomFloat01(rng), ph_RandomFloat01(rng)) - 0.5f) * ph_regir_sampling_jitter * ph_regir_cell_size;

    ivec3 cellCoord;
    if (!regir_world_to_cell(jitteredWorldPos, cellCoord)) {
        return false;
    }

    flatCellIndex = regir_flatten_cell(cellCoord);
    return true;
}

// RTXDI: RTXDI_SelectLocalLightReGIRRISTile — creates a RISTileInfo from the cell and
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
