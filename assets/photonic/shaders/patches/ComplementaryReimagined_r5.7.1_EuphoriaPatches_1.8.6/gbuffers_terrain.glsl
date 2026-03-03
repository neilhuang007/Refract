#file "/program/gbuffers_terrain.glsl"

#replace "vec3 normalM = normal, geoNormal = normal, shadowMult = vec3(1.0);"
vec3 normalM = normal, geoNormal = normal, shadowMult = vec3(1.0);
vec3 oldAlbedo = vec3(0.0);
float phPixelCenterFactor = 1.0;
float phPixelLightmapYM = 1.0;
#endreplace

#replace "DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, dither,"
oldAlbedo = color.rgb;
float phPixelLightmapY = clamp(lmCoordM.y, 0.0, 1.0);
phPixelLightmapYM = phPixelLightmapY * phPixelLightmapY * (3.0 - 2.0 * phPixelLightmapY);
phPixelCenterFactor = clamp(max(glColor.a, phPixelLightmapYM), 0.0, 1.0);
DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, dither,
#endreplace

#replace "/* DRAWBUFFERS:06 */"
/* RENDERTARGETS:0,6,10,11,13 */
#endreplace

#replace "gl_FragData[1] = vec4(smoothnessD, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));"
gl_FragData[1] = vec4(smoothnessD, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));
gl_FragData[2] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[3] = vec4(0.5 * geoNormal + 0.5, subsurfaceMode == 1 ? (0.25 + 0.5 * phPixelLightmapYM) : (centerShadowBias ? (0.76 + 0.08 * phPixelLightmapYM) : 0.0));
gl_FragData[4] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:064 */"
/* RENDERTARGETS:0,6,4,10,11,13 */
#endreplace

#replace "gl_FragData[2] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);"
gl_FragData[2] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);
gl_FragData[3] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[4] = vec4(0.5 * geoNormal + 0.5, subsurfaceMode == 1 ? (0.25 + 0.5 * phPixelLightmapYM) : (centerShadowBias ? (0.76 + 0.08 * phPixelLightmapYM) : 0.0));
gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0649 */"
/* RENDERTARGETS:0,6,4,9,10,11,13 */
#endreplace

#replace "gl_FragData[3] = vec4(lightAlbedo, 0.0);"
gl_FragData[3] = vec4(lightAlbedo, 0.0);
gl_FragData[4] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[5] = vec4(0.5 * geoNormal + 0.5, subsurfaceMode == 1 ? (0.25 + 0.5 * phPixelLightmapYM) : (centerShadowBias ? (0.76 + 0.08 * phPixelLightmapYM) : 0.0));
gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:069 */"
/* RENDERTARGETS:0,6,9,10,11,13 */
#endreplace

#replace "gl_FragData[2] = vec4(lightAlbedo, 0.0);"
gl_FragData[2] = vec4(lightAlbedo, 0.0);
gl_FragData[3] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[4] = vec4(0.5 * geoNormal + 0.5, subsurfaceMode == 1 ? (0.25 + 0.5 * phPixelLightmapYM) : (centerShadowBias ? (0.76 + 0.08 * phPixelLightmapYM) : 0.0));
gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace
