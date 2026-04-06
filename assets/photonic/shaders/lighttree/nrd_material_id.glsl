#ifndef PHOTONICS_NRD_MATERIAL_ID_GLSL
#define PHOTONICS_NRD_MATERIAL_ID_GLSL

const float NRD_MATERIAL_ID_DISABLED = 0.0;

float nrd_derive_material_id(vec4 specularData) {
    float smoothness = specularData.r;
    float metallic = specularData.g;
    float emission = specularData.a;
    float roughness = clamp(1.0 - smoothness, 0.0, 1.0);

    if (emission > 0.1) return 2.0;
    if (metallic > 0.5 && roughness < 0.3) return 1.0;
    return 3.0;
}

float nrd_encode_material_id(float materialId) {
    return clamp(materialId / 3.0, 0.0, 1.0);
}

vec4 nrd_pack_surface_material(vec4 specularData) {
    float smoothness = clamp(specularData.r, 0.0, 1.0);
    float roughness = clamp(1.0 - smoothness, 0.0, 1.0);
    float metallic = clamp(specularData.g, 0.0, 1.0);
    float emission = clamp(specularData.a, 0.0, 1.0);
    return vec4(roughness, metallic, emission, nrd_encode_material_id(nrd_derive_material_id(specularData)));
}

bool nrd_compare_materials(float materialId0, float materialId1) {
    return abs(materialId0 - materialId1) < 0.5;
}

float nrd_decode_material_id(float encoded) {
    return encoded * 3.0;
}

#endif
