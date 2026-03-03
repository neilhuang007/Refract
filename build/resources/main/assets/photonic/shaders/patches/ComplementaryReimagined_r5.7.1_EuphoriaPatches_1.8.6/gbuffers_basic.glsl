#file "/program/gbuffers_basic.glsl"

#replace "vec3 normalM = normal, geoNormal = normal, shadowMult = vec3(1.0);"
vec3 normalM = normal, geoNormal = normal, shadowMult = vec3(1.0);
vec3 oldAlbedo = vec3(0.0);
#endreplace

#replace "DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,"
oldAlbedo = color.rgb;
DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,
#endreplace

#replace "/* DRAWBUFFERS:06 */"
/* RENDERTARGETS:0,6,10,11,13 */
#endreplace

#replace "gl_FragData[1] = vec4(0.0, materialMask, 0.0, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));"
gl_FragData[1] = vec4(0.0, materialMask, 0.0, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));
gl_FragData[2] = vec4(oldAlbedo, 1.0);
gl_FragData[3] = vec4(0.5 * normal + 0.5, 0.0);
gl_FragData[4] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:069 */"
/* RENDERTARGETS:0,6,9,10,11,13 */
#endreplace

#replace "gl_FragData[2] = vec4(0.0, 0.0, 0.0, 0.0);"
gl_FragData[2] = vec4(0.0, 0.0, 0.0, 0.0);
gl_FragData[3] = vec4(oldAlbedo, 1.0);
gl_FragData[4] = vec4(0.5 * normal + 0.5, 0.0);
gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace
