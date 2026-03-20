package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.opengl.GpuTimerQuery;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.opengl.rendering.RegirComputeProgram;
import at.redi2go.photonic.client.rendering.opengl.rendering.RoutingFramebuffer;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.function.IntSupplier;
import java.util.function.Supplier;
import net.irisshaders.iris.shaderpack.include.IncludeGraph;
import net.irisshaders.iris.uniforms.SystemTimeUniforms;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.gl.uniform.UniformUpdateFrequency;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import net.minecraft.client.MinecraftClient;
import org.jetbrains.annotations.Nullable;
import org.joml.Vector2f;
import org.joml.Vector3i;
import org.joml.Vector4f;

public class LightTreeRenderer extends MainRenderer {
   private static final String directTemporalResamplingFragment = "lighttree/restir_di_temporal.fsh";
   private static final String directTemporalFragment = "lighttree/nrd_temporal_accumulation.fsh";
   private static final String directHistoryFixFragment = "lighttree/nrd_history_fix.fsh";
   private static final String directAntiFireflyFragment = "lighttree/nrd_anti_firefly.fsh";
   private static final String directAtrousFragment = "lighttree/nrd_atrous.fsh";
   private static final String directHistoryClampingFragment = "lighttree/nrd_history_clamping.fsh";
   private static final String specTemporalFragment = "lighttree/nrd_spec_temporal_accumulation.fsh";
   private static final String specHistoryFixFragment = "lighttree/nrd_spec_history_fix.fsh";
   private static final String specAntiFireflyFragment = "lighttree/nrd_spec_anti_firefly.fsh";
   private static final String specAtrousFragment = "lighttree/nrd_spec_atrous.fsh";
   private static final String specHistoryClampingFragment = "lighttree/nrd_spec_history_clamping.fsh";
   private static final String indirectTemporalFragment = "lighttree/restir_gi_temporal.fsh";
   private static final String indirectBoilingFragment = "lighttree/light_tree_indirect_boiling_filter.fsh";
   private static final String indirectAccumulationFragment = "lighttree/light_tree_indirect_accumulation.fsh";
   private static final String indirectInitialFragment = "lighttree/light_tree_indirect_initial.fsh";
   private static final String indirectDenoisingFragment = "lighttree/light_tree_indirect_denoising.fsh";
   private static final String shadeSamplesFragment = "lighttree/shade_samples.fsh";
   private static final String proposalReservoirFragment = "lighttree/light_tree_sampling_reservoir.fsh";
   private static final String shadeSamplesLightingFragment = "lighttree/shade_samples_lighting.fsh";
   private static final String shadeSamplesReservoirFragment = "lighttree/shade_samples_reservoir.fsh";
   private static final int[] proposalGeometryDrawBuffers = new int[]{0, 1, 2, 3, 4, -1, -1, -1};
   private static final int[] proposalReservoirDrawBuffers = new int[]{-1, -1, -1, -1, -1, 0, 1, 2};
   private static final int[] shadeSamplesLightingDrawBuffers = new int[]{0, 1, -1, -1, -1};
   private static final int[] shadeSamplesReservoirDrawBuffers = new int[]{-1, -1, 0, 1, 2};
   private static final int profilerLogIntervalFrames = 60;
   private static final String[] gpuProfilerRegionNames = new String[]{
      "proposalSampling", "reuseResolve", "shadeSamples", "directFeatureExtract", "directTemporal", "directAntiFirefly", "directHistoryFix", "directHistoryClamping", "directAtrous", "specTemporal", "specAntiFirefly", "specHistoryFix", "specHistoryClamping", "specAtrous", "indirectAccum", "indirectDenoise", "accumulation", "indirect"
   };
   private static final String[] profilerPassNames = new String[]{
      "proposalSampling", "reuseResolve", "shadeSamples", "directFeatureExtract", "directTemporal", "directAntiFirefly", "directHistoryFix", "directHistoryClamping", "directAtrous", "specTemporal", "specAntiFirefly", "specHistoryFix", "specHistoryClamping", "specAtrous", "indirectAccum", "indirectDenoise", "accumulation", "indirect"
   };
   private static final int proposalSamplingRegionIndex = 0;
   private static final int reuseResolveRegionIndex = 1;
   private static final int shadeSamplesRegionIndex = 2;
   private static final int directFeatureRegionIndex = 3;
   private static final int directTemporalRegionIndex = 4;
   private static final int directAntiFireflyRegionIndex = 5;
   private static final int directHistoryFixRegionIndex = 6;
   private static final int directHistoryClampingRegionIndex = 7;
   private static final int directAtrousRegionIndex = 8;
   private static final int specTemporalRegionIndex = 9;
   private static final int specAntiFireflyRegionIndex = 10;
   private static final int specHistoryFixRegionIndex = 11;
   private static final int specHistoryClampingRegionIndex = 12;
   private static final int specAtrousRegionIndex = 13;
   private static final int indirectAccumRegionIndex = 14;
   private static final int indirectDenoiseRegionIndex = 15;
   private static final int accumulationRegionIndex = 16;
   private static final int indirectRegionIndex = 17;

   private final PhotonicsProperties properties;
   private final ColorFramebuffer lightingBuffer;
   private final ColorFramebuffer lightingStageBuffer;
   private final ColorFramebuffer motionVectorBuffer;
   private final ColorFramebuffer directReservoirBuffer;
   private final ColorFramebuffer directTemporalReservoirBuffer;
   private final ColorFramebuffer directConfidenceBuffer;
   private final ColorFramebuffer compatDirectSoftBuffer;
   private final ColorFramebuffer directHistoryLengthBuffer;
   private final ColorFramebuffer directNoisyBuffer;
   private final ColorFramebuffer directResponsiveBuffer;
   private final ColorFramebuffer directSlowBuffer;
   private final ColorFramebuffer directFastBuffer;
   private final ColorFramebuffer directAntiFireflyBuffer;
   private final ColorFramebuffer directClampedSlowBuffer;
   private final ColorFramebuffer directClampedFastBuffer;
   private final ColorFramebuffer directDenoisedBuffer;
   private final ColorFramebuffer directAtrousPingBuffer;
   private final ColorFramebuffer specularNoisyBuffer;
   private final ColorFramebuffer specularResponsiveBuffer;
   private final ColorFramebuffer specularSlowBuffer;
   private final ColorFramebuffer specularFastBuffer;
   private final ColorFramebuffer specularAntiFireflyBuffer;
   private final ColorFramebuffer specularClampedSlowBuffer;
   private final ColorFramebuffer specularClampedFastBuffer;
   private final ColorFramebuffer specularDenoisedBuffer;
   private final ColorFramebuffer specularAtrousPingBuffer;
   private final ColorFramebuffer specularHistoryLengthBuffer;
   private final ColorFramebuffer indirectInitialReservoirBuffer;
   private final ColorFramebuffer indirectTemporalReservoirBuffer;
   private final ColorFramebuffer indirectReservoirBuffer;
   private final ColorFramebuffer indirectDenoisedBuffer;
   private final RoutingFramebuffer proposalFramebuffer;
   private final RoutingFramebuffer proposalReservoirFramebuffer;
   private final RoutingFramebuffer directTemporalReservoirFramebuffer;
   private final RoutingFramebuffer reuseResolveFramebuffer;
   private final RoutingFramebuffer directFeatureFramebuffer;
   private final RoutingFramebuffer directTemporalFramebuffer;
   private final RoutingFramebuffer directAntiFireflyFramebuffer;
   private final RoutingFramebuffer directHistoryFixFramebuffer;
   private final RoutingFramebuffer directHistoryClampingFramebuffer;
   private final RoutingFramebuffer directAtrousFramebuffer;
   private final RoutingFramebuffer specTemporalFramebuffer;
   private final RoutingFramebuffer specAntiFireflyFramebuffer;
   private final RoutingFramebuffer specHistoryFixFramebuffer;
   private final RoutingFramebuffer specHistoryClampingFramebuffer;
   private final RoutingFramebuffer specAtrousFramebuffer;
   private final RoutingFramebuffer indirectInitialFramebuffer;
   private final RoutingFramebuffer indirectTemporalFramebuffer;
   private final RoutingFramebuffer indirectBoilingFramebuffer;
   private final RoutingFramebuffer indirectAccumulationFramebuffer;
   private final RoutingFramebuffer indirectDenoisingFramebuffer;
   private final RoutingFramebuffer positionWriteFramebuffer;
   private final RoutingFramebuffer shadeSamplesMonolithicFramebuffer;
   private final RoutingFramebuffer shadeSamplesFramebuffer;
   private final RoutingFramebuffer shadeSamplesReservoirFramebuffer;
   @Nullable
   private CompositeRenderer proposalRenderer;
   @Nullable
   private CompositeRenderer directTemporalResamplingRenderer;
   @Nullable
   private CompositeRenderer reuseResolveRenderer;
   @Nullable
   private CompositeRenderer directFeatureRenderer;
   @Nullable
   private CompositeRenderer directTemporalRenderer;
   @Nullable
   private CompositeRenderer directAntiFireflyRenderer;
   @Nullable
   private CompositeRenderer directHistoryFixRenderer;
   @Nullable
   private CompositeRenderer directHistoryClampingRenderer;
   @Nullable
   private CompositeRenderer directAtrousRenderer;
   @Nullable
   private CompositeRenderer specTemporalRenderer;
   @Nullable
   private CompositeRenderer specAntiFireflyRenderer;
   @Nullable
   private CompositeRenderer specHistoryFixRenderer;
   @Nullable
   private CompositeRenderer specHistoryClampingRenderer;
   @Nullable
   private CompositeRenderer specAtrousRenderer;
   @Nullable
   private CompositeRenderer indirectInitialRenderer;
   @Nullable
   private CompositeRenderer indirectTemporalRenderer;
   @Nullable
   private CompositeRenderer indirectBoilingRenderer;
   @Nullable
   private CompositeRenderer indirectAccumulationRenderer;
   @Nullable
   private CompositeRenderer indirectDenoisingRenderer;
   @Nullable
   private CompositeRenderer accumulationRenderer;
   @Nullable
   private CompositeRenderer indirectRenderer;
   @Nullable
   private CompositeRenderer shadeSamplesMonolithicRenderer;
   @Nullable
   private CompositeRenderer shadeSamplesRenderer;
   private final GpuTimerQuery gpuTimerQuery;
   @Nullable
   private RegirComputeProgram regirComputeProgram;
   private final int[] directAtrousStepSizes;
   private int directAtrousIteration = 0;
   private int specAtrousIteration = 0;
   private boolean compatDirectSoftDirty = true;
   private int profilerFrameCounter = 0;
   private long lastCpuProposalSamplingNanos;
   private long lastCpuReuseResolveNanos;
   private long lastCpuShadeSamplesNanos;
   private long lastCpuDirectFeatureNanos;
   private long lastCpuDirectTemporalNanos;
   private long lastCpuDirectAntiFireflyNanos;
   private long lastCpuDirectHistoryFixNanos;
   private long lastCpuDirectHistoryClampingNanos;
   private long lastCpuDirectAtrousNanos;
   private long[] lastCpuDirectAtrousIterationNanos;
   private long lastCpuSpecTemporalNanos;
   private long lastCpuSpecAntiFireflyNanos;
   private long lastCpuSpecHistoryFixNanos;
   private long lastCpuSpecHistoryClampingNanos;
   private long lastCpuSpecAtrousNanos;
   private long lastCpuIndirectAccumNanos;
   private long lastCpuIndirectDenoiseNanos;
   private long lastCpuAccumulationNanos;
   private long lastCpuIndirectNanos;

   public LightTreeRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.properties = properties;
      this.directAtrousStepSizes = resolveDirectAtrousStepSizes(properties);
      this.lastCpuDirectAtrousIterationNanos = new long[this.directAtrousStepSizes.length];
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.createLightingBufferAttachments(this.lightingBuffer);
      this.lightingStageBuffer = new ColorFramebuffer(renderScale);
      this.createLightingStageAttachments(this.lightingStageBuffer);
      this.motionVectorBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directReservoirBuffer = this.createDirectReservoirFramebuffer(renderScale);
      this.directTemporalReservoirBuffer = this.createDirectReservoirFramebuffer(renderScale);
      this.directConfidenceBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.compatDirectSoftBuffer = new ColorFramebuffer(renderScale);
      this.compatDirectSoftBuffer.createAttachment("direct_soft_compat", "RGBA16F", false);
      this.directHistoryLengthBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directNoisyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directResponsiveBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directAntiFireflyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directClampedSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directClampedFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directDenoisedBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directAtrousPingBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularNoisyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularResponsiveBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularAntiFireflyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularClampedSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularClampedFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularDenoisedBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularAtrousPingBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularHistoryLengthBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.indirectInitialReservoirBuffer = new ColorFramebuffer(renderScale);
      this.createIndirectReservoirAttachments(this.indirectInitialReservoirBuffer);
      this.indirectTemporalReservoirBuffer = new ColorFramebuffer(renderScale);
      this.createIndirectReservoirAttachments(this.indirectTemporalReservoirBuffer);
      this.indirectReservoirBuffer = new ColorFramebuffer(renderScale);
      this.createIndirectReservoirAttachments(this.indirectReservoirBuffer);
      this.indirectDenoisedBuffer = new ColorFramebuffer(renderScale);
      this.indirectDenoisedBuffer.createAttachment("data", "RGBA16F", false);
      this.proposalFramebuffer = this.createProposalGeometryFramebuffer();
      this.proposalReservoirFramebuffer = this.createProposalReservoirFramebuffer();
      this.directTemporalReservoirFramebuffer = this.createDirectTemporalReservoirFramebuffer();
      this.reuseResolveFramebuffer = this.createReuseResolveFramebuffer();
      this.directFeatureFramebuffer = this.createDirectFeatureFramebuffer();
      this.directTemporalFramebuffer = this.createDirectTemporalFramebuffer();
      this.directAntiFireflyFramebuffer = this.createDirectAntiFireflyFramebuffer();
      this.directHistoryFixFramebuffer = this.createDirectHistoryFixFramebuffer();
      this.directHistoryClampingFramebuffer = this.createDirectHistoryClampingFramebuffer();
      this.directAtrousFramebuffer = this.createDirectAtrousFramebuffer();
      this.specTemporalFramebuffer = this.createSpecTemporalFramebuffer();
      this.specAntiFireflyFramebuffer = this.createSpecAntiFireflyFramebuffer();
      this.specHistoryFixFramebuffer = this.createSpecHistoryFixFramebuffer();
      this.specHistoryClampingFramebuffer = this.createSpecHistoryClampingFramebuffer();
      this.specAtrousFramebuffer = this.createSpecAtrousFramebuffer();
      this.indirectInitialFramebuffer = this.createIndirectInitialFramebuffer();
      this.indirectTemporalFramebuffer = this.createIndirectTemporalFramebuffer();
      this.indirectBoilingFramebuffer = this.createIndirectBoilingFramebuffer();
      this.indirectAccumulationFramebuffer = this.createIndirectAccumulationFramebuffer();
      this.indirectDenoisingFramebuffer = this.createIndirectDenoisingFramebuffer();
      this.positionWriteFramebuffer = this.createPositionWriteFramebuffer();
      this.shadeSamplesMonolithicFramebuffer = this.createShadeSamplesMonolithicFramebuffer();
      this.shadeSamplesFramebuffer = this.createShadeSamplesLightingFramebuffer();
      this.shadeSamplesReservoirFramebuffer = this.createShadeSamplesReservoirFramebuffer();
      this.gpuTimerQuery = this.createGpuTimerQuery();
      this.regirComputeProgram = new RegirComputeProgram();
   }

   @Override
   protected GLMemoryCollection buildGlMemoryCollection() {
      GLMemoryCollection memoryCollection = super.buildGlMemoryCollection();
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getGlobalLightCdfMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirCellCountMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirLightIndexMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirLightPdfMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirCompactLightDataMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightReverseMappingMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getPreviousLightsMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getNeighborOffsetMemoryManager());
      return memoryCollection;
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.proposalRenderer = rendererCreator.apply(
         List.of(
            new PhotonicsShader("lighttree/light_tree_sampling_stage.fsh", "common/screen.vsh", this.memoryCollection, this.proposalFramebuffer),
            new PhotonicsShader("lighttree/light_tree_sampling_reservoir.fsh", "common/screen.vsh", this.memoryCollection, this.proposalReservoirFramebuffer)
         )
      );
      this.directTemporalResamplingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directTemporalResamplingFragment, "common/screen.vsh", this.memoryCollection, this.directTemporalReservoirFramebuffer))
      );
      this.reuseResolveRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/reuse_resolve.fsh", "common/screen.vsh", this.memoryCollection, this.reuseResolveFramebuffer))
      );
      this.directFeatureRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/direct_feature_extract.fsh", "common/screen.vsh", this.memoryCollection, this.directFeatureFramebuffer))
      );
      this.directTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directTemporalFragment, "common/screen.vsh", this.memoryCollection, this.directTemporalFramebuffer))
      );
      this.directAntiFireflyRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directAntiFireflyFragment, "common/screen.vsh", this.memoryCollection, this.directAntiFireflyFramebuffer))
      );
      this.directHistoryFixRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directHistoryFixFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryFixFramebuffer))
      );
      this.directHistoryClampingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directHistoryClampingFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryClampingFramebuffer))
      );
      this.directAtrousRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directAtrousFragment, "common/screen.vsh", this.memoryCollection, this.directAtrousFramebuffer))
      );
      this.specTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(specTemporalFragment, "common/screen.vsh", this.memoryCollection, this.specTemporalFramebuffer))
      );
      this.specAntiFireflyRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(specAntiFireflyFragment, "common/screen.vsh", this.memoryCollection, this.specAntiFireflyFramebuffer))
      );
      this.specHistoryFixRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(specHistoryFixFragment, "common/screen.vsh", this.memoryCollection, this.specHistoryFixFramebuffer))
      );
      this.specHistoryClampingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(specHistoryClampingFragment, "common/screen.vsh", this.memoryCollection, this.specHistoryClampingFramebuffer))
      );
      this.specAtrousRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(specAtrousFragment, "common/screen.vsh", this.memoryCollection, this.specAtrousFramebuffer))
      );
      this.indirectInitialRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectInitialFragment, "common/screen.vsh", this.memoryCollection, this.indirectInitialFramebuffer))
      );
      this.indirectTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectTemporalFragment, "common/screen.vsh", this.memoryCollection, this.indirectTemporalFramebuffer))
      );
      this.indirectBoilingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectBoilingFragment, "common/screen.vsh", this.memoryCollection, this.indirectBoilingFramebuffer))
      );
      this.indirectAccumulationRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectAccumulationFragment, "common/screen.vsh", this.memoryCollection, this.indirectAccumulationFramebuffer))
      );
      this.indirectDenoisingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectDenoisingFragment, "common/screen.vsh", this.memoryCollection, this.indirectDenoisingFramebuffer))
      );
      this.accumulationRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/light_tree_accumulation.fsh", "common/screen.vsh", this.memoryCollection, this.positionWriteFramebuffer))
      );
      this.indirectRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("common/indirect.fsh", "common/screen.vsh", this.memoryCollection, null))
      );
      this.shadeSamplesMonolithicRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/shade_samples.fsh", "common/screen.vsh", this.memoryCollection, this.shadeSamplesMonolithicFramebuffer))
      );
      this.shadeSamplesRenderer = rendererCreator.apply(
         List.of(
            new PhotonicsShader("lighttree/shade_samples_lighting.fsh", "common/screen.vsh", this.memoryCollection, this.shadeSamplesFramebuffer),
            new PhotonicsShader("lighttree/shade_samples_reservoir.fsh", "common/screen.vsh", this.memoryCollection, this.shadeSamplesReservoirFramebuffer)
         )
      );
      this.compileRegirComputeShader();
   }

   private void compileRegirComputeShader() {
      if (this.regirComputeProgram == null || this.regirComputeProgram.isCompiled()) {
         return;
      }
      try {
         String presampleSource = this.loadShaderSource("lighttree/regir_presample_tiles.glsl");
         if (presampleSource != null) {
            this.regirComputeProgram.compilePresample(presampleSource);
         } else {
            Photonic.warn("[LightTree] Presample tile shader not found — ReGIR build will use tile buffer only if present");
         }
         String buildSource = this.loadShaderSource("lighttree/regir_build.glsl");
         if (buildSource != null) {
            this.regirComputeProgram.compile(buildSource);
            if (this.regirComputeProgram.isCompiled()) {
               this.worldRegistry.getLightRegistry().setGpuRegirBuildEnabled(true);
            }
         }
      } catch (Exception e) {
         Photonic.error("[LightTree] Failed to compile ReGIR compute shaders", e);
      }
   }

   private String loadShaderSource(String shaderRelativePath) {
      String resourcePath = "assets/photonic/shaders/" + shaderRelativePath;
      Path devEnvPath = Path.of("../src/main/resources/" + resourcePath);
      if (Files.exists(devEnvPath)) {
         try {
            return Files.readString(devEnvPath);
         } catch (Exception e) {
            Photonic.warn("[LightTree] Failed to read dev shader from {}: {}", devEnvPath, e.getMessage());
         }
      }
      try {
         URL jarUrl = IncludeGraph.class.getClassLoader().getResource(resourcePath);
         if (jarUrl != null) {
            return Files.readString(Path.of(jarUrl.toURI()));
         }
      } catch (Exception e) {
         Photonic.warn("[LightTree] Failed to read shader from jar ({}): {}", resourcePath, e.getMessage());
      }
      Photonic.warn("[LightTree] Shader source not found: {}", resourcePath);
      return null;
   }

   @Override
   public void registerCustomTextures(SamplerHolder samplers) {
      this.addTextureSampler(samplers, "radiosity_position", this::getCurrentGeometryPositionTexture);
      this.addTextureSampler(samplers, "radiosity_normal", this::getCurrentGeometryNormalTexture);
      this.addTextureSampler(samplers, "radiosity_mapped_normal", this::getCurrentMappedNormalTexture);
      this.addTextureSampler(samplers, "radiosity_albedo", this::getCurrentAlbedoTexture);
      this.addTextureSampler(samplers, "radiosity_material", this::getCurrentMaterialTexture);
      this.addTextureSampler(samplers, "radiosity_proposal_reservoirs", () -> this.directReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_proposal_reservoir_samples", () -> this.directReservoirBuffer.getWriteAttachment("sample"));
      this.addTextureSampler(samplers, "radiosity_proposal_reservoir_meta", () -> this.directReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "radiosity_direct", this::getResolvedDirectTexture);
      this.addTextureSampler(samplers, "radiosity_reservoirs", this::getCurrentDirectReservoirDataTexture);
      this.addTextureSampler(samplers, "radiosity_reservoir_samples", this::getCurrentDirectReservoirSampleTexture);
      this.addTextureSampler(samplers, "radiosity_reservoir_meta", this::getCurrentDirectReservoirMetaTexture);
      this.addTextureSampler(samplers, "radiosity_temporal_reservoirs", () -> this.directTemporalReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_temporal_reservoir_samples", () -> this.directTemporalReservoirBuffer.getWriteAttachment("sample"));
      this.addTextureSampler(samplers, "radiosity_temporal_reservoir_meta", () -> this.directTemporalReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "radiosity_direct_soft", this::getCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "radiosity_handheld", () -> this.lightingBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "radiosity_indirect", () -> this.lightingBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "radiosity_indirect_variance", () -> this.lightingBuffer.getWriteAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_position", this::getCurrentIndirectReservoirPositionTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_normal", this::getCurrentIndirectReservoirNormalTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_radiance", this::getCurrentIndirectReservoirRadianceTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_meta", this::getCurrentIndirectReservoirMetaTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_initial_position", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "radiosity_indirect_initial_normal", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "radiosity_indirect_initial_radiance", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("radiance"));
      this.addTextureSampler(samplers, "radiosity_indirect_initial_meta", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "radiosity_indirect_temporal_position", () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "radiosity_indirect_temporal_normal", () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "radiosity_indirect_temporal_radiance", () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("radiance"));
      this.addTextureSampler(samplers, "radiosity_indirect_temporal_meta", () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "radiosity_indirect_resolved", this::getResolvedIndirectTexture);
      this.addTextureSampler(samplers, "radiosity_motion", () -> this.motionVectorBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "diffuse_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_history_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "stage_radiosity_position", () -> this.lightingStageBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "stage_radiosity_normal", () -> this.lightingStageBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "stage_radiosity_mapped_normal", () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "stage_radiosity_albedo", () -> this.lightingStageBuffer.getWriteAttachment("albedo"));
      this.addTextureSampler(samplers, "stage_radiosity_material", () -> this.lightingStageBuffer.getWriteAttachment("material"));
      this.addTextureSampler(samplers, "stage_radiosity_direct", () -> this.lightingStageBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "stage_radiosity_direct_specular", () -> this.lightingStageBuffer.getWriteAttachment("direct_specular"));
      this.addTextureSampler(samplers, "stage_radiosity_handheld", () -> this.lightingStageBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "stage_radiosity_indirect", () -> this.lightingStageBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_mapped_normal", () -> this.lightingBuffer.getReadAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "prev_radiosity_albedo", () -> this.lightingBuffer.getReadAttachment("albedo"));
      this.addTextureSampler(samplers, "prev_radiosity_material", () -> this.lightingBuffer.getReadAttachment("material"));
      this.addTextureSampler(samplers, "prev_radiosity_direct", this::getPreviousResolvedDirectTexture);
      this.addTextureSampler(samplers, "prev_radiosity_reservoirs", () -> this.directReservoirBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoir_samples", () -> this.directReservoirBuffer.getReadAttachment("sample"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoir_meta", () -> this.directReservoirBuffer.getReadAttachment("meta"));
      this.addTextureSampler(samplers, "prev_radiosity_direct_soft", this::getPreviousCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "prev_radiosity_handheld", () -> this.lightingBuffer.getReadAttachment("handheld"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect", () -> this.lightingBuffer.getReadAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_variance", () -> this.lightingBuffer.getReadAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_position", () -> this.indirectReservoirBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_normal", () -> this.indirectReservoirBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_radiance", () -> this.indirectReservoirBuffer.getReadAttachment("radiance"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_meta", () -> this.indirectReservoirBuffer.getReadAttachment("meta"));
      this.addTextureSampler(samplers, "prev_radiosity_motion", () -> this.motionVectorBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_confidence_input", () -> this.directConfidenceBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "direct_noisy_input", () -> this.directNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_responsive_input", () -> this.directResponsiveBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_slow_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_fast_input", () -> this.directFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_history_length_input", () -> this.directHistoryLengthBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_noisy_input", () -> this.directNoisyBuffer.getReadAttachment("data"));
      // RELAX temporal accumulation consumes the final slow / fast histories produced by
      // history clamping in the previous frame.
      this.addTextureSampler(samplers, "prev_direct_slow_input", () -> this.directSlowBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_fast_input", () -> this.directClampedFastBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_history_length_input", () -> this.directHistoryLengthBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "direct_firefly_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_historyfix_input", () -> this.directAntiFireflyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_historyfix_output", () -> this.directClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_slow_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_fast_input", () -> this.directFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_noisy_input", () -> this.directNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_history_length_tex", () -> {
         if (this.shouldUseCurrentDirectHistoryLength()) {
            return this.directHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.directHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "direct_history_length_tex", () -> {
         if (this.shouldUseCurrentDirectHistoryLength()) {
            return this.directHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.directHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "direct_history_length_clamp_input", () -> this.directHistoryLengthBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_atrous_input", this::getCurrentDirectAtrousInputTexture);
      this.addTextureSampler(samplers, "spec_noisy_input", () -> this.specularNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_noisy_input", () -> this.specularNoisyBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_slow_input", () -> this.specularSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_slow_input", () -> this.specularSlowBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_fast_input", () -> this.specularFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_fast_input", () -> this.specularClampedFastBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_history_length_input", () -> {
         if (this.shouldUseCurrentSpecHistoryLength()) {
            return this.specularHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.specularHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "spec_history_length_clamp_input", () -> this.specularHistoryLengthBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_history_length_input", () -> this.specularHistoryLengthBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_firefly_input", () -> this.specularSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_historyfix_input", () -> this.specularAntiFireflyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_historyfix_output", () -> this.specularClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_clamped_slow_input", () -> this.specularClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_clamped_fast_input", () -> this.specularClampedFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_atrous_input", this::getCurrentSpecAtrousInputTexture);
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
      uniforms.uniform1i("direct_atrous_step_size", this::getCurrentDirectAtrousStepSize, listener -> {});
      uniforms.uniform1i("direct_atrous_is_last_pass", this::getCurrentDirectAtrousIsLastPass, listener -> {});
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_restir_active_checkerboard_field", this::getActiveCheckerboardField);
      uniforms.uniform1f("ph_direct_sample_budget_scale", this::getDirectSampleBudgetScale, listener -> {});
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_depth_threshold", () -> this.properties.getRestirDepthThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_normal_threshold", () -> this.properties.getRestirNormalThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_max_history", () -> (float) this.properties.getRestirTemporalMaxHistory());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_depth_threshold", () -> this.properties.getRestirTemporalDepthThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_normal_threshold", () -> this.properties.getRestirTemporalNormalThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_visibility_max_age", () -> (float) this.properties.getRestirVisibilityMaxAge());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_visibility_max_distance", () -> this.properties.getRestirVisibilityMaxDistance());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_num_local_samples", () -> (float) this.properties.getLightTreeInitialSamples());
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_initial_num_environment_samples",
         () -> -1.0f
      );
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_num_brdf_samples", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_enable_visibility", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_brdf_cutoff", () -> 0.0001f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_local_light_sampling_mode", () -> 2.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_bias_mode", () -> this.properties.getRestirTemporalBiasMode());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_permutation_sampling", () -> this.properties.getRestirTemporalPermutationSampling());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_indirect_temporal_permutation_sampling", () -> 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_visibility_shortcut", () -> this.properties.getRestirTemporalVisibilityShortcut());
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_uniform_random", () -> this.getTemporalUniformRandom());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_temporal_fallback_sampling_mode", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_bias_mode", () -> this.properties.getRestirSpatialBiasMode());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_discount_naive", () -> this.properties.getRestirSpatialDiscountNaive());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_material_test", () -> this.properties.getRestirSpatialMaterialTest());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_boost_samples", () -> this.properties.getRestirSpatialBoostSamples());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_target_history", () -> this.properties.getRestirSpatialTargetHistory());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_sample_count", () -> (float) this.properties.getRestirSpatialSampleCount());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_radius", () -> this.properties.getRestirSpatialRadius());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_depth_threshold", () -> this.properties.getRestirSpatialDepthThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_normal_threshold", () -> this.properties.getRestirSpatialNormalThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_enable_final_visibility", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_indirect_enable_final_mis", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_indirect_boiling_filter_strength", () -> 0.2f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_reuse_final_visibility", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_enable_denoiser_packing", () -> PhotonicsStorage.DEBUG_DISABLE_DENOISER.value ? 0.0f : 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_max_accumulated_frame_num", () -> 30.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_max_fast_accumulated_frame_num", () -> 6.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_depth_threshold", () -> 0.003f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_denoising_range", () -> 500.0f);
   }

   private int getTemporalUniformRandom() {
      return this.jenkinsHash(SystemTimeUniforms.COUNTER.getAsInt());
   }

   private int jenkinsHash(int value) {
      int hash = value;
      hash = (hash + 0x7ed55d16) + (hash << 12);
      hash = (hash ^ 0xc761c23c) ^ (hash >>> 19);
      hash = (hash + 0x165667b1) + (hash << 5);
      hash = (hash + 0xd3a2646c) ^ (hash << 9);
      hash = (hash + 0xfd7046c5) + (hash << 3);
      hash = (hash ^ 0xb55a4f09) ^ (hash >>> 16);
      return hash;
   }

   private int getActiveCheckerboardField() {
      String checkerboardMode = PhotonicsStorage.RESTIR_CHECKERBOARD_MODE.value;
      if (checkerboardMode == null) {
         return 0;
      }

      int frameIndex = SystemTimeUniforms.COUNTER.getAsInt();
      if ("black".equalsIgnoreCase(checkerboardMode)) {
         return (frameIndex & 1) == 0 ? 2 : 1;
      }
      if ("white".equalsIgnoreCase(checkerboardMode)) {
         return (frameIndex & 1) == 0 ? 1 : 2;
      }
      return 0;
   }

   @Override
   public void render() {
      if (this.proposalRenderer == null) {
         return;
      }

      boolean denoiserDisabled = PhotonicsStorage.DEBUG_DISABLE_DENOISER.value;
      this.resolveGpuProfile();
      this.advanceGpuProfileFrame();
      this.ensureCompatDirectSoftCleared();
      this.lightingBuffer.swap();
      this.compatDirectSoftBuffer.swap();
      this.motionVectorBuffer.swap();
      this.directReservoirBuffer.swap();
      this.directTemporalReservoirBuffer.swap();
      this.directConfidenceBuffer.swap();
      this.directHistoryLengthBuffer.swap();
      this.directNoisyBuffer.swap();
      this.directResponsiveBuffer.swap();
      this.directSlowBuffer.swap();
      this.directFastBuffer.swap();
      this.directAntiFireflyBuffer.swap();
      this.directClampedSlowBuffer.swap();
      this.directClampedFastBuffer.swap();
      this.directDenoisedBuffer.swap();
      this.directAtrousPingBuffer.swap();
      this.specularNoisyBuffer.swap();
      this.specularResponsiveBuffer.swap();
      this.specularSlowBuffer.swap();
      this.specularFastBuffer.swap();
      this.specularAntiFireflyBuffer.swap();
      this.specularClampedSlowBuffer.swap();
      this.specularClampedFastBuffer.swap();
      this.specularDenoisedBuffer.swap();
      this.specularAtrousPingBuffer.swap();
      this.specularHistoryLengthBuffer.swap();
      this.indirectInitialReservoirBuffer.swap();
      this.indirectTemporalReservoirBuffer.swap();
      this.indirectReservoirBuffer.swap();
      long t0 = System.nanoTime();
      this.dispatchRegirCompute();
      this.renderProfiled(proposalSamplingRegionIndex, this.proposalRenderer);
      long t1 = System.nanoTime();
      this.renderDirectReuseProfiled();
      long t2 = System.nanoTime();
      // RTXDI shades the current frame's resolved reservoir and stores the updated
      // visibility back for future reuse. Our ping-pong framebuffer needs an
      // explicit mid-frame flip here so shadeSamples reads the freshly resolved
      // reservoir and writes the visibility-updated result into the other side.
      this.directReservoirBuffer.swap();
      if (this.getActiveCheckerboardField() == 0 && this.shadeSamplesMonolithicRenderer != null) {
         this.renderProfiled(shadeSamplesRegionIndex, this.shadeSamplesMonolithicRenderer);
      } else {
         this.renderProfiled(shadeSamplesRegionIndex, this.shadeSamplesRenderer);
      }
      long t3 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(directFeatureRegionIndex, this.directFeatureRenderer);
      }
      long t4 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(directTemporalRegionIndex, this.directTemporalRenderer);
      }
      long t5 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(directAntiFireflyRegionIndex, this.directAntiFireflyRenderer);
      }
      long t6 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(directHistoryFixRegionIndex, this.directHistoryFixRenderer);
      }
      long t7 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(directHistoryClampingRegionIndex, this.directHistoryClampingRenderer);
      }
      long t8 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderDirectAtrousProfiled();
      }
      long t9 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(specTemporalRegionIndex, this.specTemporalRenderer);
      }
      long t10 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(specAntiFireflyRegionIndex, this.specAntiFireflyRenderer);
      }
      long t11 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(specHistoryFixRegionIndex, this.specHistoryFixRenderer);
      }
      long t12 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(specHistoryClampingRegionIndex, this.specHistoryClampingRenderer);
      }
      long t13 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderSpecAtrousProfiled();
      }
      long t14 = System.nanoTime();
      this.renderIndirectAccumulationProfiled();
      long t15 = System.nanoTime();
      if (!denoiserDisabled) {
         this.renderProfiled(indirectDenoiseRegionIndex, this.indirectDenoisingRenderer);
      }
      long t16 = System.nanoTime();
      this.renderProfiled(accumulationRegionIndex, this.accumulationRenderer);
      long t17 = System.nanoTime();
      this.renderProfiled(indirectRegionIndex, this.indirectRenderer);
      long t18 = System.nanoTime();
      this.recordCpuPassTimes(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18);
      this.worldRegistry.advanceLightBlendFrame();
      this.logRenderProfileIfNeeded(t18 - t0);
   }

   @Override
   public Map<String, TextureObject> getAutomationTextures() {
      return Map.ofEntries(
         Map.entry("direct", this.getResolvedDirectTexture()),
         Map.entry("direct_reservoir", this.directReservoirBuffer.getWriteAttachment("data")),
         Map.entry("direct_soft", this.getCompatDirectSoftTexture()),
         Map.entry("direct_denoised", this.directDenoisedBuffer.getWriteAttachment("data")),
         Map.entry("direct_raw", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("handheld", this.lightingBuffer.getWriteAttachment("handheld")),
         Map.entry("indirect", this.getResolvedIndirectTexture()),
         Map.entry("indirect_raw", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("indirect_reservoir", this.indirectReservoirBuffer.getWriteAttachment("radiance")),
         Map.entry("lighting", this.directSlowBuffer.getWriteAttachment("data")),
         Map.entry("stage_direct", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("stage_lighting", this.directResponsiveBuffer.getWriteAttachment("data")),
         Map.entry("stage_indirect", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("motion", this.motionVectorBuffer.getWriteAttachment("data"))
      );
   }

   @Override
   public void recalculateSizes() {
      this.directReservoirBuffer.updatePerFrame();
      this.directTemporalReservoirBuffer.updatePerFrame();
      this.directHistoryLengthBuffer.updatePerFrame();
      this.directNoisyBuffer.updatePerFrame();
      this.directConfidenceBuffer.updatePerFrame();
      this.directResponsiveBuffer.updatePerFrame();
      this.directSlowBuffer.updatePerFrame();
      this.directFastBuffer.updatePerFrame();
      this.directAntiFireflyBuffer.updatePerFrame();
      this.directClampedSlowBuffer.updatePerFrame();
      this.directClampedFastBuffer.updatePerFrame();
      this.directAtrousPingBuffer.updatePerFrame();
      this.specularNoisyBuffer.updatePerFrame();
      this.specularResponsiveBuffer.updatePerFrame();
      this.specularSlowBuffer.updatePerFrame();
      this.specularFastBuffer.updatePerFrame();
      this.specularAntiFireflyBuffer.updatePerFrame();
      this.specularClampedSlowBuffer.updatePerFrame();
      this.specularClampedFastBuffer.updatePerFrame();
      this.specularDenoisedBuffer.updatePerFrame();
      this.specularAtrousPingBuffer.updatePerFrame();
      this.specularHistoryLengthBuffer.updatePerFrame();
      this.motionVectorBuffer.updatePerFrame();
      this.indirectInitialReservoirBuffer.updatePerFrame();
      this.indirectTemporalReservoirBuffer.updatePerFrame();
      this.indirectReservoirBuffer.updatePerFrame();
      this.indirectDenoisedBuffer.updatePerFrame();
      this.recalculateRenderer(this.proposalRenderer);
      this.recalculateRenderer(this.directTemporalResamplingRenderer);
      this.recalculateRenderer(this.reuseResolveRenderer);
      this.recalculateRenderer(this.directFeatureRenderer);
      this.recalculateRenderer(this.directTemporalRenderer);
      this.recalculateRenderer(this.directAntiFireflyRenderer);
      this.recalculateRenderer(this.directHistoryFixRenderer);
      this.recalculateRenderer(this.directHistoryClampingRenderer);
      this.recalculateRenderer(this.directAtrousRenderer);
      this.recalculateRenderer(this.specTemporalRenderer);
      this.recalculateRenderer(this.specAntiFireflyRenderer);
      this.recalculateRenderer(this.specHistoryFixRenderer);
      this.recalculateRenderer(this.specHistoryClampingRenderer);
      this.recalculateRenderer(this.specAtrousRenderer);
      this.recalculateRenderer(this.indirectInitialRenderer);
      this.recalculateRenderer(this.indirectTemporalRenderer);
      this.recalculateRenderer(this.indirectAccumulationRenderer);
      this.recalculateRenderer(this.indirectDenoisingRenderer);
      this.recalculateRenderer(this.accumulationRenderer);
      this.recalculateRenderer(this.indirectRenderer);
      this.recalculateRenderer(this.shadeSamplesMonolithicRenderer);
      this.recalculateRenderer(this.shadeSamplesRenderer);
      this.compatDirectSoftDirty = true;
   }

   @Override
   public void free() {
      this.proposalFramebuffer.destroy();
      this.proposalReservoirFramebuffer.destroy();
      this.directTemporalReservoirFramebuffer.destroy();
      this.reuseResolveFramebuffer.destroy();
      this.directFeatureFramebuffer.destroy();
      this.directTemporalFramebuffer.destroy();
      this.directAntiFireflyFramebuffer.destroy();
      this.directHistoryFixFramebuffer.destroy();
      this.directHistoryClampingFramebuffer.destroy();
      this.directAtrousFramebuffer.destroy();
      this.specTemporalFramebuffer.destroy();
      this.specAntiFireflyFramebuffer.destroy();
      this.specHistoryFixFramebuffer.destroy();
      this.specHistoryClampingFramebuffer.destroy();
      this.specAtrousFramebuffer.destroy();
      this.indirectInitialFramebuffer.destroy();
      this.indirectTemporalFramebuffer.destroy();
      this.indirectAccumulationFramebuffer.destroy();
      this.indirectDenoisingFramebuffer.destroy();
      this.positionWriteFramebuffer.destroy();
      this.shadeSamplesMonolithicFramebuffer.destroy();
      this.shadeSamplesFramebuffer.destroy();
      this.shadeSamplesReservoirFramebuffer.destroy();
      this.lightingBuffer.destroy();
      this.lightingStageBuffer.destroy();
      this.compatDirectSoftBuffer.destroy();
      this.motionVectorBuffer.destroy();
      this.directReservoirBuffer.destroy();
      this.directTemporalReservoirBuffer.destroy();
      this.directConfidenceBuffer.destroy();
      this.directHistoryLengthBuffer.destroy();
      this.directNoisyBuffer.destroy();
      this.directResponsiveBuffer.destroy();
      this.directSlowBuffer.destroy();
      this.directFastBuffer.destroy();
      this.directAntiFireflyBuffer.destroy();
      this.directClampedSlowBuffer.destroy();
      this.directClampedFastBuffer.destroy();
      this.directDenoisedBuffer.destroy();
      this.directAtrousPingBuffer.destroy();
      this.specularNoisyBuffer.destroy();
      this.specularResponsiveBuffer.destroy();
      this.specularSlowBuffer.destroy();
      this.specularFastBuffer.destroy();
      this.specularAntiFireflyBuffer.destroy();
      this.specularClampedSlowBuffer.destroy();
      this.specularClampedFastBuffer.destroy();
      this.specularDenoisedBuffer.destroy();
      this.specularAtrousPingBuffer.destroy();
      this.specularHistoryLengthBuffer.destroy();
      this.indirectInitialReservoirBuffer.destroy();
      this.indirectTemporalReservoirBuffer.destroy();
      this.indirectReservoirBuffer.destroy();
      this.indirectDenoisedBuffer.destroy();
      this.destroyRenderer(this.proposalRenderer);
      this.destroyRenderer(this.directTemporalResamplingRenderer);
      this.destroyRenderer(this.reuseResolveRenderer);
      this.destroyRenderer(this.directFeatureRenderer);
      this.destroyRenderer(this.directTemporalRenderer);
      this.destroyRenderer(this.directAntiFireflyRenderer);
      this.destroyRenderer(this.directHistoryFixRenderer);
      this.destroyRenderer(this.directHistoryClampingRenderer);
      this.destroyRenderer(this.directAtrousRenderer);
      this.destroyRenderer(this.specTemporalRenderer);
      this.destroyRenderer(this.specAntiFireflyRenderer);
      this.destroyRenderer(this.specHistoryFixRenderer);
      this.destroyRenderer(this.specHistoryClampingRenderer);
      this.destroyRenderer(this.specAtrousRenderer);
      this.destroyRenderer(this.indirectInitialRenderer);
      this.destroyRenderer(this.indirectTemporalRenderer);
      this.destroyRenderer(this.indirectAccumulationRenderer);
      this.destroyRenderer(this.indirectDenoisingRenderer);
      this.destroyRenderer(this.accumulationRenderer);
      this.destroyRenderer(this.indirectRenderer);
      this.destroyRenderer(this.shadeSamplesMonolithicRenderer);
      this.destroyRenderer(this.shadeSamplesRenderer);
      this.destroyGpuTimerQuery();
      if (this.regirComputeProgram != null) {
         this.regirComputeProgram.destroy();
      }
   }

   private ColorFramebuffer createDirectSignalFramebuffer(float renderScale, String format) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(renderScale);
      framebuffer.createAttachment("data", format, false);
      return framebuffer;
   }

   private ColorFramebuffer createDirectReservoirFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      framebuffer.createAttachment("data", "RGBA32F", false);
      framebuffer.createAttachment("sample", "RGBA32F", false);
      // RGBA32F required: RGB channels store per-channel visibility floats [0,1];
      // alpha stores age+spatialDistance bit-packed into a single float32 integer.
      // RGBA16F lacks the integer precision needed for the bit packing (max ~8M).
      framebuffer.createAttachment("meta", "RGBA32F", false);
      return framebuffer;
   }

   private Vector2f getDirectReservoirResolution() {
      Vector2f framebufferSize = new Vector2f(
         MinecraftClient.getInstance().getWindow().getFramebufferWidth(),
         MinecraftClient.getInstance().getWindow().getFramebufferHeight()
      );
      if (this.getActiveCheckerboardField() == 0) {
         return framebufferSize;
      }
      framebufferSize.x = Math.max(1.0f, (float) Math.ceil(framebufferSize.x * 0.5f));
      return framebufferSize;
   }

   private RoutingFramebuffer createDirectTemporalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.directNoisyBuffer.getWriteAttachment("data"),
         () -> this.directResponsiveBuffer.getWriteAttachment("data"),
         () -> this.directSlowBuffer.getWriteAttachment("data"),
         () -> this.directFastBuffer.getWriteAttachment("data"),
         () -> this.directHistoryLengthBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectTemporalReservoirFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.directTemporalReservoirBuffer.getWriteAttachment("data"),
         () -> this.directTemporalReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directTemporalReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createDirectFeatureFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("material"),
         () -> this.directConfidenceBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectAntiFireflyFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.directAntiFireflyBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createDirectHistoryFixFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.directClampedSlowBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createDirectHistoryClampingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.directSlowBuffer.getWriteAttachment("data"),
         () -> this.directClampedFastBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectAtrousFramebuffer() {
      return this.createRoutingFramebuffer(this::getCurrentDirectAtrousOutputTexture);
   }

   private RoutingFramebuffer createSpecTemporalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.specularNoisyBuffer.getWriteAttachment("data"),
         () -> this.specularResponsiveBuffer.getWriteAttachment("data"),
         () -> this.specularSlowBuffer.getWriteAttachment("data"),
         () -> this.specularFastBuffer.getWriteAttachment("data"),
         () -> this.specularHistoryLengthBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createSpecAntiFireflyFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.specularAntiFireflyBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createSpecHistoryFixFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.specularClampedSlowBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createSpecHistoryClampingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.specularSlowBuffer.getWriteAttachment("data"),
         () -> this.specularClampedFastBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createSpecAtrousFramebuffer() {
      return this.createRoutingFramebuffer(this::getCurrentSpecAtrousOutputTexture);
   }

   private RoutingFramebuffer createIndirectInitialFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createIndirectTemporalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectTemporalReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createIndirectBoilingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.indirectReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private void createLightingBufferAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGB32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("mapped_normal", "RGB16F", false);
      framebuffer.createAttachment("albedo", "RGBA8", false);
      framebuffer.createAttachment("material", "RGBA16F", false);
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("direct_specular", "RGBA16F", false);
      framebuffer.createAttachment("lighting", "RGBA32F", false);
      framebuffer.createAttachment("lighting_variance", "RGBA32F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
      framebuffer.createAttachment("indirect_variance", "RGBA32F", false);
   }

   private void createLightingStageAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGB32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("mapped_normal", "RGB16F", false);
      framebuffer.createAttachment("albedo", "RGBA8", false);
      framebuffer.createAttachment("material", "RGBA16F", false);
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("direct_specular", "RGBA16F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
   }

   private void createIndirectReservoirAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGBA32F", false);
      // RTXDI packed GI reservoirs store packed normal / misc / radiance as 32-bit values.
      // These attachments are sampled back with floatBitsToUint(...), so 16-bit float formats
      // destroy the packed payload and corrupt M, age, and radiance on load.
      framebuffer.createAttachment("normal", "RGBA32F", false);
      framebuffer.createAttachment("radiance", "RGBA32F", false);
      framebuffer.createAttachment("meta", "RGBA32F", false);
   }

   private RoutingFramebuffer createProposalGeometryFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("position"),
         () -> this.lightingStageBuffer.getWriteAttachment("normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("albedo"),
         () -> this.motionVectorBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createProposalReservoirFramebuffer() {
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createReuseResolveFramebuffer() {
      // Spatial-only pass: outputs the resampled reservoir but NOT the shaded direct color.
      // Shading is deferred to the shade_samples pass.
      return this.createRoutingFramebuffer(
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createShadeSamplesLightingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("direct"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct_specular")
      );
   }

   private RoutingFramebuffer createShadeSamplesReservoirFramebuffer() {
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createIndirectAccumulationFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("indirect"),
         () -> this.lightingBuffer.getWriteAttachment("indirect_variance"),
         () -> this.lightingBuffer.getWriteAttachment("handheld"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createIndirectDenoisingFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.indirectDenoisedBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createPositionWriteFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("position"),
         () -> this.lightingBuffer.getWriteAttachment("normal"),
         () -> this.lightingBuffer.getWriteAttachment("mapped_normal"),
         () -> this.lightingBuffer.getWriteAttachment("albedo"),
         () -> this.lightingBuffer.getWriteAttachment("material"),
         () -> this.lightingBuffer.getWriteAttachment("direct"),
         () -> this.compatDirectSoftBuffer.getWriteAttachment("direct_soft_compat")
      );
   }

   private RoutingFramebuffer createShadeSamplesMonolithicFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("direct"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct_specular"),
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createRoutingFramebuffer(Supplier<TextureObject>... attachments) {
      RoutingFramebuffer framebuffer = new RoutingFramebuffer();
      for (Supplier<TextureObject> attachment : attachments) {
         framebuffer.addAttachment(attachment);
      }
      return framebuffer;
   }

   @SafeVarargs
   private final RoutingFramebuffer createDirectPackedRoutingFramebuffer(Supplier<TextureObject>... attachments) {
      return this.createRoutingFramebuffer(this::getDirectPackedViewportWidth, attachments);
   }

   @SafeVarargs
   private final RoutingFramebuffer createRoutingFramebuffer(IntSupplier viewportWidthSupplier, Supplier<TextureObject>... attachments) {
      RoutingFramebuffer framebuffer = new RoutingFramebuffer(viewportWidthSupplier::getAsInt);
      for (Supplier<TextureObject> attachment : attachments) {
         framebuffer.addAttachment(attachment);
      }
      return framebuffer;
   }

   private int getDirectPackedViewportWidth() {
      return Math.max(1, this.directReservoirBuffer.getWriteAttachment("data").getTextureDimensions()[0]);
   }

   private TextureObject getCurrentGeometryPositionTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("position");
      }
      return this.lightingBuffer.getWriteAttachment("position");
   }

   private TextureObject getCurrentGeometryNormalTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("normal");
      }
      return this.lightingBuffer.getWriteAttachment("normal");
   }

   private TextureObject getCurrentMappedNormalTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("mapped_normal");
      }
      return this.lightingBuffer.getWriteAttachment("mapped_normal");
   }

   private TextureObject getCurrentMaterialTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("material");
      }
      return this.lightingBuffer.getWriteAttachment("material");
   }

   private TextureObject getCurrentAlbedoTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("albedo");
      }
      return this.lightingBuffer.getWriteAttachment("albedo");
   }

   private boolean shouldUseStageGeometry() {
      return this.isCurrentPhotonicsFragment(shadeSamplesFragment)
         || this.isCurrentPhotonicsFragment(proposalReservoirFragment)
         || this.isCurrentPhotonicsFragment(directTemporalResamplingFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesLightingFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesReservoirFragment)
         || this.isCurrentPhotonicsFragment("lighttree/reuse_resolve.fsh")
         || this.isCurrentPhotonicsFragment(directAntiFireflyFragment)
         || this.isCurrentPhotonicsFragment(directHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(directHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(directAtrousFragment)
         || this.isCurrentPhotonicsFragment(specTemporalFragment)
         || this.isCurrentPhotonicsFragment(specAntiFireflyFragment)
         || this.isCurrentPhotonicsFragment(specHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(specHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(specAtrousFragment)
         || this.isCurrentPhotonicsFragment(indirectAccumulationFragment)
         // GI denoising runs before the accumulation pass copies the current frame
         // guides into lightingBuffer, so it must read the live stage geometry.
         || this.isCurrentPhotonicsFragment(indirectDenoisingFragment);
   }

   private boolean shouldUseCurrentDirectHistoryLength() {
      return this.isCurrentPhotonicsFragment(directTemporalFragment)
         || this.isCurrentPhotonicsFragment(directHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(directHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(directAtrousFragment);
   }

   private boolean shouldUseCurrentSpecHistoryLength() {
      return this.isCurrentPhotonicsFragment(specTemporalFragment)
         || this.isCurrentPhotonicsFragment(specHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(specHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(specAtrousFragment);
   }

   private TextureObject getCurrentDirectAtrousInputTexture() {
      if (this.directAtrousIteration == 0) {
         return this.directSlowBuffer.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 1) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private boolean isFinalDirectAtrousIteration() {
      return this.directAtrousIteration == this.directAtrousStepSizes.length - 1;
   }

   private TextureObject getCurrentDirectAtrousOutputTexture() {
      boolean isFinalPass = this.isFinalDirectAtrousIteration();
      boolean readsDenoisedBuffer = this.directAtrousIteration > 0 && (this.directAtrousIteration & 1) == 0;
      if (isFinalPass && readsDenoisedBuffer) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      if (isFinalPass) {
         return this.directDenoisedBuffer.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 0) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentSpecAtrousInputTexture() {
      if (this.specAtrousIteration == 0) {
         return this.specularSlowBuffer.getWriteAttachment("data");
      }
      if ((this.specAtrousIteration & 1) == 1) {
         return this.specularAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.specularDenoisedBuffer.getWriteAttachment("data");
   }

   private boolean isFinalSpecAtrousIteration() {
      return this.specAtrousIteration == this.directAtrousStepSizes.length - 1;
   }

   private TextureObject getCurrentSpecAtrousOutputTexture() {
      boolean isFinalPass = this.isFinalSpecAtrousIteration();
      boolean readsDenoisedBuffer = this.specAtrousIteration > 0 && (this.specAtrousIteration & 1) == 0;
      if (isFinalPass && readsDenoisedBuffer) {
         return this.specularAtrousPingBuffer.getWriteAttachment("data");
      }
      if (isFinalPass) {
         return this.specularDenoisedBuffer.getWriteAttachment("data");
      }
      if ((this.specAtrousIteration & 1) == 0) {
         return this.specularAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.specularDenoisedBuffer.getWriteAttachment("data");
   }

   private int getCurrentDirectAtrousStepSize() {
      int iterationIndex = Math.max(0, Math.min(this.directAtrousIteration, this.directAtrousStepSizes.length - 1));
      return this.directAtrousStepSizes[iterationIndex];
   }

   private float getDirectSampleBudgetScale() {
      float blendFactor = this.worldRegistry.fetchLightBlendFactor();
      boolean lightReload = this.worldRegistry.fetchLightReload();
      boolean hasActiveBlend = this.worldRegistry.hasActiveLightBlend();
      int blendRegions = this.worldRegistry.getLightBlendRegionCount();
      LightRegistry lightRegistry = this.worldRegistry.getLightRegistry();
      float lightCoverage = 0.0f;
      if (lightRegistry.totalLights() > 0) {
         lightCoverage = Math.min(1.0f, (float) lightRegistry.lightCount() / (float) lightRegistry.totalLights());
      }

      float warmupScale = 0.25f + 0.75f * blendFactor;
      if (!lightReload && blendRegions == 0) {
         warmupScale = Math.max(warmupScale, 0.85f);
      }
      if (!lightReload && hasActiveBlend) {
         warmupScale = Math.min(warmupScale, 0.55f);
      }
      float residencyScale = 0.35f + 0.65f * lightCoverage;
      return Math.max(0.2f, Math.min(1.0f, warmupScale * residencyScale));
   }

   private int getCurrentDirectAtrousIsLastPass() {
      return this.directAtrousIteration == this.directAtrousStepSizes.length - 1 ? 1 : 0;
   }

   private static int[] resolveDirectAtrousStepSizes(PhotonicsProperties properties) {
      int passCount = Math.clamp(properties.getNrdAtrousPasses(), 1, 7);
      return switch (passCount) {
         case 1 -> new int[]{4};
         case 2 -> new int[]{1, 8};
         case 3 -> new int[]{1, 4, 16};
         case 4 -> new int[]{1, 2, 8, 16};
         case 5 -> new int[]{1, 2, 4, 8, 16};
         case 6 -> new int[]{1, 2, 4, 8, 16, 16};
         case 7 -> new int[]{1, 2, 4, 8, 16, 16, 16};
         default -> throw new IllegalStateException("Unexpected direct atrous pass count: " + passCount);
      };
   }

   private GpuTimerQuery createGpuTimerQuery() {
      return new GpuTimerQuery(gpuProfilerRegionNames);
   }

   private void resolveGpuProfile() {
      this.gpuTimerQuery.resolve();
   }

   private void dispatchRegirCompute() {
      if (this.regirComputeProgram == null || !this.regirComputeProgram.isCompiled()) {
         return;
      }
      LightRegistry lightRegistry = this.worldRegistry.getLightRegistry();
      if (lightRegistry.lightCount() <= 0) {
         return;
      }

      // Update PDF mipmap texture with current per-light power values
      float[] powers = lightRegistry.getLightPowers();
      if (powers.length > 0) {
         this.regirComputeProgram.createPdfTexture(lightRegistry.lightCount());
         this.regirComputeProgram.updatePdfTexture(powers, lightRegistry.lightCount());
      }

      // RTXDI defaults: numBuildSamples = 8 (ReGIR.h:141), samplingJitter = 1.0.
      // getRegirLightIndexMemoryManager() is the unified uvec2 ReGIR output buffer,
      // allocated at 8 bytes/slot (cellCount * lightsPerCell * 8) to hold uvec2 entries.
      int gridRes = lightRegistry.getRegirGridResolution();
      this.regirComputeProgram.dispatch(
         lightRegistry.getLightsMemoryManager(),
         lightRegistry.getGlobalLightCdfMemoryManager(),
         lightRegistry.getRegirLightIndexMemoryManager(),
         lightRegistry.getRegirCompactLightDataMemoryManager(),
         lightRegistry.getRegirGridCenter(),
         new Vector3i(gridRes, gridRes, gridRes),
         lightRegistry.getRegirLightsPerCell(),
         32.0f,
         lightRegistry.lightCount(),
         SystemTimeUniforms.COUNTER.getAsInt(),
         8,    // numBuildSamples — RTXDI default from ReGIR.h:141
         1.0f  // samplingJitter — RTXDI default
      );
   }

   private void renderProfiled(int regionIndex, @Nullable CompositeRenderer renderer) {
      if (renderer == null) {
         return;
      }
      this.beginGpuRegion(regionIndex);
      renderer.renderAll();
      this.endGpuRegion(regionIndex);
   }

   private void renderDirectReuseProfiled() {
      if (this.directTemporalResamplingRenderer == null && this.reuseResolveRenderer == null) {
         return;
      }
      this.beginGpuRegion(reuseResolveRegionIndex);
      if (this.directTemporalResamplingRenderer != null) {
         this.directTemporalResamplingRenderer.renderAll();
      }
      if (this.reuseResolveRenderer != null) {
         this.reuseResolveRenderer.renderAll();
      }
      this.endGpuRegion(reuseResolveRegionIndex);
   }

   private void renderIndirectAccumulationProfiled() {
      if (this.indirectInitialRenderer == null && this.indirectTemporalRenderer == null && this.indirectAccumulationRenderer == null) {
         return;
      }
      this.beginGpuRegion(indirectAccumRegionIndex);
      if (this.indirectInitialRenderer != null) {
         this.indirectInitialRenderer.renderAll();
      }
      if (this.indirectTemporalRenderer != null) {
         this.indirectTemporalRenderer.renderAll();
      }
      if (this.indirectAccumulationRenderer != null) {
         this.indirectAccumulationRenderer.renderAll();
      }
      this.endGpuRegion(indirectAccumRegionIndex);
   }

   private void renderDirectAtrousProfiled() {
      this.beginGpuRegion(directAtrousRegionIndex);
      for (this.directAtrousIteration = 0; this.directAtrousIteration < this.directAtrousStepSizes.length; this.directAtrousIteration++) {
         long iterationStart = System.nanoTime();
         this.directAtrousRenderer.renderAll();
         this.lastCpuDirectAtrousIterationNanos[this.directAtrousIteration] = System.nanoTime() - iterationStart;
      }
      this.endGpuRegion(directAtrousRegionIndex);
   }

   private void renderSpecAtrousProfiled() {
      this.beginGpuRegion(specAtrousRegionIndex);
      for (this.specAtrousIteration = 0; this.specAtrousIteration < this.directAtrousStepSizes.length; this.specAtrousIteration++) {
         this.specAtrousRenderer.renderAll();
      }
      this.endGpuRegion(specAtrousRegionIndex);
   }

   private void beginGpuRegion(int regionIndex) {
      this.gpuTimerQuery.begin(regionIndex);
   }

   private void endGpuRegion(int regionIndex) {
      this.gpuTimerQuery.end(regionIndex);
   }

   private void destroyGpuTimerQuery() {
      this.gpuTimerQuery.destroy();
   }

   private TextureObject getResolvedDirectTexture() {
      if (PhotonicsStorage.DEBUG_DISABLE_DENOISER.value) {
         return this.lightingBuffer.getWriteAttachment("direct");
      }
      if (this.isFinalDirectAtrousIteration() && (this.directAtrousIteration & 1) == 0 && this.directAtrousIteration > 0) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getPreviousResolvedDirectTexture() {
      if (PhotonicsStorage.DEBUG_DISABLE_DENOISER.value) {
         return this.lightingBuffer.getReadAttachment("direct");
      }
      return this.directDenoisedBuffer.getReadAttachment("data");
   }

   private TextureObject getResolvedIndirectTexture() {
      if (PhotonicsStorage.DEBUG_DISABLE_DENOISER.value) {
         return this.lightingBuffer.getWriteAttachment("indirect");
      }
      return this.indirectDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentDirectReservoirDataTexture() {
      if (this.isCurrentPhotonicsFragment(shadeSamplesFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesLightingFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesReservoirFragment)) {
         return this.directReservoirBuffer.getReadAttachment("data");
      }
      return this.directReservoirBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentDirectReservoirSampleTexture() {
      if (this.isCurrentPhotonicsFragment(shadeSamplesFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesLightingFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesReservoirFragment)) {
         return this.directReservoirBuffer.getReadAttachment("sample");
      }
      return this.directReservoirBuffer.getWriteAttachment("sample");
   }

   private TextureObject getCurrentDirectReservoirMetaTexture() {
      if (this.isCurrentPhotonicsFragment(shadeSamplesFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesLightingFragment)
         || this.isCurrentPhotonicsFragment(shadeSamplesReservoirFragment)) {
         return this.directReservoirBuffer.getReadAttachment("meta");
      }
      return this.directReservoirBuffer.getWriteAttachment("meta");
   }

   private TextureObject getCurrentIndirectReservoirPositionTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("position");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("position");
   }

   private TextureObject getCurrentIndirectReservoirNormalTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("normal");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("normal");
   }

   private TextureObject getCurrentIndirectReservoirRadianceTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("radiance");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("radiance");
   }

   private TextureObject getCurrentIndirectReservoirMetaTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("meta");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("meta");
   }

   private TextureObject getCompatDirectSoftTexture() {
      return this.compatDirectSoftBuffer.getWriteAttachment("direct_soft_compat");
   }

   private TextureObject getPreviousCompatDirectSoftTexture() {
      return this.compatDirectSoftBuffer.getReadAttachment("direct_soft_compat");
   }

   private void recalculateRenderer(@Nullable CompositeRenderer renderer) {
      if (renderer != null) {
         renderer.recalculateSizes();
      }
   }

   private void destroyRenderer(@Nullable CompositeRenderer renderer) {
      if (renderer != null) {
         renderer.destroy();
      }
   }

   private void ensureCompatDirectSoftCleared() {
      if (!this.compatDirectSoftDirty) {
         return;
      }
      this.clearCompatDirectSoftAttachments();
      this.compatDirectSoftDirty = false;
   }

   private void clearCompatDirectSoftAttachments() {
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.compatDirectSoftBuffer.clear(clearColor);
      this.compatDirectSoftBuffer.swap();
      this.compatDirectSoftBuffer.clear(clearColor);
   }

   private void recordCpuPassTimes(long t0, long t1, long t2, long t3, long t4, long t5, long t6, long t7, long t8, long t9, long t10, long t11, long t12, long t13, long t14, long t15, long t16, long t17, long t18) {
      this.lastCpuProposalSamplingNanos = t1 - t0;
      this.lastCpuReuseResolveNanos = t2 - t1;
      this.lastCpuShadeSamplesNanos = t3 - t2;
      this.lastCpuDirectFeatureNanos = t4 - t3;
      this.lastCpuDirectTemporalNanos = t5 - t4;
      this.lastCpuDirectHistoryFixNanos = t6 - t5;
      this.lastCpuDirectHistoryClampingNanos = t7 - t6;
      this.lastCpuDirectAntiFireflyNanos = t8 - t7;
      this.lastCpuDirectAtrousNanos = t9 - t8;
      this.lastCpuSpecTemporalNanos = t10 - t9;
      this.lastCpuSpecHistoryFixNanos = t11 - t10;
      this.lastCpuSpecHistoryClampingNanos = t12 - t11;
      this.lastCpuSpecAntiFireflyNanos = t13 - t12;
      this.lastCpuSpecAtrousNanos = t14 - t13;
      this.lastCpuIndirectAccumNanos = t15 - t14;
      this.lastCpuIndirectDenoiseNanos = t16 - t15;
      this.lastCpuAccumulationNanos = t17 - t16;
      this.lastCpuIndirectNanos = t18 - t17;
   }

   private void logRenderProfileIfNeeded(long totalCpuNanos) {
      this.profilerFrameCounter++;
      if (this.profilerFrameCounter < profilerLogIntervalFrames) {
         return;
      }
      this.profilerFrameCounter = 0;
      long[] cpuPassNanos = this.getCpuPassNanos();
      long[] gpuPassNanos = this.getGpuPassNanos();
      int worstCpuIndex = this.getWorstPassIndex(cpuPassNanos);
      int worstGpuIndex = this.getWorstPassIndex(gpuPassNanos);
      WorldRegistry worldRegistry = this.worldRegistry;
      LightRegistry lightRegistry = worldRegistry.getLightRegistry();
      long totalGpuNanos = this.sumNanos(gpuPassNanos);
      int fbWidth = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int fbHeight = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      int renderWidth = Math.round(fbWidth * this.renderScale);
      int renderHeight = Math.round(fbHeight * this.renderScale);
      long renderPixels = (long) renderWidth * renderHeight;
      Photonic.info(
         "[Profiler] ReGIR/ReSTIR summary: cpuTotal={}us gpuTotal={}us worstCpu={}={}us worstGpu={}={}us reloadActive={} blendFactor={} blendRegions={} tracedLights={}/{} regirCells={} regirLightSlots={} regirGrid={}^3 viewport={}x{} renderRes={}x{} pixels={} proposalNsPerPixel={} stageGeometry={}",
         this.toMicros(totalCpuNanos),
         this.toMicros(totalGpuNanos),
         profilerPassNames[worstCpuIndex],
         this.toMicros(cpuPassNanos[worstCpuIndex]),
         profilerPassNames[worstGpuIndex],
         this.toMicros(gpuPassNanos[worstGpuIndex]),
         worldRegistry.fetchLightReload(),
         this.formatBlendFactor(worldRegistry.fetchLightBlendFactor()),
         worldRegistry.getLightBlendRegionCount(),
         lightRegistry.lightCount(),
         lightRegistry.totalLights(),
         lightRegistry.getRegirActiveCellCount(),
         lightRegistry.getRegirActiveLightSlotCount(),
         lightRegistry.getRegirGridResolution(),
         fbWidth, fbHeight,
         renderWidth, renderHeight,
         renderPixels,
         renderPixels > 0 ? (gpuPassNanos[proposalSamplingRegionIndex] / renderPixels) : 0,
         this.describeStageGeometryUsage()
      );
      Photonic.info(
         "[Profiler] ReGIR/ReSTIR CPU passes: proposalSampling={}us reuseResolve={}us shadeSamples={}us directFeatureExtract={}us directTemporal={}us directAntiFirefly={}us directHistoryFix={}us directHistoryClamping={}us directAtrous={}us specTemporal={}us specAntiFirefly={}us specHistoryFix={}us specHistoryClamping={}us specAtrous={}us indirectAccum={}us indirectDenoise={}us accumulation={}us indirect={}us",
         this.toMicros(cpuPassNanos[proposalSamplingRegionIndex]),
         this.toMicros(cpuPassNanos[reuseResolveRegionIndex]),
         this.toMicros(cpuPassNanos[shadeSamplesRegionIndex]),
         this.toMicros(cpuPassNanos[directFeatureRegionIndex]),
         this.toMicros(cpuPassNanos[directTemporalRegionIndex]),
         this.toMicros(cpuPassNanos[directAntiFireflyRegionIndex]),
         this.toMicros(cpuPassNanos[directHistoryFixRegionIndex]),
         this.toMicros(cpuPassNanos[directHistoryClampingRegionIndex]),
         this.toMicros(cpuPassNanos[directAtrousRegionIndex]),
         this.toMicros(cpuPassNanos[specTemporalRegionIndex]),
         this.toMicros(cpuPassNanos[specAntiFireflyRegionIndex]),
         this.toMicros(cpuPassNanos[specHistoryFixRegionIndex]),
         this.toMicros(cpuPassNanos[specHistoryClampingRegionIndex]),
         this.toMicros(cpuPassNanos[specAtrousRegionIndex]),
         this.toMicros(cpuPassNanos[indirectAccumRegionIndex]),
         this.toMicros(cpuPassNanos[indirectDenoiseRegionIndex]),
         this.toMicros(cpuPassNanos[accumulationRegionIndex]),
         this.toMicros(cpuPassNanos[indirectRegionIndex])
      );
      this.logGpuRenderProfile(gpuPassNanos);
   }

   private void logGpuRenderProfile(long[] gpuPassNanos) {
      long denoiseTotal = gpuPassNanos[directFeatureRegionIndex]
         + gpuPassNanos[directTemporalRegionIndex]
         + gpuPassNanos[directAntiFireflyRegionIndex]
         + gpuPassNanos[directHistoryFixRegionIndex]
         + gpuPassNanos[directHistoryClampingRegionIndex]
         + gpuPassNanos[directAtrousRegionIndex]
         + gpuPassNanos[specTemporalRegionIndex]
         + gpuPassNanos[specAntiFireflyRegionIndex]
         + gpuPassNanos[specHistoryFixRegionIndex]
         + gpuPassNanos[specHistoryClampingRegionIndex]
         + gpuPassNanos[specAtrousRegionIndex];
      long directTotal = gpuPassNanos[proposalSamplingRegionIndex] + gpuPassNanos[reuseResolveRegionIndex] + gpuPassNanos[shadeSamplesRegionIndex] + gpuPassNanos[accumulationRegionIndex];
      long indirectTotal = gpuPassNanos[indirectAccumRegionIndex]
         + gpuPassNanos[indirectDenoiseRegionIndex]
         + gpuPassNanos[indirectRegionIndex];
      LightRegistry lightRegistry = this.worldRegistry.getLightRegistry();
      int fbWidth = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int fbHeight = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      int renderWidth = Math.round(fbWidth * this.renderScale);
      int renderHeight = Math.round(fbHeight * this.renderScale);
      long renderPixels = (long) renderWidth * renderHeight;
      Photonic.info(
         "[Profiler] ReGIR/ReSTIR GPU passes: proposalSampling={}us reuseResolve={}us shadeSamples={}us directFeatureExtract={}us directTemporal={}us directAntiFirefly={}us directHistoryFix={}us directHistoryClamping={}us directAtrous={}us specTemporal={}us specAntiFirefly={}us specHistoryFix={}us specHistoryClamping={}us specAtrous={}us indirectAccum={}us indirectDenoise={}us accumulation={}us indirect={}us",
         this.toMicros(gpuPassNanos[proposalSamplingRegionIndex]),
         this.toMicros(gpuPassNanos[reuseResolveRegionIndex]),
         this.toMicros(gpuPassNanos[shadeSamplesRegionIndex]),
         this.toMicros(gpuPassNanos[directFeatureRegionIndex]),
         this.toMicros(gpuPassNanos[directTemporalRegionIndex]),
         this.toMicros(gpuPassNanos[directAntiFireflyRegionIndex]),
         this.toMicros(gpuPassNanos[directHistoryFixRegionIndex]),
         this.toMicros(gpuPassNanos[directHistoryClampingRegionIndex]),
         this.toMicros(gpuPassNanos[directAtrousRegionIndex]),
         this.toMicros(gpuPassNanos[specTemporalRegionIndex]),
         this.toMicros(gpuPassNanos[specAntiFireflyRegionIndex]),
         this.toMicros(gpuPassNanos[specHistoryFixRegionIndex]),
         this.toMicros(gpuPassNanos[specHistoryClampingRegionIndex]),
         this.toMicros(gpuPassNanos[specAtrousRegionIndex]),
         this.toMicros(gpuPassNanos[indirectAccumRegionIndex]),
         this.toMicros(gpuPassNanos[indirectDenoiseRegionIndex]),
         this.toMicros(gpuPassNanos[accumulationRegionIndex]),
         this.toMicros(gpuPassNanos[indirectRegionIndex])
      );
      Photonic.info(
         "[Profiler] ReGIR/ReSTIR GPU buckets: direct={}us denoise={}us indirect={}us directShare={} denoiseShare={} indirectShare={}",
         this.toMicros(directTotal),
         this.toMicros(denoiseTotal),
         this.toMicros(indirectTotal),
         this.formatShare(directTotal, gpuPassNanos),
         this.formatShare(denoiseTotal, gpuPassNanos),
         this.formatShare(indirectTotal, gpuPassNanos)
      );
      long proposalNs = gpuPassNanos[proposalSamplingRegionIndex];
      long reuseNs = gpuPassNanos[reuseResolveRegionIndex];
      long denoiseNs = denoiseTotal;
      long indirectNs = indirectTotal;
      Photonic.info(
         "[Profiler] ReGIR/ReSTIR per-pixel: proposalNspp={}ns reuseNspp={}ns denoiseNspp={}ns indirectNspp={}ns regirCells={} regirLightSlots={}",
         renderPixels > 0 ? proposalNs / renderPixels : 0,
         renderPixels > 0 ? reuseNs / renderPixels : 0,
         renderPixels > 0 ? denoiseNs / renderPixels : 0,
         renderPixels > 0 ? indirectNs / renderPixels : 0,
         lightRegistry.getRegirActiveCellCount(),
         lightRegistry.getRegirActiveLightSlotCount()
      );
      this.logDirectAtrousBreakdown();
   }

   private void logDirectAtrousBreakdown() {
      if (this.lastCpuDirectAtrousIterationNanos.length == 0) {
         return;
      }
      StringBuilder passSummary = new StringBuilder();
      long worstNanos = 0L;
      int worstPass = 0;
      for (int i = 0; i < this.lastCpuDirectAtrousIterationNanos.length; i++) {
         long iterationNanos = this.lastCpuDirectAtrousIterationNanos[i];
         if (i > 0) {
            passSummary.append(' ');
         }
         passSummary.append("pass")
            .append(i)
            .append("(step=")
            .append(this.directAtrousStepSizes[i])
            .append(")=")
            .append(this.toMicros(iterationNanos))
            .append("us");
         if (iterationNanos > worstNanos) {
            worstNanos = iterationNanos;
            worstPass = i;
         }
      }
      Photonic.info(
         "[Profiler] ReGIR/ReSTIR directAtrous breakdown: passes={} worstPass=pass{}(step={})={}us",
         passSummary,
         worstPass,
         this.directAtrousStepSizes[worstPass],
         this.toMicros(worstNanos)
      );
   }

   private long[] getCpuPassNanos() {
      return new long[]{
         this.lastCpuProposalSamplingNanos,
         this.lastCpuReuseResolveNanos,
         this.lastCpuShadeSamplesNanos,
         this.lastCpuDirectFeatureNanos,
         this.lastCpuDirectTemporalNanos,
         this.lastCpuDirectAntiFireflyNanos,
         this.lastCpuDirectHistoryFixNanos,
         this.lastCpuDirectHistoryClampingNanos,
         this.lastCpuDirectAtrousNanos,
         this.lastCpuSpecTemporalNanos,
         this.lastCpuSpecAntiFireflyNanos,
         this.lastCpuSpecHistoryFixNanos,
         this.lastCpuSpecHistoryClampingNanos,
         this.lastCpuSpecAtrousNanos,
         this.lastCpuIndirectAccumNanos,
         this.lastCpuIndirectDenoiseNanos,
         this.lastCpuAccumulationNanos,
         this.lastCpuIndirectNanos
      };
   }

   private long[] getGpuPassNanos() {
      return new long[]{
         this.gpuTimerQuery.getTimeNanos(proposalSamplingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(reuseResolveRegionIndex),
         this.gpuTimerQuery.getTimeNanos(shadeSamplesRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directFeatureRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directTemporalRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directAntiFireflyRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directHistoryFixRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directHistoryClampingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directAtrousRegionIndex),
         this.gpuTimerQuery.getTimeNanos(specTemporalRegionIndex),
         this.gpuTimerQuery.getTimeNanos(specAntiFireflyRegionIndex),
         this.gpuTimerQuery.getTimeNanos(specHistoryFixRegionIndex),
         this.gpuTimerQuery.getTimeNanos(specHistoryClampingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(specAtrousRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectAccumRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectDenoiseRegionIndex),
         this.gpuTimerQuery.getTimeNanos(accumulationRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectRegionIndex)
      };
   }

   private int getWorstPassIndex(long[] passNanos) {
      int worstIndex = 0;
      for (int i = 1; i < passNanos.length; i++) {
         if (passNanos[i] > passNanos[worstIndex]) {
            worstIndex = i;
         }
      }
      return worstIndex;
   }

   private long sumNanos(long[] passNanos) {
      long total = 0L;
      for (long passNano : passNanos) {
         total += passNano;
      }
      return total;
   }

   private void advanceGpuProfileFrame() {
      this.gpuTimerQuery.nextFrame();
   }

   private String formatShare(long bucketNanos, long[] allPassNanos) {
      long total = this.sumNanos(allPassNanos);
      if (total <= 0L) {
         return "0.000";
      }
      return String.format(java.util.Locale.ROOT, "%.3f", (double) bucketNanos / (double) total);
   }

   private String formatBlendFactor(float blendFactor) {
      return String.format(java.util.Locale.ROOT, "%.3f", blendFactor);
   }

   private String describeStageGeometryUsage() {
      return "shadeSamples+historyFix+historyClamping+atrous+indirectDenoise";
   }

   private long toMicros(long nanos) {
      return nanos / 1_000L;
   }
}




