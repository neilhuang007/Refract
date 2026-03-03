#file "/program/gbuffers_block.glsl"

#replace "float smoothnessG = 0.0, highlightMult = 1.0, emission = 0.0, noiseFactor = 1.0;"
float smoothnessG = 0.0, highlightMult = 1.0, emission = 0.0, noiseFactor = 1.0;
vec3 oldAlbedo = vec3(0.0);
float phPixelCenterFactor = 1.0;
#endreplace

#replace "DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,"
oldAlbedo = color.rgb;
float phPixelLightmapY = clamp(lmCoordM.y, 0.0, 1.0);
float phPixelLightmapYM = phPixelLightmapY * phPixelLightmapY * (3.0 - 2.0 * phPixelLightmapY);
phPixelCenterFactor = clamp(max(glColor.a, phPixelLightmapYM), 0.0, 1.0);
DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,
#endreplace

#replace "/* DRAWBUFFERS:036 */"
/* RENDERTARGETS:0,3,6,10,11,13 */
#endreplace

#replace "gl_FragData[2] = vec4(smoothnessD, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));"
gl_FragData[2] = vec4(smoothnessD, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));
gl_FragData[3] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[4] = vec4(0.5 * geoNormal + 0.5, 0.0);
gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0364 */"
/* RENDERTARGETS:0,3,6,4,10,11,13 */
#endreplace

#replace "gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);"
gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);
gl_FragData[4] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[5] = vec4(0.5 * geoNormal + 0.5, 0.0);
gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:03649 */"
/* RENDERTARGETS:0,3,6,4,9,10,11,13 */
#endreplace

#replace "gl_FragData[4] = vec4(lightAlbedo, 0.0);"
gl_FragData[4] = vec4(lightAlbedo, 0.0);
gl_FragData[5] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[6] = vec4(0.5 * geoNormal + 0.5, 0.0);
gl_FragData[7] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0369 */"
/* RENDERTARGETS:0,3,6,9,10,11,13 */
#endreplace

#replace "gl_FragData[3] = vec4(lightAlbedo, 0.0);"
gl_FragData[3] = vec4(lightAlbedo, 0.0);
gl_FragData[4] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[5] = vec4(0.5 * geoNormal + 0.5, 0.0);
gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace
