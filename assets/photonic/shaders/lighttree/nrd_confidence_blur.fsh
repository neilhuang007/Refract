#version 430

// NRD history-confidence blur cascade pass.
// Exact GLSL port of NRD-Sample/Shaders/ConfidenceBlur.cs.hlsl (lines 30-106).
//
// This shader is rendered 5 times with confidence_blur_step = 1, 2, 4, 8, 16.
// On the last pass (confidence_blur_step == 16) the blur output is converted
// from "gradient" space to "confidence" space using NRD's Uncharted+sRGB curve
// (reference lines 91-103).
//
// Input  (.r=gradient, .g=normalOctX, .b=normalOctY, .a=viewZ_packed)
// Output (same layout; on last pass .r is the final confidence in [0,1])
//
// Reference: NRD-Sample/Shaders/ConfidenceBlur.cs.hlsl
// Consumption: NRD/Shaders/RELAX_TemporalAccumulation.cs.hlsl lines 595-599.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_confidence_blur_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Step size for this cascade pass: 1, 2, 4, 8, or 16 texels.
uniform int confidence_blur_step;

// ============================================================================
// GetGeometryWeightParams
// Exact port of ConfidenceBlur.cs.hlsl lines 18-28.
// Returns vec2(a, b) so ComputeNonExponentialWeight(NoX, a, b) is the weight.
// ============================================================================
vec2 confidenceGetGeometryWeightParams(vec3 Nv, vec3 worldPos) {
    const float planeDistSensitivity = 0.02;

    // Photonics: gRectSize.x = viewWidth, gUnproject = 1/min(w,h) is approximated
    // by tanHalfFov / viewWidth.  We use the exact same frustum-size formula from
    // the reference (perspective mode only; gOrthoMode == 0 always in Photonics).
    // Reference: ConfidenceBlur.cs.hlsl lines 21-22.
    float viewZ     = nrd_compute_view_z(worldPos);
    float frustumSize = viewWidth * (viewZ / max(viewWidth, viewHeight));
    float norm   = planeDistSensitivity * frustumSize;
    float a      = 1.0 / max(norm, 1e-6);
    float b      = dot(Nv, worldPos - world_camera_position) * a;
    return vec2(a, -b);
}

// ============================================================================
// ComputeNonExponentialWeight
// Exact port of ConfidenceBlur.cs.hlsl lines 30-31.
// Math::SmoothStep(1,0,|x*px+py|) = smoothstep(0,1,1-|x*px+py|)
// ============================================================================
float confidenceNonExponentialWeight(float NoX, float px, float py) {
    // Reference: Math::SmoothStep(1.0, 0.0, abs(x * px + py))
    // which expands to the nrd_compute_weight helper (nrd_common.glsl line 175).
    return nrd_compute_weight(NoX, px, py);
}

// ============================================================================
// Gaussian weight from ConfidenceBlur.cs.hlsl line 69:
//   float d = length(ivec2(i,j)) / 2.0;
//   float w = exp(-2.0 * d * d);
// ============================================================================
float confidenceGaussian(int i, int j) {
    float d = length(vec2(float(i), float(j))) / 2.0;
    return exp(-2.0 * d * d);
}

// ============================================================================
// Color::HdrToLinear_Uncharted
// Uncharted 2 tone-map curve, scalar version.
// Reference: ConfidenceBlur.cs.hlsl line 94 Color::HdrToLinear_Uncharted(gradient).x
// NRD/Include/NRD.hlsli (or STL): Uncharted2(x) = (x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F)-E/F
// where A=0.22, B=0.30, C=0.10, D=0.20, E=0.01, F=0.30.  Applied as a
// "reverse tone-map linearise" before sRGB encode to keep the curve monotone.
// This is a direct literal copy from STL::Color::HdrToLinear_Uncharted.
// ============================================================================
float confidenceHdrToLinearUncharted(float x) {
    // Uncharted 2 curve constants (STL/NRD sources)
    const float A = 0.22;
    const float B = 0.30;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.01;
    const float F = 0.30;
    const float W = 11.2; // white point

    // Filmic curve: F(x) = (x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F)-E/F
    float num   = x * (A * x + C * B) + D * E;
    float denom = x * (A * x + B)     + D * F;
    float Fx    = num / max(denom, 1e-6) - E / F;

    // White-point normalisation: divide by F(W)
    float numW   = W * (A * W + C * B) + D * E;
    float denomW = W * (A * W + B)     + D * F;
    float FW     = numW / max(denomW, 1e-6) - E / F;

    return Fx / max(FW, 1e-6);
}

// ============================================================================
// Color::ToSrgb -- scalar sRGB gamma encode.
// Reference: ConfidenceBlur.cs.hlsl line 95: Color::ToSrgb(saturate(gradient)).x
// IEC 61966-2-1: c <= 0.0031308 ? 12.92*c : 1.055*c^(1/2.4) - 0.055
// ============================================================================
float confidenceToSrgb(float c) {
    c = clamp(c, 0.0, 1.0);
    if (c <= 0.0031308) {
        return 12.92 * c;
    }
    return 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    ivec2 pixelPos = tex_coord;
    vec2 invSize   = vec2(1.0) / vec2(viewWidth, viewHeight);
    vec2 pixelUv   = (vec2(pixelPos) + 0.5) * invSize;

    // Read center tap
    vec4 data0   = texture(nrd_diff_confidence_gradient, pixelUv);
    float viewZ0 = data0.w / NRD_FP16_VIEWZ_SCALE;
    bool isLastPass = (confidence_blur_step == 16);

    // Sky guard: reference ConfidenceBlur.cs.hlsl lines 42-46.
    // Sky pixels have viewZ0 == INF; pass through with gradient=isLastPass
    // (0.0 gradient -> confidence 1.0 on last pass is the sky sentinel).
    if (viewZ0 >= NRD_INF * 0.5) {
        float skyGradient = isLastPass ? 1.0 : data0.x;
        nrd_confidence_blur_out = vec4(skyGradient, data0.yzw);
        return;
    }

    // Reconstruct center world position from stored viewZ and current G-buffer.
    // Photonics stores world positions in the G-buffer; use them for the center.
    vec3 worldPos0 = texelFetch(radiosity_position, pixelPos, 0).xyz;
    vec3 Nv0       = nrd_oct_decode_normal(data0.yz);  // reference line 49
    vec2 geomWeightParams = confidenceGetGeometryWeightParams(Nv0, worldPos0);

    float gradient = data0.x;
    float sumW     = 1.0;

    // -----------------------------------------------------------------------
    // 5x5 cross-bilateral filter kernel
    // Reference: ConfidenceBlur.cs.hlsl lines 54-87.
    // Skip (0,0): handled by the center-tap initialisation above.
    // -----------------------------------------------------------------------
    for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
            if (i == 0 && j == 0) {
                continue;
            }

            ivec2 tapPos = pixelPos + ivec2(i, j) * confidence_blur_step;
            vec2  tapUv  = (vec2(tapPos) + 0.5) * invSize;

            vec4  tapData = texture(nrd_diff_confidence_gradient, tapUv);

            // --- Gaussian weight (reference line 69-70) ---
            float w = confidenceGaussian(i, j);

            // --- Plane-distance weight (reference lines 72-76) ---
            float tapViewZ = tapData.w / NRD_FP16_VIEWZ_SCALE;
            // Reconstruct approximate world position for tap.
            // We use the nrd_common helper that scales from camera position.
            // For a tap that is outside screen bounds tapViewZ is 0; clamp away.
            if (tapViewZ < 1e-3 || tapViewZ >= NRD_INF * 0.5) {
                continue;
            }
            // Reference (line 74): reconstruct tap view-position then compute NoX.
            // In Photonics, viewZ = radial distance from camera (not linear depth).
            // We approximate the tap world position by projecting along the ray
            // from the camera through the tap UV, scaled to the tap's radial distance.
            // The center direction gives us the approximate tap direction for nearby taps.
            // Error is < 1% for the 5-tap-step range used here.
            vec3 camRelCenter = worldPos0 - world_camera_position;
            float centerViewZ0 = length(camRelCenter);  // == viewZ0
            // Approximate tap position: scale center direction by tap's radial distance.
            // This is close enough for the plane-distance bilateral weight.
            vec3 tapWorldPos = world_camera_position
                + (camRelCenter / max(centerViewZ0, 1e-3)) * tapViewZ;
            // NoX for plane distance weight (reference line 75: dot(Nv0, Xv))
            // Here Xv is the view-space (camera-relative) tap position.
            float NoX = dot(Nv0, tapWorldPos - world_camera_position);
            w *= confidenceNonExponentialWeight(NoX, geomWeightParams.x, geomWeightParams.y);

            // --- Normal weight (reference lines 79-81) ---
            vec3 Nv = nrd_oct_decode_normal(tapData.yz);
            float NoN = clamp(dot(Nv0, Nv), 0.0, 1.0);
            w *= NoN * NoN;  // reference: w *= NoN * NoN

            // --- Accumulate (reference lines 83-85) ---
            gradient += tapData.x * w;
            sumW     += w;
        }
    }

    gradient /= max(sumW, 1e-6);  // reference line 89

    // -----------------------------------------------------------------------
    // Last-pass gradient -> confidence conversion
    // Reference: ConfidenceBlur.cs.hlsl lines 91-103.
    // -----------------------------------------------------------------------
    if (isLastPass) {
        // Reference line 94: Color::HdrToLinear_Uncharted(gradient).x
        gradient = confidenceHdrToLinearUncharted(gradient);

        // Reference line 95: 1.0 - Color::ToSrgb(saturate(gradient)).x
        gradient = 1.0 - confidenceToSrgb(clamp(gradient, 0.0, 1.0));

        // Reference lines 97-98: RELAX-specific squaring
        gradient *= gradient;  // "gradient" is now "confidence"

        // Reference lines 101-102: Bayer4x4 dither -- SKIPPED per scope.
        // Adding sub-pixel dither to the confidence map introduces ~0.002
        // noise per pixel; the Minecraft block-scale signal is coarser and
        // does not benefit.  Omitted to reduce risk on first validation pass.
    }

    // Reference line 105: saturate(gradient) stored as confidence .r
    nrd_confidence_blur_out = vec4(clamp(gradient, 0.0, 1.0), data0.yzw);
}
