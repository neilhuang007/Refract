package at.redi2go.photonic.client.api;

import net.irisshaders.iris.helpers.OptionalBoolean;

public interface PhotonicsProperties {
   float DEFAULT_RENDER_SCALE = 1.0F;
   int DEFAULT_MAX_LIGHTS = 1000;
   int DEFAULT_MAX_SAMPLES = 20;
   float DEFAULT_MIN_TRACED_LIGHT_LUMA = 0.001F;
   AlphaMode DEFAULT_ALPHA_MODE = AlphaMode.NONE;
   LightingMode DEFAULT_LIGHTING_MODE = LightingMode.LIGHT_TREE;
   int DEFAULT_RESTIR_INITIAL_SAMPLES = 32;
   int DEFAULT_RESTIR_SPATIAL_REUSE_SAMPLES = 5;
   float DEFAULT_RESTIR_SPATIAL_REUSE_RADIUS = 10.0F;
   int DEFAULT_RESTIR_ACCUMULATION_FRAMES = 15;
   int DEFAULT_RESTIR_DENOISER_PASSES = 5;
   int DEFAULT_NRD_ATROUS_PASSES = 5;

   OptionalBoolean isPhotonicsEnabled();
   float getRenderScale();
   int getMaxLights();
   int getMaxSamples();
   float getMinTracedLightLuma();
   AlphaMode getAlphaMode();
   OptionalBoolean isGiEnabled();
   OptionalBoolean isBlockLightEnabled();
   OptionalBoolean isHandheldLightEnabled();
   OptionalBoolean isLightBinningEnabled();
   OptionalBoolean voxelizeLava();
   LightingMode getLightingMode();
   int getRestirInitialSamples();
   int getRestirSpatialReuseSamples();
   float getRestirSpatialReuseRadius();
   int getRestirAccumulationFrames();
   OptionalBoolean useRestirSoftShadows();
   int getRestirDenoiserPasses();
   int getNrdAtrousPasses();
}
