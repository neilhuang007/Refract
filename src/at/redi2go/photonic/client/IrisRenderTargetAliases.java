package at.redi2go.photonic.client;

import com.google.common.collect.ImmutableSet;
import it.unimi.dsi.fastutil.ints.Int2IntMap;
import it.unimi.dsi.fastutil.ints.Int2IntOpenHashMap;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Supplier;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.blending.BufferBlendInformation;
import net.irisshaders.iris.shaderpack.loading.ProgramArrayId;
import net.irisshaders.iris.shaderpack.loading.ProgramId;
import net.irisshaders.iris.shaderpack.programs.ProgramSet;
import net.irisshaders.iris.shaderpack.programs.ProgramSource;
import net.irisshaders.iris.shaderpack.properties.PackDirectives;
import net.irisshaders.iris.shaderpack.properties.PackRenderTargetDirectives;
import net.irisshaders.iris.shaderpack.properties.ProgramDirectives;
import net.irisshaders.iris.targets.RenderTarget;
import net.irisshaders.iris.targets.RenderTargets;
import at.redi2go.photonic.client.mixin.PackRenderTargetDirectivesAccessor;

public final class IrisRenderTargetAliases {
   private static final int MAX_IRIS_TARGETS = 16;
   private static final ImmutableSet<Integer> EXTRA_SUPPORTED_TARGETS = ImmutableSet.of(18, 19, 20);
   private static final ImmutableSet<Integer> SUPPORTED_RENDER_TARGETS = ImmutableSet.<Integer>builder()
      .addAll(PackRenderTargetDirectives.BASELINE_SUPPORTED_RENDER_TARGETS)
      .addAll(EXTRA_SUPPORTED_TARGETS)
      .build();
   private static final Int2IntOpenHashMap LOGICAL_TO_PHYSICAL = new Int2IntOpenHashMap();

   static {
      LOGICAL_TO_PHYSICAL.defaultReturnValue(-1);
   }

   private IrisRenderTargetAliases() {
   }

   public static synchronized void configure(ProgramSet programSet) {
      LOGICAL_TO_PHYSICAL.clear();
      if (programSet == null) {
         return;
      }

      PackDirectives packDirectives = programSet.getPackDirectives();
      if (packDirectives == null) {
         return;
      }

      PackRenderTargetDirectives renderTargetDirectives = packDirectives.getRenderTargetDirectives();
      Map<Integer, PackRenderTargetDirectives.RenderTargetSettings> settings = (
         (PackRenderTargetDirectivesAccessor)renderTargetDirectives
      ).photonic$getRenderTargetSettings();
      if (settings.isEmpty()) {
         return;
      }

      Set<Integer> usedTargets = collectUsedTargets(programSet);
      List<Integer> overflowTargets = usedTargets.stream().filter(target -> target >= MAX_IRIS_TARGETS).sorted().toList();
      if (overflowTargets.isEmpty()) {
         return;
      }

      List<Integer> freePhysicalTargets = new ArrayList<>();
      for (int target = 0; target < MAX_IRIS_TARGETS; target++) {
         if (!usedTargets.contains(target)) {
            freePhysicalTargets.add(target);
         }
      }

      int aliasCount = Math.min(overflowTargets.size(), freePhysicalTargets.size());
      for (int i = 0; i < aliasCount; i++) {
         int logicalTarget = overflowTargets.get(i);
         int physicalTarget = freePhysicalTargets.get(i);
         LOGICAL_TO_PHYSICAL.put(logicalTarget, physicalTarget);
         PackRenderTargetDirectives.RenderTargetSettings logicalSettings = settings.get(logicalTarget);
         if (logicalSettings != null) {
            settings.put(physicalTarget, logicalSettings);
         }
         settings.remove(logicalTarget);
      }

      for (Integer target : new ArrayList<>(settings.keySet())) {
         if (target.intValue() >= MAX_IRIS_TARGETS) {
            settings.remove(target);
         }
      }

      if (LOGICAL_TO_PHYSICAL.isEmpty()) {
         Photonic.warn(
            "[Iris] Unsupported render targets {} were requested, but no free alias slots were available (used targets: {})",
            overflowTargets,
            usedTargets
         );
         return;
      }

      if (aliasCount < overflowTargets.size()) {
         Photonic.warn(
            "[Iris] Only aliased {} of {} unsupported render targets: {}",
            aliasCount,
            overflowTargets.size(),
            describeMappings()
         );
      } else {
         Photonic.info(
            "[Iris] Aliasing unsupported render targets {} using free targets {}",
            describeMappings(),
            freePhysicalTargets.subList(0, aliasCount)
         );
      }
   }

   public static ImmutableSet<Integer> supportedRenderTargets() {
      return SUPPORTED_RENDER_TARGETS;
   }

   public static synchronized int alias(int target) {
      int aliased = LOGICAL_TO_PHYSICAL.get(target);
      return aliased >= 0 ? aliased : target;
   }

   public static synchronized int[] alias(int[] drawBuffers) {
      if (drawBuffers == null || drawBuffers.length == 0 || LOGICAL_TO_PHYSICAL.isEmpty()) {
         return drawBuffers;
      }

      int[] aliased = drawBuffers.clone();
      boolean changed = false;
      for (int i = 0; i < aliased.length; i++) {
         int mappedTarget = alias(aliased[i]);
         if (mappedTarget != aliased[i]) {
            aliased[i] = mappedTarget;
            changed = true;
         }
      }

      return changed ? aliased : drawBuffers;
   }

   public static synchronized ImmutableSet<Integer> alias(ImmutableSet<Integer> targets) {
      if (targets == null || targets.isEmpty() || LOGICAL_TO_PHYSICAL.isEmpty()) {
         return targets;
      }

      ImmutableSet.Builder<Integer> aliased = ImmutableSet.builder();
      boolean changed = false;
      for (Integer target : targets) {
         int mappedTarget = alias(target.intValue());
         aliased.add(mappedTarget);
         if (mappedTarget != target.intValue()) {
            changed = true;
         }
      }

      return changed ? aliased.build() : targets;
   }

   public static synchronized Map<Integer, Boolean> alias(Map<Integer, Boolean> targets) {
      if (targets == null || targets.isEmpty() || LOGICAL_TO_PHYSICAL.isEmpty()) {
         return targets;
      }

      Map<Integer, Boolean> aliased = new LinkedHashMap<>();
      boolean changed = false;
      for (Map.Entry<Integer, Boolean> entry : targets.entrySet()) {
         int target = entry.getKey().intValue();
         int mappedTarget = alias(target);
         aliased.put(mappedTarget, entry.getValue());
         if (mappedTarget != target) {
            changed = true;
         }
      }

      return changed ? aliased : targets;
   }

   public static synchronized List<BufferBlendInformation> aliasBufferBlendOverrides(List<BufferBlendInformation> overrides) {
      if (overrides == null || overrides.isEmpty() || LOGICAL_TO_PHYSICAL.isEmpty()) {
         return overrides;
      }

      List<BufferBlendInformation> aliased = new ArrayList<>(overrides.size());
      boolean changed = false;
      for (BufferBlendInformation override : overrides) {
         int mappedTarget = alias(override.index());
         aliased.add(mappedTarget == override.index() ? override : new BufferBlendInformation(mappedTarget, override.blendMode()));
         if (mappedTarget != override.index()) {
            changed = true;
         }
      }

      return changed ? aliased : overrides;
   }

   public static synchronized void addSamplerAliases(
      SamplerHolder samplers,
      Supplier<ImmutableSet<Integer>> flipped,
      RenderTargets renderTargets
   ) {
      if (LOGICAL_TO_PHYSICAL.isEmpty()) {
         return;
      }

      for (Int2IntMap.Entry entry : LOGICAL_TO_PHYSICAL.int2IntEntrySet()) {
         int logicalTarget = entry.getIntKey();
         int physicalTarget = entry.getIntValue();
         samplers.addDynamicSampler(
            () -> {
               RenderTarget renderTarget = renderTargets.getOrCreate(physicalTarget);
               return flipped.get().contains(physicalTarget) ? renderTarget.getAltTexture() : renderTarget.getMainTexture();
            },
            "colortex" + logicalTarget
         );
      }
   }

   public static synchronized String describeMappings() {
      return LOGICAL_TO_PHYSICAL.int2IntEntrySet()
         .stream()
         .sorted(Comparator.comparingInt(Int2IntMap.Entry::getIntKey))
         .map(entry -> "colortex" + entry.getIntKey() + "->colortex" + entry.getIntValue())
         .reduce((left, right) -> left + ", " + right)
         .orElse("[]");
   }

   private static Set<Integer> collectUsedTargets(ProgramSet programSet) {
      LinkedHashSet<Integer> usedTargets = new LinkedHashSet<>();
      Arrays.stream(ProgramId.values()).map(programSet::get).flatMap(optional -> optional.stream()).forEach(source -> collectUsedTargets(source, usedTargets));
      Arrays.stream(ProgramArrayId.values())
         .map(programSet::getComposite)
         .flatMap(Arrays::stream)
         .forEach(source -> collectUsedTargets(source, usedTargets));
      return usedTargets;
   }

   private static void collectUsedTargets(ProgramSource source, Set<Integer> usedTargets) {
      if (source == null || !source.isValid()) {
         return;
      }

      ProgramDirectives directives = source.getDirectives();
      Arrays.stream(directives.getDrawBuffers()).forEach(usedTargets::add);
      usedTargets.addAll(directives.getExplicitFlips().keySet());
      usedTargets.addAll(directives.getMipmappedBuffers());
      directives.getBufferBlendOverrides().stream().map(BufferBlendInformation::index).forEach(usedTargets::add);
   }
}
