#version 430

// Publishes the reconnection payload paired with the reservoir promoted by
// ShadeSamples.fsh when spatial reuse is disabled.

in vec4 direction_vert_out;

layout(location = 0) out vec4 reconnection0_frag_out;
layout(location = 1) out vec4 reconnection1_frag_out;
layout(location = 2) out vec4 reconnection2_frag_out;
layout(location = 3) out vec4 reconnection3_frag_out;
layout(location = 4) out vec4 reconnection4_frag_out;

//ph_required: uniform float viewWidth, viewHeight;

// Packed 5-layer array replacing scatter_reconnection0..4.
uniform sampler2DArray scatter_reconnections;

uniform int ph_restir_active_checkerboard_field;

void storeEmptyReconnection()
{
    reconnection0_frag_out = vec4(0.0f);
    reconnection1_frag_out = vec4(0.0f);
    reconnection2_frag_out = vec4(0.0f);
    reconnection3_frag_out = vec4(0.0f);
    reconnection4_frag_out = vec4(0.0f);
}

ivec2 PromoteReconnection_reservoirPosToPixelPos(ivec2 reservoirPos)
{
    if (ph_restir_active_checkerboard_field == 0)
    {
        return reservoirPos;
    }

    ivec2 pixelPos = ivec2(reservoirPos.x << 1, reservoirPos.y);
    pixelPos.x += ((pixelPos.y + ph_restir_active_checkerboard_field) & 1);
    return pixelPos;
}

bool PromoteReconnection_isActiveReservoirLane(ivec2 reservoirPos)
{
    ivec2 pixelPos = PromoteReconnection_reservoirPosToPixelPos(reservoirPos);
    return all(greaterThanEqual(pixelPos, ivec2(0)))
        && all(lessThan(pixelPos, ivec2(int(viewWidth), int(viewHeight))));
}

void main()
{
    ivec2 reservoirPos = ivec2(gl_FragCoord.xy);
    if (!PromoteReconnection_isActiveReservoirLane(reservoirPos))
    {
        storeEmptyReconnection();
        return;
    }

    reconnection0_frag_out = texelFetch(scatter_reconnections, ivec3(reservoirPos, 0), 0);
    reconnection1_frag_out = texelFetch(scatter_reconnections, ivec3(reservoirPos, 1), 0);
    reconnection2_frag_out = texelFetch(scatter_reconnections, ivec3(reservoirPos, 2), 0);
    reconnection3_frag_out = texelFetch(scatter_reconnections, ivec3(reservoirPos, 3), 0);
    reconnection4_frag_out = texelFetch(scatter_reconnections, ivec3(reservoirPos, 4), 0);
}
