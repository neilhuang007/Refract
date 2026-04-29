struct RTXDI_RISTileInfo
{
    uint risTileOffset;
    uint risTileSize;
};

const uint RTXDI_LocalLightContextSamplingMode_UNIFORM = 0u;
const uint RTXDI_LocalLightContextSamplingMode_RIS = 1u;
const uint RTXDI_LocalLightContextSamplingMode_INVALID = 0xFFFFFFFFu;

struct RTXDI_LocalLightSelectionContext
{
    uint mode;
    uint proposalFamily;
    RTXDI_RISTileInfo risTileInfo;
    RTXDI_LightBufferRegion lightBufferRegion;
};

RTXDI_LightBufferRegion RTXDI_GetLocalLightBufferRegion()
{
    RTXDI_LightBufferRegion region;
    region.firstLightIndex = 0u;
    region.numLights = uint(max(ph_light_count, 0));
    region.pad1 = 0u;
    region.pad2 = 0u;
    return region;
}

RTXDI_RISBufferSegmentParameters RTXDI_GetLocalLightRISBufferSegmentParameters()
{
    RTXDI_RISBufferSegmentParameters params;
    params.bufferOffset = uint(max(ph_ris_tile_buffer_offset, 0));
    params.tileSize = uint(max(ph_ris_tile_size, 0));
    params.tileCount = uint(max(ph_ris_tile_count, 0));
    params.pad1 = 0u;
    return params;
}

void RTXDI_RandomlySelectLightUniformly(
    float rnd,
    RTXDI_LightBufferRegion region,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    lightInfo = RAB_EmptyLightInfo();
    lightIndex = 0u;
    invSourcePdf = 0.0f;

    if (region.numLights == 0u) {
        return;
    }

    invSourcePdf = float(region.numLights);
    lightIndex = region.firstLightIndex + min(uint(floor(rnd * float(region.numLights))), region.numLights - 1u);
    lightInfo = RAB_LoadLightInfo(int(lightIndex), false);
}

void RTXDI_RandomlySelectLightDataFromRISTile(
    float rnd,
    RTXDI_RISTileInfo bufferInfo,
    out uvec2 tileData,
    out uint risBufferPtr)
{
    tileData = uvec2(0u);
    risBufferPtr = 0u;

    uint risSample = min(uint(floor(rnd * float(bufferInfo.risTileSize))), bufferInfo.risTileSize - 1u);
    risBufferPtr = risSample + bufferInfo.risTileOffset;
    tileData = ph_ris_data[risBufferPtr];
}

RTXDI_RISTileInfo RTXDI_RandomlySelectRISTile(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_RISBufferSegmentParameters params)
{
    RTXDI_RISTileInfo risTileInfo;
    risTileInfo.risTileOffset = params.bufferOffset;
    risTileInfo.risTileSize = params.tileSize;

    float tileRnd = RTXDI_GetNextRandom(coherentRng);
    uint tileIndex = uint(tileRnd * float(params.tileCount));
    risTileInfo.risTileOffset = tileIndex * params.tileSize + params.bufferOffset;
    return risTileInfo;
}

RTXDI_RISTileInfo RTXDI_SelectLocalLightReGIRRISTile(int cellIndex)
{
    RTXDI_RISTileInfo tileInfo;
    tileInfo.risTileOffset = uint(cellIndex) * uint(ph_regir_lights_per_cell) + uint(ph_regir_ris_buffer_offset);
    tileInfo.risTileSize = uint(ph_regir_lights_per_cell);
    return tileInfo;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextUniform(RTXDI_LightBufferRegion lightBufferRegion)
{
    RTXDI_LocalLightSelectionContext ctx;
    ctx.mode = RTXDI_LocalLightContextSamplingMode_UNIFORM;
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_UNIFORM;
    ctx.lightBufferRegion = lightBufferRegion;
    ctx.risTileInfo.risTileOffset = 0u;
    ctx.risTileInfo.risTileSize = 0u;
    return ctx;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextRIS(RTXDI_RISTileInfo risTileInfo)
{
    RTXDI_LocalLightSelectionContext ctx;
    ctx.mode = RTXDI_LocalLightContextSamplingMode_RIS;
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_POWER_RIS;
    ctx.risTileInfo = risTileInfo;
    ctx.lightBufferRegion.firstLightIndex = 0u;
    ctx.lightBufferRegion.numLights = 0u;
    ctx.lightBufferRegion.pad1 = 0u;
    ctx.lightBufferRegion.pad2 = 0u;
    return ctx;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextRIS(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_RISBufferSegmentParameters risBufferSegmentParams)
{
    return RTXDI_InitializeLocalLightSelectionContextRIS(
        RTXDI_RandomlySelectRISTile(coherentRng, risBufferSegmentParams)
    );
}

int RTXDI_GetReservoirLightIndexForFrame(
    RTXDI_DIReservoir reservoir,
    bool reservoirPreviousFrame,
    bool targetPreviousFrame)
{
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return -1;
    }

    return lt_translate_reservoir_light_index_between_frames(
        rtxdi_get_light_index(reservoir),
        reservoirPreviousFrame,
        targetPreviousFrame
    );
}

bool RTXDI_GetReservoirLightForFrame(
    RTXDI_DIReservoir reservoir,
    bool reservoirPreviousFrame,
    bool targetPreviousFrame,
    out Light light)
{
    int lightIndex = RTXDI_GetReservoirLightIndexForFrame(
        reservoir,
        reservoirPreviousFrame,
        targetPreviousFrame
    );
    if (lightIndex < 0) {
        light = lt_invalid_light();
        return false;
    }

    light = targetPreviousFrame ? load_previous_light(lightIndex) : load_light(lightIndex);
    return light.index >= 0;
}
