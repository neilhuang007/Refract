#version 430

// ---------------------------------------------------------------------------
// nrd_classify_tiles.fsh
//
// Mirror of RELAX_ClassifyTiles.cs.hlsl.
//
// The reference is a compute shader with 8x4 threads (32 total) each processing
// a 2x4 block of pixels, reducing 256 pixels per 16x16 tile via a shared-memory
// atomic.  Fragment shaders cannot use groupshared memory, so the reduction is
// implemented as a plain loop over all 16x16 source pixels.
//
// This shader is dispatched at TILE resolution:
//   ceil(viewWidth/16) x ceil(viewHeight/16)
// so each fragment corresponds to exactly one 16x16 tile.
//
// Output: .r = 1.0 if ALL 256 pixels in the tile are sky / out-of-denoising-range,
//              0.0 otherwise.
// Reference: RELAX_ClassifyTiles.cs.hlsl:23-51
// ---------------------------------------------------------------------------

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_tiles_out;  // R8 → nrdTilesFb

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void main() {
    // tex_coord here is in TILE space (one texel per 16x16 pixel tile).
    // Convert to the top-left pixel coordinate in the source G-buffer.
    ivec2 tilePos = tex_coord;
    ivec2 basePixel = tilePos * 16;

    int skyCount = 0;

    // RELAX_ClassifyTiles.cs.hlsl:32-43 -- OR-reduce over all 16x16 pixels.
    // Reference uses 32 threads each handling 2x4 = 8 pixels; we linearise.
    for (int dy = 0; dy < 16; dy++) {
        for (int dx = 0; dx < 16; dx++) {
            ivec2 pixelPos = basePixel + ivec2(dx, dy);

            // Clamp to screen bounds (same as reference globalPos = clamp(...,0,gRectSize-1))
            pixelPos = clamp(pixelPos, ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));

            // Read world-space position to compute viewZ and detect sky pixels.
            // RELAX_ClassifyTiles.cs.hlsl:39: float viewZ = abs(gIn_ViewZ[pos])
            // In Photonics, viewZ = length(worldPos - cameraPos); sky = !is_in_world().
            vec3 worldPos = texelFetch(radiosity_position, pixelPos, 0).xyz;
            float viewZ = nrd_compute_view_z(worldPos);

            // RELAX_ClassifyTiles.cs.hlsl:41:
            //   isSky += !IsInDenoisingRange(viewZ) ? 1 : 0;
            // IsInDenoisingRange(z) = (z < gDenoisingRange)
            // A pixel is "sky" when it is NOT in denoising range.
            // Additionally, pixels not in the world (depth >= 0.99999) are sky.
            bool isSkyPixel = (viewZ >= ph_nrd_denoising_range);
            // Also treat pixels outside the world geometry as sky.
            float depthVal = texelFetch(depthtex0, pixelPos, 0).x;
            if (depthVal > 0.99999) isSkyPixel = true;

            if (isSkyPixel) skyCount++;
        }
    }

    // RELAX_ClassifyTiles.cs.hlsl:50:
    //   gOut_Tiles[tilePos] = s_isSky == 256 ? 1.0 : 0.0;
    // 256 = 16*16 total pixels per tile.
    float skyMask = (skyCount == 256) ? 1.0 : 0.0;
    nrd_tiles_out = vec4(skyMask, 0.0, 0.0, 1.0);
}
