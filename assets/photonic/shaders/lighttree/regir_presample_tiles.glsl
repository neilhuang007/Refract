#version 430

// RTXDI_PresampleLocalLights — presample tiles compute shader.
// Reference: PresamplingFunctions.hlsli:31-134, PresampleLights.hlsl
// Uses 2D PDF mipmap texture traversal (RTXDI_SamplePdfMipmap) instead of 1D CDF binary search.

// RTXDI presample dispatch: 2D groups — x = sampleInTile, y = tileIndex.
// glDispatchCompute(tileSize/GROUP_SIZE, tileCount, 1)
layout(local_size_x = 256, local_size_y = 1) in;

// ---------------------------------------------------------------------------
// SSBOs
// ---------------------------------------------------------------------------
layout(std430, binding = 5) restrict buffer ph_ris_buffer {
    uvec2 ph_ris_data[];
};

// RTXDI companion buffer: packed light data stored alongside each RIS entry.
// Each entry occupies 4 uvec4 (64 bytes), matching the shared Photonics compact-light contract.
// Indexing: risBufferPtr * ph_compact_light_stride + [0..3].
layout(std430, binding = 6) restrict buffer ph_ris_compact_light_data {
    uvec4 ph_compact_light_data[];
};

const uint ph_compact_light_stride = 4u;

// Light list — needed to read light data for compact storage.
// vec4[0]: position.xyz, blockId(w)
// vec4[1]: color.xyz, intensity(w)
// vec4[2]: attenuation.xy, falloff(z), block_radius(w)
// vec4[3]: emissionAxis.xyz, orientationSpread(w)
layout(std140, binding = 0) restrict readonly buffer ph_light_list_presample {
    vec4 ph_lights_array_presample[];
};

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform int   ph_light_count;
uniform int   ph_ris_tile_size;
uniform int   ph_ris_tile_count;
uniform uint  ph_ris_frame_index;    // RTXDI: g_Const.runtimeParams.frameIndex (raw frame count)
uniform uint  ph_ris_tile_buffer_offset;

// PDF mipmap texture (2D R32F, mip 0 = per-light flux at Z-curve positions)
uniform sampler2D u_LocalLightPdfTexture;
uniform ivec2     ph_pdf_texture_size;

// ---------------------------------------------------------------------------
// RTXDI RNG — exact port of RandomSamplerState.hlsli + Math.hlsli
// ---------------------------------------------------------------------------

// RTXDI_IntegerExplode: inserts a 0 between each bit (16-bit input → 32-bit output)
uint RTXDI_IntegerExplode(uint x) {
    x = (x | (x << 8u)) & 0x00FF00FFu;
    x = (x | (x << 4u)) & 0x0F0F0F0Fu;
    x = (x | (x << 2u)) & 0x33333333u;
    x = (x | (x << 1u)) & 0x55555555u;
    return x;
}

// RTXDI_ZCurveToLinearIndex: 2D→1D Morton/Z-curve interleave
uint RTXDI_ZCurveToLinearIndex(uvec2 xy) {
    return RTXDI_IntegerExplode(xy.x) | (RTXDI_IntegerExplode(xy.y) << 1u);
}

// RTXDI_JenkinsHash: 32-bit Jenkins one-at-a-time hash
uint RTXDI_JenkinsHash(uint a) {
    a = (a + 0x7ed55d16u) + (a << 12u);
    a = (a ^ 0xc761c23cu) ^ (a >> 19u);
    a = (a + 0x165667b1u) + (a << 5u);
    a = (a + 0xd3a2646cu) ^ (a << 9u);
    a = (a + 0xfd7046c5u) + (a << 3u);
    a = (a ^ 0xb55a4f09u) ^ (a >> 16u);
    return a;
}

// RTXDI_RandomSamplerState
struct RTXDI_RandomSamplerState {
    uint seed;
    uint index;
};

// RTXDI_RANDAOM_SAMPLER_PRIME_CONSTANT (yes, RTXDI has the typo)
const uint RTXDI_RANDOM_SAMPLER_PRIME_CONSTANT = 31u;

// RTXDI_InitRandomSampler
RTXDI_RandomSamplerState RTXDI_InitRandomSampler(uvec2 pixelPos, uint frameIndex, uint pass) {
    RTXDI_RandomSamplerState state;
    uint linearPixelIndex = RTXDI_ZCurveToLinearIndex(pixelPos);
    state.index = 1u;
    state.seed = RTXDI_JenkinsHash(linearPixelIndex) + frameIndex + (pass * RTXDI_RANDOM_SAMPLER_PRIME_CONSTANT);
    return state;
}

// RTXDI_murmur3
uint RTXDI_murmur3(inout RTXDI_RandomSamplerState r) {
    uint c1 = 0xcc9e2d51u;
    uint c2 = 0x1b873593u;

    uint hash = r.seed;
    uint k = r.index++;
    k *= c1;
    k = (k << 15u) | (k >> 17u); // ROT32(k, 15)
    k *= c2;

    hash ^= k;
    hash = (hash << 13u) | (hash >> 19u); // ROT32(hash, 13)
    hash = hash * 5u + 0xe6546b64u;

    hash ^= 4u;
    hash ^= (hash >> 16u);
    hash *= 0x85ebca6bu;
    hash ^= (hash >> 13u);
    hash *= 0xc2b2ae35u;
    hash ^= (hash >> 16u);

    return hash;
}

// RTXDI_GetNextRandom — returns [0, 1)
float RTXDI_GetNextRandom(inout RTXDI_RandomSamplerState rng) {
    uint v = RTXDI_murmur3(rng);
    const uint one = 0x3f800000u; // asuint(1.0f)
    const uint mask = (1u << 23u) - 1u;
    return uintBitsToFloat((mask & v) | one) - 1.0;
}

// ---------------------------------------------------------------------------
// RTXDI_SamplePdfMipmap — exact port of PresamplingFunctions.hlsli:31-95
// Traverses from the coarsest mip down to mip 0, picking 1 of 4 children
// at each level proportional to their weight.
// Child sampling order: (0,0), (0,1), (1,0), (1,1) — y increments before x.
// ---------------------------------------------------------------------------
void RTXDI_SamplePdfMipmap(
    inout RTXDI_RandomSamplerState rng,
    sampler2D pdfTexture,
    ivec2 pdfTextureSize,
    out uvec2 position,
    out float pdf
) {
    int lastMipLevel = max(0, int(floor(log2(float(max(pdfTextureSize.x, pdfTextureSize.y))))) - 1);

    position = uvec2(0u, 0u);
    pdf = 1.0;

    for (int mipLevel = lastMipLevel; mipLevel >= 0; mipLevel--) {
        position *= 2u;

        vec4 samples;
        samples.x = max(0.0, texelFetch(pdfTexture, ivec2(position.x + 0u, position.y + 0u), mipLevel).x);
        samples.y = max(0.0, texelFetch(pdfTexture, ivec2(position.x + 0u, position.y + 1u), mipLevel).x);
        samples.z = max(0.0, texelFetch(pdfTexture, ivec2(position.x + 1u, position.y + 0u), mipLevel).x);
        samples.w = max(0.0, texelFetch(pdfTexture, ivec2(position.x + 1u, position.y + 1u), mipLevel).x);

        float weightSum = samples.x + samples.y + samples.z + samples.w;
        if (weightSum <= 0.0) {
            pdf = 0.0;
            return;
        }

        samples /= weightSum;

        float rnd = RTXDI_GetNextRandom(rng);

        if (rnd < samples.x) {
            pdf *= samples.x;
        } else {
            rnd -= samples.x;
            if (rnd < samples.y) {
                position += uvec2(0u, 1u);
                pdf *= samples.y;
            } else {
                rnd -= samples.y;
                if (rnd < samples.z) {
                    position += uvec2(1u, 0u);
                    pdf *= samples.z;
                } else {
                    position += uvec2(1u, 1u);
                    pdf *= samples.w;
                }
            }
        }
    }
}

// RTXDI COMPACT_BIT / INDEX_MASK — stored on lightIndex in RIS tile entries.
// bit 31 = 1 when compact light data is available in ph_compact_light_data.
const uint RTXDI_LIGHT_COMPACT_BIT = 0x80000000u;
const uint RTXDI_LIGHT_INDEX_MASK  = 0x7FFFFFFFu;

// ---------------------------------------------------------------------------
// RAB_StoreCompactLightInfo — Photonics compact-light packer.
// Stores the full 4xvec4 light record in 4xuvec4 companion payload so the
// compact entry reloads one coherent light object instead of a truncated subset.
// Returns true on success (compact bit should be set on the RIS entry).
// ---------------------------------------------------------------------------
bool RAB_StoreCompactLightInfo(uint risBufferPtr, int lightIndex) {
    if (lightIndex < 0) return false;
    int base = lightIndex * 4; // light_size = 4
    uint dst = risBufferPtr * ph_compact_light_stride;
    ph_compact_light_data[dst + 0u] = floatBitsToUint(ph_lights_array_presample[base + 0]);
    ph_compact_light_data[dst + 1u] = floatBitsToUint(ph_lights_array_presample[base + 1]);
    ph_compact_light_data[dst + 2u] = floatBitsToUint(ph_lights_array_presample[base + 2]);
    ph_compact_light_data[dst + 3u] = floatBitsToUint(ph_lights_array_presample[base + 3]);
    return true;
}

// ---------------------------------------------------------------------------
// Main — RTXDI_PresampleLocalLights
// Reference: PresampleLights.hlsl
//   dispatch: glDispatchCompute(tileSize/GROUP_SIZE, tileCount, 1)
//   gl_GlobalInvocationID.x = sampleInTile (within [0, tileSize))
//   gl_GlobalInvocationID.y = tileIndex    (within [0, tileCount))
// ---------------------------------------------------------------------------
void main() {
    uint sampleInTile = gl_GlobalInvocationID.x;
    uint tileIndex    = gl_GlobalInvocationID.y;
    uint tileSize     = uint(ph_ris_tile_size);
    uint tileCount    = uint(ph_ris_tile_count);

    if (tileIndex >= tileCount) return;
    if (sampleInTile >= tileSize) return;

    // RTXDI: rng = RTXDI_InitRandomSampler(GlobalIndex.xy, frameIndex, 0)
    // PresampleLights.hlsl uses 2D dispatch: GlobalIndex.x = sampleInTile, GlobalIndex.y = tileIndex
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(sampleInTile, tileIndex),
        ph_ris_frame_index,
        0u  // pass = 0 for presample
    );

    // RTXDI: RTXDI_SamplePdfMipmap
    uvec2 texelPosition;
    float pdf;
    RTXDI_SamplePdfMipmap(rng, u_LocalLightPdfTexture, ph_pdf_texture_size, texelPosition, pdf);

    // RTXDI: lightIndex = RTXDI_ZCurveToLinearIndex(texelPosition)
    uint lightIndex = RTXDI_ZCurveToLinearIndex(texelPosition);

    float invSourcePdf = (pdf > 0.0) ? (1.0 / pdf) : 0.0;

    // RTXDI: RIS_BUFFER[risBufferPtr] = uint2(lightIndex, asuint(invSourcePdf))
    // Attempt compact storage; if successful, set COMPACT_BIT on the stored index.
    uint risBufferPtr = ph_ris_tile_buffer_offset + sampleInTile + tileIndex * tileSize;
    int signedLightIndex = int(lightIndex);
    uint packedIndex = lightIndex & RTXDI_LIGHT_INDEX_MASK;
    if (RAB_StoreCompactLightInfo(risBufferPtr, signedLightIndex)) {
        packedIndex |= RTXDI_LIGHT_COMPACT_BIT;
    }
    ph_ris_data[risBufferPtr] = uvec2(packedIndex, floatBitsToUint(invSourcePdf));
}
