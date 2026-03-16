#ifndef PH_NRD_COMMON_INCLUDE
#define PH_NRD_COMMON_INCLUDE

float nrd_luminance(vec3 color) {
    return dot(color, vec3(0.2126f, 0.7152f, 0.0722f));
}

vec3 nrd_rgb_to_ycocg(vec3 color) {
    float co = color.r - color.b;
    float temp = color.b + co * 0.5f;
    float cg = color.g - temp;
    float y = temp + cg * 0.5f;
    return vec3(y, co, cg);
}

vec3 nrd_ycocg_to_rgb(vec3 ycocg) {
    float temp = ycocg.x - ycocg.z * 0.5f;
    float g = ycocg.z + temp;
    float b = temp - ycocg.y * 0.5f;
    float r = ycocg.y + b;
    return vec3(r, g, b);
}

float nrd_get_plane_distance_weight(
    vec3 centerPos,
    vec3 centerNormal,
    float centerViewZ,
    vec3 samplePos,
    float threshold
) {
    float safeViewZ = max(abs(centerViewZ), 1e-4f);
    float safeThreshold = max(threshold, 1e-4f);
    float planeDistance = abs(dot(samplePos - centerPos, centerNormal));
    float normalizedDistance = planeDistance / safeViewZ;
    return 1.0f - clamp(normalizedDistance / safeThreshold, 0.0f, 1.0f);
}

#endif
