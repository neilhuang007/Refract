package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.AtomicIntegerImage;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.IRenderDispatcher;
import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.IntStream;
import kroppeb.stareval.function.FunctionReturn;
import kroppeb.stareval.function.Type;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.parsing.MatrixType;
import net.irisshaders.iris.parsing.VectorType;
import net.irisshaders.iris.pipeline.IrisRenderingPipeline;
import net.irisshaders.iris.pipeline.WorldRenderingPipeline;
import net.irisshaders.iris.uniforms.CapturedRenderingState;
import net.irisshaders.iris.uniforms.custom.CustomUniforms;
import net.irisshaders.iris.uniforms.custom.cached.CachedUniform;
import net.minecraft.client.util.Window;
import net.minecraft.entity.Entity;
import net.minecraft.entity.player.PlayerInventory;
import net.minecraft.item.Item;
import net.minecraft.item.ItemStack;
import net.minecraft.world.World;
import net.minecraft.block.Block;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.chunk.ChunkSection;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.RegistryKey;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.registry.Registries;
import org.joml.Matrix4f;
import org.joml.Vector3f;

public class RenderDispatcher implements IRenderDispatcher, Destructable {
   private static final MinecraftClient MC_INSTANCE = MinecraftClient.getInstance();
   private final AtomicIntegerImage[] gi;
   private final Map<Integer, Integer> boundTextures = new HashMap<>();
   private final Set<PChunkPos> inboundChunks = new HashSet<>();
   private int cachedInboundCenterX = Integer.MIN_VALUE;
   private int cachedInboundCenterY = Integer.MIN_VALUE;
   private int cachedInboundCenterZ = Integer.MIN_VALUE;
   private int cachedInboundRenderRadius = Integer.MIN_VALUE;

   public RenderDispatcher(float renderScale) {
      this.gi = IntStream.range(0, 5).mapToObj(i -> new AtomicIntegerImage(() -> {
         Window window = MinecraftClient.getInstance().getWindow();
         return new Vector3f(window.getFramebufferWidth() * renderScale, window.getFramebufferHeight() * renderScale, 2.0F);
      })).toArray(AtomicIntegerImage[]::new);
   }

   @Override
   public TextureObject getTextureObject(String textureType) {
      return switch (textureType) {
         case "gi_x" -> this.gi[0];
         case "gi_y" -> this.gi[1];
         case "gi_z" -> this.gi[2];
         case "gi_w" -> this.gi[3];
         case "gi_d" -> this.gi[4];
         default -> throw new UnsupportedOperationException();
      };
   }

   @Override
   public void onChunkLoad() {
   }

   @Override
   public Set<PChunkPos> getInboundChunks() {
      Entity cameraEntity = MinecraftClient.getInstance().getCameraEntity();
      if (cameraEntity == null) {
         this.inboundChunks.clear();
         this.cachedInboundCenterX = Integer.MIN_VALUE;
         this.cachedInboundCenterY = Integer.MIN_VALUE;
         this.cachedInboundCenterZ = Integer.MIN_VALUE;
         this.cachedInboundRenderRadius = Integer.MIN_VALUE;
         return Set.of();
      }

      Vec3d chunkPos = cameraEntity.getPos().multiply(0.0625, 0.0625, 0.0625);
      int centerX = (int) chunkPos.x;
      int centerY = (int) chunkPos.y;
      int centerZ = (int) chunkPos.z;
      int renderRadius = (Integer) MinecraftClient.getInstance().options.getViewDistance().getValue() + 1;
      if (centerX == this.cachedInboundCenterX
         && centerY == this.cachedInboundCenterY
         && centerZ == this.cachedInboundCenterZ
         && renderRadius == this.cachedInboundRenderRadius) {
         return this.inboundChunks;
      }

      this.cachedInboundCenterX = centerX;
      this.cachedInboundCenterY = centerY;
      this.cachedInboundCenterZ = centerZ;
      this.cachedInboundRenderRadius = renderRadius;
      this.inboundChunks.clear();
      for (int x = -renderRadius; x < renderRadius; x++) {
         for (int y = -renderRadius; y < renderRadius; y++) {
            for (int z = -renderRadius; z < renderRadius; z++) {
               this.inboundChunks.add(new PChunkPos(centerX + x, centerY + y, centerZ + z));
            }
         }
      }
      return this.inboundChunks;
   }

   @Override
   public boolean isChunkEmpty(PChunkPos pos) {
      World level = MC_INSTANCE.world;
      if (level == null) {
         return true;
      } else if (level.isOutOfHeightLimit(16 * pos.y)) {
         return true;
      } else {
         ChunkSection[] sections = level.getChunk(new BlockPos(16 * pos.x, 16 * pos.y, 16 * pos.z)).getSectionArray();
         int posY = pos.y - level.getBottomY() / 16;
         return sections[posY] == null || sections[posY].isEmpty();
      }
   }

   public Matrix4f getModelViewMatrix(Vector3f cameraPosition) {
      Matrix4f matrix4f = new Matrix4f(CapturedRenderingState.INSTANCE.getGbufferModelView());
      return matrix4f.translate(-cameraPosition.x, -cameraPosition.y, -cameraPosition.z);
   }

   @Override
   public Matrix4f getModelViewProjectionMatrix(Vector3f cameraPosition) {
      return new Matrix4f(CapturedRenderingState.INSTANCE.getGbufferProjection()).mul(this.getModelViewMatrix(cameraPosition));
   }

   @Override
   public boolean isLeftHanded() {
      return true;
   }

   public Object getValueUniform(String uniformName) {
      WorldRenderingPipeline worldRenderingPipeline = Iris.getPipelineManager().getPipelineNullable();
      if (!(worldRenderingPipeline instanceof IrisRenderingPipeline)) {
         return null;
      } else {
         CustomUniforms customUniforms = ((IrisRenderingPipeline)worldRenderingPipeline).getCustomUniforms();

         CachedUniform cachedUniform;
         try {
            cachedUniform = (CachedUniform)customUniforms.getVariable(uniformName);
         } catch (RuntimeException var7) {
            return null;
         }

         if (cachedUniform == null) {
            return null;
         } else {
            cachedUniform.update();
            FunctionReturn functionReturn = new FunctionReturn();
            cachedUniform.writeTo(functionReturn);
            if (cachedUniform.getType() == Type.Float) {
               return functionReturn.floatReturn;
            } else if (cachedUniform.getType() == Type.Int) {
               return functionReturn.intReturn;
            } else if (cachedUniform.getType() == VectorType.VEC3) {
               Vector3f vector3f = (Vector3f)functionReturn.objectReturn;
               return new Vector3f(vector3f.x, vector3f.y, vector3f.z);
            } else if (cachedUniform.getType() == MatrixType.MAT4) {
               return functionReturn.objectReturn;
            } else {
               throw new IllegalArgumentException();
            }
         }
      }
   }

   @Override
   public Vector3f getHandheldColor() {
      return getHandheld();
   }

   private static Vector3f getHandheld() {
      ClientPlayerEntity player = MC_INSTANCE.player;
      if (player == null) {
         return new Vector3f();
      } else {
         PlayerInventory inventory = player.getInventory();
         List<ItemStack> itemStacks = new ArrayList<>();
         itemStacks.add(inventory.getMainHandStack());
         itemStacks.add((ItemStack)inventory.offHand.get(0));
         Vector3f color = new Vector3f();

         for (ItemStack itemStack : itemStacks) {
            if (itemStack.hasEnchantments()) {
               color.add(0.12941177F, 0.050980393F, 0.30980393F);
            } else {
               RegistryKey<Item> itemRegistryKey = (RegistryKey<Item>)Registries.ITEM.getKey(itemStack.getItem()).orElse(null);
               if (itemRegistryKey != null) {
                  Block block = (Block)Registries.BLOCK.get(itemRegistryKey.getValue());
                  BlockLightInfo light = PhotonicsConfig.getLightList().getDefault(block);
                  if (light != null) {
                     color.add(light.getColorAsVector());
                  }
               }
            }
         }

         return color;
      }
   }

   @Override
   public void free() {
      for (AtomicIntegerImage image : this.gi) {
         image.free();
      }
   }
}
