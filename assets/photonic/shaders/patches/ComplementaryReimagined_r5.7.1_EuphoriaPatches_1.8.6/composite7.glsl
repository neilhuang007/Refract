#file "/program/composite7.glsl"

#replace "float GetLinearDepth(float depth) {"
uniform float ph_mod_shadow_pixelation_enabled;
uniform sampler2D colortex13;

bool phHasPixelatedCastLight() {
    return ph_mod_shadow_pixelation_enabled > 0.5 && texelFetch(colortex13, texelCoord, 0).a > 0.5;
}

float GetLinearDepth(float depth) {
#endreplace

#replace "            FXAA311(color);"
            // if (!(ph_mod_shadow_pixelation_enabled > 0.5)
            bool phSkipFXAA = phHasPixelatedCastLight();
            if (!phSkipFXAA) {
                FXAA311(color);
            }
#endreplace
