#file "/program/gbuffers_entities.glsl"

#replace "vec3 normalM = normal, shadowMult = vec3(1.0);"
vec3 normalM = normal, shadowMult = vec3(1.0);
vec3 oldAlbedo = vec3(0.0);
float phPixelCenterFactor = 1.0;
float phPixelLightmapYM = 1.0;
#endreplace

#replace "DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,"
oldAlbedo = color.rgb;
float phPixelLightmapY = clamp(lmCoordM.y, 0.0, 1.0);
phPixelLightmapYM = phPixelLightmapY * phPixelLightmapY * (3.0 - 2.0 * phPixelLightmapY);
phPixelCenterFactor = clamp(max(glColor.a, phPixelLightmapYM), 0.0, 1.0);
DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,
#endreplace

#replace "/* DRAWBUFFERS:036 */"
/* RENDERTARGETS:0,3,6,10,11,13 */
#endreplace

#replace "gl_FragData[2] = vec4(smoothnessD, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emissionOld));"
gl_FragData[2] = vec4(smoothnessD, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emissionOld));
gl_FragData[3] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[4] = vec4(0.5 * normalM + 0.5, entityId == 50076 ? (0.9 + 0.1 * phPixelLightmapYM) : (0.76 + 0.08 * phPixelLightmapYM));
gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0364 */"
/* RENDERTARGETS:0,3,6,4,10,11,13 */
#endreplace

#replace "gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);"
gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);
gl_FragData[4] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[5] = vec4(0.5 * normalM + 0.5, entityId == 50076 ? (0.9 + 0.1 * phPixelLightmapYM) : (0.76 + 0.08 * phPixelLightmapYM));
gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:03649 */"
/* RENDERTARGETS:0,3,6,4,9,10,11,13 */
#endreplace

#replace "gl_FragData[4] = vec4(lightAlbedo, entitySSBLMask);"
gl_FragData[4] = vec4(lightAlbedo, entitySSBLMask);
gl_FragData[5] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[6] = vec4(0.5 * normalM + 0.5, entityId == 50076 ? (0.9 + 0.1 * phPixelLightmapYM) : (0.76 + 0.08 * phPixelLightmapYM));
gl_FragData[7] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0369 */"
/* RENDERTARGETS:0,3,6,9,10,11,13 */
#endreplace

#replace "gl_FragData[3] = vec4(lightAlbedo, entitySSBLMask);"
gl_FragData[3] = vec4(lightAlbedo, entitySSBLMask);
gl_FragData[4] = vec4(oldAlbedo, phPixelCenterFactor);
gl_FragData[5] = vec4(0.5 * normalM + 0.5, entityId == 50076 ? (0.9 + 0.1 * phPixelLightmapYM) : (0.76 + 0.08 * phPixelLightmapYM));
gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace
