#version 430

// Fused diffuse + specular history fix pass.
// Reference: RELAX_HistoryFix.cs.hlsl (NRD v4).
// For disoccluded pixels (historyLength <= gHistoryFixFrameNum) a 5x5 sparse
// cross-bilateral filter is run on the SLOW signal (PING buffer from temporal
// accumulation) and the result is written to the PONG buffer, replacing the
// responsive value at young pixels.  Old pixels (historyLength > threshold)
// pass through the existing responsive PONG signal unchanged.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_pong_fixed_out;
layout(location = 1) out vec4 nrd_spec_pong_fixed_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Samplers declared in samplers.glsl (via header.glsl → photonics.glsl → ph_samplers.glsl → samplers.glsl):
//   nrd_diff_illum_ping, nrd_spec_illum_ping, nrd_diff_illum_pong, nrd_spec_illum_pong,
//   nrd_history_length, nrd_in_tiles,
//   radiosity_position, radiosity_normal, radiosity_mapped_normal, radiosity_material

// RELAX_HistoryFix.cs.hlsl:21-24
// pow(max(0.01, dot(n0, n1)), power) -- lower-clamped dot prevents negative pow
float getDiffuseNormalWeight(vec3 centerNormal, vec3 pointNormal) {
    return pow(max(0.01, dot(centerNormal, pointNormal)), max(ph_nrd_history_fix_normal_power, 0.01));
}

void main() {
    // RELAX_HistoryFix.cs.hlsl:32-34 -- tile-based early out
    // Tile texture is at 1/16 resolution; shift coord right by 4 to index it.
    if (texelFetch(nrd_in_tiles, tex_coord >> 4, 0).r > 0.5) {
        nrd_diff_pong_fixed_out = vec4(0.0);
        nrd_spec_pong_fixed_out = vec4(0.0);
        return;
    }

    // RELAX_HistoryFix.cs.hlsl:38-41 -- per-pixel early out.
    // If the center pixel is sky / out of denoising range, or has enough history,
    // write the responsive (PONG) signal through and return.
    vec3 centerWorldPos = texelFetch(radiosity_position, tex_coord, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerWorldPos);
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length, tex_coord, 0));

    if (centerViewZ > ph_nrd_denoising_range ||
        historyLength > ph_nrd_history_fix_frame_num ||
        ph_nrd_history_fix_frame_num == 1.0)
    {
        // Reference returns without writing; in our MRT model we must explicitly
        // output the responsive (PONG) value to preserve it.
        nrd_diff_pong_fixed_out = texelFetch(nrd_diff_illum_pong, tex_coord, 0);
        nrd_spec_pong_fixed_out = texelFetch(nrd_spec_illum_pong, tex_coord, 0);
        return;
    }

    // RELAX_HistoryFix.cs.hlsl:44-50 -- load center data
    vec3 centerGeomNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerNormal = nrd_select_surface_normal(
        centerGeomNormal,
        texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz
    );
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);
    // roughness stored in .r channel of material texture
    float centerRoughness = centerMaterial.r;
    // view vector from surface toward camera (perspective: centerV = -normalize(X))
    vec3 centerV = -normalize(centerWorldPos - world_camera_position);
    // depthThreshold = gDepthThreshold * centerViewZ (perspective mode, gOrthoMode == 0)
    // RELAX_HistoryFix.cs.hlsl:50
    float depthThreshold = ph_nrd_depth_threshold * centerViewZ;

    // RELAX_HistoryFix.cs.hlsl:52-58 -- init diffuse accumulator with center pixel
    vec4 diffuseIllumSum = texelFetch(nrd_diff_illum_ping, tex_coord, 0);
    float diffuseWSum = 1.0;

    // RELAX_HistoryFix.cs.hlsl:59-72 -- init specular accumulator + specular normal weight params
    vec4 specularIllumSum = texelFetch(nrd_spec_illum_ping, tex_coord, 0);
    float specularWSum = 1.0;
    // GetNormalWeightParams_ATrous with history=5.0, confidence=1.0, relaxation=0.0
    // (hard-coded per reference lines 66-71: history fix always uses these fixed values)
    vec2 specularNormalWeightParams = nrd_spec_normal_weight_params_atrous(
        centerRoughness,
        5.0,  // numFramesInHistory -- hard-coded per reference
        1.0,  // specReprojConfidence -- hard-coded per reference
        0.0,  // normalEdgeStoppingRelaxation -- hard-coded per reference
        ph_nrd_lobe_angle_fraction,
        ph_nrd_spec_lobe_angle_slack
    );

    // RELAX_HistoryFix.cs.hlsl:75-77 -- stride computation
    // r = round(baseStride / (1 + historyLength)); reference allows r=0 but the
    // early-out on line 40 handles all pixels where historyLength is large enough
    // for the stride to degenerate.
    float r = round(ph_nrd_history_fix_base_stride / (1.0 + historyLength));

    ivec2 texSize = textureSize(nrd_diff_illum_ping, 0);

    // RELAX_HistoryFix.cs.hlsl:79-144 -- 5x5 sparse cross-bilateral filter, skip center
    for (int j = -2; j <= 2; j++) {
        for (int i = -2; i <= 2; i++) {
            if (i == 0 && j == 0) {
                continue;
            }

            ivec2 samplePosInt = tex_coord + ivec2(i, j) * int(r);

            // RELAX_HistoryFix.cs.hlsl:91-93 -- mirror OOB taps back into screen
            vec2 uv = (vec2(samplePosInt) + 0.5) / vec2(texSize);
            uv = nrd_mirror_uv(uv);
            samplePosInt = ivec2(uv * vec2(texSize));

            vec3 sampleGeomNormal = nrd_safe_normal(texelFetch(radiosity_normal, samplePosInt, 0).xyz);
            vec3 sampleNormal = nrd_select_surface_normal(
                sampleGeomNormal,
                texelFetch(radiosity_mapped_normal, samplePosInt, 0).xyz
            );
            vec4 sampleMaterial = texelFetch(radiosity_material, samplePosInt, 0);
            vec3 sampleWorldPos = texelFetch(radiosity_position, samplePosInt, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(sampleWorldPos);

            // RELAX_HistoryFix.cs.hlsl:101-102 -- geometry weight + denoising range gate
            float geometryWeight = nrd_plane_distance_weight(
                centerWorldPos, centerNormal, sampleWorldPos, depthThreshold
            );
            // IsInDenoisingRange(sampleViewZ): zero weight for sky / far-field taps
            geometryWeight = (sampleViewZ < ph_nrd_denoising_range) ? geometryWeight : 0.0;

            // RELAX_HistoryFix.cs.hlsl:104-119 -- diffuse tap accumulation
            {
                float diffuseW = geometryWeight;
                diffuseW *= getDiffuseNormalWeight(centerNormal, sampleNormal);
                diffuseW *= nrd_material_weight(centerMaterial, sampleMaterial);

                if (diffuseW > 1e-4) {
                    vec4 sampleDiffuse = texelFetch(nrd_diff_illum_ping, samplePosInt, 0);
                    diffuseIllumSum += sampleDiffuse * diffuseW;
                    diffuseWSum += diffuseW;
                }
            }

            // RELAX_HistoryFix.cs.hlsl:121-142 -- specular tap accumulation
            {
                // RELAX_HistoryFix.cs.hlsl:124-125: bias sample view vector toward center
                // by adding gRoughnessEdgeStoppingRelaxation * centerWorldPos (world-space).
                // This relaxes view-direction-based rejection for rough specular.
                vec3 sampleV = -normalize(
                    (sampleWorldPos - world_camera_position) +
                    ph_nrd_roughness_edge_stopping_relaxation * (centerWorldPos - world_camera_position)
                );

                float specularW = geometryWeight;
                specularW *= nrd_spec_normal_weight_atrous_full(
                    specularNormalWeightParams, centerNormal, sampleNormal, centerV, sampleV
                );
                specularW *= nrd_material_weight(centerMaterial, sampleMaterial);

                if (specularW > 1e-4) {
                    vec4 sampleSpecular = texelFetch(nrd_spec_illum_ping, samplePosInt, 0);
                    specularIllumSum += sampleSpecular * specularW;
                    specularWSum += specularW;
                }
            }
        }
    }

    // RELAX_HistoryFix.cs.hlsl:148-162 -- write filtered result to PONG.
    // This replaces the responsive signal at disoccluded pixels with the
    // spatially-filtered slow signal, seeding the clamping pass with a
    // hole-free estimate.
    nrd_diff_pong_fixed_out = diffuseIllumSum / diffuseWSum;
    nrd_spec_pong_fixed_out = specularIllumSum / specularWSum;
}
