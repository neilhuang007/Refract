package at.redi2go.photonic.client.config.lights;

import java.util.List;
import java.util.Objects;
import net.minecraft.block.BlockState;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.fluid.FluidState;
import net.minecraft.registry.DynamicRegistryManager;
import net.minecraft.registry.entry.RegistryEntry;
import net.minecraft.resource.featuretoggle.FeatureSet;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.Direction;
import net.minecraft.util.shape.VoxelShape;
import net.minecraft.world.Heightmap;
import net.minecraft.world.WorldView;
import net.minecraft.world.biome.Biome;
import net.minecraft.world.biome.source.BiomeAccess;
import net.minecraft.world.border.WorldBorder;
import net.minecraft.world.chunk.Chunk;
import net.minecraft.world.chunk.ChunkStatus;
import net.minecraft.world.chunk.light.LightingProvider;
import net.minecraft.world.dimension.DimensionType;
import org.jetbrains.annotations.Nullable;

public class FakeLevelReader implements WorldView {
   private final BlockState blockState;

   public FakeLevelReader(BlockState blockState) {
      this.blockState = Objects.requireNonNull(blockState, "block was null");
   }

   @Override
   public boolean isChunkLoaded(int chunkX, int chunkZ) {
      return true;
   }

   @Override
   public BlockState getBlockState(BlockPos pos) {
      return this.blockState;
   }

   @Override
   @Nullable
   public BlockEntity getBlockEntity(BlockPos pos) {
      return null;
   }

   @Override
   public DynamicRegistryManager getRegistryManager() {
      return Objects.requireNonNull(MinecraftClient.getInstance().world).getRegistryManager();
   }

   @Override
   @Nullable
   public Chunk getChunk(int chunkX, int chunkZ, ChunkStatus leastStatus, boolean create) {
      throw new UnsupportedOperationException("getChunk");
   }

   @Override
   public int getTopY(Heightmap.Type heightmap, int x, int z) {
      throw new UnsupportedOperationException("getTopY");
   }

   @Override
   public int getAmbientDarkness() {
      throw new UnsupportedOperationException("getAmbientDarkness");
   }

   @Override
   public BiomeAccess getBiomeAccess() {
      throw new UnsupportedOperationException("getBiomeAccess");
   }

   @Override
   public RegistryEntry<Biome> getGeneratorStoredBiome(int biomeX, int biomeY, int biomeZ) {
      throw new UnsupportedOperationException("getGeneratorStoredBiome");
   }

   @Override
   public boolean isClient() {
      return true;
   }

   @Override
   public int getSeaLevel() {
      throw new UnsupportedOperationException("getSeaLevel");
   }

   @Override
   public DimensionType getDimension() {
      throw new UnsupportedOperationException("getDimension");
   }

   @Override
   public FeatureSet getEnabledFeatures() {
      throw new UnsupportedOperationException("getEnabledFeatures");
   }

   @Override
   public float getBrightness(Direction direction, boolean shaded) {
      throw new UnsupportedOperationException("getBrightness");
   }

   @Override
   public LightingProvider getLightingProvider() {
      throw new UnsupportedOperationException("getLightingProvider");
   }

   @Override
   public WorldBorder getWorldBorder() {
      throw new UnsupportedOperationException("getWorldBorder");
   }

   @Override
   public List<VoxelShape> getEntityCollisions(@Nullable Entity entity, Box box) {
      throw new UnsupportedOperationException("getEntityCollisions");
   }

   @Override
   public FluidState getFluidState(BlockPos pos) {
      throw new UnsupportedOperationException("getFluidState");
   }
}
