#file "/program/gbuffers_hand.glsl"

#replace "vec3 normalM = normal, shadowMult = vec3(0.5); // Reduced shadowMult for held items to not get too bright"
vec3 normalM = normal, shadowMult = vec3(0.5); // Reduced shadowMult for held items to not get too bright
vec3 oldAlbedo = vec3(0.0);
#endreplace

#replace "DoLighting(color, shadowMult, playerPos, viewPos, 0.0, geoNormal, normalM, 0.5,"
oldAlbedo = color.rgb;
DoLighting(color, shadowMult, playerPos, viewPos, 0.0, geoNormal, normalM, 0.5,
#endreplace

#replace "/* DRAWBUFFERS:06 */"
/* RENDERTARGETS:0,6,10,11,13 */
#endreplace

#replace "gl_FragData[1] = vec4(smoothnessD, materialMask, skyLightFactor, purkinjeData);"
gl_FragData[1] = vec4(smoothnessD, materialMask, skyLightFactor, purkinjeData);
gl_FragData[2] = vec4(oldAlbedo, 1.0);
gl_FragData[3] = vec4(0.5 * normalM + 0.5, 0.0);
gl_FragData[4] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:064 */"
/* RENDERTARGETS:0,6,4,10,11,13 */
#endreplace

#replace "gl_FragData[2] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);"
gl_FragData[2] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);
gl_FragData[3] = vec4(oldAlbedo, 1.0);
gl_FragData[4] = vec4(0.5 * normalM + 0.5, 0.0);
gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0649 */"
/* RENDERTARGETS:0,6,4,9,10,11,13 */
#endreplace

#replace "gl_FragData[3] = vec4(lightAlbedo, handSSBLMask);"
gl_FragData[3] = vec4(lightAlbedo, handSSBLMask);
gl_FragData[4] = vec4(oldAlbedo, 1.0);
gl_FragData[5] = vec4(0.5 * normalM + 0.5, 0.0);
gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:069 */"
/* RENDERTARGETS:0,6,9,10,11,13 */
#endreplace

#replace "gl_FragData[2] = vec4(lightAlbedo, handSSBLMask);"
gl_FragData[2] = vec4(lightAlbedo, handSSBLMask);
gl_FragData[3] = vec4(oldAlbedo, 1.0);
gl_FragData[4] = vec4(0.5 * normalM + 0.5, 0.0);
gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace
