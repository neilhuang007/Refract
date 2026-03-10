package at.redi2go.photonic.client.config;

import at.redi2go.photonic.client.Photonic;
import java.io.IOException;
import java.nio.file.FileSystems;
import java.nio.file.Path;
import java.nio.file.StandardWatchEventKinds;
import java.nio.file.WatchEvent;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;
import java.util.List;
import net.minecraft.client.MinecraftClient;

public class PhotonicsConfigWatchThread extends Thread {
   private static String ERROR_MESSAGE = "an error was thrown in the config watch service";
   public static PhotonicsConfigWatchThread INSTANCE = new PhotonicsConfigWatchThread();
   private WatchService service;
   private WatchKey key;
   private volatile boolean isSaving = false;
   private volatile boolean ignoreNextModify = false;

   private PhotonicsConfigWatchThread() {
      super("photonics-config-watcher");
   }

   public static void beginSave() {
      INSTANCE.isSaving = true;
   }

   public static void endSave() {
      INSTANCE.ignoreNextModify = true;
      INSTANCE.isSaving = false;
   }

   public static void reset() {
      INSTANCE.ignoreNextModify = false;
      INSTANCE.isSaving = false;
   }

   private void runImpl() throws IOException, InterruptedException {
      this.service = FileSystems.getDefault().newWatchService();
      Path folder = Photonic.CONFIG_PATH.getParent();
      Path file = folder.relativize(Photonic.CONFIG_PATH);
      this.key = folder.register(this.service, StandardWatchEventKinds.ENTRY_MODIFY);

      while (true) {
         try {
            List<WatchEvent<?>> events = this.key.pollEvents();
            if (!events.isEmpty()) {
               for (WatchEvent<?> event : events) {
                  Path path = (Path) event.context();
                  if (path.equals(file) && !this.isSaving) {
                     if (this.ignoreNextModify) {
                        this.ignoreNextModify = false;
                     } else {
                        MinecraftClient.getInstance().execute(() -> {
                           Photonic.info("Detected config change, reloading...");
                           PhotonicsConfig.reloadConfig();
                        });
                     }
                  }
               }
            }
         } catch (Exception e) {
            Photonic.error(new RuntimeException("Error reloading config", e));
         } finally {
            Thread.sleep(1000L);
         }
      }
   }

   @Override
   public void run() {
      try {
         this.runImpl();
      } catch (InterruptedException | IOException e) {
         Photonic.error(new RuntimeException(ERROR_MESSAGE, e));
         if (this.key != null) {
            this.key.cancel();
            this.key = null;
         }
         if (this.service != null) {
            try {
               this.service.close();
               this.service = null;
            } catch (IOException ex) {
               Photonic.error(new RuntimeException(ERROR_MESSAGE, ex));
            }
         }
      }
   }
}
