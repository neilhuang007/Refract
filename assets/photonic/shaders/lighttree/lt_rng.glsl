#ifndef PHOTONICS_LT_RNG_GLSL
#define PHOTONICS_LT_RNG_GLSL

// Consumer must declare RTXDI_RandomSamplerState before including this file
// (provided by /photonics/lighttree/light_tree.glsl).

uint lt_rng_hash(uint x)
{
    x ^= x >> 16u;
    x *= 0x7feb352du;
    x ^= x >> 15u;
    x *= 0x846ca68bu;
    x ^= x >> 16u;
    return x;
}

RTXDI_RandomSamplerState lt_init_random_sampler(uvec2 pixelPosition, uint frameIndex, uint seed)
{
    RTXDI_RandomSamplerState rng;
    uint mixed = pixelPosition.x * 0x1f123bb5u;
    mixed ^= pixelPosition.y * 0x5f356495u;
    mixed ^= frameIndex * 0x9e3779b9u;
    mixed ^= seed * 0x85ebca6bu;
    rng.seed = lt_rng_hash(mixed | 1u);
    rng.index = 1u;
    return rng;
}

float lt_next_random(inout RTXDI_RandomSamplerState rng)
{
    rng.seed = lt_rng_hash(rng.seed + 0x9e3779b9u);
    return float(rng.seed & 0x00ffffffu) / float(0x01000000u);
}

#endif
