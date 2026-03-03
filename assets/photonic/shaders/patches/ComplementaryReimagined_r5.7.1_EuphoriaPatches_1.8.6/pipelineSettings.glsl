#file "/lib/pipelineSettings.glsl"

#replace "const int colortex10Format = RGBA16F;       // Screenspace colored light Blurred"
const int colortex10Format = RGBA8;         // Photonics albedo cache
const int colortex11Format = RGBA8;         // Photonics normal cache
const int colortex12Format = RGBA16F;       // Photonics indirect result
const int colortex13Format = RGBA32F;       // Photonics pixelated player position cache (avoid half-float snap seams)
#endreplace

#replace "const bool colortex10Clear = false;"
const bool colortex10Clear = true;
const bool colortex11Clear = true;
const bool colortex12Clear = true;
const bool colortex13Clear = true;
#endreplace
