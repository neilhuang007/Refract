#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE
#define PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE 1

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/MultiSortReprojectedReservoirs.glsl"

void MultiSortReprojectedReservoirs_storeEmptyComputeCellOffsetsResult()
{
    reservoir_frag_out = vec4(0.0f);
    reservoir_sample_frag_out = vec4(0.0f);
    reservoir_meta_frag_out = vec4(0.0f);
}

void main()
{
    MultiSortReprojectedReservoirs_storeEmptyComputeCellOffsetsResult();

    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    MultiSortReprojectedReservoirs_computeCellOffsets(pixel);
}
