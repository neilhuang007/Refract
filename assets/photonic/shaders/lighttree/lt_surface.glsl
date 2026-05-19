#ifndef PHOTONICS_LT_SURFACE_GLSL
#define PHOTONICS_LT_SURFACE_GLSL

// ---------------------------------------------------------------------------
// RAB_Surface struct, surface factory overloads, and load helpers.
// Consumer requirements:
//   - lt_material.glsl MUST be included before this file — RAB_Material is
//     used as a struct field and parameter type.
//   - Uniforms: world_offset, world_camera_position,
//     previous_world_camera_position, world_pos, block_normal, normal,
//     albedo, tex_coord, viewWidth, viewHeight, modelview_projection
//     (provided by /photonics/common/header.glsl and /photonics/photonics.glsl).
//   - lt_resolve_reuse_normal — defined in reuse_bridge.glsl above the
//     include site.
//   - Sampler bindings: radiosity_position, radiosity_normal,
//     radiosity_mapped_normal, radiosity_albedo, radiosity_material and the
//     prev_radiosity_* counterparts (from lt_samplers.glsl or photonics.glsl).
//   - ph_linear_view_depth helper.
// No #include directives are needed inside this file.
// ---------------------------------------------------------------------------

const float BACKGROUND_DEPTH = 0.0f;

struct RAB_Surface {
    vec3 worldPos;
    vec3 viewDir;
    vec3 normal;
    vec3 geoNormal;
    float viewDepth;
    float diffuseProbability;
    RAB_Material material;
};

RAB_Surface lt_load_surface(ivec2 uv);
RAB_Surface lt_load_previous_surface(ivec2 uv);
RAB_Surface RAB_EmptySurface();
bool lt_materials_similar(RAB_Surface a, RAB_Surface b);
bool lt_is_complex_surface(RAB_Surface surface);

vec3 lt_surface_rt_pos(RAB_Surface surface) {
    return surface.worldPos - world_offset;
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, RAB_Material materialValue, vec3 cameraWorldPosition, float linearDepthValue) {
    vec3 resolvedGeoNormal = lt_resolve_reuse_normal(geoNormalValue, geoNormalValue);
    vec3 resolvedShadingNormal = lt_resolve_reuse_normal(geoNormalValue, shadingNormalValue);
    vec3 viewDir = cameraWorldPosition - worldPosValue;
    float viewDirLengthSq = dot(viewDir, viewDir);
    viewDir = (viewDirLengthSq > 1e-6f) ? (viewDir * inversesqrt(viewDirLengthSq)) : vec3(0.0f, 0.0f, 1.0f);
    materialValue.diffuseAlbedo = clamp(albedoValue, vec3(0.0f), vec3(1.0f));
    materialValue.specularF0 = clamp(materialValue.specularF0, vec3(0.0f), vec3(1.0f));

    return RAB_Surface(
        worldPosValue,
        viewDir,
        resolvedShadingNormal,
        resolvedGeoNormal,
        linearDepthValue,
        lt_material_diffuse_probability_with_view(materialValue, resolvedShadingNormal, viewDir),
        materialValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, RAB_Material materialValue, float linearDepthValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        materialValue,
        world_camera_position,
        linearDepthValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, RAB_Material materialValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        materialValue,
        ph_linear_view_depth(modelview_projection, worldPosValue)
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec4 materialValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        vec3(1.0f),
        lt_make_material(materialValue, vec3(1.0f))
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, vec4 materialValue, vec3 cameraWorldPosition, float linearDepthValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        lt_make_material(materialValue, albedoValue),
        cameraWorldPosition,
        linearDepthValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, vec4 materialValue, float linearDepthValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        lt_make_material(materialValue, albedoValue),
        linearDepthValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue) {
    return lt_make_surface(worldPosValue, geoNormalValue, shadingNormalValue, vec3(1.0f), RAB_EmptyMaterial());
}

// RTXDI: RAB_EmptySurface() -- returns a zeroed surface with a well-defined up-normal.
// Used to initialize temporalSurface before a valid temporal neighbor is found,
// matching RTXDI TemporalResampling.hlsli line 69: RAB_Surface temporalSurface = RAB_EmptySurface();
RAB_Surface lt_empty_surface() {
    return RAB_Surface(
        vec3(0.0f),
        vec3(0.0f),
        vec3(0.0f),
        vec3(0.0f),
        BACKGROUND_DEPTH,
        0.0f,
        RAB_EmptyMaterial()
    );
}

RAB_Surface lt_current_surface() {
    return lt_make_surface(
        world_pos,
        block_normal,
        normal,
        clamp(albedo, vec3(0.04f), vec3(1.0f)),
        lt_extract_material_at_uv((vec2(tex_coord) + vec2(0.5f)) / vec2(viewWidth, viewHeight)),
        ph_linear_view_depth(modelview_projection, world_pos)
    );
}

RAB_Surface lt_load_surface(ivec2 uv) {
    vec4 positionData = texelFetch(radiosity_position, uv, 0);
    if (positionData.w == BACKGROUND_DEPTH) {
        return RAB_EmptySurface();
    }
    return lt_make_surface(
        positionData.xyz,
        texelFetch(radiosity_normal, uv, 0).xyz,
        texelFetch(radiosity_mapped_normal, uv, 0).xyz,
        clamp(texelFetch(radiosity_albedo, uv, 0).rgb, vec3(0.04f), vec3(1.0f)),
        texelFetch(radiosity_material, uv, 0),
        positionData.w
    );
}

RAB_Surface lt_load_previous_surface(ivec2 uv) {
    vec4 positionData = texelFetch(prev_radiosity_position, uv, 0);
    if (positionData.w == BACKGROUND_DEPTH) {
        return RAB_EmptySurface();
    }
    return lt_make_surface(
        positionData.xyz,
        texelFetch(prev_radiosity_normal, uv, 0).xyz,
        texelFetch(prev_radiosity_mapped_normal, uv, 0).xyz,
        clamp(texelFetch(prev_radiosity_albedo, uv, 0).rgb, vec3(0.04f), vec3(1.0f)),
        texelFetch(prev_radiosity_material, uv, 0),
        previous_world_camera_position,
        positionData.w
    );
}

float rtxdi_surface_linear_depth(RAB_Surface surface, mat4 modelViewProjection) {
    return surface.viewDepth;
}

bool RAB_IsSurfaceValid(RAB_Surface surface);
vec3 RAB_GetSurfaceNormal(RAB_Surface surface);
float RAB_GetSurfaceLinearDepth(RAB_Surface surface);
RAB_Material RAB_GetMaterial(RAB_Surface surface);

#endif // PHOTONICS_LT_SURFACE_GLSL
