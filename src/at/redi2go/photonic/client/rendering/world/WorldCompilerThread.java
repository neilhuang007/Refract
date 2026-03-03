package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;

public class WorldCompilerThread extends Thread implements Destructable {
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
   }

   @Override
   public void run() {
      super.run();

      while (this.started) {
         if (this.worldRegistry == null) {
            return;
         }

         try {
            this.worldRegistry.compileWorld();
         } catch (Exception var6) {
            var6.printStackTrace();
         }

         synchronized (this) {
            try {
               this.wait(200L);
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
