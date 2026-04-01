package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.config.lights.color.RgbColor;
import at.redi2go.photonic.client.config.lights.orientation.LightOrientation;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.position.LightNodePos;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import org.joml.Vector3f;
import org.junit.jupiter.api.Test;

import java.nio.IntBuffer;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Deque;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
   void createTracedLightsRetainsInactivePlaceholderForTemporaryDisappearances() throws Exception {
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
      assertEquals(2, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertFalse(tracedLights[0].active(), "Removed light should be retained as an inactive placeholder");
      assertEquals(lightB, tracedLights[1].position());
      assertTrue(tracedLights[1].active());

      short[] newLightIndices = (short[]) getField(registry, "newLightIndices");
      assertEquals(0, newLightIndices[0], "Previous light A index should map to its inactive placeholder");
      assertEquals(1, newLightIndices[1], "Unchanged light B index should remain stable");
   }

   @Test
   void createTracedLightsKeepsStableIndicesForUnchangedCappedSelection() throws Exception {
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
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightB, tracedLights[1].position());

      short[] newLightIndices = (short[]) getField(registry, "newLightIndices");
      assertEquals(0, newLightIndices[0]);
      assertEquals(1, newLightIndices[1]);
   }



   @Test
   void createTracedLightsRetainsPreviousMemberWhenNewcomerOnlySlightlyImprovesCameraScore() throws Exception {
      LightRegistry registry = new LightRegistry(2, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo info = createTestLightInfo(100.0F);
      Vector3f lightA = new Vector3f(0.5F, 0.5F, 0.5F);
      Vector3f lightB = new Vector3f(2.5F, 0.5F, 0.5F);
      Vector3f lightC = new Vector3f(2.0F, 0.5F, 0.5F);

      positions.put(lightA, new TracedLightPosition(1, info));
      positions.put(lightB, new TracedLightPosition(2, info));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.put(lightC, new TracedLightPosition(3, info));
      assertFalse(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      LightInstance[] tracedLights = (LightInstance[]) getField(registry, "tracedLights");
      assertEquals(2, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightB, tracedLights[1].position());
   }

   @Test
   void createTracedLightsReplacesPreviousMemberWhenNewcomerIsMeaningfullyBetter() throws Exception {
      LightRegistry registry = new LightRegistry(2, 4, 0.001F, 8, 64);
      @SuppressWarnings("unchecked")
      Map<Vector3f, TracedLightPosition> positions = (Map<Vector3f, TracedLightPosition>) getField(registry, "tracedLightPositions");
      BlockLightInfo info = createTestLightInfo(100.0F);
      Vector3f lightA = new Vector3f(0.5F, 0.5F, 0.5F);
      Vector3f lightB = new Vector3f(2.5F, 0.5F, 0.5F);
      Vector3f lightC = new Vector3f(1.0F, 0.5F, 0.5F);

      positions.put(lightA, new TracedLightPosition(1, info));
      positions.put(lightB, new TracedLightPosition(2, info));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      positions.put(lightC, new TracedLightPosition(3, info));
      assertTrue(invokeCreateTracedLights(registry, invokeToLightInstanceArray(registry)));

      LightInstance[] tracedLights = (LightInstance[]) getField(registry, "tracedLights");
      assertEquals(2, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightC, tracedLights[1].position());
   }

   @Test
   void createTracedLightsDropsVeryWeakUnselectedLightsBeforeCapping() throws Exception {
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
      assertEquals(2, tracedLights.length);
      assertEquals(lightA, tracedLights[0].position());
      assertEquals(lightB, tracedLights[1].position());
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
      assertTrue(churn.contains("added=1"), churn);
      assertTrue(churn.contains("removed=1"), churn);
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
   void buildSpatialGridSkipsInactivePlaceholderLights() throws Exception {
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
      assertTrue(lightGrid.values().stream().allMatch(indices -> indices.stream().allMatch(index -> index == 0)));
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

      Method method = LightRegistry.class.getDeclaredMethod("storeGlobalLightCdf");
      method.setAccessible(true);
      method.invoke(registry);

      float[] lightPowers = registry.getLightPowers();
      assertTrue(lightPowers[0] > 0.0F);
      assertEquals(0.0F, lightPowers[1], 1.0e-6F);

      MemoryOwner cdfMemory = (MemoryOwner) getField(registry, "globalLightCdfMemory");
      java.nio.FloatBuffer cdf = cdfMemory.getMemory().getBuffer().asFloatBuffer();
      assertTrue(cdf.get(0) > 0.0F);
      assertEquals(cdf.get(0), cdf.get(1), 1.0e-6F, "Inactive placeholders must not increase the global CDF");
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
      return createTestLightInfo(100.0F);
   }

   private static BlockLightInfo createTestLightInfo(float intensity) {
      return new BlockLightInfo(
         new LightPredicate() {
            @Override
            public Block block() {
               return null;
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

