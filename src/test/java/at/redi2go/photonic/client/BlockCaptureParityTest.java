package at.redi2go.photonic.client;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BlockCaptureParityTest {
   private static final Path BLOCK_BUILDER = Path.of("src/at/redi2go/photonic/client/BlockBuilder.java");
   private static final Path GAME_RENDERER_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/GameRendererMixin.java");
   private static final Path BLOCK_MODEL_RENDERER_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/BlockModelRendererMixin.java");
   private static final Path FABRIC_MODEL_ACCESS_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/FabricModelAccessMixin.java");
   private static final Path MIXINS_JSON = Path.of("photonics.mixins.json");

   @Test
   void blockBuilderUsesDispatcherEntityRenderPathForVoxelCapture() throws Exception {
      String source = Files.readString(BLOCK_BUILDER);

      assertTrue(source.contains(".getBlockRenderManager().renderBlockAsEntity("));
      assertFalse(source.contains(".getModelRenderer()"));
      assertFalse(source.contains("RenderLayers.getBlockLayer(blockState)"));
   }

   @Test
   void schematic7KeepsOverlayVertexFormatParity() throws Exception {
      String source = Files.readString(GAME_RENDERER_MIXIN);

      assertTrue(source.contains("new ShaderProgram(resourceProvider, \"schematic7\", VertexFormats.POSITION_COLOR_TEXTURE_OVERLAY_LIGHT_NORMAL);"));
   }

   @Test
   void fabricModelAccessFilteringExistsForBlockCapture() throws Exception {
      assertTrue(Files.exists(FABRIC_MODEL_ACCESS_MIXIN));

      String source = Files.readString(FABRIC_MODEL_ACCESS_MIXIN);
      String mixins = Files.readString(MIXINS_JSON);

      assertTrue(source.contains("@Mixin(FabricModelAccess.class)"));
      assertTrue(source.contains("BlockBuilder.IS_BUILDING_BLOCK_BUFFER"));
      assertTrue(source.contains(".filter(bakedQuad -> ((BakedQuadExt)bakedQuad).photonic$shouldBeVoxelized())"));
      assertTrue(mixins.contains("\"FabricModelAccessMixin\""));
   }

   @Test
   void blockCaptureDoesNotUseExtraBlockModelRendererPruning() throws Exception {
      String mixins = Files.readString(MIXINS_JSON);

      assertFalse(Files.exists(BLOCK_MODEL_RENDERER_MIXIN));
      assertFalse(mixins.contains("\"BlockModelRendererMixin\""));
   }
}
