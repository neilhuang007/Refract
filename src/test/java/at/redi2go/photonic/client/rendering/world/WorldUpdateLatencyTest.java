package at.redi2go.photonic.client.rendering.world;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WorldUpdateLatencyTest {
   private static final Path WORLD_REGISTRY = Path.of("src/at/redi2go/photonic/client/rendering/world/WorldRegistry.java");
   private static final Path LIGHT_REGISTRY = Path.of("src/at/redi2go/photonic/client/rendering/world/LightRegistry.java");
   private static final Path CHUNK_MESHING_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/ChunkBuilderMeshingTaskMixin.java");
   private static final Path WORLD_COMPILER_THREAD = Path.of("src/at/redi2go/photonic/client/rendering/world/WorldCompilerThread.java");

   @Test
   void compileWorldUsesDirtyTrackingToSkipRedundantWork() throws Exception {
      String source = normalize(Files.readString(WORLD_REGISTRY));

      assertTrue(source.contains("chunkSyncNeeded"));
      assertTrue(source.contains("shadowStateDirty"));
      assertTrue(source.contains("update(this.rootMemoryManager, rootNeedsRebuild)"));
      assertTrue(source.contains("consumeShadowStateDirty()"));
      assertTrue(source.contains("consumeTracedLightSetDirty()"));
   }

   @Test
   void queueBuildJobSetsDirtyFlags() throws Exception {
      String source = normalize(Files.readString(WORLD_REGISTRY));

      assertTrue(source.contains("this.shadowStateDirty = true;"));
   }

   @Test
   void initialChunkLoadingUsesHigherBootstrapBudget() throws Exception {
      String source = normalize(Files.readString(WORLD_REGISTRY));

      assertTrue(source.contains("this.chunks.isEmpty() ? INITIAL_CHUNK_LOAD_BUDGET : CHUNK_LOAD_BUDGET"));
   }

   @Test
   void lightRegistryTracksTracedLightPositionsBeforeBuilderWakeup() throws Exception {
      String lightRegistry = normalize(Files.readString(LIGHT_REGISTRY));
      String chunkMeshingMixin = normalize(Files.readString(CHUNK_MESHING_MIXIN));

      String tracedLightScan = "for (BlockPos blockPos : BlockPos.iterate(lowerCorner, upperCorner))";
      String wakeUpBuilder = "Raytracer.INSTANCE.getWorldRegistry().wakeUpWorldBuilder();";
      assertTrue(chunkMeshingMixin.contains(tracedLightScan));
      assertTrue(chunkMeshingMixin.contains("lightRegistry.onBlockLoad(new Vector3f(blockPos.getX(), blockPos.getY(), blockPos.getZ()));"));
      assertTrue(chunkMeshingMixin.indexOf(tracedLightScan) < chunkMeshingMixin.indexOf(wakeUpBuilder));
      assertFalse(chunkMeshingMixin.contains("Lock lock = lightRegistry.readLock();"));

      assertTrue(lightRegistry.contains("private volatile boolean tracedLightSetDirty = true;"));
      assertTrue(lightRegistry.contains("public boolean consumeTracedLightSetDirty()"));
   }

   @Test
   void worldCompilerLoopAvoidsGlobalLockAndUsesModerateCadence() throws Exception {
      String source = normalize(Files.readString(WORLD_COMPILER_THREAD));
      assertFalse(source.contains("synchronized (Raytracer.LOCK)"));
      assertTrue(source.contains("private static final long BUSY_WAIT_MILLIS = 4L;"));
      assertTrue(source.contains("private static final long IDLE_WAIT_MILLIS = 16L;"));
      assertTrue(source.contains("this.wait(hasPendingWork ? BUSY_WAIT_MILLIS : IDLE_WAIT_MILLIS);"));
      assertFalse(source.contains("this.wait(hasPendingWork ? 1L : 16L);"));
   }

   private static String normalize(String s) {
      return s.replace("\r\n", "\n");
   }
}
