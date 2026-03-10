package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;

public record TracedLightPosition(int blockId, BlockLightInfo lightInfo) {}
