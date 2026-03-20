#ifndef PHOTONICS_NRD_MATERIAL_ID_GLSL
#define PHOTONICS_NRD_MATERIAL_ID_GLSL

const float NRD_MATERIAL_ID_DISABLED = 0.0;

float nrd_derive_material_id(vec4 specularData) {
    return NRD_MATERIAL_ID_DISABLED;
}

bool nrd_compare_materials(float materialId0, float materialId1) {
    return true;
}

float nrd_encode_material_id(float materialId) {
    return clamp(materialId / 3.0, 0.0, 1.0);
}

float nrd_decode_material_id(float encoded) {
    return encoded * 3.0;
}

#endif
