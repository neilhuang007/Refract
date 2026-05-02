package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.config.lights.LightList;
import at.redi2go.photonic.client.config.lights.color.RgbColor;
import at.redi2go.photonic.client.config.lights.orientation.LightOrientation;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.position.LightNodePos;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import org.joml.Vector3f;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.IntBuffer;
import java.util.Deque;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

@Disabled("Requires Minecraft/LWJGL runtime classpath")
class LightRegistryIncrementalInvalidationTest {
   @Test
   void lightNodePositionConversionIsConsistent() {
      PBlockPos offset = new PBlockPos(0, 0, 0);
      int nodeSize = 8;
      PBlockPos blockPos = new PBlockPos(24, 40, 56);
      LightNodePos lightPos = blockPos.toLightPos(nodeSize, offset);

      PBlockPos roundTrip = lightPos.toBlockPos(nodeSize, offset);
      assertTrue(roundTrip.x == 24 && roundTrip.y == 40 && roundTrip.z == 56,
         "Block position -> light node -> block position must round-trip correctly");
   }

   @Test
   void lightNodePositionConversionWithOffset() {
      PBlockPos offset = new PBlockPos(10, 20, 30);
      int nodeSize = 8;
      PBlockPos blockPos = new PBlockPos(26, 44, 62);
      LightNodePos lightPos = blockPos.toLightPos(nodeSize, offset);

      PBlockPos roundTrip = lightPos.toBlockPos(nodeSize, offset);
      assertTrue(roundTrip.x == 26 && roundTrip.y == 44 && roundTrip.z == 62,
         "Round-trip with non-zero offset must preserve block coordinates");
   }

   @Test
   void toLightPosNegativeCoordinatesWithoutOffset() {
      PBlockPos offset = new PBlockPos(0, 0, 0);
      int nodeSize = 8;

      LightNodePos neg1 = new PBlockPos(-1, -1, -1).toLightPos(nodeSize, offset);
      assertEquals(-1, neg1.x, "Block at -1 must map to light node -1 (floor division)");
      assertEquals(-1, neg1.y);
      assertEquals(-1, neg1.z);

      LightNodePos neg9 = new PBlockPos(-9, -9, -9).toLightPos(nodeSize, offset);
      assertEquals(-2, neg9.x, "Block at -9 must map to light node -2 (floor division)");
      assertEquals(-2, neg9.y);
      assertEquals(-2, neg9.z);

      LightNodePos neg8 = new PBlockPos(-8, -8, -8).toLightPos(nodeSize, offset);
      assertEquals(-1, neg8.x, "Block at -8 is the start of light node -1");
      assertEquals(-1, neg8.y);
      assertEquals(-1, neg8.z);
   }

   @Test
   void toLightPosNegativeCoordinatesWithNonZeroOffset() {
      PBlockPos offset = new PBlockPos(10, 20, 30);
      int nodeSize = 8;

      LightNodePos neg = new PBlockPos(9, 19, 29).toLightPos(nodeSize, offset);
      assertEquals(-1, neg.x, "Block 9 with offset 10 → relative -1 → light node -1");
      assertEquals(-1, neg.y);
      assertEquals(-1, neg.z);

      LightNodePos boundary = new PBlockPos(2, 12, 22).toLightPos(nodeSize, offset);
      assertEquals(-1, boundary.x, "Block 2 with offset 10 → relative -8 → light node -1");
      assertEquals(-1, boundary.y);
      assertEquals(-1, boundary.z);

      LightNodePos beyond = new PBlockPos(1, 11, 21).toLightPos(nodeSize, offset);
      assertEquals(-2, beyond.x, "Block 1 with offset 10 → relative -9 → light node -2");
      assertEquals(-2, beyond.y);
      assertEquals(-2, beyond.z);
   }

   @Test
   void toLightPosExactNodeBoundaries() {
      PBlockPos offset = new PBlockPos(0, 0, 0);
      int nodeSize = 8;

      assertEquals(0, new PBlockPos(0, 0, 0).toLightPos(nodeSize, offset).x);
      assertEquals(1, new PBlockPos(8, 8, 8).toLightPos(nodeSize, offset).x);
      assertEquals(2, new PBlockPos(16, 16, 16).toLightPos(nodeSize, offset).x);

      assertEquals(-1, new PBlockPos(-8, -8, -8).toLightPos(nodeSize, offset).x);
      assertEquals(-2, new PBlockPos(-16, -16, -16).toLightPos(nodeSize, offset).x);

      assertEquals(0, new PBlockPos(7, 7, 7).toLightPos(nodeSize, offset).x);
      assertEquals(-1, new PBlockPos(-1, -1, -1).toLightPos(nodeSize, offset).x);
      assertEquals(-1, new PBlockPos(-8, -8, -8).toLightPos(nodeSize, offset).x);
      assertEquals(-2, new PBlockPos(-9, -9, -9).toLightPos(nodeSize, offset).x);
   }

   @Test
   void toLightPosNegativeRoundTrip() {
      PBlockPos offset = new PBlockPos(5, 10, 15);
      int nodeSize = 8;

      PBlockPos original = new PBlockPos(0, 0, 0);
      LightNodePos lightPos = original.toLightPos(nodeSize, offset);

      assertEquals(-1, lightPos.x);
      assertEquals(-2, lightPos.y);
      assertEquals(-2, lightPos.z);

      PBlockPos roundTrip = lightPos.toBlockPos(nodeSize, offset);
      assertEquals(-3, roundTrip.x, "Round-trip x: node -1 → block = -1*8+5 = -3");
      assertEquals(-6, roundTrip.y, "Round-trip y: node -2 → block = -2*8+10 = -6");
      assertEquals(-1, roundTrip.z, "Round-trip z: node -2 → block = -2*8+15 = -1");
   }

   @Test
   void createTracedLightsKeepsStableIndicesWhenMapIterationOrderChanges() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo info = createTestLightInfo();
      Vector3f lightA = new Vector3f(8.5F, 3.5F, 9.5F);
      Vector3f lightB = new Vector3f(2.5F, 9.5F, 4.5F);
      Vector3f lightC = new Vector3f(2.5F, 1.5F, 7.5F);

      positions.put(lightA, new TracedLightPosition(3, info));
      positions.put(lightB, new TracedLightPosition(2, info));
      positions.put(lightC, new TracedLightPosition(1, info));

      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.clear();
      positions.put(lightB, new TracedLightPosition(2, info));
      positions.put(lightC, new TracedLightPosition(1, info));
      positions.put(lightA, new TracedLightPosition(3, info));

      assertFalse(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      short[] newLightIndices = (short[]) getField(registry, "newLightIndices");
      assertEquals(0, newLightIndices[0]);
      assertEquals(1, newLightIndices[1]);
      assertEquals(2, newLightIndices[2]);
   }

   @Test
   void createTracedLightsTreatsBlockIdChangesAtStablePositionsAsDirty() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo info = createTestLightInfo();
      Vector3f lightPos = new Vector3f(8.5F, 3.5F, 9.5F);

      positions.put(lightPos, new TracedLightPosition(3, info));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.clear();
      positions.put(lightPos, new TracedLightPosition(7, info));

      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)),
         "Changing the block ID at a stable light position must force a light-list refresh");
   }

   @Test
   void createTracedLightsCompactsRemovedLightsOutOfTheActiveList() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo info = createTestLightInfo();
      Vector3f lightA = new Vector3f(2.5F, 1.5F, 7.5F);
      Vector3f lightB = new Vector3f(8.5F, 3.5F, 9.5F);

      positions.put(lightA, new TracedLightPosition(1, info));
      positions.put(lightB, new TracedLightPosition(2, info));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.clear();
      positions.put(lightB, new TracedLightPosition(2, info));

      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      LightInstance[] tracedLights = (LightInstance[]) getField(registry, "tracedLights");
      assertEquals(1, tracedLights.length);
      assertEquals(lightB, tracedLights[0].position());
      assertTrue(tracedLights[0].active());

      short[] newLightIndices = (short[]) getField(registry, "newLightIndices");
      assertEquals(-1, newLightIndices[0], "Removed light should no longer map into the active list");
      assertEquals(0, newLightIndices[1], "Remaining light should be compacted to dense slot 0");
   }

   @Test
   void createTracedLightsKeepsStableIndicesForUnchangedUncappedTracking() throws Exception {
      LightRegistry registry = new LightRegistry(2, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo bright = createTestLightInfo(100.0F);
      BlockLightInfo dim = createTestLightInfo(10.0F);
      Vector3f lightA = new Vector3f(2.5F, 1.5F, 7.5F);
      Vector3f lightB = new Vector3f(2.5F, 9.5F, 4.5F);
      Vector3f lightC = new Vector3f(8.5F, 3.5F, 9.5F);

      positions.put(lightC, new TracedLightPosition(3, dim));
      positions.put(lightB, new TracedLightPosition(2, bright));
      positions.put(lightA, new TracedLightPosition(1, bright));

      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.clear();
      positions.put(lightA, new TracedLightPosition(1, bright));
      positions.put(lightC, new TracedLightPosition(3, dim));
      positions.put(lightB, new TracedLightPosition(2, bright));

      assertFalse(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      LightInstance[] tracedLights = (LightInstance[]) getField(registry, "tracedLights");
      assertEquals(3, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightB, tracedLights[1].position());
      assertEquals(lightC, tracedLights[2].position());

      short[] newLightIndices = (short[]) getField(registry, "newLightIndices");
      assertEquals(0, newLightIndices[0]);
      assertEquals(1, newLightIndices[1]);
      assertEquals(2, newLightIndices[2]);
   }

   @Test
   void createTracedLightsAdmitsNewcomerWhenCapacityWasPreviouslySaturated() throws Exception {
      LightRegistry registry = new LightRegistry(2, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo incumbent = createTestLightInfo(100.0F);
      BlockLightInfo slightUpgrade = createTestLightInfo(110.0F);
      Vector3f lightA = new Vector3f(0.5F, 0.5F, 0.5F);
      Vector3f lightB = new Vector3f(2.5F, 0.5F, 0.5F);
      Vector3f lightC = new Vector3f(1.0F, 0.5F, 0.5F);

      positions.put(lightA, new TracedLightPosition(1, incumbent));
      positions.put(lightB, new TracedLightPosition(2, incumbent));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.put(lightC, new TracedLightPosition(3, slightUpgrade));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      LightInstance[] tracedLights = (LightInstance[]) getField(registry, "tracedLights");
      assertEquals(3, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightB, tracedLights[1].position());
      assertEquals(lightC, tracedLights[2].position());
   }

   @Test
   void createTracedLightsPreservesAllTrackedLightsWhenAddingStrongerNewcomer() throws Exception {
      LightRegistry registry = new LightRegistry(2, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo incumbent = createTestLightInfo(100.0F);
      BlockLightInfo stronger = createTestLightInfo(140.0F);
      Vector3f lightA = new Vector3f(0.5F, 0.5F, 0.5F);
      Vector3f lightB = new Vector3f(2.5F, 0.5F, 0.5F);
      Vector3f lightC = new Vector3f(1.0F, 0.5F, 0.5F);

      positions.put(lightA, new TracedLightPosition(1, incumbent));
      positions.put(lightB, new TracedLightPosition(2, incumbent));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.put(lightC, new TracedLightPosition(3, stronger));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      LightInstance[] tracedLights = (LightInstance[]) getField(registry, "tracedLights");
      assertEquals(3, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightB, tracedLights[1].position());
      assertEquals(lightC, tracedLights[2].position());
   }

   @Test
   void createTracedLightsTracksWeakLightsInsteadOfDroppingThemBeforeCapping() throws Exception {
      LightRegistry registry = new LightRegistry(2, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo bright = createTestLightInfo(100.0F);
      BlockLightInfo weak = createTestLightInfo(0.01F);
      Vector3f lightA = new Vector3f(2.5F, 1.5F, 7.5F);
      Vector3f lightB = new Vector3f(2.5F, 9.5F, 4.5F);
      Vector3f lightC = new Vector3f(40.5F, 40.5F, 40.5F);

      positions.put(lightA, new TracedLightPosition(1, bright));
      positions.put(lightB, new TracedLightPosition(2, bright));
      positions.put(lightC, new TracedLightPosition(3, weak));

      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      LightInstance[] tracedLights = (LightInstance[]) getField(registry, "tracedLights");
      assertEquals(3, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightB, tracedLights[1].position());
      assertEquals(lightC, tracedLights[2].position());
   }


   @Test
   void queueIdentityLightMappingsIfNeededWritesIdentityOnce() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      MemoryOwner lightMappingMemory = (MemoryOwner) getField(registry, "lightMappingMemory");
      MemoryOwner lightReverseMappingMemory = (MemoryOwner) getField(registry, "lightReverseMappingMemory");
      for (int i = 0; i < 8; i++) {
         lightMappingMemory.getMemory().getBuffer().asIntBuffer().put(i, -1);
         lightReverseMappingMemory.getMemory().getBuffer().asIntBuffer().put(i, -1);
      }

      setField(registry, "identityLightMappingPending", true);

      assertTrue(registry.queueIdentityLightMappingsIfNeeded());
      assertFalse(registry.queueIdentityLightMappingsIfNeeded());

      int[] mappings = new int[8];
      lightMappingMemory.getMemory().getBuffer().asIntBuffer().get(0, mappings);
      assertArrayEquals(new int[]{0, 1, 2, 3, 4, 5, 6, 7}, mappings);
      int[] reverseMappings = new int[8];
      lightReverseMappingMemory.getMemory().getBuffer().asIntBuffer().get(0, reverseMappings);
      assertArrayEquals(new int[]{0, 1, 2, 3, 4, 5, 6, 7}, reverseMappings);

      @SuppressWarnings("unchecked")
      Deque<MemoryOwner> uploadQueue = (Deque<MemoryOwner>) getField(registry.getLightMappingMemoryManager(), "uploadQueue");
      assertEquals(1, uploadQueue.size());
      @SuppressWarnings("unchecked")
      Deque<MemoryOwner> reverseUploadQueue = (Deque<MemoryOwner>) getField(getField(registry, "lightReverseMappingMemoryManager"), "uploadQueue");
      assertEquals(1, reverseUploadQueue.size());
   }

   @Test
   void queueIdentityLightMappingsIfNeededRefreshesPreviousLights() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      MemoryOwner lightsMemory = (MemoryOwner) getField(registry, "lightsMemory");
      MemoryOwner previousLightsMemory = (MemoryOwner) getField(registry, "previousLightsMemory");
      IntBuffer lightsBuffer = lightsMemory.getMemory().getBuffer().asIntBuffer();
      IntBuffer previousBuffer = previousLightsMemory.getMemory().getBuffer().asIntBuffer();

      lightsBuffer.put(0, 0x12345678);
      lightsBuffer.put(1, 0x0BADF00D);
      previousBuffer.put(0, -1);
      previousBuffer.put(1, -1);

      setField(registry, "identityLightMappingPending", true);

      assertTrue(registry.queueIdentityLightMappingsIfNeeded());
      assertEquals(0x12345678, previousBuffer.get(0));
      assertEquals(0x0BADF00D, previousBuffer.get(1));

      @SuppressWarnings("unchecked")
      Deque<MemoryOwner> previousUploadQueue = (Deque<MemoryOwner>) getField(getField(registry, "previousLightsMemoryManager"), "uploadQueue");
      assertEquals(1, previousUploadQueue.size());
   }

   @Test
   void syncTracedLightTreatsEquivalentLightDescriptorInstancesAsNoop() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo infoA = createTestLightInfo(100.0F);
      BlockLightInfo infoB = createTestLightInfo(100.0F);
      Vector3f lightPos = new Vector3f(8.5F, 3.5F, 9.5F);
      positions.put(lightPos, new TracedLightPosition(-1, infoA));
      setField(registry, "tracedLightSetDirty", false);

      Method method = LightRegistry.class.getDeclaredMethod("syncTracedLight", net.minecraft.util.math.BlockPos.class, net.minecraft.block.BlockState.class, BlockLightInfo.class);
      method.setAccessible(true);
      method.invoke(registry, new net.minecraft.util.math.BlockPos(8, 3, 9), null, infoB);

      assertFalse((boolean) getField(registry, "tracedLightSetDirty"), "Equivalent light descriptors should not dirty the traced light set");
      TracedLightPosition updated = positions.get(lightPos);
      assertEquals(-1, updated.blockId());
      assertSame(infoA, updated.lightInfo(), "Equivalent updates should preserve the existing tracked light instance");
   }

   @Test
   void clearChunkLightsRemovesOnlyLightsInsideTheChunk() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo info = createTestLightInfo();

      positions.put(new Vector3f(1.5F, 1.5F, 1.5F), new TracedLightPosition(1, info));
      positions.put(new Vector3f(15.5F, 15.5F, 15.5F), new TracedLightPosition(2, info));
      positions.put(new Vector3f(16.5F, 1.5F, 1.5F), new TracedLightPosition(3, info));

      registry.clearChunkLights(new at.redi2go.photonic.client.rendering.world.position.PChunkPos(0, 0, 0));

      assertEquals(1, positions.size());
      assertTrue(positions.containsKey(new Vector3f(16.5F, 1.5F, 1.5F)));
      assertTrue((boolean) getField(registry, "tracedLightSetDirty"));
   }



   @Test
   void describeRecentChurnOmitsDeferredRemovalMetric() {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      assertFalse(registry.describeRecentChurn().contains("deferredRemove="), registry.describeRecentChurn());
   }

   @Test
   void clearChunkLightsDropsLoadedMarkerAndPreservesOutsideLights() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      @SuppressWarnings("unchecked")
      java.util.Set<Long> loadedChunks = (java.util.Set<Long>) getField(registry, "loadedLightChunks");
      BlockLightInfo info = createTestLightInfo();

      positions.put(new Vector3f(1.5F, 1.5F, 1.5F), new TracedLightPosition(1, info));
      positions.put(new Vector3f(16.5F, 1.5F, 1.5F), new TracedLightPosition(2, info));
      loadedChunks.add(invokeChunkKey(0, 0, 0));
      loadedChunks.add(invokeChunkKey(1, 0, 0));

      registry.clearChunkLights(new at.redi2go.photonic.client.rendering.world.position.PChunkPos(0, 0, 0));

      assertFalse(loadedChunks.contains(invokeChunkKey(0, 0, 0)));
      assertTrue(loadedChunks.contains(invokeChunkKey(1, 0, 0)));
      assertEquals(1, positions.size());
      assertTrue(positions.containsKey(new Vector3f(16.5F, 1.5F, 1.5F)));
   }

   @Test
   void toLightInstanceArraySortsLightsDeterministicallyByPosition() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo info = createTestLightInfo();

      positions.put(new Vector3f(8.5F, 3.5F, 9.5F), new TracedLightPosition(3, info));
      positions.put(new Vector3f(2.5F, 9.5F, 4.5F), new TracedLightPosition(2, info));
      positions.put(new Vector3f(2.5F, 1.5F, 7.5F), new TracedLightPosition(1, info));

      LightInstance[] lights = invokeToLightInstanceArray(registry);

      assertEquals(new Vector3f(2.5F, 1.5F, 7.5F), lights[0].position());
      assertEquals(new Vector3f(2.5F, 9.5F, 4.5F), lights[1].position());
      assertEquals(new Vector3f(8.5F, 3.5F, 9.5F), lights[2].position());
   }


   @Test
   void describeRecentChurnReportsLightChanges() throws Exception {
      LightRegistry registry = new LightRegistry(2, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo bright = createTestLightInfo(100.0F);
      BlockLightInfo dim = createTestLightInfo(10.0F);

      positions.put(new Vector3f(2.5F, 1.5F, 7.5F), new TracedLightPosition(1, bright));
      positions.put(new Vector3f(2.5F, 9.5F, 4.5F), new TracedLightPosition(2, bright));
      positions.put(new Vector3f(8.5F, 3.5F, 9.5F), new TracedLightPosition(3, dim));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.clear();
      positions.put(new Vector3f(2.5F, 1.5F, 7.5F), new TracedLightPosition(1, dim));
      positions.put(new Vector3f(2.5F, 9.5F, 4.5F), new TracedLightPosition(2, bright));
      positions.put(new Vector3f(8.5F, 3.5F, 9.5F), new TracedLightPosition(3, bright));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      String churn = registry.describeRecentChurn();
      assertTrue(churn.contains("added=0"), churn);
      assertTrue(churn.contains("removed=0"), churn);
      assertTrue(churn.contains("lightInfo=0"), churn);
      assertTrue(churn.contains("radiometry=2"), churn);
   }

   @Test
   void regirGridBuildCapturesActiveCellsAndLightSlots() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      BlockLightInfo info = createTestLightInfo(100.0F);
      LightInstance[] lights = new LightInstance[] {
         new LightInstance(1, new Vector3f(1.5F, 1.5F, 1.5F), info),
         new LightInstance(1, new Vector3f(36.5F, 1.5F, 1.5F), info),
         new LightInstance(1, new Vector3f(68.5F, 33.5F, 1.5F), info),
         new LightInstance(1, new Vector3f(100.5F, 65.5F, 1.5F), info)
      };
      setField(registry, "tracedLights", lights);
      setField(registry, "offset", new PBlockPos(0, 0, 0));

      invokeBuildSpatialGrid(registry, lights);
      invokeBuildRegirGrid(registry);

      Vector3f gridOrigin = registry.getRegirGridOrigin();
      assertEquals(-64.0F, gridOrigin.x);
      assertEquals(-64.0F, gridOrigin.y);
      assertEquals(-64.0F, gridOrigin.z);
      assertEquals(4, registry.getRegirGridResolution());
      assertTrue(registry.getRegirActiveCellCount() >= 3);
      assertTrue(registry.getRegirActiveLightSlotCount() >= lights.length);

      MemoryOwner cellCountMemory = (MemoryOwner) getField(registry, "regirCellCountMemory");
      IntBuffer cellCountBuffer = cellCountMemory.getMemory().getBuffer().asIntBuffer();
      assertTrue(cellCountBuffer.get(0) > 0, "First ReGIR cell should contain at least one candidate light");

      MemoryOwner lightIndexMemory = (MemoryOwner) getField(registry, "regirLightIndexMemory");
      IntBuffer lightIndexBuffer = lightIndexMemory.getMemory().getBuffer().asIntBuffer();
      assertTrue(lightIndexBuffer.get(0) >= 0, "First populated ReGIR slot should point at a traced light index");
   }

   @Test
   void regirSamplingAndLookupJitterMatchRtxdiRuntimeScale() {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      assertEquals(2.0F, registry.getRegirSamplingJitter(), 1.0e-6F);
      assertEquals(2.0F, registry.getRegirLookupJitter(), 1.0e-6F);
   }

   @Test
   void buildSpatialGridKeepsInactivePlaceholderTopology() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      BlockLightInfo info = createTestLightInfo(100.0F);
      LightInstance[] lights = new LightInstance[] {
         new LightInstance(1, new Vector3f(1.5F, 1.5F, 1.5F), info, true),
         new LightInstance(2, new Vector3f(36.5F, 1.5F, 1.5F), info, false)
      };

      invokeBuildSpatialGrid(registry, lights);

      @SuppressWarnings("unchecked")
      Map<Long, java.util.List<Integer>> lightGrid = (Map<Long, java.util.List<Integer>>) getField(registry, "lightGrid");
      assertFalse(lightGrid.isEmpty(), "Active lights should still populate the grid");
      assertTrue(lightGrid.values().stream().anyMatch(indices -> indices.contains(1)),
         "Inactive placeholders should remain in spatial topology so toggling on does not require a grid rebuild");
   }

   @Test
   void semanticLayoutHashIgnoresRadiometryChanges() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      Vector3f lightPos = new Vector3f(1.5F, 1.5F, 1.5F);
      setField(registry, "tracedLights", new LightInstance[] {
         new LightInstance(1, lightPos, createTestLightInfo(100.0F), true)
      });
      long initialHash = registry.getSemanticLayoutHash();

      setField(registry, "tracedLights", new LightInstance[] {
         new LightInstance(1, lightPos, createTestLightInfo(25.0F), true)
      });

      assertEquals(initialHash, registry.getSemanticLayoutHash(),
         "Intensity changes should update light buffers/PDFs without changing the sampling layout identity");
   }

   @Test
   void buildSpatialGridExpandsCoverageToMatchRegirBuildVolume() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      BlockLightInfo info = createTestLightInfo(100.0F);
      LightInstance[] lights = new LightInstance[] {
         new LightInstance(1, new Vector3f(0.5F, 0.5F, 0.5F), info, true)
      };

      invokeBuildSpatialGrid(registry, lights);

      @SuppressWarnings("unchecked")
      Map<Long, java.util.List<Integer>> lightGrid = (Map<Long, java.util.List<Integer>>) getField(registry, "lightGrid");
      long nearbyButOutOfRawRadiusCell = invokeGridKey(2, 0, 0);
      java.util.List<Integer> candidates = lightGrid.get(nearbyButOutOfRawRadiusCell);
      assertTrue(candidates != null, "ReGIR spatial coverage should include cells reached by the jitter-expanded build volume");
      assertTrue(candidates.contains(0), "Nearby cells in the ReGIR build volume should see the light as a candidate");
   }

   @Test
   void storeGlobalLightCdfRespondsToCameraMovementWithoutLightSetChanges() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      BlockLightInfo info = createTestLightInfo(100.0F);
      LightInstance[] lights = new LightInstance[] {
         new LightInstance(1, new Vector3f(1.5F, 1.5F, 1.5F), info, true),
         new LightInstance(2, new Vector3f(96.5F, 1.5F, 1.5F), info, true)
      };
      setField(registry, "tracedLights", lights);

      Method shouldRefresh = LightRegistry.class.getDeclaredMethod("shouldRefreshGlobalLightCdf", Vector3f.class, boolean.class);
      shouldRefresh.setAccessible(true);
      Method storeCdf = LightRegistry.class.getDeclaredMethod("storeGlobalLightCdf", Vector3f.class);
      storeCdf.setAccessible(true);
      Method markCamera = LightRegistry.class.getDeclaredMethod("markGlobalLightCdfCamera", Vector3f.class);
      markCamera.setAccessible(true);

      Vector3f initialCamera = new Vector3f(0.0F, 0.0F, 0.0F);
      assertTrue((boolean) shouldRefresh.invoke(registry, initialCamera, false));
      storeCdf.invoke(registry, initialCamera);
      markCamera.invoke(registry, initialCamera);

      float[] initialWeights = registry.getLightPowers().clone();
      assertTrue(initialWeights[0] > initialWeights[1], "Initial camera should prefer the nearby light");

      Vector3f movedCamera = new Vector3f(96.5F, 1.5F, 1.5F);
      assertTrue((boolean) shouldRefresh.invoke(registry, movedCamera, false), "Large camera moves should trigger a CDF refresh");
      storeCdf.invoke(registry, movedCamera);
      markCamera.invoke(registry, movedCamera);

      float[] movedWeights = registry.getLightPowers();
      assertTrue(movedWeights[1] > movedWeights[0], "Moved camera should now prefer the new nearby light");
   }

   @Test
   void storeGlobalLightCdfPrioritizesNearbyVisibleLights() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      BlockLightInfo info = createTestLightInfo(100.0F);
      LightInstance[] lights = new LightInstance[] {
         new LightInstance(1, new Vector3f(1.5F, 1.5F, 1.5F), info, true),
         new LightInstance(2, new Vector3f(96.5F, 1.5F, 1.5F), info, true)
      };
      setField(registry, "tracedLights", lights);
      setField(registry, "frozenLightSelectionCamera", new Vector3f(0.0F, 0.0F, 0.0F));
      setField(registry, "frozenLightSelectionCameraInitialized", true);
      System.setProperty("photonics.freezeLightSelectionCamera", "true");
      try {
         Method method = LightRegistry.class.getDeclaredMethod("storeGlobalLightCdf", Vector3f.class);
         method.setAccessible(true);
         method.invoke(registry, new Vector3f(0.0F, 0.0F, 0.0F));
      } finally {
         System.clearProperty("photonics.freezeLightSelectionCamera");
      }

      float[] lightPowers = registry.getLightPowers();
      assertTrue(lightPowers[0] > lightPowers[1], "Nearby light should receive more global sampling weight than a far light");

      MemoryOwner cdfMemory = (MemoryOwner) getField(registry, "globalLightCdfMemory");
      java.nio.FloatBuffer cdf = cdfMemory.getMemory().getBuffer().asFloatBuffer();
      assertTrue(cdf.get(0) > 0.0F);
      assertTrue(cdf.get(1) > cdf.get(0), "Second CDF entry should accumulate both nearby and far light weights");
   }

   @Test
   void storeGlobalLightCdfGivesInactivePlaceholderZeroWeight() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      BlockLightInfo info = createTestLightInfo(100.0F);
      LightInstance[] lights = new LightInstance[] {
         new LightInstance(1, new Vector3f(1.5F, 1.5F, 1.5F), info, true),
         new LightInstance(2, new Vector3f(36.5F, 1.5F, 1.5F), info, false)
      };
      setField(registry, "tracedLights", lights);

      Method method = LightRegistry.class.getDeclaredMethod("storeGlobalLightCdf", Vector3f.class);
      method.setAccessible(true);
      method.invoke(registry, new Vector3f(0.0F, 0.0F, 0.0F));

      float[] lightPowers = registry.getLightPowers();
      assertTrue(lightPowers[0] > 0.0F);
      assertEquals(0.0F, lightPowers[1], 1.0e-6F);

      MemoryOwner cdfMemory = (MemoryOwner) getField(registry, "globalLightCdfMemory");
      java.nio.FloatBuffer cdf = cdfMemory.getMemory().getBuffer().asFloatBuffer();
      assertTrue(cdf.get(0) > 0.0F);
      assertEquals(cdf.get(0), cdf.get(1), 1.0e-6F, "Inactive placeholders must not increase the global CDF");
   }

   @Test
   void shouldRefreshGlobalLightCdfEveryFrameWhenGpuRegirBuildEnabled() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 128);
      setField(registry, "gpuRegirBuildEnabled", true);
      setField(registry, "tracedLights", new LightInstance[] {
         new LightInstance(1, new Vector3f(1.5F, 1.5F, 1.5F), createTestLightInfo(100.0F), true)
      });

      Method shouldRefresh = LightRegistry.class.getDeclaredMethod("shouldRefreshGlobalLightCdf", Vector3f.class, boolean.class);
      shouldRefresh.setAccessible(true);
      Method markCamera = LightRegistry.class.getDeclaredMethod("markGlobalLightCdfCamera", Vector3f.class);
      markCamera.setAccessible(true);

      Vector3f camera = new Vector3f(0.0F, 0.0F, 0.0F);
      markCamera.invoke(registry, camera);

      assertTrue((boolean) shouldRefresh.invoke(registry, camera, false),
         "GPU ReGIR path should refresh the global CDF every frame so presample tiles follow camera-priority changes immediately");
   }

   @Test
   void hasPossibleLightIsConservativeForConfiguredBlockTypes() throws Exception {
      LightRegistry registry = new LightRegistry(8, 4, 0.001F, 8, 64);
      LightList lightList = new LightList();
      Block configuredBlock = constructorFreeBlock();
      Block otherBlock = constructorFreeBlock();
      BlockLightInfo info = createTestLightInfo(configuredBlock);

      lightList.add(info);
      setField(registry, "lightList", lightList);

      assertTrue(registry.hasPossibleLight(configuredBlock),
         "Configured block types must be treated as possible lights even when predicates need world context");
      assertFalse(registry.hasPossibleLight(otherBlock),
         "Unconfigured block types should still avoid neighbor light refresh work");
   }

   private static Block constructorFreeBlock() throws Exception {
      sun.misc.Unsafe unsafe = getUnsafe();
      return (Block) unsafe.allocateInstance(Block.class);
   }

   private static sun.misc.Unsafe getUnsafe() throws Exception {
      Field field = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
      field.setAccessible(true);
      return (sun.misc.Unsafe) field.get(null);
   }

   private static LightInstance[] invokeToLightInstanceArray(LightRegistry registry) throws Exception {
      Method method = LightRegistry.class.getDeclaredMethod("toLightInstanceArray");
      method.setAccessible(true);
      return (LightInstance[]) method.invoke(registry);
   }

   private static void invokeBuildSpatialGrid(LightRegistry registry, LightInstance[] lights) throws Exception {
      Method method = LightRegistry.class.getDeclaredMethod("buildSpatialGrid", LightInstance[].class);
      method.setAccessible(true);
      method.invoke(registry, (Object) lights);
   }

   private static void invokeBuildRegirGrid(LightRegistry registry) throws Exception {
      Method method = LightRegistry.class.getDeclaredMethod("buildRegirGrid");
      method.setAccessible(true);
      method.invoke(registry);
   }

   private static long invokeGridKey(int x, int y, int z) throws Exception {
      Method method = LightRegistry.class.getDeclaredMethod("gridKey", int.class, int.class, int.class);
      method.setAccessible(true);
      return (long) method.invoke(null, x, y, z);
   }

   private static long invokeChunkKey(int x, int y, int z) throws Exception {
      Method method = LightRegistry.class.getDeclaredMethod("chunkKey", int.class, int.class, int.class);
      method.setAccessible(true);
      return (long) method.invoke(null, x, y, z);
   }

   private static boolean invokeCreateTracedLights(LightRegistry registry, LightInstance[] lights) throws Exception {
      Method method = LightRegistry.class.getDeclaredMethod("createTracedLights", LightInstance[].class);
      method.setAccessible(true);
      return (boolean) method.invoke(registry, (Object) lights);
   }

   private static Object getField(Object target, String fieldName) throws Exception {
      Field field = target.getClass().getDeclaredField(fieldName);
      field.setAccessible(true);
      return field.get(target);
   }

   private static void setField(Object target, String fieldName, Object value) throws Exception {
      Field field = target.getClass().getDeclaredField(fieldName);
      field.setAccessible(true);
      field.set(target, value);
   }

   private static BlockLightInfo createTestLightInfo() {
      return createTestLightInfo(null, 100.0F);
   }

   private static BlockLightInfo createTestLightInfo(Block block) {
      return createTestLightInfo(block, 100.0F);
   }

   private static BlockLightInfo createTestLightInfo(float intensity) {
      return createTestLightInfo(null, intensity);
   }

   private static BlockLightInfo createTestLightInfo(Block block, float intensity) {
      return new BlockLightInfo(
         new LightPredicate() {
            @Override
            public Block block() {
               return block;
            }

            @Override
            public int priority() {
               return LightPredicate.NORMAL_PRIORITY;
            }

            @Override
            public boolean test(CachedBlockPosition block) {
               return false;
            }
         },
         new RgbColor(255, 255, 255),
         intensity,
         16.0F,
         1.0F,
         true,
         true,
         LightOrientation.OMNI
      );
   }
}

