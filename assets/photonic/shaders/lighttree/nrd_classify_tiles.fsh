#version 430

// Tile classifier for the RELAX-style direct lighting pipeline.
// Runs at ceil(viewWidth / 16) x ceil(viewHeight / 16), one fragment per tile.
// Output .r is 1.0 only when the entire 16x16 tile is sky/out of denoising range.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_tiles_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void main() {
    ivec2 tilePos = tex_coord;
    ivec2 basePixel = tilePos * 16;
    ivec2 screenSize = ivec2(int(viewWidth), int(viewHeight));

    int skyCount = 0;

    for (int dy = 0; dy < 16; dy++) {
        for (int dx = 0; dx < 16; dx++) {
            ivec2 pixelPos = basePixel + ivec2(dx, dy);

            if (pixelPos.x < 0 || pixelPos.y < 0 ||
                pixelPos.x >= screenSize.x || pixelPos.y >= screenSize.y) {
                skyCount++;
                continue;
            }

            vec3 worldPos = texelFetch(radiosity_position, pixelPos, 0).xyz;
            float viewZ = nrd_compute_view_z(worldPos);
            float depthVal = texelFetch(depthtex0, pixelPos, 0).x;

            // depthVal < 0.56 = first-person hand item (Iris convention, see common/impl/is_hand.glsl).
            // Hand-only tiles get the same skip flag as sky tiles; downstream NRD a-trous/history-fix
            // passes branch on `nrd_in_tiles.r > 0.5` and skip the entire 16x16 tile. RTXDI parity:
            // RELAX classifies hand tiles as kBackgroundTile in the same way.
            bool isSkyPixel = (viewZ >= ph_nrd_denoising_range) || (depthVal > 0.99999);
            bool isHandPixel = depthVal < 0.56;
            if (isSkyPixel || isHandPixel) {
                skyCount++;
            }
        }
    }

    nrd_tiles_out = vec4((skyCount == 256) ? 1.0 : 0.0, 0.0, 0.0, 1.0);
}
