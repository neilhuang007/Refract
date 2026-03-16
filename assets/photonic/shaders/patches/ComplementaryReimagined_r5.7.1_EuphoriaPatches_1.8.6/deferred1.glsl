#file "/program/deferred1.glsl"

#replace "const bool colortex0MipmapEnabled = true;"
const bool colortex0MipmapEnabled = true;

uniform sampler2D radiosity_handheld;
uniform sampler2D radiosity_direct;
uniform sampler2D radiosity_direct_soft;
uniform sampler2D colortex10;
uniform sampler2D colortex12;
uniform float ph_debug_lighting_master_scale;
uniform float ph_debug_cast_light_threshold;
uniform float ph_mod_pixelation_debug_enabled;
#endreplace

#replace "vec4 color = vec4(albedoTextureSample.rgb, 1.0);"
vec4 color = vec4(albedoTextureSample.rgb, 1.0);
float z0ph = texelFetch(depthtex0, texelCoord, 0).r;
if (z0ph < 0.99999) {
	vec4 castDirectSoft = texelFetch(radiosity_direct_soft, texelCoord, 0);
	vec3 baseDirect = texelFetch(radiosity_handheld, texelCoord, 0).rgb;
	#if PH_LIGHTING_MODE >= 2
	baseDirect += texelFetch(radiosity_direct, texelCoord, 0).rgb;
	#else
	baseDirect += texelFetch(radiosity_direct, texelCoord, 0).rgb
		+ castDirectSoft.rgb / max(castDirectSoft.a, 1.0);
	#endif
	vec3 pixelatedDirect = baseDirect;
	// Upstream shadow pixelation already applied in ph_lighting.glsl.
	pixelatedDirect = baseDirect;
	if (ph_mod_pixelation_debug_enabled > 0.5) {
		color.rgb = pixelatedDirect;
	} else {
		vec3 centerIndirect = texelFetch(colortex12, texelCoord, 0).rgb * 0.15;
		float pixelatedStrength = max(pixelatedDirect.r, max(pixelatedDirect.g, pixelatedDirect.b));
		float indirectStrength = max(centerIndirect.r, max(centerIndirect.g, centerIndirect.b));
		float threshold = max(ph_debug_cast_light_threshold, 0.0);
		// Let stable GI open the composite gate too; otherwise indirect-only
		// surfaces disappear and only bright direct-light spots remain visible.
		float lightingGate = threshold > 0.0
			? smoothstep(0.25 * threshold, 2.0 * threshold, max(pixelatedStrength, indirectStrength))
			: 1.0;
		vec3 photonicsAlbedo = texelFetch(colortex10, texelCoord, 0).rgb;
		if (any(isnan(photonicsAlbedo)) || any(isinf(photonicsAlbedo))) {
			photonicsAlbedo = vec3(0.0);
		}
		photonicsAlbedo = clamp(photonicsAlbedo, vec3(0.0), vec3(1.0));
		if ((photonicsAlbedo.r > 0.0 || photonicsAlbedo.g > 0.0 || photonicsAlbedo.b > 0.0) && lightingGate > 0.0) {
			vec3 photonicsLighting = max(centerIndirect + pixelatedDirect, vec3(0.0));
			if (any(isnan(photonicsLighting)) || any(isinf(photonicsLighting))) {
				photonicsLighting = vec3(0.0);
			}
			photonicsLighting = min(photonicsLighting, vec3(5.0));
			photonicsLighting *= clamp(ph_debug_lighting_master_scale, 0.0, 4.0) * lightingGate;
			color.rgb += photonicsLighting * photonicsAlbedo;
		}
	}
}
#endreplace
