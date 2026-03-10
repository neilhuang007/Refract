#file "/program/composite6.glsl"

#replace "float GetLinearDepth(float depth) {"
uniform float ph_mod_shadow_pixelation_enabled;
uniform sampler2D colortex13;

bool phHasPixelatedCastLight() {
    return ph_mod_shadow_pixelation_enabled > 0.5 && texelFetch(colortex13, texelCoord, 0).a > 0.5;
}

float GetLinearDepth(float depth) {
#endreplace

#replace "                z1 = texelFetch(depthtex1, texelCoord, 0).r;
                DoTAA(color, temp, z1);"
                z1 = texelFetch(depthtex1, texelCoord, 0).r;
                if (!(ph_mod_shadow_pixelation_enabled > 0.5) || phHasPixelatedCastLight()) {
                    if (phHasPixelatedCastLight()) {
                        color = texelFetch(colortex3, texelCoord, 0).rgb;
                        temp = color;
                    }
                    DoTAA(color, temp, z1);
                }
#endreplace
