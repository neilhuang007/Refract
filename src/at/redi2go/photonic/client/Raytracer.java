package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.rendering.MainRenderer;
import at.redi2go.photonic.client.rendering.opengl.rendering.ShaderUtil;
import at.redi2go.photonic.client.rendering.patching.Patch;
import at.redi2go.photonic.client.rendering.world.LightBlock;
import at.redi2go.photonic.client.rendering.world.LightType;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import com.mojang.blaze3d.systems.RenderSystem;
import java.io.File;
import java.io.IOException;
import java.net.URISyntaxException;
import java.net.URL;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardWatchEventKinds;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Properties;
import java.util.Set;
import java.util.function.Consumer;
import java.util.stream.Stream;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.shaderpack.include.IncludeGraph;
import net.minecraft.client.render.RenderLayer;
import net.minecraft.block.Blocks;
import net.minecraft.block.Block;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import net.minecraft.block.RedstoneWireBlock;
import net.minecraft.block.BlockState;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.model.json.ModelElementFace;
import org.joml.Vector2f;
import org.joml.Vector3f;

public class Raytracer implements Destructable {
   public static Raytracer INSTANCE;
   public static final Path DEV_ENV_SHADERS_PATH = Path.of("../src/main/resources/assets/photonic/shaders");
   public static Map<String, String> SHADERPACK_CHANGED_OPTIONS = null;
   public static Properties SHADERPACK_PROPERTIES = null;
   public static final List<Patch> AVAILABLE_PATCHES = new ArrayList<>();
   public static final TerrainRenderPass VOXEL = new TerrainRenderPass(RenderLayer.getCutout(), false, true);
   public static final Set<Block> DEFAULT_VOLUMETRIC_RENDERED_BLOCKS = Set.of(
      Blocks.CRAFTING_TABLE,
      Blocks.FURNACE,
      Blocks.LADDER,
      Blocks.SCULK_VEIN,
      Blocks.REDSTONE_WIRE,
      Blocks.DETECTOR_RAIL,
      Blocks.RAIL,
      Blocks.POWERED_RAIL,
      Blocks.ACTIVATOR_RAIL
   );
   public static final Set<LightBlock> DEFAULT_LIGHT_BLOCKS;
   private final MainRenderer mainRenderer;
   private final RenderDispatcher renderDispatcher;
   private final WorldRegistry worldRegistry;
   private final BlockRegistry blockRegistry = new BlockRegistry();
   public Path shaderPackPath = Iris.getShaderpacksDirectory()
      .resolve((String)Iris.getIrisConfig().getShaderPackName().orElseThrow(() -> new RuntimeException("No shaderpack selected!")));
   private final Consumer<Set<Block>> volumetricBlocksUpdated;

   public Raytracer() {
      this.renderDispatcher = new RenderDispatcher();
      this.worldRegistry = new WorldRegistry(this.renderDispatcher);
      this.mainRenderer = new MainRenderer(this.worldRegistry);
      this.worldRegistry.startWorldBuilder();
      this.volumetricBlocksUpdated = volumetricBlocks -> MinecraftClient.getInstance().worldRenderer.reload();
      PhotonicsStorage.VOLUMETRIC_RENDERED_BLOCKS.addObserver(this.volumetricBlocksUpdated);
   }

   public void queueBuildJob(Runnable job) {
      this.worldRegistry.queueBuildJob(job);
   }

   public void queueUrgentBuildJob(Runnable job) {
      this.queueBuildJob(job);
      this.worldRegistry.wakeUpWorldBuilder();
   }

   public void queueOpenGLJob(Runnable job) {
      this.worldRegistry.queueGlJob(job);
   }

   public static void filterDoubleFaces(Map<Direction, ModelElementFace> faces, Vector3f from, Vector3f to) {
      Vector3f delta = new Vector3f(from).add(-to.x, -to.y, -to.z);
      if (delta.x * delta.y * delta.z == 0.0F) {
         Vector3f normal = new Vector3f(to).add(from).mul(0.03125F).add(new Vector3f(-0.5F, -0.5F, -0.5F));
         normal.mul(1.0F / normal.length());
         Direction normalDirection = Arrays.stream(Direction.values())
            .filter(
               direction -> Vec3d.of(direction.getVector()).dotProduct(new Vec3d(normal.x, normal.y, normal.z))
                  > Math.cos(Math.toRadians(45.0))
            )
            .findFirst()
            .orElse(null);
         if (normalDirection != null) {
            faces.forEach((key, value) -> {
               Direction oppositeDirection = key.getOpposite();
               if (faces.containsKey(oppositeDirection)) {
                  if (key == normalDirection) {
                     ((BlockElementFaceExt)(Object)value).photonic$setShouldBeVoxelized(false);
                  }
               }
            });
         }
      }
   }

   @Override
   public void free() {
      this.renderDispatcher.free();
      this.blockRegistry.free();
      this.worldRegistry.free();
      this.mainRenderer.free();
      PhotonicsStorage.VOLUMETRIC_RENDERED_BLOCKS.removeObserver(this.volumetricBlocksUpdated);
   }

   public static boolean isDisabled() {
      return INSTANCE == null;
   }

   public static boolean shouldBeEnabled() {
      if (!Iris.getIrisConfig().areShadersEnabled()) {
         return false;
      } else {
         if (SHADERPACK_PROPERTIES == null) {
            return false;
         }
         boolean shaderPackSupported = Boolean.parseBoolean(SHADERPACK_PROPERTIES.getOrDefault("photonics.enabled", false).toString());
         boolean photonicsEnabled = Boolean.parseBoolean(SHADERPACK_CHANGED_OPTIONS.getOrDefault("PHOTONICS_ENABLED", "true"));
         return !shaderPackSupported ? false : photonicsEnabled;
      }
   }

   public static void watchFolder(File folder, Runnable callback) {
      if (folder.exists()) {
         try {
            WatchService watcher = FileSystems.getDefault().newWatchService();
            WatchKey watchKey = folder.toPath().register(watcher, StandardWatchEventKinds.ENTRY_MODIFY);
            new Thread(() -> {
               while (true) {
                  if (!watchKey.pollEvents().isEmpty()) {
                     callback.run();
                  }

                  try {
                     Thread.sleep(100L);
                  } catch (InterruptedException var3x) {
                     throw new RuntimeException(var3x);
                  }
               }
            }).start();
         } catch (IOException var4) {
            throw new RuntimeException(var4);
         }
      }
   }

   public MainRenderer getMainRenderer() {
      return this.mainRenderer;
   }

   public RenderDispatcher getRenderDispatcher() {
      return this.renderDispatcher;
   }

   public WorldRegistry getWorldRegistry() {
      return this.worldRegistry;
   }

   public BlockRegistry getBlockRegistry() {
      return this.blockRegistry;
   }

   public static Patch getAppliedPatch() {
      Patch result = Iris.getIrisConfig()
         .getShaderPackName()
         .map(config -> {
            return Patch.selectBestPatch(AVAILABLE_PATCHES, config, shouldBeEnabled());
         })
         .orElse(null);
      return result;
   }

   public static void reloadPatches() {
      AVAILABLE_PATCHES.clear();
      Path fsPath = DEV_ENV_SHADERS_PATH.resolve("patches");

      try {
         try (
            Stream<Path> fsStream = Files.exists(fsPath) ? Files.list(fsPath) : Stream.of();
            Stream<Path> classStream = Files.list(
               Path.of(Objects.requireNonNull(Patch.class.getClassLoader().getResource("assets/photonic/shaders/patches/")).toURI())
            );
         ) {
            Stream.concat(fsStream, classStream).filter(x$0 -> Files.exists(x$0)).forEach(p -> {
               try {
                  AVAILABLE_PATCHES.add(Patch.of(p, true));
                  AVAILABLE_PATCHES.add(Patch.of(p, false));
               } catch (IOException var2x) {
                  throw new RuntimeException(var2x);
               }
            });
         }
      } catch (URISyntaxException | IOException var9) {
         throw new RuntimeException(var9);
      }
   }

   public static String readShaderFile(ShaderPackPath path, boolean patchFile) {
      String source = null;
      Patch patch = getAppliedPatch();
      if (patch != null && patchFile) {
         source = patch.readPatchedFile(path);
      }

      if (source == null) {
         try {
            if (!path.isPhotonicsPath()) {
               String preprocessed = readShaderAndPreprocess(path);
               return preprocessed;
            }

            String relativeToPhotonics = path.getRelativeToPhotonics();
            Path devEnvShaderPath = DEV_ENV_SHADERS_PATH.resolve(relativeToPhotonics);
            if (Files.exists(devEnvShaderPath)) {
               String preprocessed = readShaderAndPreprocess(new ShaderPackPath(devEnvShaderPath));
               return preprocessed;
            }

            URL jarShaderUrl = IncludeGraph.class.getClassLoader().getResource("assets/photonic/shaders/" + relativeToPhotonics);
            if (jarShaderUrl == null) {
               return null;
            }

            Path jarShaderPath = Path.of(jarShaderUrl.toURI());
            if (Files.exists(jarShaderPath)) {
               String preprocessed = readShaderAndPreprocess(new ShaderPackPath(jarShaderPath));
               return preprocessed;
            }
         } catch (Exception var7) {
         }
      }

      if (source == null) {
         throw new IllegalStateException("Couldn't read file " + path);
      } else {
         return ShaderUtil.preprocessForward(source);
      }
   }

   private static String readShaderAndPreprocess(ShaderPackPath path) throws IOException {
      return ShaderUtil.preprocessForward(path.readFile());
   }

   private static void registerDefaultLightBlock(List<LightBlock> lightBlocks, Vector3f color, boolean traced, Block... blocks) {
      for (Block block : blocks) {
         LightType lightType = new LightType(color, new Vector2f(0.9F, 0.9F), traced);
         lightBlocks.add(new LightBlock(block, lightType));
      }
   }

   public static boolean blockStateEmitsLight(BlockState blockState) {
      Block block = blockState.getBlock();
      if (block == Blocks.REDSTONE_WIRE) {
         return (Integer)blockState.get(RedstoneWireBlock.POWER) > 0;
      } else {
         return block != Blocks.REDSTONE_BLOCK && block != Blocks.EMERALD_BLOCK && block != Blocks.LAPIS_BLOCK ? blockState.getLuminance() > 0 : true;
      }
   }

   static {
      watchFolder(DEV_ENV_SHADERS_PATH.toFile(), () -> RenderSystem.recordRenderCall(() -> {
         try {
            Iris.reload();
         } catch (IOException var1x) {
         }
      }));
      List<LightBlock> lightBlocks = new LinkedList<>();
      Vector3f redstoneColor = new Vector3f(255.0F, 51.0F, 51.0F).mul(0.003921569F);
      registerDefaultLightBlock(lightBlocks, redstoneColor, true, Blocks.REDSTONE_TORCH, Blocks.REDSTONE_WALL_TORCH);
      registerDefaultLightBlock(
         lightBlocks, redstoneColor, false, Blocks.REDSTONE_BLOCK, Blocks.REDSTONE_ORE, Blocks.DEEPSLATE_REDSTONE_ORE, Blocks.REDSTONE_WIRE
      );
      Vector3f torchColor = new Vector3f(119.0F, 106.0F, 56.0F).mul(0.003921569F);
      registerDefaultLightBlock(
         lightBlocks,
         torchColor,
         true,
         Blocks.CANDLE,
         Blocks.WHITE_CANDLE,
         Blocks.ORANGE_CANDLE,
         Blocks.MAGENTA_CANDLE,
         Blocks.LIGHT_BLUE_CANDLE,
         Blocks.YELLOW_CANDLE,
         Blocks.LIME_CANDLE,
         Blocks.PINK_CANDLE,
         Blocks.GRAY_CANDLE,
         Blocks.LIGHT_GRAY_CANDLE,
         Blocks.CYAN_CANDLE,
         Blocks.PURPLE_CANDLE,
         Blocks.BLUE_CANDLE,
         Blocks.BROWN_CANDLE,
         Blocks.GREEN_CANDLE,
         Blocks.RED_CANDLE,
         Blocks.BLACK_CANDLE,
         Blocks.CANDLE_CAKE,
         Blocks.WHITE_CANDLE_CAKE,
         Blocks.ORANGE_CANDLE_CAKE,
         Blocks.MAGENTA_CANDLE_CAKE,
         Blocks.LIGHT_BLUE_CANDLE_CAKE,
         Blocks.YELLOW_CANDLE_CAKE,
         Blocks.LIME_CANDLE_CAKE,
         Blocks.PINK_CANDLE_CAKE,
         Blocks.GRAY_CANDLE_CAKE,
         Blocks.LIGHT_GRAY_CANDLE_CAKE,
         Blocks.CYAN_CANDLE_CAKE,
         Blocks.PURPLE_CANDLE_CAKE,
         Blocks.BLUE_CANDLE_CAKE,
         Blocks.BROWN_CANDLE_CAKE,
         Blocks.GREEN_CANDLE_CAKE,
         Blocks.RED_CANDLE_CAKE,
         Blocks.BLACK_CANDLE_CAKE
      );
      registerDefaultLightBlock(
         lightBlocks,
         torchColor,
         true,
         Blocks.TORCH,
         Blocks.WALL_TORCH,
         Blocks.JACK_O_LANTERN,
         Blocks.LANTERN,
         Blocks.CAMPFIRE,
         Blocks.REDSTONE_LAMP
      );
      registerDefaultLightBlock(
         lightBlocks,
         torchColor,
         true,
         Blocks.COPPER_BULB,
         Blocks.EXPOSED_COPPER_BULB,
         Blocks.OXIDIZED_COPPER_BULB,
         Blocks.WEATHERED_COPPER_BULB,
         Blocks.WAXED_COPPER_BULB,
         Blocks.WAXED_EXPOSED_COPPER_BULB,
         Blocks.WAXED_OXIDIZED_COPPER_BULB,
         Blocks.WAXED_WEATHERED_COPPER_BULB
      );
      registerDefaultLightBlock(
         lightBlocks,
         torchColor,
         false,
         Blocks.LAVA,
         Blocks.MAGMA_BLOCK,
         Blocks.SHROOMLIGHT,
         Blocks.GLOWSTONE,
         Blocks.LAVA_CAULDRON,
         Blocks.FIRE,
         Blocks.BREWING_STAND,
         Blocks.FURNACE,
         Blocks.BLAST_FURNACE,
         Blocks.SMOKER,
         Blocks.CAVE_VINES,
         Blocks.CAVE_VINES_PLANT
      );
      Vector3f soulColor = new Vector3f(51.0F, 204.0F, 255.0F).mul(0.003921569F);
      registerDefaultLightBlock(lightBlocks, soulColor, true, Blocks.SOUL_TORCH, Blocks.SOUL_WALL_TORCH, Blocks.SOUL_LANTERN, Blocks.SOUL_CAMPFIRE);
      registerDefaultLightBlock(lightBlocks, soulColor, false, Blocks.SOUL_FIRE);
      Vector3f endColor = new Vector3f(170.0F, 170.0F, 170.0F).mul(0.003921569F);
      registerDefaultLightBlock(lightBlocks, endColor, true, Blocks.END_ROD);
      registerDefaultLightBlock(lightBlocks, endColor, false, Blocks.END_PORTAL, Blocks.END_PORTAL_FRAME, Blocks.END_GATEWAY);
      Vector3f whiteColor = new Vector3f(100.0F, 100.0F, 100.0F).mul(0.003921569F);
      registerDefaultLightBlock(
         lightBlocks, whiteColor, false, Blocks.LIGHT, Blocks.ENDER_CHEST, Blocks.SEA_PICKLE, Blocks.SEA_LANTERN, Blocks.BEACON
      );
      registerDefaultLightBlock(lightBlocks, new Vector3f(whiteColor).mul(0.5F), true, Blocks.DRAGON_EGG);
      registerDefaultLightBlock(lightBlocks, new Vector3f(whiteColor).mul(0.5F), false, Blocks.TRIAL_SPAWNER);
      registerDefaultLightBlock(lightBlocks, new Vector3f(whiteColor).mul(0.5F), false, Blocks.VAULT);
      Vector3f purpleColor = new Vector3f(131.0F, 8.0F, 228.0F).mul(0.003921569F);
      registerDefaultLightBlock(lightBlocks, purpleColor, false, Blocks.CRYING_OBSIDIAN, Blocks.RESPAWN_ANCHOR, Blocks.NETHER_PORTAL);
      Vector3f amethystColor = new Vector3f(new Vector3f(122.0F, 91.0F, 181.0F).mul(0.003921569F));
      registerDefaultLightBlock(
         lightBlocks,
         amethystColor,
         false,
         Blocks.AMETHYST_BLOCK,
         Blocks.AMETHYST_CLUSTER,
         Blocks.LARGE_AMETHYST_BUD,
         Blocks.MEDIUM_AMETHYST_BUD,
         Blocks.SMALL_AMETHYST_BUD
      );
      Vector3f sculkColor = new Vector3f(39.0F, 133.0F, 145.0F).mul(0.003921569F);
      registerDefaultLightBlock(lightBlocks, sculkColor, false, Blocks.SCULK_SENSOR, Blocks.CALIBRATED_SCULK_SENSOR, Blocks.SCULK_CATALYST);
      registerDefaultLightBlock(lightBlocks, new Vector3f(0.0F, 0.0F, 0.0F).mul(0.003921569F), false, Blocks.BROWN_MUSHROOM, Blocks.CONDUIT);
      registerDefaultLightBlock(lightBlocks, new Vector3f(227.0F, 236.0F, 228.0F).mul(0.003921569F), false, Blocks.SCULK_SHRIEKER);
      registerDefaultLightBlock(lightBlocks, new Vector3f(29.0F, 74.0F, 149.0F).mul(0.003921569F), false, Blocks.LAPIS_BLOCK);
      registerDefaultLightBlock(lightBlocks, new Vector3f(23.0F, 221.0F, 98.0F).mul(0.003921569F), false, Blocks.EMERALD_BLOCK);
      registerDefaultLightBlock(lightBlocks, new Vector3f(178.0F, 138.0F, 189.0F).mul(0.003921569F), false, Blocks.PEARLESCENT_FROGLIGHT);
      registerDefaultLightBlock(lightBlocks, new Vector3f(145.0F, 195.0F, 130.0F).mul(0.003921569F), false, Blocks.VERDANT_FROGLIGHT);
      registerDefaultLightBlock(lightBlocks, new Vector3f(150.0F, 220.0F, 134.0F).mul(0.003921569F), false, Blocks.OCHRE_FROGLIGHT);
      registerDefaultLightBlock(lightBlocks, new Vector3f(128.0F, 70.0F, 0.0F).mul(0.003921569F), false, Blocks.ENCHANTING_TABLE);
      registerDefaultLightBlock(lightBlocks, new Vector3f(113.0F, 134.0F, 126.0F).mul(0.003921569F), false, Blocks.GLOW_LICHEN);
      DEFAULT_LIGHT_BLOCKS = new HashSet<>(lightBlocks);
   }
}
