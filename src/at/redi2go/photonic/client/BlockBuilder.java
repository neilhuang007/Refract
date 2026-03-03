package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.opengl.GL;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.PBlock;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import com.mojang.blaze3d.platform.GlStateManager.Viewport;
import com.mojang.blaze3d.systems.RenderSystem;
import java.util.HashMap;
import java.util.Map;
import net.irisshaders.iris.uniforms.CapturedRenderingState;
import net.minecraft.client.render.model.BakedModel;
import net.minecraft.client.render.RenderLayer;
import net.minecraft.block.Blocks;
import net.minecraft.util.math.BlockPos;
import net.minecraft.block.BlockEntityProvider;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.block.BlockState;
import net.minecraft.client.render.BufferBuilder;
import net.minecraft.client.render.VertexFormats;
import net.minecraft.client.gl.VertexBuffer;
import net.minecraft.client.render.VertexFormat;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.client.render.OverlayTexture;
import net.minecraft.client.render.RenderLayers;
import net.minecraft.util.math.random.Random;
import net.minecraft.client.gl.ShaderProgram;
import net.minecraft.client.render.block.entity.BlockEntityRenderer;
import net.minecraft.client.util.BufferAllocator;
import net.minecraft.client.render.BuiltBuffer;
import net.minecraft.client.gl.VertexBuffer.Usage;
import org.joml.Matrix4f;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL42;

public class BlockBuilder {
   private static final Map<VertexFormat, String> SCHEMATIC_SHADER_BY_FORMAT = new HashMap<>(
      Map.of(VertexFormats.POSITION_COLOR_TEXTURE_LIGHT_NORMAL, "schematic6", VertexFormats.POSITION_COLOR_TEXTURE_OVERLAY_LIGHT_NORMAL, "schematic7")
   );
   private static final GlMemoryManager SCHEMATIC_MEMORY_MANAGER = new GlMemoryManager(GlTarget.SSBO, "world_array_block", 16384, false);
   private static final MemoryOwner SCHEMATIC_MEMORY = new SimpleMemoryOwner(SCHEMATIC_MEMORY_MANAGER, SCHEMATIC_MEMORY_MANAGER.getCapacity());
   public static int RENDER_INDEX = 0;
   public static boolean IS_BUILDING_BLOCK_BUFFER = false;
   private static final Map<RenderLayer, BufferBuilder> RENDER_TYPE_BUFFER_BUILDERS = new HashMap<>();
   private static VertexBuffer BLOCK_RENDERER = null;
   private static final VertexConsumerProvider MULTI_BUFFER_BUILDER = renderType -> {
      BufferBuilder bufferBuilder = RENDER_TYPE_BUFFER_BUILDERS.get(renderType);
      if (bufferBuilder != null) {
         return bufferBuilder;
      } else {
         RENDER_TYPE_BUFFER_BUILDERS.put(renderType, bufferBuilder = new BufferBuilder(new BufferAllocator(4096), renderType.getDrawMode(), renderType.getVertexFormat()));
         return bufferBuilder;
      }
   };

   public static void streamBlockBuild(BlockState blockState, PBlock block) {
      if (blockState.getBlock() != Blocks.LAVA
         && blockState.getBlock() != Blocks.LIGHT
         && blockState.getBlock() != Blocks.END_PORTAL) {
         Raytracer.INSTANCE.queueOpenGLJob(() -> {
            Schematic schematic = buildBlockSchematic(blockState);
            schematic.initialize();
            Raytracer.INSTANCE.queueUrgentBuildJob(() -> {
               block.setCompiledSchematicSupplier(() -> schematic);
               block.update(Raytracer.INSTANCE.getWorldRegistry().getCbMemoryManager());
            });
            schematic.optimizeThreaded().thenRun(() -> Raytracer.INSTANCE.queueUrgentBuildJob(() -> {
               block.setCompiledSchematicSupplier(() -> schematic);
               block.update(Raytracer.INSTANCE.getWorldRegistry().getCbMemoryManager());
            }));
         });
      }
   }

   public static Schematic buildBlockSchematic(BlockState blockState) {
      if (BLOCK_RENDERER == null) {
         BLOCK_RENDERER = new VertexBuffer(Usage.DYNAMIC);
      }

      MinecraftClient minecraft = MinecraftClient.getInstance();
      IS_BUILDING_BLOCK_BUFFER = true;
      if (blockState.hasBlockEntity()) {
         BlockEntityProvider entityBlock = (BlockEntityProvider)blockState.getBlock();
         BlockEntity blockEntity = entityBlock.createBlockEntity(new BlockPos(0, 0, 0), blockState);
         if (blockEntity != null) {
            blockEntity.setWorld(minecraft.world);
            float partialTick = CapturedRenderingState.INSTANCE.getTickDelta();
            BlockEntityRenderer<BlockEntity> blockEntityRenderer = minecraft.getBlockEntityRenderDispatcher().get(blockEntity);
            MatrixStack poseStack = new MatrixStack();
            poseStack.push();
            if (blockEntityRenderer != null) {
               blockEntityRenderer.render(blockEntity, partialTick, poseStack, MULTI_BUFFER_BUILDER, 240, OverlayTexture.DEFAULT_UV);
            }
         }
      }

      BakedModel model = minecraft.getBlockRenderManager().getModel(blockState);
      if (model != minecraft.getBakedModelManager().getMissingModel()) {
         minecraft.getBlockRenderManager()
            .getModelRenderer()
            .render(
               MinecraftClient.getInstance().world,
               model,
               blockState,
               new BlockPos(0, 0, 0),
               new MatrixStack(),
               MULTI_BUFFER_BUILDER.getBuffer(RenderLayers.getBlockLayer(blockState)),
               false,
               Random.create(0L),
               blockState.getRenderingSeed(new BlockPos(0, 0, 0)),
               OverlayTexture.DEFAULT_UV
            );
      }

      IS_BUILDING_BLOCK_BUFFER = false;
      BLOCK_RENDERER.bind();
      Matrix4f modelViewMatrix = new Matrix4f();
      modelViewMatrix.identity();
      Matrix4f identityMatrix = new Matrix4f();
      identityMatrix.identity();
      GL11.glViewport(0, 0, 16, 16);
      SCHEMATIC_MEMORY_MANAGER.queueUpload(SCHEMATIC_MEMORY);
      SCHEMATIC_MEMORY_MANAGER.upload();
      RENDER_TYPE_BUFFER_BUILDERS.forEach((renderType, bufferBuilder) -> {
         BuiltBuffer meshData = bufferBuilder.endNullable();

         label53: {
            try {
               if (meshData == null) {
                  break label53;
               }

               BLOCK_RENDERER.upload(meshData);
               ShaderProgram shader = minecraft.gameRenderer.getProgram(SCHEMATIC_SHADER_BY_FORMAT.get(renderType.getVertexFormat()));
               if (shader == null) {
                  throw new IllegalStateException("There is no shader for vertex format " + renderType.getVertexFormat());
               }

               renderType.startDrawing();
               RenderSystem.setShader(() -> shader);
               RenderSystem.disableCull();
               int blockIndex = SCHEMATIC_MEMORY_MANAGER.findInProgram(shader.getGlRef());
               SCHEMATIC_MEMORY_MANAGER.bind(shader.getGlRef(), blockIndex, 0);

               for (RENDER_INDEX = 0; RENDER_INDEX < 3; RENDER_INDEX++) {
                  BLOCK_RENDERER.draw(modelViewMatrix, identityMatrix, RenderSystem.getShader());
               }

               renderType.endDrawing();
            } catch (Throwable var9x) {
               if (meshData != null) {
                  try {
                     meshData.close();
                  } catch (Throwable var8x) {
                     var9x.addSuppressed(var8x);
                  }
               }

               throw var9x;
            }

            if (meshData != null) {
               meshData.close();
            }

            return;
         }

         if (meshData != null) {
            meshData.close();
         }
      });
      RENDER_TYPE_BUFFER_BUILDERS.clear();
      RenderSystem.enableCull();
      RenderSystem.enableDepthTest();
      GL11.glViewport(Viewport.getX(), Viewport.getY(), Viewport.getWidth(), Viewport.getHeight());
      GL11.glFinish();
      GL42.glMemoryBarrier(512);
      GL42.glMemoryBarrier(GL.pGetShaderWriteToCpuBarrierBits());
      int[] schematicData = new int[SCHEMATIC_MEMORY.getSize() >> 2];
      SCHEMATIC_MEMORY_MANAGER.download(byteBuffer -> byteBuffer.asIntBuffer().get(schematicData));
      return new Schematic(schematicData, 16, 16, 16);
   }
}
