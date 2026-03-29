package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.GL;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.PBlock;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import com.mojang.blaze3d.platform.GlStateManager.Viewport;
import com.mojang.blaze3d.systems.RenderSystem;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import net.irisshaders.iris.uniforms.CapturedRenderingState;
import net.minecraft.block.BlockEntityProvider;
import net.minecraft.block.BlockState;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gl.ShaderProgram;
import net.minecraft.client.gl.VertexBuffer;
import net.minecraft.client.gl.VertexBuffer.Usage;
import net.minecraft.client.render.BuiltBuffer;
import net.minecraft.client.render.BufferBuilder;
import net.minecraft.client.render.OverlayTexture;
import net.minecraft.client.render.RenderLayer;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.client.render.VertexFormat;
import net.minecraft.client.render.VertexFormats;
import net.minecraft.client.render.block.entity.BlockEntityRenderer;
import net.minecraft.client.util.BufferAllocator;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.util.math.BlockPos;
import org.joml.Matrix4f;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL42;

public class BlockBuilder {
   private static final int MAX_DEBUG_VOXELS_TO_LOG = Integer.getInteger("photonics.debug.maxVoxelLogs", 8);
   private static final Map<VertexFormat, String> SCHEMATIC_SHADER_BY_FORMAT = new HashMap<>(
      Map.of(VertexFormats.POSITION_COLOR_TEXTURE_LIGHT_NORMAL, "schematic6", VertexFormats.POSITION_COLOR_TEXTURE_OVERLAY_LIGHT_NORMAL, "schematic7")
   );
   private static final GlMemoryManager SCHEMATIC_MEMORY_MANAGER = new GlMemoryManager(GlTarget.SSBO, "world_array_block", 16384, false);
   private static final MemoryOwner SCHEMATIC_MEMORY = new SimpleMemoryOwner(SCHEMATIC_MEMORY_MANAGER, SCHEMATIC_MEMORY_MANAGER.getCapacity());
   public static int RENDER_INDEX = 0;
   public static boolean IS_BUILDING_BLOCK_BUFFER = false;
   private static final Map<RenderLayer, BufferBuilder> RENDER_TYPE_BUFFER_BUILDERS = new LinkedHashMap<>();
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
      Raytracer.INSTANCE.queueOpenGLJob(() -> {
         Schematic schematic = buildBlockSchematic(blockState);
         schematic.initialize();
         Raytracer.INSTANCE.queueUrgentBuildJob(() -> block.setCompiledSchematicSupplier(() -> schematic));
         schematic.optimizeThreaded().thenRun(() -> Raytracer.INSTANCE.queueUrgentBuildJob(() -> block.setCompiledSchematicSupplier(() -> schematic)));
      });
   }

   public static Schematic buildBlockSchematic(BlockState blockState) {
      long buildStartNanos = System.nanoTime();
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

      minecraft.getBlockRenderManager().renderBlockAsEntity(blockState, new MatrixStack(), MULTI_BUFFER_BUILDER, 15728880, OverlayTexture.DEFAULT_UV);

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
      int renderTypesUsed = RENDER_TYPE_BUFFER_BUILDERS.size();
      RENDER_TYPE_BUFFER_BUILDERS.clear();
      RenderSystem.enableCull();
      RenderSystem.enableDepthTest();
      GL11.glViewport(Viewport.getX(), Viewport.getY(), Viewport.getWidth(), Viewport.getHeight());
      GL11.glFinish();
      GL42.glMemoryBarrier(512);
      GL42.glMemoryBarrier(GL.pGetShaderWriteToCpuBarrierBits());
      int[] schematicData = new int[SCHEMATIC_MEMORY.getSize() >> 2];
      SCHEMATIC_MEMORY_MANAGER.download(byteBuffer -> byteBuffer.asIntBuffer().get(schematicData));
      int nonZeroVoxelCount = 0;
      int pureRedVoxelCount = 0;
      int pureGreenVoxelCount = 0;
      int pureYellowVoxelCount = 0;
      int lowInfoVoxelCount = 0;
      int sampledSuspiciousVoxels = 0;
      StringBuilder suspicious = Photonic.automationEnabled() ? new StringBuilder() : null;

      for (int i = 0; i < schematicData.length; i++) {
         schematicData[i] = repackShaderVoxelWord(schematicData[i]);
         int word = schematicData[i];
         if (word != 0) {
            nonZeroVoxelCount++;
            int r = word & 255;
            int g = word >> 8 & 255;
            int b = word >> 16 & 255;
            int a = word >>> 24;
            boolean pureRed = r >= 250 && g <= 8 && b <= 8;
            boolean pureGreen = g >= 250 && r <= 8 && b <= 8;
            boolean pureYellow = r >= 250 && g >= 250 && b <= 8;
            boolean lowInfo = r <= 2 && g <= 2 && b <= 2 && a > 0 && a < 255;
            if (pureRed) {
               pureRedVoxelCount++;
            }
            if (pureGreen) {
               pureGreenVoxelCount++;
            }
            if (pureYellow) {
               pureYellowVoxelCount++;
            }
            if (lowInfo) {
               lowInfoVoxelCount++;
            }
            if (suspicious != null && sampledSuspiciousVoxels < MAX_DEBUG_VOXELS_TO_LOG && (pureRed || pureGreen || pureYellow || lowInfo)) {
               suspicious.append(" idx=")
                  .append(i)
                  .append(" rgba=")
                  .append(r)
                  .append(',')
                  .append(g)
                  .append(',')
                  .append(b)
                  .append(',')
                  .append(a);
               sampledSuspiciousVoxels++;
            }
         }
      }

      if (Photonic.automationEnabled()) {
         long elapsedMillis = (System.nanoTime() - buildStartNanos) / 1000000L;
         if (pureRedVoxelCount > 0 || pureGreenVoxelCount > 0 || pureYellowVoxelCount > 0 || lowInfoVoxelCount > 0 || elapsedMillis >= 25L || nonZeroVoxelCount == 0) {
            Photonic.info(
               "[BlockBuilderDebug] state={} ms={} nonZeroVoxels={} pureRed={} pureGreen={} pureYellow={} lowInfo={} renderTypes={} queuedGlJobs={}{}",
               blockState,
               elapsedMillis,
               nonZeroVoxelCount,
               pureRedVoxelCount,
               pureGreenVoxelCount,
               pureYellowVoxelCount,
               lowInfoVoxelCount,
               renderTypesUsed,
               Raytracer.INSTANCE.getWorldRegistry().getGlQueue().size(),
               suspicious == null || suspicious.isEmpty() ? "" : suspicious.toString()
            );
         }
      }

      return new Schematic(schematicData, 16, 16, 16);
   }

   static int repackShaderVoxelWord(int color) {
      int alpha = color >>> 24 & 127;
      int rgb = color & 16777215;
      return rgb | ((127 - alpha) << 24);
   }
}
