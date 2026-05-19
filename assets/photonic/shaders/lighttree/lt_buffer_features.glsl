#ifndef PHOTONICS_LIGHTTREE_BUFFER_FEATURES_GLSL
#define PHOTONICS_LIGHTTREE_BUFFER_FEATURES_GLSL

// ----------------------------------------------------------------------------
// LightTree buffer-feature manifest (single source of truth, opt-in)
// ----------------------------------------------------------------------------
//
// Background: NVIDIA fragment shaders have a strict limit on bindable storage
// buffers (typically 16 per stage). The full LightTree SSBO surface (REGIR
// RIS + hash buffers, light data arrays, floating-coords, neighbour offsets,
// plus per-pass scatter sort/counter buffers) exceeds that limit, so every
// .fsh must only bind the SSBOs it actually uses.
//
// Mechanism: each .fsh sets one or more PH_LIGHTTREE_ENABLE_<STAGE>_STAGE
// identity flags at the top of the file. This manifest reads those identity
// flags and expands the appropriate PH_LIGHTTREE_USES_<FEATURE> opt-in flags.
// SSBO declaration sites gate their declarations on the USES_* flags. Default
// = no USES_* flag is defined, which yields the safe "lean" buffer surface.
//
// Add a new pass: extend one of the branches below. Do NOT scatter
// PH_LIGHTTREE_USES_* defines across individual .fsh files — that defeats the
// "single source of truth" property and recreates the maintenance burden this
// manifest was introduced to eliminate.
// ----------------------------------------------------------------------------

// Lean-pass sentinel: any pass listed here is a scatter/sort-only pass that must
// not pull in REGIR, LIGHT_DATA, FLOATING_COORDS, or NEIGHBOR_OFFSETS SSBOs.
// Each .fsh sets exactly one PH_LIGHTTREE_ENABLE_*_STAGE flag; we OR them here so
// that this file remains the single authoritative gating point (no per-.fsh USES_*).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)              \
 || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE)             \
 || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)     \
 || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)       \
 || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)          \
 || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)        \
 || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
    // Lean scatter / sort passes: only scatter sort/counter SSBOs (declared by
    // restir_di_temporal_buffer_bridge.glsl gated by PH_LIGHTTREE_ENABLE_*) plus
    // reservoir/G-buffer textures. No REGIR, no LIGHT_DATA, no FLOATING_COORDS,
    // no NEIGHBOR_OFFSETS.
#elif defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
    // Reprojection: needs REGIR initial-sample helpers and FLOATING_COORDS
    // (robust-gather pixel coordinates). Does not consume the full light data
    // arrays — light evaluation is deferred to the sampling/shading stages.
    #define PH_LIGHTTREE_USES_REGIR
    #define PH_LIGHTTREE_USES_FLOATING_COORDS
#else
    // Default (full): initial candidates, sampling stage, gather, shading,
    // spatial reuse, indirect-light passes, etc. Pull in every SSBO the
    // LightTree pipeline can possibly reference.
    #define PH_LIGHTTREE_USES_REGIR
    #define PH_LIGHTTREE_USES_LIGHT_DATA
    #define PH_LIGHTTREE_USES_FLOATING_COORDS
    #define PH_LIGHTTREE_USES_NEIGHBOR_OFFSETS
#endif

#endif // PHOTONICS_LIGHTTREE_BUFFER_FEATURES_GLSL
