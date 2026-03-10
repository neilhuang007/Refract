package at.redi2go.photonic.client;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class BlockRegistryShaderPointerBudgetTest {
   private static final Path BLOCK_REGISTRY = Path.of("src/at/redi2go/photonic/client/BlockRegistry.java");

   @Test
   void blockRegistryReservesNullPointerAndCapsShaderIndices() throws Exception {
      String source = Files.readString(BLOCK_REGISTRY);

      assertTrue(source.contains("memoryManager.allocate(PBlock.BYTE_SIZE);"));
      assertTrue(source.contains("PBlock.numAllocated >= 4095"));
      assertTrue(source.contains("this.freeUnused();"));
   }
}
