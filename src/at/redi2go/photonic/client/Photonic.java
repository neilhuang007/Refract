package at.redi2go.photonic.client;

import net.fabricmc.api.ModInitializer;
import net.fabricmc.loader.api.FabricLoader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Photonic implements ModInitializer {
   public static final String MOD_ID = "photonics";
   public static String MOD_VERSION = "";
   private static final Logger LOGGER = LoggerFactory.getLogger("Photonics");

   public void onInitialize() {
      FabricLoader.getInstance()
         .getModContainer("photonics")
         .ifPresent(modContainer -> MOD_VERSION = modContainer.getMetadata().getVersion().getFriendlyString());
   }

   public static void info(String info, Object... objects) {
      LOGGER.info(info, objects);
   }

   public static void warn(String warning, Object... objects) {
      LOGGER.warn(warning, objects);
   }

   public static void error(Exception e) {
      LOGGER.error("Photonics reported an error:", e);
   }
}
