#file "/lib/lighting/mainLighting.glsl"

#replace "vec3 highlightColor = normalize(pow(lightColor, vec3(0.37))) * (0.3 + 1.5 * sunVisibility2) * (1.0 - 0.85 * rainFactor);"
vec3 ph_pixelated_player_pos = vec3(0.0);
float ph_has_pixelated_player_pos = 0.0;
vec3 highlightColor = normalize(pow(lightColor, vec3(0.37))) * (0.3 + 1.5 * sunVisibility2) * (1.0 - 0.85 * rainFactor);
#endreplace

#replace "void DoLighting(inout vec4 color, inout vec3 shadowMult, vec3 playerPos, vec3 viewPos, float lViewPos, vec3 geoNormal, vec3 normalM, float dither,"
void DoLighting(inout vec4 color, inout vec3 shadowMult, vec3 playerPos, vec3 viewPos, float lViewPos, vec3 geoNormal, vec3 normalM, float dither,
#endreplace

#replace "                inout float enderDragonDead) {"
                inout float enderDragonDead) {
    ph_pixelated_player_pos = playerPos;
    ph_has_pixelated_player_pos = 1.0;
#endreplace

#replace "    vec2 oldLightmap = lightmap.xy;"
    vec2 oldLightmap = lightmap.xy;
    ph_pixelated_player_pos = playerPos;
    ph_has_pixelated_player_pos = 1.0;
#endreplace

#replace "        #ifdef PIXELATED_BLOCKLIGHT"
        #ifdef PIXELATED_SHADOWS
            ph_pixelated_player_pos = playerPosPixelated;
            ph_has_pixelated_player_pos = 1.0;
        #endif
        #ifdef PIXELATED_BLOCKLIGHT
#endreplace

#replace "                        // Shadow bias without peter-panning //"
                        // Shadow bias without peter-panning //
#endreplace

#replace "vec3 blockLighting = lightmapXM * blocklightCol;"
vec3 blockLighting = lightmapXM * blocklightCol;
#ifdef PHOTONICS_ENABLED
    // Native block lighting must be disabled when RT block lighting is composited in deferred.
    blockLighting = vec3(0.0);
#endif
#endreplace

#replace "vec3 sceneLighting = lightColorM * shadowLightMult + ambientColorM * ambientMult;"
vec3 sceneLighting = lightColorM * shadowLightMult + ambientColorM * ambientMult;
#ifdef PHOTONICS_ENABLED
    // Keep direct shadowed sunlight mostly intact and attenuate ambient to avoid additive over-lighting.
    sceneLighting = lightColorM * shadowLightMult + ambientColorM * ambientMult * 0.6;
#endif
#endreplace

#replace "vec3 heldLighting = GetHeldLighting(playerPosForHeldLighting, color.rgb, emission, worldGeoNormal, normalM, viewPos);"
#ifdef PHOTONICS_ENABLED
        vec3 heldLighting = vec3(0.0);
#else
        vec3 heldLighting = GetHeldLighting(playerPosForHeldLighting, color.rgb, emission, worldGeoNormal, normalM, viewPos);
#endif
#endreplace

#replace "                        vec3 centerPlayerPos = floor(playerPos + cameraPosition + worldGeoNormal * 0.01) - cameraPosition + 0.5;"
                        vec3 centerPlayerPos = floor(playerPos + cameraPosition + worldGeoNormal * 0.01) - cameraPosition + 0.5;
#endreplace

#replace "                                distanceBias = 0.12 + 0.0008 * distanceBias;"
                                distanceBias = 0.12 + 0.0008 * distanceBias;
#endreplace

#replace "                                vec3 bias = worldGeoNormal * distanceBias * (2.0 - 0.95 * NdotLmax0); // 0.95 fixes pink petals noon shadows"
                                vec3 bias = worldGeoNormal * distanceBias * (2.0 - 0.95 * NdotLmax0); // 0.95 fixes pink petals noon shadows
#endreplace

#replace "                                        bias *= vec3(0.0, 0.0, -0.5);"
                                        bias *= vec3(0.0, 0.0, -0.5);
#endreplace

#replace "                                        bias.z += 0.25 * signMidCoordPos.x * NdotE;"
                                        bias.z += 0.25 * signMidCoordPos.x * NdotE;
#endreplace

#replace "                                    shadowPos.z -= max(NdotL * 0.0001, 0.0) * lightmapYM;"
                                    shadowPos.z -= max(NdotL * 0.0001, 0.0) * lightmapYM;
#endreplace

#replace "                                        shadowPos.z -= 0.0002;"
                                        shadowPos.z -= 0.0002;
#endreplace

#replace "                                    shadowPos.z -= 0.000175 * lightmapYM;"
                                    shadowPos.z -= 0.000175 * lightmapYM;
#endreplace
