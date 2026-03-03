#file "/program/gbuffers_water.glsl"

#replace "vec3 normalM = VdotN > 0.0 ? -normal : normal; // Inverted Iris Water Normal Workaround"
vec3 normalM = VdotN > 0.0 ? -normal : normal; // Inverted Iris Water Normal Workaround
vec3 oldAlbedo = vec3(0.0);
#endreplace

#replace "DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, dither,"
oldAlbedo = color.rgb;
DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, dither,
#endreplace

#replace "/* DRAWBUFFERS:03 */
    gl_FragData[0] = color;
    gl_FragData[1] = vec4(1.0 - translucentMult.rgb, translucentMult.a);"
/* RENDERTARGETS:0,3,10,11,13 */
    gl_FragData[0] = color;
    gl_FragData[1] = vec4(1.0 - translucentMult.rgb, translucentMult.a);
    gl_FragData[2] = vec4(oldAlbedo, 1.0);
    gl_FragData[3] = vec4(0.5 * geoNormal + 0.5, 0.0);
    gl_FragData[4] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:036 */
        gl_FragData[2] = vec4(1.0, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));"
/* RENDERTARGETS:0,3,6,10,11,13 */
        gl_FragData[2] = vec4(1.0, materialMask, skyLightFactor, lmCoord.x + clamp01(purkinjeOverwrite) + clamp01(emission));
        gl_FragData[3] = vec4(oldAlbedo, 1.0);
        gl_FragData[4] = vec4(0.5 * geoNormal + 0.5, 0.0);
        gl_FragData[5] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:036489 */
                gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, sqrt(fresnelM * color.a * fogAlpha));
                gl_FragData[4] = vec4(reflection.rgb * fresnelM * color.a * fogAlpha, reflection.a);
                gl_FragData[5] = vec4(lightAlbedo, SSBLAlpha);"
/* RENDERTARGETS:0,3,6,4,8,9,10,11,13 */
                gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, sqrt(fresnelM * color.a * fogAlpha));
                gl_FragData[4] = vec4(reflection.rgb * fresnelM * color.a * fogAlpha, reflection.a);
                gl_FragData[5] = vec4(lightAlbedo, SSBLAlpha);
                gl_FragData[6] = vec4(oldAlbedo, 1.0);
                gl_FragData[7] = vec4(0.5 * geoNormal + 0.5, 0.0);
                gl_FragData[8] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:03648 */
                gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, sqrt(fresnelM * color.a * fogAlpha));
                gl_FragData[4] = vec4(reflection.rgb * fresnelM * color.a * fogAlpha, reflection.a);"
/* RENDERTARGETS:0,3,6,4,8,10,11,13 */
                gl_FragData[3] = vec4(mat3(gbufferModelViewInverse) * normalM, sqrt(fresnelM * color.a * fogAlpha));
                gl_FragData[4] = vec4(reflection.rgb * fresnelM * color.a * fogAlpha, reflection.a);
                gl_FragData[5] = vec4(oldAlbedo, 1.0);
                gl_FragData[6] = vec4(0.5 * geoNormal + 0.5, 0.0);
                gl_FragData[7] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0369 */
            gl_FragData[3] = vec4(lightAlbedo, SSBLAlpha);"
/* RENDERTARGETS:0,3,6,9,10,11,13 */
            gl_FragData[3] = vec4(lightAlbedo, SSBLAlpha);
            gl_FragData[4] = vec4(oldAlbedo, 1.0);
            gl_FragData[5] = vec4(0.5 * geoNormal + 0.5, 0.0);
            gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace

#replace "/* DRAWBUFFERS:0348 */
        gl_FragData[2] = vec4(mat3(gbufferModelViewInverse) * normalM, sqrt(fresnelM * color.a * fogAlpha));
        gl_FragData[3] = vec4(reflection.rgb * fresnelM * color.a * fogAlpha, reflection.a);"
/* RENDERTARGETS:0,3,4,8,10,11,13 */
        gl_FragData[2] = vec4(mat3(gbufferModelViewInverse) * normalM, sqrt(fresnelM * color.a * fogAlpha));
        gl_FragData[3] = vec4(reflection.rgb * fresnelM * color.a * fogAlpha, reflection.a);
        gl_FragData[4] = vec4(oldAlbedo, 1.0);
        gl_FragData[5] = vec4(0.5 * geoNormal + 0.5, 0.0);
        gl_FragData[6] = vec4(ph_pixelated_player_pos, ph_has_pixelated_player_pos);
#endreplace
