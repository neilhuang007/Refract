#file "/program/final.glsl"

#replace "#include "/lib/pipelineSettings.glsl""
#include "/lib/pipelineSettings.glsl"

uniform float ph_mod_oilify_enabled;
uniform float ph_mod_oilify_size;
uniform float ph_mod_oilify_sharpness;
uniform float ph_mod_oilify_scale;
uniform float ph_mod_oilify_tuning;
uniform float ph_mod_oilify_iterations;
uniform float ph_mod_oilify_depth_scaling;
uniform float ph_mod_oilify_stroke_strength;

const float PH_PI = 3.1415926536;
const float PH_GAUSSIAN_WEIGHTS[5] = float[5](0.095766, 0.303053, 0.20236, 0.303053, 0.095766);
const float PH_GAUSSIAN_OFFSETS[5] = float[5](-3.2979345488, -1.40919905099, 0.0, 1.40919905099, 3.2979345488);

vec3 phGetAnisotropyData(sampler2D tex, vec2 texCoord) {
	vec2 pixelSize = vec2(1.0 / viewWidth, 1.0 / viewHeight);
	vec3 center = texture2D(tex, texCoord).rgb * 255.0;
	vec3 dx = center * PH_GAUSSIAN_WEIGHTS[2];
	vec3 dy = dx;
	for (int i = 0; i < 5; i++) {
		if (i == 2) continue;
		float off = PH_GAUSSIAN_OFFSETS[i];
		dx += texture2D(tex, texCoord + vec2(pixelSize.x * off, 0.0)).rgb * PH_GAUSSIAN_WEIGHTS[i] * 255.0;
		dy += texture2D(tex, texCoord + vec2(0.0, pixelSize.y * off)).rgb * PH_GAUSSIAN_WEIGHTS[i] * 255.0;
	}
	vec3 gradX = dFdx(dx);
	vec3 gradY = dFdy(dy);
	float e = dot(gradX, gradX);
	float f = dot(gradX, gradY);
	float g = dot(gradY, gradY);
	float root = sqrt((e - g) * (e - g) + 4.0 * f * f);
	vec2 eigenvalues = vec2(e + g + root, e + g - root) * 0.5;
	vec2 t;
	if (abs(eigenvalues.x - e) > 1e-15 || abs(f) > 1e-15) {
		t = normalize(vec2(eigenvalues.x - e, -f));
	} else {
		t = vec2(1.0, 0.0);
	}
	float anisotropy = abs((eigenvalues.y - eigenvalues.x) / max(eigenvalues.x + eigenvalues.y, 1e-15));
	anisotropy *= anisotropy;
	anisotropy = clamp(anisotropy, 1e-15, 1.0);
	return vec3(t, anisotropy);
}

vec4 phOilifyKuwahara(sampler2D tex, vec2 texCoord, float sizeParam, vec3 anisotropyData, float adaptiveScale) {
	int oilifySize = int(clamp(sizeParam, 3.0, 15.0));
	float oilifyScale = clamp(adaptiveScale, 0.5, 16.0);
	float oilifyTuning = clamp(ph_mod_oilify_tuning, 0.0, 4.0);
	float oilifySharpness = clamp(ph_mod_oilify_sharpness, 0.0, 1.0);
	float sharpnessMultiplier = max(1023.0 * pow((2.0 * oilifySharpness / 3.0) + 0.333333, 4.0), 1e-10);
	vec3 sum[6];
	vec3 squaredSum[6];
	float sampleCount[6];
	for (int k = 0; k < 6; k++) {
		sum[k] = vec3(0.0);
		squaredSum[k] = vec3(0.0);
		sampleCount[k] = 0.0;
	}
	float radius = length(vec2(float(oilifySize) * 0.5, float(oilifySize) * 0.25));
	vec2 t = anisotropyData.xy;
	float anisotropy = anisotropyData.z;
	float tuning = exp2(oilifyTuning - 1.0);
	float tuningA = tuning / (anisotropy + tuning);
	float tuningB = (tuning + anisotropy) / tuning;
	vec2 pixelSize = vec2(1.0 / viewWidth, 1.0 / viewHeight);
	vec3 centerColor = texture2D(tex, texCoord).rgb * sharpnessMultiplier;
	for (int i = -(oilifySize / 2); i < ((oilifySize + 1) / 2); i++) {
		for (int j = -(oilifySize / 2); j < ((oilifySize + 1) / 2); j++) {
			vec2 offset = vec2(float(i), float(j));
			if ((abs(j) % 2) != 0) {
				offset.y -= 0.5;
			}
			if (i == 0 && j == 0) {
				for (int k = 0; k < 6; k++) {
					sum[k] += centerColor;
					squaredSum[k] += centerColor * centerColor;
					sampleCount[k] += 1.0;
				}
			} else if (length(offset) <= radius) {
				float angle = atan(offset.x, offset.y) + PH_PI;
				if (angle > 5.75958653158) {
					angle -= 2.0 * PH_PI;
				}
				float sectorOffset = (float((angle * 6.0) / PH_PI) + 1.0) * 0.5;
				int sector = int(floor(sectorOffset));
				offset *= pixelSize * oilifyScale;
				vec2 rotatedOffset = vec2(offset.x * t.x + offset.y * t.y, offset.x * -t.y + offset.y * t.x);
				offset = vec2(rotatedOffset.x * tuningA, rotatedOffset.y * tuningB);
				vec2 sampleUV = texCoord + offset;
				vec3 c = texture2D(tex, sampleUV).rgb * sharpnessMultiplier;
				sum[sector] += c;
				squaredSum[sector] += c * c;
				sampleCount[sector] += 1.0;
			}
		}
	}
	vec3 weightedSum = vec3(0.0);
	float weightSum = 0.0;
	float totalVariance = 0.0;
	for (int k = 0; k < 6; k++) {
		vec3 sumSquared = sum[k] * sum[k];
		vec3 mean = sum[k] / sampleCount[k];
		vec3 variance = squaredSum[k] - (sumSquared / sampleCount[k]);
		variance /= sampleCount[0];
		float varLum = dot(variance, vec3(0.299, 0.587, 0.114));
		totalVariance += varLum;
		float weight = 1.0 / (1.0 + pow(sqrt(max(varLum, 1e-5)), 8.0));
		weightedSum += mean * weight;
		weightSum += weight;
	}
	vec3 result = (weightedSum / weightSum) / sharpnessMultiplier;
	float edgeInfo = clamp(totalVariance / (6.0 * sharpnessMultiplier * sharpnessMultiplier), 0.0, 1.0);
	return vec4(result, edgeInfo);
}
#endreplace

#replace "    /* DRAWBUFFERS:0 */"
    if (ph_mod_oilify_enabled > 0.5) {
        float effectiveSize = clamp(ph_mod_oilify_size + max(floor(ph_mod_oilify_iterations + 0.5) - 1.0, 0.0), 3.0, 15.0);

        float depthAdapt = clamp(ph_mod_oilify_depth_scaling, 0.0, 2.0);
        float baseScale = clamp(ph_mod_oilify_scale, 1.0, 4.0);
        float adaptiveScale = baseScale;
        if (depthAdapt > 0.001) {
            float rawDepth = texture2D(depthtex0, texCoordM).r;
            float linDepth = GetLinearDepth(rawDepth);
            float depthFactor = clamp(0.03 / max(linDepth, 0.001), 1.0, 6.0);
            adaptiveScale = baseScale * mix(1.0, depthFactor, depthAdapt);
        }

        vec3 aniso = phGetAnisotropyData(colortex3, texCoordM);
        vec4 oilResult = phOilifyKuwahara(colortex3, texCoordM, effectiveSize, aniso, adaptiveScale);
        vec3 oilified = oilResult.rgb;
        float edgeInfo = oilResult.a;

        float strokeStr = clamp(ph_mod_oilify_stroke_strength, 0.0, 1.0);
        if (strokeStr > 0.001) {
            float edgeDarken = smoothstep(0.0, 0.15, edgeInfo) * strokeStr * 0.4;
            oilified *= 1.0 - edgeDarken;
            float canvas = texture2DLod(noisetex, texCoordM * vec2(viewWidth, viewHeight) / 128.0, 0.0).r;
            oilified += (canvas - 0.5) * strokeStr * 0.02;
        }

        color = oilified;
    }

    /* DRAWBUFFERS:0 */
#endreplace
