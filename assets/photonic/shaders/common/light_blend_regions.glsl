#ifndef PH_DIRTY_REGION_DEFINED
#define PH_DIRTY_REGION_DEFINED

uniform float light_blend_factor;
uniform int light_blend_region_count;
uniform vec3 light_blend_min;
uniform vec3 light_blend_max;
uniform vec3 light_blend_min_1;
uniform vec3 light_blend_max_1;
uniform vec3 light_blend_min_2;
uniform vec3 light_blend_max_2;
uniform vec3 light_blend_min_3;
uniform vec3 light_blend_max_3;
uniform vec3 light_blend_min_4;
uniform vec3 light_blend_max_4;
uniform vec3 light_blend_min_5;
uniform vec3 light_blend_max_5;
uniform vec3 light_blend_min_6;
uniform vec3 light_blend_max_6;
uniform vec3 light_blend_min_7;
uniform vec3 light_blend_max_7;

bool ph_dirty_region_contains(vec3 worldPosition, vec3 regionMin, vec3 regionMax) {
    bvec3 insideMin = greaterThanEqual(worldPosition, regionMin);
    bvec3 insideMax = lessThan(worldPosition, regionMax);
    return all(insideMin) && all(insideMax);
}

uint ph_dirty_region_mask(vec3 worldPosition) {
    if (light_blend_region_count <= 0) return 0u;

    uint mask = 0u;
    if (ph_dirty_region_contains(worldPosition, light_blend_min, light_blend_max)) mask |= 1u;
    if (light_blend_region_count > 1 && ph_dirty_region_contains(worldPosition, light_blend_min_1, light_blend_max_1)) mask |= (1u << 1);
    if (light_blend_region_count > 2 && ph_dirty_region_contains(worldPosition, light_blend_min_2, light_blend_max_2)) mask |= (1u << 2);
    if (light_blend_region_count > 3 && ph_dirty_region_contains(worldPosition, light_blend_min_3, light_blend_max_3)) mask |= (1u << 3);
    if (light_blend_region_count > 4 && ph_dirty_region_contains(worldPosition, light_blend_min_4, light_blend_max_4)) mask |= (1u << 4);
    if (light_blend_region_count > 5 && ph_dirty_region_contains(worldPosition, light_blend_min_5, light_blend_max_5)) mask |= (1u << 5);
    if (light_blend_region_count > 6 && ph_dirty_region_contains(worldPosition, light_blend_min_6, light_blend_max_6)) mask |= (1u << 6);
    if (light_blend_region_count > 7 && ph_dirty_region_contains(worldPosition, light_blend_min_7, light_blend_max_7)) mask |= (1u << 7);
    return mask;
}

float ph_dirty_region_factor(vec3 worldPosition) {
    if (light_blend_factor <= 0.0f) return 0.0f;
    return ph_dirty_region_mask(worldPosition) != 0u ? light_blend_factor : 0.0f;
}

bool ph_dirty_region_signature_matches(vec3 aWorldPosition, vec3 bWorldPosition) {
    if (light_blend_factor <= 0.0f || light_blend_region_count <= 0) {
        return true;
    }

    return ph_dirty_region_mask(aWorldPosition) == ph_dirty_region_mask(bWorldPosition);
}

#endif
