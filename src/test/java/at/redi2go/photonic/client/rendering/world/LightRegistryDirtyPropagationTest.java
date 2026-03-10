package at.redi2go.photonic.client.rendering.world;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class LightRegistryDirtyPropagationTest {
   private static final Path LIGHT_REGISTRY = Path.of("src/at/redi2go/photonic/client/rendering/world/LightRegistry.java");
   private static final Path WORLD_REGISTRY = Path.of("src/at/redi2go/photonic/client/rendering/world/WorldRegistry.java");

   @Test
   void worldRegistryGuardsLightCompileWithDirtyChecks() throws IOException {
      String source = Files.readString(WORLD_REGISTRY);

      assertTrue(source.contains("this.lightRegistry.compileRegistry(this.rtToWorldBlockOffset, previousBlockOffset);"));
      assertTrue(source.contains("consumeShadowStateDirty()"));
      assertTrue(source.contains("consumeTracedLightSetDirty()"));
      assertTrue(source.contains("this.blockLightEnabled"));
   }

   @Test
   void lightBlockRegistrationAllowsMissingLightEntriesWithoutThrowing() throws IOException {
      String source = Files.readString(LIGHT_REGISTRY);

      assertTrue(source.contains("Pair.of(e.getValue(), lights.get(e.getKey()))"));
   }

   @Test
   void lightCullLogicMatchesUpstreamExposedBlockBehavior() throws IOException {
      String source = Files.readString(LIGHT_REGISTRY);

      assertTrue(source.contains("BlockPos neighborPos = blockPos.add(offset);"));
      assertTrue(source.contains("neighbor.isSolidBlock(level, neighborPos)"));
      assertTrue(source.contains("return false;"));
   }

   @Test
   void tracedLightMutationsMarkDirtyForFollowUpCompiles() throws IOException {
      String source = Files.readString(LIGHT_REGISTRY);

      assertTrue(source.contains("private volatile boolean tracedLightSetDirty = true;"));
      assertTrue(source.contains("this.tracedLightSetDirty = true;"));
      assertTrue(source.contains("public boolean consumeTracedLightSetDirty()"));
   }
}
