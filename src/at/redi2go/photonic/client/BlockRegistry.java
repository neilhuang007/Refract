package at.redi2go.photonic.client;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.config.lights.LightList;
import at.redi2go.photonic.client.magicavoxel.VoxReader;
import at.redi2go.photonic.client.mixin.ReloadableResourceManagerAccessor;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.MinecraftAtlasDownloader;
import at.redi2go.photonic.client.rendering.world.NativeBlockPayload;
import at.redi2go.photonic.client.rendering.world.NativeBlockPayloadBuilder;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonics.core.rendering.world.allocator.BufferWorldAllocator;
import at.redi2go.photonics.core.rendering.world.block.BlockEntry;
import at.redi2go.photonics.core.rendering.world.block.palette.TextureData;
import com.google.common.collect.UnmodifiableIterator;
import java.io.IOException;
import java.nio.charset.Charset;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.Map.Entry;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Consumer;
import net.minecraft.world.World;
import net.minecraft.block.Blocks;
import net.minecraft.block.Block;
import net.minecraft.util.math.BlockPos;
import net.minecraft.block.BlockState;
import net.minecraft.state.property.Properties;
import net.minecraft.state.property.Property;
import net.minecraft.util.Identifier;
import net.minecraft.client.MinecraftClient;
import net.minecraft.resource.Resource;
import net.minecraft.resource.ResourceReloader;
import net.minecraft.resource.ReloadableResourceManagerImpl;
import net.minecraft.util.Unit;
import net.minecraft.resource.ResourceFactory;
import net.minecraft.registry.Registries;
import org.apache.commons.io.IOUtils;
import org.joml.Vector3f;

public class BlockRegistry implements Destructable {
   private static final Schematic EMPTY_BLOCK = new Schematic(BlockBuilder.BLOCK_VOXEL_SIZE, BlockBuilder.BLOCK_VOXEL_SIZE, BlockBuilder.BLOCK_VOXEL_SIZE);
   public static final Set<Block> DEFAULT_STATE_BLOCKS = Set.of(Blocks.NOTE_BLOCK);
   public static final Set<Block> VANILLA_RENDERED_BLOCK = Set.of(
      Blocks.WATER,
      Blocks.LAVA,
      Blocks.BARRIER,
      Blocks.END_PORTAL,
      Blocks.END_GATEWAY,
      Blocks.TRIPWIRE,
      Blocks.ZOMBIE_HEAD,
      Blocks.ZOMBIE_WALL_HEAD,
      Blocks.PLAYER_HEAD,
      Blocks.PLAYER_WALL_HEAD,
      Blocks.CREEPER_HEAD,
      Blocks.CREEPER_WALL_HEAD,
      Blocks.DRAGON_HEAD,
      Blocks.DRAGON_WALL_HEAD,
      Blocks.PIGLIN_HEAD,
      Blocks.PIGLIN_WALL_HEAD,
      Blocks.OAK_SIGN,
      Blocks.SPRUCE_SIGN,
      Blocks.BIRCH_SIGN,
      Blocks.ACACIA_SIGN,
      Blocks.CHERRY_SIGN,
      Blocks.JUNGLE_SIGN,
      Blocks.DARK_OAK_SIGN,
      Blocks.MANGROVE_SIGN,
      Blocks.BAMBOO_SIGN,
      Blocks.OAK_WALL_SIGN,
      Blocks.SPRUCE_WALL_SIGN,
      Blocks.BIRCH_WALL_SIGN,
      Blocks.ACACIA_WALL_SIGN,
      Blocks.CHERRY_WALL_SIGN,
      Blocks.JUNGLE_WALL_SIGN,
      Blocks.DARK_OAK_WALL_SIGN,
      Blocks.MANGROVE_WALL_SIGN,
      Blocks.BAMBOO_WALL_SIGN,
      Blocks.OAK_HANGING_SIGN,
      Blocks.SPRUCE_HANGING_SIGN,
      Blocks.BIRCH_HANGING_SIGN,
      Blocks.ACACIA_HANGING_SIGN,
      Blocks.CHERRY_HANGING_SIGN,
      Blocks.JUNGLE_HANGING_SIGN,
      Blocks.DARK_OAK_HANGING_SIGN,
      Blocks.CRIMSON_HANGING_SIGN,
      Blocks.WARPED_HANGING_SIGN,
      Blocks.MANGROVE_HANGING_SIGN,
      Blocks.BAMBOO_HANGING_SIGN,
      Blocks.OAK_WALL_HANGING_SIGN,
      Blocks.SPRUCE_WALL_HANGING_SIGN,
      Blocks.BIRCH_WALL_HANGING_SIGN,
      Blocks.ACACIA_WALL_HANGING_SIGN,
      Blocks.CHERRY_WALL_HANGING_SIGN,
      Blocks.JUNGLE_WALL_HANGING_SIGN,
      Blocks.DARK_OAK_WALL_HANGING_SIGN,
      Blocks.MANGROVE_WALL_HANGING_SIGN,
      Blocks.CRIMSON_WALL_HANGING_SIGN,
      Blocks.WARPED_WALL_HANGING_SIGN,
      Blocks.BAMBOO_WALL_HANGING_SIGN,
      Blocks.CRIMSON_SIGN,
      Blocks.WARPED_SIGN,
      Blocks.CRIMSON_WALL_SIGN,
      Blocks.WARPED_WALL_SIGN,
      Blocks.WHITE_BANNER,
      Blocks.ORANGE_BANNER,
      Blocks.MAGENTA_BANNER,
      Blocks.LIGHT_BLUE_BANNER,
      Blocks.YELLOW_BANNER,
      Blocks.LIME_BANNER,
      Blocks.PINK_BANNER,
      Blocks.GRAY_BANNER,
      Blocks.LIGHT_GRAY_BANNER,
      Blocks.CYAN_BANNER,
      Blocks.PURPLE_BANNER,
      Blocks.BLUE_BANNER,
      Blocks.BROWN_BANNER,
      Blocks.GREEN_BANNER,
      Blocks.RED_BANNER,
      Blocks.BLACK_BANNER,
      Blocks.WHITE_WALL_BANNER,
      Blocks.ORANGE_WALL_BANNER,
      Blocks.MAGENTA_WALL_BANNER,
      Blocks.LIGHT_BLUE_WALL_BANNER,
      Blocks.YELLOW_WALL_BANNER,
      Blocks.LIME_WALL_BANNER,
      Blocks.PINK_WALL_BANNER,
      Blocks.GRAY_WALL_BANNER,
      Blocks.LIGHT_GRAY_WALL_BANNER,
      Blocks.CYAN_WALL_BANNER,
      Blocks.PURPLE_WALL_BANNER,
      Blocks.BLUE_WALL_BANNER,
      Blocks.BROWN_WALL_BANNER,
      Blocks.GREEN_WALL_BANNER,
      Blocks.RED_WALL_BANNER,
      Blocks.BLACK_WALL_BANNER
   );
   public static final Set<Property<?>> DEFAULT_PROPERTIES = Set.of(
      Properties.PERSISTENT, Properties.DISTANCE_1_7, Properties.WATERLOGGED, Properties.OCCUPIED
   );
   private static final MinecraftAtlasDownloader ATLAS_DOWNLOADER = new MinecraftAtlasDownloader();
   private final MemoryManager memoryManager;
   private final BufferWorldAllocator referenceAllocator;
   private final Map<BlockState, BlockEntry> referenceBlockEntryCache = new ConcurrentHashMap<>();
   private final Map<BlockState, Boolean> referenceOcclusionCache = new ConcurrentHashMap<>();
   private final Map<BlockState, Integer> emissiveColorCache = new ConcurrentHashMap<>();
   private final ResourceReloader resourceReloadListener = (preparationBarrier, resourceManager, profilerFiller, applyProfiler, applyExecutor, executor2) ->
      preparationBarrier.whenPrepared(Unit.INSTANCE).thenRunAsync(this::reloadBlockModels, applyExecutor);

   public BlockRegistry(MemoryManager memoryManager) {
      ((ReloadableResourceManagerImpl)MinecraftClient.getInstance().getResourceManager()).registerReloader(this.resourceReloadListener);
      this.memoryManager = memoryManager;
      this.referenceAllocator = NativeBlockPayloadBuilder.createAllocator(ATLAS_DOWNLOADER);
      memoryManager.allocate(NativeBlockPayload.BYTE_SIZE);
      NativeBlockPayload.numAllocated = 0;
   }

   public void freeUnused() {
      this.referenceAllocator.freeUnusedObjects();
   }

   public void ensureAllocated(NativeBlockPayload block) {
      synchronized (block) {
         if (block.isAllocated()) {
            if (block.needsUpdate()) {
               block.update(this.memoryManager);
            }
         } else {
            block.allocate(this.memoryManager);
            block.update(this.memoryManager);
         }
      }
   }

   public int getPackedBlock(PBlockPos blockPosition, int skyBrightness) {
      World level = MinecraftClient.getInstance().world;
      if (level == null) {
         return 0;
      } else {
         BlockState blockState;
         try {
            blockState = level.getBlockState(new BlockPos(blockPosition.x, blockPosition.y, blockPosition.z));
         } catch (Exception var6) {
            blockState = Blocks.AIR.getDefaultState();
         }

         return this.getPackedBlock(blockState, skyBrightness);
      }
   }

   public int getPackedBlock(BlockState blockState, int skyBrightness) {
      BlockEntry entry = this.getReferenceBlock(blockState, skyBrightness);
      return entry != null ? entry.begin() : 0;
   }

   public void updateLightInfo(BlockState blockState, BlockLightInfo lightInfo) {
      blockState = cleanUpBlockState(blockState);
      if (blockState == null) {
         return;
      }
      int emissiveColor = lightInfo == null || lightInfo.isTraced() ? 0 : lightInfo.packedColor() & 16777215;
      this.emissiveColorCache.put(blockState, emissiveColor);
      BlockEntry cachedEntry = this.referenceBlockEntryCache.remove(blockState);
      if (cachedEntry != null) {
         cachedEntry.close();
      }
   }

   public void refreshLightCache(LightList lights) {
      this.emissiveColorCache.clear();
      for (BlockState blockState : this.referenceBlockEntryCache.keySet()) {
         this.updateLightInfo(blockState, lights.get(blockState));
      }
   }

   public Schematic getSchematic(BlockState blockState) {
      blockState = cleanUpBlockState(blockState);
      if (blockState == null) {
         return null;
      }
      int blockId = at.redi2go.photonic.client.rendering.util.IrisUtil.getBlockId(blockState);
      int[] data = NativeBlockPayloadBuilder.build(blockState, blockId);
      return new Schematic(data, BlockBuilder.BLOCK_VOXEL_SIZE, BlockBuilder.BLOCK_VOXEL_SIZE, BlockBuilder.BLOCK_VOXEL_SIZE);
   }

   public int getEmissiveColor(BlockState blockState) {
      blockState = cleanUpBlockState(blockState);
      if (blockState == null) {
         return 0;
      }
      return this.emissiveColorCache.computeIfAbsent(blockState, state -> {
         LightRegistry lightRegistry = Raytracer.INSTANCE != null ? Raytracer.INSTANCE.getWorldRegistry().getLightRegistry() : null;
         BlockLightInfo lightInfo = lightRegistry != null ? lightRegistry.resolveBlockStateLightInfo(state) : null;
         return lightInfo == null || lightInfo.isTraced() ? 0 : lightInfo.packedColor() & 16777215;
      });
   }

   public NativeBlockPayload getBlock(PBlockPos blockPosition) {
      World level = MinecraftClient.getInstance().world;
      if (level == null) {
         return null;
      } else {
         BlockState blockState;
         try {
            blockState = level.getBlockState(new BlockPos(blockPosition.x, blockPosition.y, blockPosition.z));
         } catch (Exception var6) {
            blockState = Blocks.AIR.getDefaultState();
         }

         return this.getBlock(blockState);
      }
   }

   public NativeBlockPayload getBlock(BlockState blockState) {
      blockState = cleanUpBlockState(blockState);
      return blockState == null ? null : this.createNativePayload(blockState);
   }

   private NativeBlockPayload createNativePayload(BlockState blockState) {
      int blockId = at.redi2go.photonic.client.rendering.util.IrisUtil.getBlockId(blockState);
      NativeBlockPayloadBuilder.VoxelBake bake = NativeBlockPayloadBuilder.buildBake(blockState, blockId);
      NativeBlockPayload block = new NativeBlockPayload(blockId, bake.data());
      block.canOcclude = this.referenceOcclusionCache.computeIfAbsent(blockState, state -> bake.solidVoxelCount() >= NativeBlockPayload.SCHEMATIC_SIZE);
      block.setPackedEmissionColor(this.getEmissiveColor(blockState));
      return block;
   }

   public BlockEntry getReferenceBlock(BlockState blockState, int skyBrightness) {
      blockState = cleanUpBlockState(blockState);
      if (blockState == null) {
         return null;
      }

      BlockEntry cached = this.referenceBlockEntryCache.computeIfAbsent(blockState, this::createReferenceBlockEntry);
      if (cached == null) {
         return null;
      }

      if (cached.skylight() == skyBrightness) {
         return cached;
      }

      BlockEntry.Builder builder = cached.createBuilder();
      builder.setSkylight(Math.max(0, skyBrightness));
      BlockEntry result = builder.build();
      builder.close();
      return result;
   }

   private BlockEntry createReferenceBlockEntry(BlockState blockState) {
      int blockId = at.redi2go.photonic.client.rendering.util.IrisUtil.getBlockId(blockState);
      NativeBlockPayloadBuilder.ReferenceBake bake = NativeBlockPayloadBuilder.buildReferenceBake(blockState, blockId, this.referenceAllocator);
      if (bake == null || bake.entry() == null) {
         return null;
      }
      this.referenceOcclusionCache.put(blockState, bake.solidVoxelCount() >= NativeBlockPayload.SCHEMATIC_SIZE);
      return bake.entry();
   }

   public boolean canReferenceBlockOcclude(BlockState blockState) {
      blockState = cleanUpBlockState(blockState);
      if (blockState == null) {
         return false;
      }
      this.getReferenceBlock(blockState, 0);
      return this.referenceOcclusionCache.getOrDefault(blockState, false);
   }

   public boolean upload() {
      return this.memoryManager.upload();
   }

   public void reloadBlockModels() {
      Raytracer.INSTANCE.queueUrgentBuildJob(() -> {
         for (BlockEntry blockEntry : this.referenceBlockEntryCache.values()) {
            blockEntry.close();
         }
         this.referenceBlockEntryCache.clear();
         this.referenceOcclusionCache.clear();
         this.emissiveColorCache.clear();
         this.referenceAllocator.freeUnusedObjects();
      });
   }

   @Override
   public void free() {
      for (BlockEntry entry : this.referenceBlockEntryCache.values()) {
         entry.close();
      }
      this.referenceBlockEntryCache.clear();
      this.referenceOcclusionCache.clear();
      this.emissiveColorCache.clear();
      this.referenceAllocator.close();
      NativeBlockPayload.numAllocated = 0;
      ((ReloadableResourceManagerAccessor)MinecraftClient.getInstance().getResourceManager()).getListeners().remove(this.resourceReloadListener);
      this.memoryManager.free();
   }

   private static Schematic loadSchematicFromDisk(BlockState blockState, boolean aliased) {
      ResourceFactory resourceFactory = MinecraftClient.getInstance().getResourceManager();
      if (!aliased) {
         try {
            Optional<Resource> resource = resourceFactory.getResource(Identifier.ofVanilla("schematics/" + encodeBlockState(blockState) + ".alias"));
            if (resource.isPresent()) {
               List<String> lines = IOUtils.readLines(resource.get().getInputStream(), Charset.defaultCharset());
               if (lines.size() >= 2) {
                  BlockState baseBlockState = decodeBlockState(lines.get(0));
                  Consumer<Vector3f> transformation = decodeTransformation(lines.get(1));
                  Schematic schematic = loadSchematicFromDisk(baseBlockState, true);
                  if (baseBlockState != null && schematic != null) {
                     schematic = schematic.transform(transformation);
                     if (schematic != null) {
                        return schematic;
                     }
                  }
               }
            }
         } catch (IOException var9) {
         }
      }

      try {
         Optional<Resource> resource = resourceFactory.getResource(Identifier.ofVanilla("schematics/" + encodeBlockState(blockState) + ".vox"));
         if (resource.isPresent()) {
            Schematic schematic = VoxReader.readToSchematic(resource.get().getInputStream());
            if (schematic.getWidth() == BlockBuilder.BLOCK_VOXEL_SIZE
               && schematic.getHeight() == BlockBuilder.BLOCK_VOXEL_SIZE
               && schematic.getDepth() == BlockBuilder.BLOCK_VOXEL_SIZE) {
               return schematic;
            }
         }
      } catch (IOException var8) {
      }

      return null;
   }

   public static String encodeTransformation(int[] baseHash, int[] targetHash) {
      StringBuilder builder = new StringBuilder();
      boolean[] usedAxis = new boolean[3];
      int matches = 0;

      for (int i = 0; i < 3; i++) {
         for (int j = 0; j < 3; j++) {
            if (!usedAxis[j] && Math.abs(baseHash[j]) == Math.abs(targetHash[i])) {
               int sign = baseHash[j] != targetHash[i] ? -1 : 1;
               builder.append(sign * (j + 1)).append(' ');
               usedAxis[j] = true;
               matches++;
               break;
            }
         }
      }

      if (matches < 3) {
         System.err.println("Incorrect number of matches");
         return "1 2 3";
      } else {
         return builder.toString();
      }
   }

   public static Consumer<Vector3f> decodeTransformation(String encodedTransformation) {
      int[] transformation = Arrays.stream(encodedTransformation.split(" ")).mapToInt(Integer::parseInt).toArray();
      int[] indices = new int[3];
      int[] signs = new int[3];
      int[] offsets = new int[3];

      for (int i = 0; i < transformation.length; i++) {
         indices[i] = Math.abs(transformation[i]) - 1;
         signs[i] = transformation[i] < 0 ? -1 : 1;
         offsets[i] = transformation[i] < 0 ? BlockBuilder.BLOCK_VOXEL_SIZE - 1 : 0;
      }

      return p -> {
         float[] values = new float[]{p.x, p.y, p.z};
         p.set(
            signs[0] * values[indices[0]] + offsets[0],
            signs[1] * values[indices[1]] + offsets[1],
            signs[2] * values[indices[2]] + offsets[2]
         );
      };
   }

   public static String encodeBlockState(BlockState blockState) {
      if (blockState == null) {
         return "";
      } else {
         StringBuilder builder = new StringBuilder();
         builder.append(Registries.BLOCK.getId(blockState.getBlock()).toString().replace(':', '_'));
         if (!blockState.getEntries().isEmpty()) {
            builder.append('[');
            Iterator<Entry<Property<?>, Comparable<?>>> var2 = blockState.getEntries().entrySet().iterator();

            while (var2.hasNext()) {
               Entry<Property<?>, Comparable<?>> entry = (Entry)var2.next();
               builder.append(entry.getKey().getName())
                  .append('=')
                  .append(getValueName(entry.getKey(), entry.getValue()));
               if (var2.hasNext()) {
                  builder.append(',');
               }
            }

            builder.append(']');
         }
         return builder.toString();
      }
   }

   @SuppressWarnings("unchecked")
   private static <T extends Comparable<T>> String getValueName(Property<T> property, Comparable<?> value) {
      return property.name((T)value);
   }

   public static BlockState decodeBlockState(String blockStateName) {
      String[] split = blockStateName.split("\\[", 2);
      if (split.length == 0 || split[0].isEmpty()) {
         return null;
      }
      Identifier id = Identifier.tryParse(split[0].replace('_', ':'));
      if (id == null) {
         return null;
      }
      Block block = Registries.BLOCK.get(id);
      if (block == Blocks.AIR && !Registries.BLOCK.containsId(id)) {
         return null;
      }
      BlockState blockState = block.getDefaultState();
      if (split.length == 2 && split[1].endsWith("]")) {
         String properties = split[1].substring(0, split[1].length() - 1);
         for (String prop : properties.split(",")) {
            String[] propertySplit = prop.split("=", 2);
            if (propertySplit.length == 2) {
               Property<?> property = block.getStateManager().getProperty(propertySplit[0]);
               if (property != null) {
                  blockState = setProperty(blockState, property, propertySplit[1]);
               }
            }
         }
      }
      return blockState;
   }

   private static <T extends Comparable<T>> BlockState setProperty(BlockState blockState, Property<T> property, String value) {
      Optional<T> propertyValue = property.parse(value);
      return propertyValue.map(t -> blockState.with(property, t)).orElse(blockState);
   }

   public static BlockState cleanUpBlockState(BlockState blockState) {
      if (blockState == null || blockState.isAir() || !at.redi2go.photonic.client.config.PhotonicsConfig.isVoxelized(blockState.getBlock()) || VANILLA_RENDERED_BLOCK.contains(blockState.getBlock())) {
         return null;
      } else {
         if (DEFAULT_STATE_BLOCKS.contains(blockState.getBlock())) {
            blockState = blockState.getBlock().getDefaultState();
         }

         for (Property<?> property : DEFAULT_PROPERTIES) {
            if (blockState.contains(property)) {
               blockState = resetProperty(blockState, property);
            }
         }

         return blockState;
      }
   }

   private static <T extends Comparable<T>> BlockState resetProperty(BlockState blockState, Property<T> property) {
      return blockState.with(property, property.getValues().stream().toList().get(0));
   }
}
