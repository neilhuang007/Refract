package at.redi2go.photonic.client;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class BlockRegistryParityTest {
   private static final Path BLOCK_REGISTRY = Path.of("src/at/redi2go/photonic/client/BlockRegistry.java");

   @Test
   void blockRegistryPreservesUpstreamVanillaRenderedBlockExclusion() throws Exception {
      String source = Files.readString(BLOCK_REGISTRY);

      assertTrue(source.contains("public static final Set<Block> VANILLA_RENDERED_BLOCK = Set.of("));
      assertTrue(source.contains("Blocks.WATER"));
      assertTrue(source.contains("Blocks.END_PORTAL"));
      assertTrue(source.contains("Blocks.OAK_SIGN"));
      assertTrue(source.contains("Blocks.WHITE_BANNER"));
      assertTrue(source.contains("private static boolean isVanillaRendered(Block block) {"));
      assertTrue(source.contains("Raytracer.getProperties().map(e -> e.voxelizeLava().orElse(false)).orElse(false) ? false : VANILLA_RENDERED_BLOCK.contains(block);"));
      assertTrue(source.contains("if (!blockState.isAir() && !isVanillaRendered(blockState.getBlock())) {"));
   }

   @Test
   void blockRegistryMatchesUpstreamStateEncodingLocaleAndUnknownIdHandling() throws Exception {
      String source = Files.readString(BLOCK_REGISTRY);

      assertTrue(source.contains("p.getName().toLowerCase(Locale.ENGLISH)"));
      assertTrue(source.contains("v.toString().toLowerCase(Locale.ENGLISH)"));
      assertTrue(source.contains("Optional<Block> block = Registries.BLOCK.getOrEmpty(Identifier.ofVanilla(blockName));"));
      assertTrue(source.contains("if (block.isEmpty()) {"));
      assertTrue(source.contains("UnmodifiableIterator var2 = block.get().getStateManager().getStates().iterator();"));
   }
}
