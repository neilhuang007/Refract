package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;

public class WorldCompilerThread extends Thread implements Destructable {
   private static final long BUSY_WAIT_MILLIS = 4L;
   private static final long IDLE_WAIT_MILLIS = 16L;
   private WorldRegistry worldRegistry;
   private volatile boolean started = false;

   public WorldCompilerThread(WorldRegistry worldRegistry) {
      this.worldRegistry = worldRegistry;
      super.setDaemon(true);
      super.setName("WorldCompilerThread");
   }

   public void ensureRunning() {
      if (!this.started) {
         this.start();
         this.started = true;
      }
   }

   public void sendStopSignal() {
      this.started = false;
      synchronized (this) {
         this.notifyAll();
      }
   }

   @Override
   public void run() {
      super.run();

      while (this.started) {
         WorldRegistry registry = this.worldRegistry;
         if (registry == null) {
            return;
         }

         try {
            registry.compileWorld();
         } catch (Exception var6) {
            var6.printStackTrace();
         }

         boolean hasPendingWork = registry.hasPendingWork();
         synchronized (this) {
            try {
               this.wait(hasPendingWork ? BUSY_WAIT_MILLIS : IDLE_WAIT_MILLIS);
            } catch (InterruptedException var4) {
            }
         }
      }
   }

   @Override
   public void free() {
      this.sendStopSignal();
      this.worldRegistry = null;
   }
}
