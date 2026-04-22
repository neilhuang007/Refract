#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE 1

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/ScatterBackupTemporalResampling.glsl"

void ScatterBackupTemporalResampling_storeResult(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    float transportAux0;
    float transportAux1;
    scatter_pack_reconnection_fields(
        reconnectionData.firstHit.worldPos,
        reconnectionData.firstHit.viewDepth,
        reconnectionData.lightPdf,
        reconnectionData.time,
        reconnectionData.irradiance,
        reconnectionData.subPixel,
        reconnectionData.subPixelJacobian,
        reconnectionData.lensVertexJacobian,
        reconnectionData.secondaryPathJacobian,
        reconnectionData.firstHit.faceId,
        reconnectionData.pathLength,
        reconnectionData.firstBSDFComponentType,
        reconnectionData.secondBSDFComponentType,
        reconnectionData.transmissionEvent,
        reconnectionData.lightIsNEE,
        reconnectionData.lightIsDistant,
        transportAux0,
        transportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out
    );
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
}

void ScatterBackupTemporalResampling_storeEmptyResult()
{
    ScatterBackupTemporalResampling_storeResult(RTXDI_EmptyDIReservoir(), ReservoirSplattingReconnectionData_init());
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!RTXDI_IsActiveCheckerboardPixel(pixel, false, int(ph_restir_active_checkerboard_field))) {
        ScatterBackupTemporalResampling_storeEmptyResult();
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        ScatterBackupTemporalResampling_storeEmptyResult();
        return;
    }

    ReservoirSplattingReconnectionData currReconnectionData = ReservoirSplattingReconnectionData_init();
    RTXDI_DIReservoir dstReservoir = ScatterBackupTemporalResampling_run(
        pixel,
        currReconnectionData
    );

    ScatterBackupTemporalResampling_storeResult(dstReservoir, currReconnectionData);
}
