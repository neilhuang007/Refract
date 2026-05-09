#version 430

// NRD history-confidence gradient pass.
// Computes a per-pixel luma gradient between the previous accumulated diffuse
// and the current noisy direct-diffuse radiance.  The result is packed into
// an RGBA16F texture that the subsequent blur cascade reads:
//
//   .r = luma gradient in [0, 1]
//   .g = octahedral-encoded normal X
//   .b = octahedral-encoded normal Y
//   .a = viewZ * FP16_VIEWZ_SCALE  (packed so the blur can unpack with /scale)
//
// The blur cascade consumes this and produces a confidence in [0, 1] that
// is sampled next frame by RELAXTemporalAccumulation.
//
// Reference: NRD-Sample/Shaders/ConfidenceBlur.cs.hlsl (gradient input is
// produced by a separate GradientBlend pass in the reference; here we
// compute it inline).  Consumption: NRD/Shaders/RELAX_TemporalAccumulation.cs.hlsl
// lines 595-599.

in vec4 direction_vert_out;

// Single RGBA16F output: (gradient, normalOctX, normalOctY, viewZ_packed)
layout(location = 0) out vec4 nrd_confidence_gradient_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void main() {
    ivec2 pixelPos = tex_coord;

    // Sky tiles have no geometry; output sky sentinel (z0 == INF kills blur taps)
    float isSky = texelFetch(nrd_in_tiles, pixelPos >> 4, 0).r;
    if (isSky > 0.5) {
        // Store NRD_INF in .a so ConfidenceBlur's sky-guard fires.
        nrd_confidence_gradient_out = vec4(0.0, 0.0, 0.0, NRD_INF);
        return;
    }

    // -----------------------------------------------------------------------
    // Geometry data (for plane-distance weights in the blur cascade)
    // -----------------------------------------------------------------------
    vec3 worldPos = texelFetch(radiosity_position, pixelPos, 0).xyz;
    float viewZ   = nrd_compute_view_z(worldPos);

    vec3 geomNormal   = nrd_safe_normal(texelFetch(radiosity_normal, pixelPos, 0).xyz);
    vec3 mappedNormal = nrd_select_surface_normal(
        geomNormal,
        texelFetch(radiosity_mapped_normal, pixelPos, 0).xyz
    );

    // -----------------------------------------------------------------------
    // Luma gradient -- reference kernel from task description:
    //   gradient = |prevLuma - currLuma| / (prevLuma + currLuma + eps)  when max > eps
    // This is a symmetric relative difference (similar to SSIM luminance distance).
    // Reference: ConfidenceBlur.cs.hlsl consumes pre-computed gradient in .r.
    // -----------------------------------------------------------------------
    // Current noisy direct radiance (what TA consumed this frame as gIn_Diff).
    // 3x3 box mean to suppress single-pixel ReGIR sampling variance: comparing
    // raw single-sample current vs many-frame-accumulated previous would treat
    // sampling noise as a "lighting change" and crash confidence at light bases.
    vec3 currNoisy = vec3(0.0);
    float currWeight = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            ivec2 sp = clamp(pixelPos + ivec2(dx, dy), ivec2(0), ivec2(viewWidth - 1, viewHeight - 1));
            currNoisy += max(texelFetch(nrd_in_diff_radiance_hitdist, sp, 0).rgb, vec3(0.0));
            currWeight += 1.0;
        }
    }
    currNoisy /= max(currWeight, 1.0);

    // Previous accumulated diffuse + 2nd moment (alpha) from history texture.
    // 2nd moment lets us derive expected per-pixel std-dev = sqrt(2nd_moment - mean^2)
    // and use it as a noise floor: real lighting changes exceed it, ReGIR variance does not.
    vec4 prevAccumWith2M = texture(nrd_diff_illum_prev, vec2(pixelPos + 0.5) / vec2(viewWidth, viewHeight));
    vec3 prevAccum = max(prevAccumWith2M.rgb, vec3(0.0));
    float prevLumaSq2M = max(prevAccumWith2M.a, 0.0);

    float prevLuma = nrd_luminance(prevAccum);
    float currLuma = nrd_luminance(currNoisy);

    // Variance-aware noise floor.  Subtract one std-dev of expected fluctuation
    // before forming the gradient.  This is the variance-aware analog of NRD's
    // sparse path-traced gradient comparison (SharcUpdate / GradientBlend in NRD-Sample),
    // which we cannot replicate without a separate path-tracing pass.
    float prevVariance = max(prevLumaSq2M - prevLuma * prevLuma, 0.0);
    float prevStdDev   = sqrt(prevVariance);

    float deltaLuma     = abs(prevLuma - currLuma);
    float effectiveDelta = max(deltaLuma - prevStdDev, 0.0);

    float maxLuma  = max(prevLuma, currLuma);
    float gradient = (maxLuma > 1e-6)
        ? effectiveDelta / (prevLuma + currLuma + 1e-6)
        : 0.0;

    // -----------------------------------------------------------------------
    // Pack normal using octahedral encoding.
    // Reference: ConfidenceBlur.cs.hlsl line 49 reads Packing::DecodeUnitVector(data.yz).
    // Inverse: nrd_oct_encode_normal()  (helper declared in nrd_common.glsl).
    // -----------------------------------------------------------------------
    vec2 octNormal = nrd_oct_encode_normal(mappedNormal);

    // -----------------------------------------------------------------------
    // Pack viewZ with FP16_VIEWZ_SCALE so the blur's sky guard works.
    // Reference: ConfidenceBlur.cs.hlsl line 39: float z0 = data0.w / FP16_VIEWZ_SCALE
    // NRD_FP16_VIEWZ_SCALE = 0.125 (packed so viewZ * scale fits in FP16 range).
    // -----------------------------------------------------------------------
    float viewZPacked = viewZ * NRD_FP16_VIEWZ_SCALE;

    nrd_confidence_gradient_out = vec4(gradient, octNormal.x, octNormal.y, viewZPacked);
}
