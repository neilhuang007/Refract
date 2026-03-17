#version 430

/*
    -- INPUT VARIABLES --
*/
in vec4 direction_vert_out;

/*
    -- OUTPUT VARIABLES --
*/
layout(location = 0) out vec3 color_frag_out;
layout(location = 1) out float variance_frag_out;

#include "/photonics/common/header.glsl"
vec3 ph_sun_direction = ph_signed_nudge(sun_direction);
#include "/photonics/restir/restir.glsl"
#include "/photonics/common/lighting.glsl"

//ph_required: uniform int atrous_iteration;

const float kernelWeights[3] = float[](1.0f, 2.0f / 3.0f, 1.0f / 6.0f);
const vec3 LUM_COEFF = vec3(0.2126, 0.7152, 0.0722);
const float INDIRECT_HISTORY_SHORT = 4.0f;
const float INDIRECT_STAGE_LUMA_CLAMP_SIGMA = 2.5f;
const float INDIRECT_STAGE_LUMA_CLAMP_FLOOR = 0.04f;

float normal_edge_stopping_weight(vec3 center_normal, vec3 sample_normal, float power)
{
    return pow(clamp(dot(center_normal, sample_normal), 0.0f, 1.0f), power);
}

float ph_confidence_from_history(float historyLength)
{
    return clamp(historyLength / float(PH_RESTIR_ACCUMULATION_FRAMES), 0.0f, 1.0f);
}

float ph_indirect_normal_power(float historyLength)
{
    float confidence = ph_confidence_from_history(historyLength);
    return mix(24.0f, 96.0f, confidence);
}

float ph_indirect_luma_phi(float centerLuma, float variance, float historyConfidence)
{
    float sigmaScale = mix(7.5f, 3.5f, historyConfidence);
    float floorPhi = mix(0.30f, 0.08f, historyConfidence) * max(centerLuma, 0.05f);
    return max(sigmaScale * sqrt(max(variance, 1e-6f)), floorPhi);
}

float depth_edge_stopping_weight(float center_depth, float sample_depth, vec2 depth_gradient, ivec2 sample_offset)
{
    float expected_depth = center_depth + dot(depth_gradient, vec2(sample_offset));
    float phi = max(abs(dot(depth_gradient, vec2(sample_offset))), 1e-4f);
    return exp(-abs(sample_depth - expected_depth) / phi);
}

float luma_edge_stopping_weight(float center_luma, float sample_luma, float phi)
{
    return exp(-abs(center_luma - sample_luma) / phi);
}

float ph_linearize_depth(float d)
{
    return near * far / (far + d * (near - far));
}

float kernel_5x5(ivec2 p)
{
    return kernelWeights[abs(p.x)] * kernelWeights[abs(p.y)];
}

void main() {
    if (!is_in_world()) {
        color_frag_out = vec3(0f);
        variance_frag_out = 1f;

        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    if (atrous_iteration == -1) {
        vec4 centerPacked = texelFetch(radiosity_indirect, tex_coord, 0);
        vec3 color = centerPacked.rgb;
        if (any(isnan(color))) color = vec3(0f);
        color = ph_clamp_indirect_radiance(color);
        float historyLength = centerPacked.a;
        vec4 varianceData = texelFetch(radiosity_indirect_variance, tex_coord, 0);
        if (any(isnan(varianceData))) varianceData = vec4(0.0f);

        float centerLumaRaw = dot(color, LUM_COEFF);
        float centerVarianceRaw = max(varianceData.y - varianceData.x * varianceData.x, 0.0f);
        float clampPhi = max(INDIRECT_STAGE_LUMA_CLAMP_SIGMA * sqrt(max(centerVarianceRaw, 1e-6f)), INDIRECT_STAGE_LUMA_CLAMP_FLOOR * max(centerLumaRaw, 0.05f));
        vec3 nMin = color;
        vec3 nMax = color;
        for (int yy = -1; yy <= 1; yy++) {
            for (int xx = -1; xx <= 1; xx++) {
                if (xx == 0 && yy == 0) continue;
                vec3 c = ph_clamp_indirect_radiance(texelFetch(radiosity_indirect, tex_coord + ivec2(xx, yy), 0).rgb);
                nMin = min(nMin, c);
                nMax = max(nMax, c);
            }
        }
        vec3 clampedNeighborhood = clamp(color, nMin, nMax);
        float clampedLuma = dot(clampedNeighborhood, LUM_COEFF);
        if (centerLumaRaw > clampedLuma + clampPhi && centerLumaRaw > 1.0e-4f) {
            color *= (clampedLuma + clampPhi) / centerLumaRaw;
        }

        color_frag_out = color;

        if (historyLength < INDIRECT_HISTORY_SHORT) {
            ivec2 tex_size = textureSize(radiosity_indirect, 0);
            float centerDepth = ph_linearize_depth(texelFetch(depthtex0, tex_coord, 0).r);
            vec3 centerGeometryNormal = texelFetch(radiosity_normal, tex_coord, 0).xyz;
            vec3 centerMappedNormal = texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz;
            float centerLuma = dot(color_frag_out, LUM_COEFF);
            float centerVariance = max(varianceData.y - varianceData.x * varianceData.x, 0.0f);
            float phiDepth = max(centerDepth, 1e-4f) * mix(4.5f, 2.5f, ph_confidence_from_history(historyLength));
            float normalPower = ph_indirect_normal_power(historyLength);
            float phiLuma = ph_indirect_luma_phi(centerLuma, centerVariance, clamp(varianceData.w, 0.0f, 1.0f));
            float sumW = 0.0f;
            vec3 sumColor = vec3(0.0f);
            vec2 sumMoments = vec2(0.0f);

            for (int yy = -3; yy <= 3; yy++) {
                for (int xx = -3; xx <= 3; xx++) {
                    ivec2 p = clamp(tex_coord + ivec2(xx, yy), ivec2(0), tex_size - 1);
                    vec4 samplePacked = texelFetch(radiosity_indirect, p, 0);
                    if (samplePacked.a <= 0.0f) continue;
                    vec3 sampleColor = ph_clamp_indirect_radiance(samplePacked.rgb);
                    float sampleLuma = dot(sampleColor, LUM_COEFF);
                    float sampleDepth = ph_linearize_depth(texelFetch(depthtex0, p, 0).r);
                    vec3 sampleMappedNormal = texelFetch(radiosity_mapped_normal, p, 0).xyz;
                    float wN = normal_edge_stopping_weight(centerMappedNormal, sampleMappedNormal, normalPower);
                    float wD = exp(-abs(centerDepth - sampleDepth) / max(phiDepth * length(vec2(xx, yy)), 1e-4f));
                    float wL = luma_edge_stopping_weight(centerLuma, sampleLuma, phiLuma);
                    float w = wN * wD * wL;
                    vec2 sampleMoments = texelFetch(radiosity_indirect_variance, p, 0).xy;
                    sumW += w;
                    sumColor += sampleColor * w;
                    sumMoments += sampleMoments * w;
                }
            }

            // Technique C: History Fix — wider kernel for very short history (disoccluded pixels)
            if (historyLength < 2.5f) {
                for (int yy = -2; yy <= 2; yy++) {
                    for (int xx = -2; xx <= 2; xx++) {
                        if (xx == 0 && yy == 0) continue;
                        ivec2 p = clamp(tex_coord + ivec2(xx, yy) * 4, ivec2(0), tex_size - 1);
                        vec4 samplePacked = texelFetch(radiosity_indirect, p, 0);
                        if (samplePacked.a <= 0.0f) continue;
                        vec3 sampleColor = ph_clamp_indirect_radiance(samplePacked.rgb);
                        float sampleHistory = samplePacked.a;
                        float sampleLuma = dot(sampleColor, LUM_COEFF);
                        float sampleDepth = ph_linearize_depth(texelFetch(depthtex0, p, 0).r);
                        vec3 sampleMappedNormal = texelFetch(radiosity_mapped_normal, p, 0).xyz;
                        // Relaxed edge stopping: normal power 32 instead of 128
                        float wN = normal_edge_stopping_weight(centerMappedNormal, sampleMappedNormal, 18.0f);
                        float wD = exp(-abs(centerDepth - sampleDepth) / max(phiDepth * length(vec2(xx, yy) * 4.0f), 1e-4f));
                        float wL = luma_edge_stopping_weight(centerLuma, sampleLuma, phiLuma);
                        // Prefer neighbors with longer history
                        float wH = clamp(sampleHistory / 4.0f, 0.1f, 1.0f);
                        float w = wN * wD * wL * wH;
                        vec2 sampleMoments = texelFetch(radiosity_indirect_variance, p, 0).xy;
                        sumW += w;
                        sumColor += sampleColor * w;
                        sumMoments += sampleMoments * w;
                    }
                }
            }

            sumW = max(sumW, 1e-4f);
            color_frag_out = sumColor / sumW;
            vec2 moments = sumMoments / sumW;
            float variance = max(moments.y - moments.x * moments.x, 0.0f);
            variance *= 4.0f / max(historyLength, 1.0f);
            variance_frag_out = variance;
        } else {
            float variance = max(varianceData.y - varianceData.x * varianceData.x, 0.0f);
            variance_frag_out = variance;
        }

        return;
    }

    int step_width = 1 << atrous_iteration;

    vec3 C0 = texelFetch(prev_indirect_denoise_color, tex_coord, 0).rgb;
    float L0 = dot(C0, LUM_COEFF);
    vec3 N0 = texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz;
    ivec2 tex_size = textureSize(prev_indirect_denoise_color, 0);
    float D0 = ph_linearize_depth(texelFetch(depthtex0, tex_coord, 0).r);
    float D_right = ph_linearize_depth(texelFetch(depthtex0, clamp(tex_coord + ivec2(1, 0), ivec2(0), tex_size - 1), 0).r);
    float D_down = ph_linearize_depth(texelFetch(depthtex0, clamp(tex_coord + ivec2(0, 1), ivec2(0), tex_size - 1), 0).r);
    vec2 depth_grad = vec2(D_right - D0, D_down - D0);

    float V0 = 0.0f;
    float sumw = 0.0f;
    for (int yy = -1; yy <= 1; yy++) {
        for (int xx = -1; xx <= 1; xx++) {
            ivec2 p = clamp(tex_coord + ivec2(xx, yy), ivec2(0), tex_size - 1);
            float Vi = texelFetch(prev_indirect_denoise_variance, p, 0).x;
            float k = kernelWeights[abs(xx)] * kernelWeights[abs(yy)];
            V0 += Vi * k;
            sumw += k;
        }
    }
    V0 /= sumw;

    // Indirect GI needs aggressive spatial smoothing — keep fixed permissive sigma
    // (GI signal is ~1spp and too noisy for confidence-driven tightening)
    float historyLength = texelFetch(radiosity_indirect, tex_coord, 0).a;
    float confidence = ph_confidence_from_history(historyLength);
    float pV = mix(7.0f, 3.0f, confidence) * sqrt(max(V0, 1e-6f)) + mix(0.18f, 0.05f, confidence) * max(L0, 0.05f) + 1e-6;
    float normalPower = mix(20.0f, 96.0f, confidence);

    vec3 C_sum = vec3(0.0f);
    float W_sum = 0.0f;
    float V_sum = 0.0f;

    W_sum = 1.0f;
    C_sum = C0;
    V_sum = V0;

    for (int yy = -2; yy <= 2; ++yy) {
        for (int xx = -2; xx <= 2; ++xx) {
            if (xx == 0 && yy == 0) continue;
            ivec2 localOffset = ivec2(xx, yy);
            ivec2 p = clamp(tex_coord + step_width * localOffset, ivec2(0), tex_size - 1);
            vec3 Ci = texelFetch(prev_indirect_denoise_color, p, 0).rgb;
            float Vi = texelFetch(prev_indirect_denoise_variance, p, 0).x;
            float Li = dot(Ci.xyz, LUM_COEFF);
            vec3 Ni = texelFetch(radiosity_mapped_normal, p, 0).xyz;
            float Di = ph_linearize_depth(texelFetch(depthtex0, p, 0).x);
            float k = kernel_5x5(localOffset);

            float wC = luma_edge_stopping_weight(L0, Li, pV);
            float wN = normal_edge_stopping_weight(N0, Ni, normalPower);
            float wP = depth_edge_stopping_weight(D0, Di, depth_grad, step_width * localOffset);
            float w = wC * wN * wP * k;
            W_sum += w;
            C_sum += Ci * w;
            V_sum += Vi * w * w;
        }
    }

    W_sum = max(0.0001f, W_sum);
    V_sum = max(0.0001f, V_sum);

    color_frag_out = C_sum / W_sum;
    variance_frag_out = max(V_sum / (W_sum * W_sum), 0.0f);
}

