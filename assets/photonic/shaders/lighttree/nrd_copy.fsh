#version 430

// ---------------------------------------------------------------------------
// nrd_copy.fsh
//
// Mirror of RELAX_Copy.cs.hlsl.
//
// Trivially copies the post-clamping permanent slow history buffers
// (nrd_diff_illum_prev / nrd_spec_illum_prev) into the public output buffers
// (nrd_out_diff_radiance_hitdist_out / nrd_out_spec_radiance_hitdist_out).
//
// This is required so that:
//   (a) AntiFirefly can read the "clean" post-clamping signal from the public
//       output buffers while writing its filtered result back to the permanent
//       prev buffers (avoiding a same-buffer read/write hazard).
//   (b) The A-trous passes read from a stable pre-firefly-suppressed signal.
//
// Per the contract (section 7, Copy): tile early-out is applied; sky pixels
// write zero rather than garbage to avoid poisoning downstream passes.
//
// Reference: RELAX_Copy.cs.hlsl:21-34
// ---------------------------------------------------------------------------

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_out_diff_radiance_hitdist_out;  // RGBA16F → nrdOutDiffRadianceHitDistFb
layout(location = 1) out vec4 nrd_out_spec_radiance_hitdist_out;  // RGBA16F → nrdOutSpecRadianceHitDistFb

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void main() {
    ivec2 pixelPos = tex_coord;

    // Tile early-out (contract section 11, rule 7)
    ivec2 tileCoord = pixelPos >> 4;
    float isSky = texelFetch(nrd_in_tiles, tileCoord, 0).r;
    if (isSky > 0.5) {
        nrd_out_diff_radiance_hitdist_out = vec4(0.0);
        nrd_out_spec_radiance_hitdist_out = vec4(0.0);
        return;
    }

    // RELAX_Copy.cs.hlsl:27-33 -- trivial copy.
    // gIn_Spec  → nrd_spec_illum_prev  (permanent slow, just written by clamping)
    // gOut_Spec → nrd_out_spec_radiance_hitdist_out
    // gIn_Diff  → nrd_diff_illum_prev
    // gOut_Diff → nrd_out_diff_radiance_hitdist_out
    nrd_out_diff_radiance_hitdist_out = texelFetch(nrd_diff_illum_prev, pixelPos, 0);
    nrd_out_spec_radiance_hitdist_out = texelFetch(nrd_spec_illum_prev, pixelPos, 0);
}
