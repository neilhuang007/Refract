package at.redi2go.photonic.client;

import java.nio.file.Path;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.loader.api.FabricLoader;
import net.fabricmc.loader.api.ModContainer;
import net.fabricmc.loader.api.Version;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Photonic implements ModInitializer {
   public static final String MOD_ID = "photonics";
   public static String MOD_VERSION = "";
   public static Version VERSION;
   public static final Path CONFIG_PATH = initConfigPath();
   public static final String DEFAULT_CONFIG_PATH = "assets/photonic/default_config.json";
   private static final Logger LOGGER = LoggerFactory.getLogger("Photonics");
   private static final boolean AUTOMATION_ENABLED = Boolean.getBoolean("photonics.automation.enabled");

   public void onInitialize() {
      ModContainer photonics = (ModContainer)FabricLoader.getInstance()
         .getModContainer("photonics")
         .orElseThrow(() -> new RuntimeException("Missing photonics mod container :("));
      VERSION = photonics.getMetadata().getVersion();
      MOD_VERSION = VERSION.getFriendlyString();
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

   public static void error(String message, Exception e) {
      LOGGER.error(message, e);
   }

   public static boolean automationEnabled() {
      return AUTOMATION_ENABLED;
   }

   private static Path initConfigPath() {
      try {
         return FabricLoader.getInstance().getConfigDir().resolve("photonics.json");
      } catch (Exception e) {
         return Path.of("photonics.json");
      }
   }
}
