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
	if (ph_mod_pixelation_debug_enabled > 0.5) {
		color.rgb = baseDirect;
	} else {
		// Composite the resolved RT lighting directly; do not gate or downscale it.
		vec3 photonicsLighting = texelFetch(colortex12, texelCoord, 0).rgb + baseDirect;
		color.rgb += photonicsLighting
			* texelFetch(colortex10, texelCoord, 0).rgb
			* clamp(ph_debug_lighting_master_scale, 0.0, 4.0);
	}
}
#endreplace
