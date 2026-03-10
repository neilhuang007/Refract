package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class VoxelizedBlockParityTest {
   private static final Path SETTINGS_SCREEN = Path.of("src/at/redi2go/photonic/client/ModSettingsScreen.java");
   private static final Path CHUNK_MESHING_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/ChunkBuilderMeshingTaskMixin.java");
   private static final Path BLOCK_OCCLUSION_CACHE_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/BlockOcclusionCacheMixin.java");

   @Test
   void settingsScreenUsesPhotonicsConfigForVoxelAndTracedBlockOverrides() throws IOException {
      String source = Files.readString(SETTINGS_SCREEN);

      assertTrue(source.contains("PhotonicsConfig.prepareModify();"));
      assertTrue(source.contains("PhotonicsConfig.onChanged();"));
      assertTrue(source.contains("PhotonicsConfig.save();"));
      assertTrue(source.contains("return PhotonicsConfig.isVoxelized(this.block);"));
      assertTrue(source.contains("PhotonicsConfig.setVoxelized(this.block, enabled);"));
      assertTrue(source.contains("Boolean override = PhotonicsConfig.getTracedOverrides().get(this.block);"));
      assertTrue(source.contains("return override != null ? override : PhotonicsConfig.getLightList().isTraced(this.block);"));
      assertTrue(source.contains("PhotonicsConfig.getTracedOverrides().put(this.block, traced);"));
   }

   @Test
   void voxelizedChunkMeshingUsesProxyGeometryFromCompiledBlockData() throws IOException {
      String source = Files.readString(CHUNK_MESHING_MIXIN);

      assertTrue(source.contains("PhotonicsConfig.isVoxelized(instance.getBlock())"));
      assertTrue(source.contains("PBlock block = Raytracer.INSTANCE.getBlockRegistry().getBlock(instance);"));
      assertTrue(source.contains("block != null && block.canOcclude ? Blocks.STONE.getDefaultState() : Blocks.GLASS.getDefaultState()"));
      assertTrue(source.contains("cache.getBlockModels().getModelManager().getMissingModel()"));
   }

   @Test
   void blockOcclusionUsesVoxelizedConfigAndCompiledOcclusionFlag() throws IOException {
      String source = Files.readString(BLOCK_OCCLUSION_CACHE_MIXIN);

      assertTrue(source.contains("PhotonicsConfig.isVoxelized(neighborBlockState.getBlock())"));
      assertTrue(source.contains("PBlock block = Raytracer.INSTANCE != null ? Raytracer.INSTANCE.getBlockRegistry().getBlock(neighborBlockState) : null;"));
      assertTrue(source.contains("if (block != null && !block.canOcclude)"));
   }
}
