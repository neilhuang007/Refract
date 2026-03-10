package at.redi2go.photonic.client.api;

import net.irisshaders.iris.helpers.OptionalBoolean;

public interface PhotonicsProperties {
   float DEFAULT_RENDER_SCALE = 1.0F;
   int DEFAULT_MAX_LIGHTS = 1000;
   int DEFAULT_MAX_SAMPLES = 20;
   AlphaMode DEFAULT_ALPHA_MODE = AlphaMode.NONE;

   OptionalBoolean isPhotonicsEnabled();
   OptionalBoolean useDeferredPass();
   float getRenderScale();
   int getMaxLights();
   int getMaxSamples();
   AlphaMode getAlphaMode();
   OptionalBoolean isGiEnabled();
   OptionalBoolean isBlockLightEnabled();
   OptionalBoolean isHandheldLightEnabled();
   OptionalBoolean voxelizeLava();
}
