#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE 1
// SSBO/sampler inclusion is driven by lt_buffer_features.glsl based on the
// PH_LIGHTTREE_ENABLE_*_STAGE flag above. Lean scatter passes opt out of
// ReGIR/light-data/floating-coords SSBOs centrally — no per-shader overrides.

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;
layout(location = 5) out vec4 reconnection2_frag_out;
layout(location = 6) out vec4 reconnection3_frag_out;
layout(location = 7) out vec4 reconnection4_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/ScatterBackupTemporalResampling.glsl"

void ScatterBackupTemporalResampling_storeResult(
    RTXDI_DIReservoir reservoir,
    ReconnectionData reconnectionData)
{
    float reconnectionTransportAux0;
    float reconnectionTransportAux1;
    scatter_pack_reconnection_fields(
        reconnectionData,
        reconnectionTransportAux0,
        reconnectionTransportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out,
        reconnection2_frag_out,
        reconnection3_frag_out,
        reconnection4_frag_out
    );
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
}

void ScatterBackupTemporalResampling_storeEmptyResult()
{
    ScatterBackupTemporalResampling_storeResult(RTXDI_EmptyDIReservoir(), ReconnectionData_init());
}

void main()
{
    ivec2 reservoirPos = ivec2(gl_FragCoord.xy);
    int activeField = int(ph_restir_active_checkerboard_field);
    ivec2 pixel = (activeField == 0)
        ? reservoirPos
        : RTXDI_ReservoirPosToPixelPos(reservoirPos, activeField);
    if (!RTXDI_IsActiveCheckerboardPixel(pixel, false, activeField)) {
        ScatterBackupTemporalResampling_storeEmptyResult();
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        ScatterBackupTemporalResampling_storeEmptyResult();
        return;
    }

    ReconnectionData currReconnectionData = ReconnectionData_init();
    RTXDI_DIReservoir dstReservoir = ScatterBackupTemporalResampling_run(
        pixel,
        currReconnectionData
    );

    ScatterBackupTemporalResampling_storeResult(dstReservoir, currReconnectionData);
}
