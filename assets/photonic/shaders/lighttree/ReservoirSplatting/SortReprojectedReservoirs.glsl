#ifndef PHOTONICS_RESERVOIR_SPLATTING_SORT_REPROJECTED_RESERVOIRS_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_SORT_REPROJECTED_RESERVOIRS_GLSL

#include "/photonics/lighttree/restir_di_temporal_scatter_bridge.glsl"

void SortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    lt_SortReprojectedReservoirs_compute_cell_offsets(pixel);
}

void SortReprojectedReservoirs_sortCellData(uint index)
{
    lt_SortReprojectedReservoirs_sort_cell_data(index);
}

#endif
