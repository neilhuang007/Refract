#ifndef PHOTONICS_LT_SCATTER_PACKING_GLSL
#define PHOTONICS_LT_SCATTER_PACKING_GLSL

float scatter_pack_half2(vec2 value) {
    return uintBitsToFloat(packHalf2x16(value));
}

vec2 scatter_unpack_half2(float packedValue) {
    return unpackHalf2x16(floatBitsToUint(packedValue));
}

uint scatter_pack_reconnection_time_bits(float time)
{
    float clampedTime = clamp(time, 0.0f, 1.0f);
    return min(uint(round(clampedTime * float(SCATTER_RECONNECTION_TIME_MASK))), SCATTER_RECONNECTION_TIME_MASK);
}

float scatter_unpack_reconnection_time_bits(uint packedMeta)
{
    return float((packedMeta >> SCATTER_RECONNECTION_TIME_SHIFT) & SCATTER_RECONNECTION_TIME_MASK)
        / float(SCATTER_RECONNECTION_TIME_MASK);
}

#endif
