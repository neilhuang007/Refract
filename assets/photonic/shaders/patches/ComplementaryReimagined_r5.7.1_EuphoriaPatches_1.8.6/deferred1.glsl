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
// Apply Photonics lighting to all in-world fragments, including near geometry.
if (z0ph < 0.99999) {
	vec4 castDirectSoft = texelFetch(radiosity_direct_soft, texelCoord, 0);
	vec3 baseDirect = texelFetch(radiosity_handheld, texelCoord, 0).rgb
		+ texelFetch(radiosity_direct, texelCoord, 0).rgb
		+ castDirectSoft.rgb / max(castDirectSoft.a, 1.0);
	vec3 pixelatedDirect = baseDirect;
	// Upstream shadow pixelation already applied in ph_lighting.glsl.
	pixelatedDirect = baseDirect;
	if (ph_mod_pixelation_debug_enabled > 0.5) {
		color.rgb = pixelatedDirect;
	} else {
		vec3 positiveDirect = max(pixelatedDirect, vec3(0.0));
		float pixelatedLuminance = dot(positiveDirect, vec3(0.2126, 0.7152, 0.0722));
		float threshold = max(ph_debug_cast_light_threshold, 0.0);
		float lightingGate = threshold > 0.0 ? smoothstep(0.25 * threshold, 2.0 * threshold, pixelatedLuminance) : 1.0;
		pixelatedDirect = positiveDirect;
		vec3 photonicsAlbedo = texelFetch(colortex10, texelCoord, 0).rgb;
		if (any(isnan(photonicsAlbedo)) || any(isinf(photonicsAlbedo))) {
			photonicsAlbedo = vec3(0.0);
		}
		photonicsAlbedo = clamp(photonicsAlbedo, vec3(0.0), vec3(1.0));
		if ((photonicsAlbedo.r > 0.0 || photonicsAlbedo.g > 0.0 || photonicsAlbedo.b > 0.0) && lightingGate > 0.0) {
			vec3 centerIndirect = texelFetch(colortex12, texelCoord, 0).rgb * 0.15;
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
