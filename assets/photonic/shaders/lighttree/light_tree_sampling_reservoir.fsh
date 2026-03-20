#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

void storeEmptyProposalReservoirOutputs() {
    Reservoir emptyReservoir = rtxdi_empty_reservoir();
    reservoir_frag_out = rtxdi_pack_reservoir(emptyReservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(emptyReservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(emptyReservoir);
}

void main() {
    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        storeEmptyProposalReservoirOutputs();
        return;
    }

    ivec2 pixelPosition = lt_current_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeEmptyProposalReservoirOutputs();
        return;
    }

    DirectSurface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        storeEmptyProposalReservoirOutputs();
        return;
    }

    Reservoir reservoir = RTXDI_SampleLightsForSurface(currentSurface);

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}
