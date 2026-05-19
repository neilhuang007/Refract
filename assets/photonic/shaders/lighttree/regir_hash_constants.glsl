#ifndef PHOTONICS_REGIR_HASH_CONSTANTS_GLSL
#define PHOTONICS_REGIR_HASH_CONSTANTS_GLSL

const uint REGIR_HASH_CLAIMED    = 0xffffffffu;
const int  REGIR_HASH_MAX_PROBES = 128; // Tuned 32→128 per commit 6d1b19d (2026-04-30) for higher cell occupancy.

#endif // PHOTONICS_REGIR_HASH_CONSTANTS_GLSL
