#ifndef PHOTONICS_RESERVOIR_SPLATTING_MULTI_SORT_REPROJECTED_RESERVOIRS_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_MULTI_SORT_REPROJECTED_RESERVOIRS_GLSL

#include "/photonics/lighttree/restir_di_temporal_scatter_bridge.glsl"

void MultiSortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    lt_MultiSortReprojectedReservoirs_compute_cell_offsets(pixel);
}

void MultiSortReprojectedReservoirs_sortCellData(uint index)
{
    lt_MultiSortReprojectedReservoirs_sort_cell_data(index);
}

#endif
