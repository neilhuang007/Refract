package at.redi2go.photonic.client.config.lights;

public interface LightsProvider {
   void registerLights(LightList lights);
   void registerChangeListener(Runnable listener);
   void clearListeners();
}
