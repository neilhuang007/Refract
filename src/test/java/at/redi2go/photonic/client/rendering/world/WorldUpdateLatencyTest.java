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
   void shadowStateDirtyIsSetAndConsumedByWorldRegistry() throws Exception {
      String source = Files.readString(WORLD_REGISTRY);

      assertTrue(source.contains("private boolean shadowStateDirty = true;"));
      assertTrue(source.contains("this.shadowStateDirty = true;"));
      assertTrue(source.contains("public boolean consumeShadowStateDirty()"));
      assertTrue(source.contains("this.shadowStateDirty = false;"));
      assertTrue(source.contains("this.lightRegistry.consumeTracedLightSetDirty() || this.consumeShadowStateDirty()"));
   }

   @Test
   void dirtyChunkUpdatesTriggerImmediateLightRecompilePath() throws Exception {
      String worldRegistry = Files.readString(WORLD_REGISTRY);
      String lightRegistry = Files.readString(LIGHT_REGISTRY);
      String chunkMeshingMixin = Files.readString(CHUNK_MESHING_MIXIN);

      assertTrue(worldRegistry.contains("boolean chunkContentChanged = this.update(this.rootMemoryManager, rootNeedsRebuild);"));
      assertTrue(worldRegistry.contains("if (chunkContentChanged) {\n            this.closeChunkUpdate = true;\n         }"));
      assertTrue(worldRegistry.contains("if (!forceRootUpload) {"));
      assertTrue(worldRegistry.contains("this.dirty = true;\n         return true;"));

      assertTrue(chunkMeshingMixin.contains("for (BlockPos blockPos : BlockPos.iterate(lowerCorner, upperCorner))"));
      assertTrue(chunkMeshingMixin.contains("lightRegistry.onBlockLoad(new Vector3f(blockPos.getX(), blockPos.getY(), blockPos.getZ()));"));

      assertTrue(lightRegistry.contains("boolean isTracedLight = lightType != null && lightType.isTraced() && lightType.blockStateEmitsLight(blockState);"));
      assertTrue(lightRegistry.contains("else if (this.tracedLightPositions.remove(tracedPosition))"));
      assertTrue(lightRegistry.contains("this.tracedLightSetDirty = true;"));
      assertTrue(lightRegistry.contains("public boolean consumeTracedLightSetDirty()"));
   }

   @Test
   void worldCompilerLoopRunsAtFrameRateCadence() throws Exception {
      String source = Files.readString(WORLD_COMPILER_THREAD);
      assertTrue(source.contains("this.wait(16L);"), "World compiler thread wait must be 16ms for responsive updates");
      assertFalse(source.contains("this.wait(1000L);"), "Legacy 1s wait should not be present");
   }
}
