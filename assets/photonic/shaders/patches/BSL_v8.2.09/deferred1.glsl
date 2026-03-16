#file "/program/deferred1.glsl"

#replace "#ifdef FSH"
#ifdef FSH
uniform sampler2D radiosity_handheld;
uniform sampler2D radiosity_direct;
uniform sampler2D radiosity_direct_soft;
uniform sampler2D colortex10;
uniform sampler2D colortex12;
uniform float ph_mod_oilify_enabled;
#endreplace

#replace "vec4 color = texture2D(colortex0, texCoord);"
vec4 color = texture2D(colortex0, texCoord);
vec4 direct = texture2D(radiosity_direct, texCoord);
vec4 direct_soft = texture2D(radiosity_direct_soft, texCoord);
color.xyz += (
    texture2D(colortex12, texCoord).xyz + // indirect
    texture2D(radiosity_handheld, texCoord).xyz +
    #if PH_LIGHTING_MODE >= 2
    direct.xyz
    #else
    direct.xyz + direct_soft.xyz / max(direct_soft.w, 1.0f)
    #endif
) * texture2D(colortex10, texCoord).xyz; // albedo
if (ph_mod_oilify_enabled > 0.5) {
    const int PH_OIL_RADIUS = 3;
    const float PH_OIL_PI = 3.1415926536;
    vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);
    vec3 oilSum[4];
    vec3 oilSqSum[4];
    float oilCount[4];
    for (int k = 0; k < 4; k++) {
        oilSum[k] = vec3(0.0);
        oilSqSum[k] = vec3(0.0);
        oilCount[k] = 0.0;
    }
    for (int oi = -PH_OIL_RADIUS; oi <= PH_OIL_RADIUS; oi++) {
        for (int oj = -PH_OIL_RADIUS; oj <= PH_OIL_RADIUS; oj++) {
            vec2 sampleUV = texCoord + vec2(float(oi), float(oj)) * pixelSize;
            sampleUV = clamp(sampleUV, vec2(0.0), vec2(1.0));
            vec3 c = texture2D(colortex0, sampleUV).rgb;
            float angle = atan(float(oj), float(oi)) + PH_OIL_PI;
            int sector = int(mod(angle * 2.0 / PH_OIL_PI, 4.0));
            sector = clamp(sector, 0, 3);
            oilSum[sector] += c;
            oilSqSum[sector] += c * c;
            oilCount[sector] += 1.0;
        }
    }
    vec3 oilWeightedSum = vec3(0.0);
    float oilWeightSum = 0.0;
    for (int k = 0; k < 4; k++) {
        if (oilCount[k] < 1.0) continue;
        vec3 mean = oilSum[k] / oilCount[k];
        vec3 variance = oilSqSum[k] / oilCount[k] - mean * mean;
        float v = dot(variance, vec3(0.299, 0.587, 0.114));
        float w = 1.0 / (1.0 + v * 1000.0);
        oilWeightedSum += mean * w;
        oilWeightSum += w;
    }
    if (oilWeightSum > 0.0) {
        color.rgb = oilWeightedSum / oilWeightSum;
    }
}
#endreplace
