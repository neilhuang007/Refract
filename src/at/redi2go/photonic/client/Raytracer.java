package at.redi2go.photonic.client;

import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.mixin.ShaderPackAccessor;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.ShaderUtil;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.LightTreeRenderer;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.MainRenderer;
import at.redi2go.photonic.client.rendering.patching.Patch;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import com.mojang.blaze3d.systems.RenderSystem;
import it.unimi.dsi.fastutil.ints.IntOpenHashSet;
import it.unimi.dsi.fastutil.ints.IntSet;
import java.io.File;
import java.io.IOException;
import java.net.URISyntaxException;
import java.net.URL;
import java.nio.file.FileSystem;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardWatchEventKinds;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Properties;
import java.util.Set;
import java.util.stream.Stream;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.include.IncludeGraph;
import net.minecraft.client.render.RenderLayer;
import net.minecraft.block.Block;
import net.minecraft.client.render.model.BakedQuad;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.model.json.ModelElementFace;
import org.joml.Vector3f;
import java.lang.reflect.Field;

public class Raytracer implements Destructable {
   public static final Object LOCK = new Object();
   public static Raytracer INSTANCE;
   public static final Path SHADER_PATCHES_PATH = Path.of("./shader-patches");
   public static final Path DEV_ENV_SHADERS_PATH = Path.of("../src/main/resources/assets/photonic/shaders");
   private static final Set<String> AUTO_REPLACED_FILES = Set.of("photonics.glsl", "ph_samplers.glsl");
   public static Map<String, String> SHADERPACK_CHANGED_OPTIONS = null;
   public static Properties SHADERPACK_PROPERTIES = null;
   public static Properties PATCHED_SHADERPACK_PROPERTIES = null;
   public static final IntSet USED_BUFFERS = new IntOpenHashSet();
   public static ColorFramebuffer CURRENT_FRAMEBUFFER = null;
   private static final List<FileSystem> FILE_SYSTEMS = new ArrayList<>();
   public static final List<Patch> AVAILABLE_PATCHES = new ArrayList<>();
   public static final TerrainRenderPass VOXEL = new TerrainRenderPass(RenderLayer.getCutout(), false, true);
   private static volatile Field PHOTONIC_FACE_VOXELIZED_FIELD;
   private static volatile Field PHOTONIC_BAKED_QUAD_VOXELIZED_FIELD;
   private final MainRenderer mainRenderer;
   private final RenderDispatcher renderDispatcher;
   private final WorldRegistry worldRegistry;
   public final Path shaderPackPath;
   private final PhotonicsConfig.Observer<Set<Block>> voxelizedBlockObserver;

   public Raytracer() {
      String shaderPackName = (String)Iris.getIrisConfig().getShaderPackName().orElseThrow(() -> new RuntimeException("No shaderpack selected!"));
      this.shaderPackPath = Iris.getShaderpacksDirectory().resolve(shaderPackName);

      ShaderPack buffers = (ShaderPack)Iris.getCurrentPack().orElseThrow();
      USED_BUFFERS.clear();
      it.unimi.dsi.fastutil.ints.IntIterator bufferIter = buffers.getBufferObjects().keySet().iterator();
      while (bufferIter.hasNext()) {
         USED_BUFFERS.add((int)(Integer)bufferIter.next());
      }

      PhotonicsProperties properties = getProperties().orElseThrow();
      this.renderDispatcher = new RenderDispatcher(properties.getRenderScale());
      this.worldRegistry = new WorldRegistry(
         this.renderDispatcher,
         properties.getMaxLights(),
         properties.getMaxSamples(),
         properties.getMinTracedLightLuma(),
         properties.isBlockLightEnabled().orElse(true)
      );
      Photonic.info(
         "[Startup] photonics: lightingPipeline=LIGHT_TREE_RESTIR multithreading={} blockLight={} gi={}",
         PhotonicsStorage.DO_MULTITHREADING.value,
         properties.isBlockLightEnabled().orElse(true),
         properties.isGiEnabled().orElse(true)
      );
      this.mainRenderer = new LightTreeRenderer(this.worldRegistry, properties.getRenderScale(), properties);
      this.worldRegistry.startWorldBuilder();
      this.voxelizedBlockObserver = PhotonicsConfig.observe(c -> c.voxelizedBlocks, unused -> MinecraftClient.getInstance().worldRenderer.reload());
   }

   public static Optional<PhotonicsProperties> getProperties() {
      return Iris.getCurrentPack().map(e -> (ShaderPackAccessor)e).map(ShaderPackAccessor::getShaderProperties).map(e -> (PhotonicsProperties)e);
   }

   public static void bindBuffers(int shaderId) {
      if (!isDisabled()) {
         INSTANCE.getMainRenderer().bindProgramBuffers(shaderId, USED_BUFFERS);
      }
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
                     setFaceVoxelized(value, false);
                  }
               }
            });
         }
      }
   }

   @Override
   public void free() {
      synchronized (LOCK) {
         this.renderDispatcher.free();
         this.worldRegistry.free();
         this.mainRenderer.free();
         this.voxelizedBlockObserver.unregister();
         USED_BUFFERS.clear();
         INSTANCE = null;
      }
   }

   public static boolean isDisabled() {
      return INSTANCE == null;
   }

   public static boolean shouldBeEnabled() {
      if (!Iris.getIrisConfig().areShadersEnabled()) return false;
      if (getAppliedPatch(true) != null) {
         boolean shaderPackSupported = Boolean.parseBoolean(PATCHED_SHADERPACK_PROPERTIES.getOrDefault("photonics.supported", false).toString());
         if (!shaderPackSupported) return false;
         return Boolean.parseBoolean(SHADERPACK_CHANGED_OPTIONS.getOrDefault("PHOTONICS_ENABLED", "true"));
      }
      return getProperties().map(PhotonicsProperties::isPhotonicsEnabled).map(e -> e.orElse(false)).orElse(false);
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
      return this.worldRegistry.getBlockRegistry();
   }

   private static Optional<Patch> getPatch(String name, boolean enabled) {
      return AVAILABLE_PATCHES.stream().filter(p -> p.canBeApplied(name, enabled)).findFirst();
   }

   private static Patch getAppliedPatch(boolean enabled) {
      if (SHADERPACK_PROPERTIES != null && SHADERPACK_PROPERTIES.containsKey("photonics.enabled")) return null;
      return Iris.getIrisConfig().getShaderPackName().flatMap(e -> getPatch(e, enabled)).orElse(null);
   }

   public static Patch getAppliedPatch() {
      return getAppliedPatch(shouldBeEnabled());
   }

   private static Stream<Path> loadClassStream() throws URISyntaxException, IOException {
      URL resource = Patch.class.getClassLoader().getResource("assets/photonic/shaders/patches/");
      return resource == null ? Stream.empty() : Files.list(Path.of(resource.toURI()));
   }

   public static void reloadPatches() {
      for (FileSystem fs : FILE_SYSTEMS) {
         try {
            fs.close();
         } catch (IOException var11) {
            Photonic.error("Error while closing patch file system", var11);
         }
      }

      FILE_SYSTEMS.clear();
      AVAILABLE_PATCHES.clear();
      Path fsDevPath = DEV_ENV_SHADERS_PATH.resolve("patches");
      Path fsPath = SHADER_PATCHES_PATH;
      if (Files.notExists(fsPath)) {
         try {
            Files.createDirectory(fsPath);
         } catch (IOException var10) {
            Photonic.error("Failed to create default patches directory", var10);
         }
      }

      try {
         try (
            Stream<Path> fsDevStream = Files.exists(fsDevPath) ? Files.list(fsDevPath) : Stream.of();
            Stream<Path> fsStream = Files.exists(fsPath) ? Files.list(fsPath) : Stream.of();
            Stream<Path> classStream = loadClassStream();
         ) {
            Stream.of(fsStream, fsDevStream, classStream).flatMap(s -> s).filter(x$0 -> Files.exists(x$0)).map(p -> {
               String name = p.getFileName().toString();
               int extensionIndex = name.lastIndexOf(46);
               if (extensionIndex == -1) {
                  return new PathFsPair(p, null);
               }
               String extension = name.substring(extensionIndex);
               if (!extension.equals(".zip")) {
                  return new PathFsPair(p, null);
               }
               try {
                  FileSystem fs = FileSystems.newFileSystem(p);
                  return new PathFsPair(fs.getPath("./"), fs);
               } catch (IOException e) {
                  return new PathFsPair(p, null);
               }
            }).forEach(pair -> {
               try {
                  if (pair.fs() != null) {
                     FILE_SYSTEMS.add(pair.fs());
                  }
                  AVAILABLE_PATCHES.add(Patch.of(pair.path(), true));
                  AVAILABLE_PATCHES.add(Patch.of(pair.path(), false));
               } catch (IOException var2x) {
                  Photonic.warn("Skipping invalid patch directory: {}", pair.path());
               }
            });
         }
      } catch (URISyntaxException | IOException var15) {
         throw new RuntimeException(var15);
      }
   }

   private record PathFsPair(Path path, FileSystem fs) {}

   public static String readShaderFile(ShaderPackPath path, boolean patchFile) {
      String source = null;
      Patch patch = getAppliedPatch();
      if (patch != null && patchFile) {
         source = patch.readPatchedFile(path);
      }

      if (source == null) {
         try {
            if (!path.isPhotonicsPath()) {
               return readShaderAndPreprocess(path);
            }

            String relativeToPhotonics = path.getRelativeToPhotonics();

            if (patch == null && !AUTO_REPLACED_FILES.contains(relativeToPhotonics)) {
               Optional<String> content = tryReadFile(path);
               if (content.isPresent()) {
                  return readShaderAndPreprocess(path);
               }
            }

            Path devEnvShaderPath = DEV_ENV_SHADERS_PATH.resolve(relativeToPhotonics);
            if (Files.exists(devEnvShaderPath)) {
               return readShaderAndPreprocess(new ShaderPackPath(devEnvShaderPath));
            }

            URL jarShaderUrl = IncludeGraph.class.getClassLoader().getResource("assets/photonic/shaders/" + relativeToPhotonics);
            if (jarShaderUrl == null) {
               return null;
            }

            Path jarShaderPath = Path.of(jarShaderUrl.toURI());
            if (Files.exists(jarShaderPath)) {
               return readShaderAndPreprocess(new ShaderPackPath(jarShaderPath));
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

   private static Optional<String> tryReadFile(ShaderPackPath path) {
      try {
         return Optional.of(path.readFile());
      } catch (IOException var2) {
         return Optional.empty();
      }
   }

   public static boolean getFaceVoxelized(ModelElementFace face) {
      try {
         return photonic$getVoxelizedField(ModelElementFace.class).getBoolean(face);
      } catch (IllegalAccessException exception) {
         throw new RuntimeException("Failed reading voxelization flag from ModelElementFace", exception);
      }
   }

   public static void setFaceVoxelized(ModelElementFace face, boolean shouldBeVoxelized) {
      try {
         photonic$getVoxelizedField(ModelElementFace.class).setBoolean(face, shouldBeVoxelized);
      } catch (IllegalAccessException exception) {
         throw new RuntimeException("Failed writing voxelization flag on ModelElementFace", exception);
      }
   }

   public static boolean getBakedQuadVoxelized(BakedQuad bakedQuad) {
      try {
         return photonic$getVoxelizedField(BakedQuad.class).getBoolean(bakedQuad);
      } catch (IllegalAccessException exception) {
         throw new RuntimeException("Failed reading voxelization flag from BakedQuad", exception);
      }
   }

   public static void setBakedQuadVoxelized(BakedQuad bakedQuad, boolean shouldBeVoxelized) {
      try {
         photonic$getVoxelizedField(BakedQuad.class).setBoolean(bakedQuad, shouldBeVoxelized);
      } catch (IllegalAccessException exception) {
         throw new RuntimeException("Failed writing voxelization flag on BakedQuad", exception);
      }
   }

   static {
      watchFolder(DEV_ENV_SHADERS_PATH.toFile(), () -> RenderSystem.recordRenderCall(() -> {
         try {
            Iris.reload();
         } catch (IOException var1x) {
         }
      }));
   }

   private static Field photonic$getVoxelizedField(Class<?> owner) {
      Field field;
      if (owner == ModelElementFace.class) {
         field = PHOTONIC_FACE_VOXELIZED_FIELD;
         if (field != null) {
            return field;
         }
      } else if (owner == BakedQuad.class) {
         field = PHOTONIC_BAKED_QUAD_VOXELIZED_FIELD;
         if (field != null) {
            return field;
         }
      }

      try {
         field = owner.getDeclaredField("photonic$shouldBeVoxelized");
      } catch (ReflectiveOperationException exception) {
         throw new RuntimeException("Missing voxelization flag on " + owner.getName(), exception);
      }

      field.setAccessible(true);
      if (owner == ModelElementFace.class) {
         PHOTONIC_FACE_VOXELIZED_FIELD = field;
      } else if (owner == BakedQuad.class) {
         PHOTONIC_BAKED_QUAD_VOXELIZED_FIELD = field;
      }
      return field;
   }
}
