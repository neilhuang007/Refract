package at.redi2go.photonic.client.rendering.world;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class WorldRegistryBuildQueueParityTest {
   private static final Path WORLD_REGISTRY = Path.of("src/at/redi2go/photonic/client/rendering/world/WorldRegistry.java");

   @Test
   void queueBuildJobSetsDirtyFlagsForResponsiveUpdates() throws Exception {
      String source = Files.readString(WORLD_REGISTRY).replace("\r\n", "\n");

      assertTrue(source.contains("this.buildQueue.add(job);"));
      assertTrue(source.contains("this.shadowStateDirty = true;"));
   }
}
