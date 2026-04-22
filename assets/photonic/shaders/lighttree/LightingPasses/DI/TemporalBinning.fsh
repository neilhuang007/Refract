#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING 1

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/SortReprojectedReservoirs.glsl"

void SortReprojectedReservoirs_storeEmptySortCellDataResult()
{
    reservoir_frag_out = vec4(0.0f);
    reservoir_sample_frag_out = vec4(0.0f);
    reservoir_meta_frag_out = vec4(0.0f);
}

void main()
{
    SortReprojectedReservoirs_storeEmptySortCellDataResult();

    uint index = uint(gl_FragCoord.x);
    SortReprojectedReservoirs_sortCellData(index);
}


