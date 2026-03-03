package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.AtomicIntegerImage;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.IRenderDispatcher;
import at.redi2go.photonic.client.rendering.world.LightBlock;
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

   public RenderDispatcher() {
      this.gi = IntStream.range(0, 5).mapToObj(i -> new AtomicIntegerImage(() -> {
         Window window = MinecraftClient.getInstance().getWindow();
         return new Vector3f(window.getFramebufferWidth(), window.getFramebufferHeight(), 2.0F);
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
      Set<PChunkPos> chunks = new HashSet<>();
      Entity cameraEntity = MinecraftClient.getInstance().getCameraEntity();
      if (cameraEntity == null) {
         return Set.of();
      } else {
         Vec3d chunkPos = cameraEntity.getPos().multiply(0.0625, 0.0625, 0.0625);
         int renderRadius = (Integer)MinecraftClient.getInstance().options.getViewDistance().getValue() + 1;

         for (int x = -renderRadius; x < renderRadius; x++) {
            for (int y = -renderRadius; y < renderRadius; y++) {
               for (int z = -renderRadius; z < renderRadius; z++) {
                  PChunkPos worldChunkPos = new PChunkPos((int)(chunkPos.x + x), (int)(chunkPos.y + y), (int)(chunkPos.z + z));
                  chunks.add(worldChunkPos);
               }
            }
         }

         return chunks;
      }
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
                  LightBlock lightBlock = PhotonicsStorage.TRACED_LIGHT_BLOCKS
                     .value
                     .stream()
                     .filter(lightBlock1 -> lightBlock1.block == block)
                     .findFirst()
                     .orElse(null);
                  if (lightBlock != null && lightBlock.lightType.blockStateEmitsLight(block.getDefaultState())) {
                     color.add(lightBlock.lightType.getColor());
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
