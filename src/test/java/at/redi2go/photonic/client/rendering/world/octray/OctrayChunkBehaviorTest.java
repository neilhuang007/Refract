package at.redi2go.photonic.client.rendering.world.octray;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.PBlock;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Validates hybrid octray page behavior: occupancy mip generation,
 * CPU/shader addressing agreement, and empty-mip-cell air AABB semantics.
 */
class OctrayChunkBehaviorTest {

    // ---------- Occupancy mip generation ----------

    @Test
    void fullyEmptyChunkHasAllZeroMips() {
        GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
        OctrayChunk chunk = new OctrayChunk();
        chunk.allocate(chunkMemory);
        chunk.finishUpdate(chunkMemory);

        IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
        for (int i = OctrayChunk.LEAF_INT_COUNT; i < OctrayChunk.CHUNK_PAGE_INT_COUNT; i++) {
            assertEquals(0, ints.get(i), "Mip entry at index " + i + " must be 0 for a fully empty chunk");
        }

        chunk.free(chunkMemory);
        chunkMemory.free();
    }

    @Test
    void singleOccupiedBlockSetsAllAncestorMipCells() {
        GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
        GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_blk", PBlock.BYTE_SIZE * 4, true);
        OctrayChunk chunk = new OctrayChunk();
        PBlock block = new PBlock(1, () -> new Schematic(16, 16, 16));
        blockMemory.allocate(PBlock.BYTE_SIZE);
        block.allocate(blockMemory);
        chunk.allocate(chunkMemory);

        chunk.set(3, 5, 7, block, 0);
        chunk.finishUpdate(chunkMemory);

        IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();

        // All 4 LOD levels must be marked occupied for the cell containing (3,5,7)
        for (int lod = 1; lod <= 4; lod++) {
            int addr = OctrayChunk.getSubChunkAddr(3, 5, 7, lod);
            assertTrue(ints.get(addr) > 0,
                "LOD " + lod + " mip cell containing (3,5,7) must be marked occupied");
        }

        chunk.free(chunkMemory);
        block.free(blockMemory);
        chunkMemory.free();
        blockMemory.free();
    }

    @Test
    void occupiedBlockDoesNotSetUnrelatedMipCells() {
        GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
        GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_blk", PBlock.BYTE_SIZE * 4, true);
        OctrayChunk chunk = new OctrayChunk();
        PBlock block = new PBlock(2, () -> new Schematic(16, 16, 16));
        blockMemory.allocate(PBlock.BYTE_SIZE);
        block.allocate(blockMemory);
        chunk.allocate(chunkMemory);

        // Place block at (0,0,0) — in the very first 2x2x2 cell at LOD1
        chunk.set(0, 0, 0, block, 0);
        chunk.finishUpdate(chunkMemory);

        IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();

        // LOD1 cell containing (0,0,0) must be occupied
        assertTrue(ints.get(OctrayChunk.getSubChunkAddr(0, 0, 0, 1)) > 0);

        // LOD1 cell containing (8,8,8) must NOT be occupied (different quadrant)
        assertEquals(0, ints.get(OctrayChunk.getSubChunkAddr(8, 8, 8, 1)),
            "LOD1 cell for (8,8,8) must be empty when only (0,0,0) is occupied");

        chunk.free(chunkMemory);
        block.free(blockMemory);
        chunkMemory.free();
        blockMemory.free();
    }

    @Test
    void twoBlocksInDifferentLod1CellsSetCorrectMips() {
        GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
        GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_blk", PBlock.BYTE_SIZE * 4, true);
        OctrayChunk chunk = new OctrayChunk();
        PBlock blockA = new PBlock(3, () -> new Schematic(16, 16, 16));
        PBlock blockB = new PBlock(4, () -> new Schematic(16, 16, 16));
        blockMemory.allocate(PBlock.BYTE_SIZE);
        blockA.allocate(blockMemory);
        blockMemory.allocate(PBlock.BYTE_SIZE);
        blockB.allocate(blockMemory);
        chunk.allocate(chunkMemory);

        chunk.set(0, 0, 0, blockA, 0);    // corner cell
        chunk.set(15, 15, 15, blockB, 0);  // opposite corner
        chunk.finishUpdate(chunkMemory);

        IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();

        // LOD1: both cells must be marked occupied
        assertTrue(ints.get(OctrayChunk.getSubChunkAddr(0, 0, 0, 1)) > 0);
        assertTrue(ints.get(OctrayChunk.getSubChunkAddr(15, 15, 15, 1)) > 0);

        // LOD4 (single root cell): must be occupied since at least one block exists
        assertTrue(ints.get(OctrayChunk.getSubChunkAddr(0, 0, 0, 4)) > 0);

        // An intermediate empty cell at LOD1 should be 0
        assertEquals(0, ints.get(OctrayChunk.getSubChunkAddr(8, 0, 0, 1)),
            "LOD1 cell at (8,0,0) must be empty");

        chunk.free(chunkMemory);
        blockA.free(blockMemory);
        blockB.free(blockMemory);
        chunkMemory.free();
        blockMemory.free();
    }

    // ---------- Shader/CPU mip offset agreement ----------

    @Test
    void cpuSubChunkAddrMatchesShaderFormula() {
        // The shader computes:
        //   voxel_pos = (block_position & 15) >> lod
        //   edge = 16 >> lod
        //   addr = base(lod) + voxel_pos.x * edge + voxel_pos.y * edge * edge + voxel_pos.z
        //
        // Verify the Java getSubChunkAddr produces the same result for representative positions.
        int[][] positions = {
            {0, 0, 0}, {1, 2, 3}, {7, 7, 7}, {8, 8, 8}, {15, 15, 15},
            {4, 0, 12}, {0, 15, 0}, {11, 3, 9}
        };

        for (int lod = 1; lod <= 4; lod++) {
            int[] lodBases = {0, 4096, 4608, 4672, 4680};
            int base = lodBases[lod];
            int edge = 16 >> lod;

            for (int[] pos : positions) {
                int vx = (pos[0] & 15) >> lod;
                int vy = (pos[1] & 15) >> lod;
                int vz = (pos[2] & 15) >> lod;
                int shaderAddr = base + vx * edge + vy * edge * edge + vz;

                assertEquals(shaderAddr, OctrayChunk.getSubChunkAddr(pos[0], pos[1], pos[2], lod),
                    String.format("CPU addr must match shader for pos=(%d,%d,%d) lod=%d", pos[0], pos[1], pos[2], lod));
            }
        }
    }

    @Test
    void lodBaseAddressesMatchShaderConstants() {
        assertEquals(4096, OctrayChunk.getSubChunkLodBaseAddr(1));
        assertEquals(4608, OctrayChunk.getSubChunkLodBaseAddr(2));
        assertEquals(4672, OctrayChunk.getSubChunkLodBaseAddr(3));
        assertEquals(4680, OctrayChunk.getSubChunkLodBaseAddr(4));
    }

    // ---------- Empty mip cell → air AABB semantics ----------

    @Test
    void emptyLod1CellImplies2x2x2AirAABB() {
        // When the shader finds mip_entry == 0 at LOD1 for a query position,
        // it returns an air AABB spanning the 2x2x2 cell.
        // Verify that logic by simulating the shader's air-entry construction.

        // Query position (4, 6, 3) at LOD1:
        // cell_min = ((pos & 15) >> 1) << 1 = (4, 6, 2)
        // span = 1 << 1 = 2
        // AABB = (4, 6, 2) to (6, 8, 4)
        int qx = 4, qy = 6, qz = 3;
        int lod = 1;
        int cellMinX = ((qx & 15) >> lod) << lod;
        int cellMinY = ((qy & 15) >> lod) << lod;
        int cellMinZ = ((qz & 15) >> lod) << lod;
        int span = 1 << lod;

        int airEntry = AirEntry.toAirEntry(cellMinX, cellMinY, cellMinZ,
            cellMinX + span, cellMinY + span, cellMinZ + span);

        assertEquals(4, AirEntry.getX1(airEntry));
        assertEquals(6, AirEntry.getY1(airEntry));
        assertEquals(2, AirEntry.getZ1(airEntry));
        assertEquals(6, AirEntry.getX2(airEntry));
        assertEquals(8, AirEntry.getY2(airEntry));
        assertEquals(4, AirEntry.getZ2(airEntry));
    }

    @Test
    void emptyLod2CellImplies4x4x4AirAABB() {
        int qx = 5, qy = 13, qz = 10;
        int lod = 2;
        int cellMinX = ((qx & 15) >> lod) << lod;
        int cellMinY = ((qy & 15) >> lod) << lod;
        int cellMinZ = ((qz & 15) >> lod) << lod;
        int span = 1 << lod;

        int airEntry = AirEntry.toAirEntry(cellMinX, cellMinY, cellMinZ,
            cellMinX + span, cellMinY + span, cellMinZ + span);

        assertEquals(4, AirEntry.getX1(airEntry));
        assertEquals(12, AirEntry.getY1(airEntry));
        assertEquals(8, AirEntry.getZ1(airEntry));
        assertEquals(8, AirEntry.getX2(airEntry));
        assertEquals(16, AirEntry.getY2(airEntry));
        assertEquals(12, AirEntry.getZ2(airEntry));
    }

    @Test
    void emptyLod4CellImplies16x16x16AirAABB() {
        // LOD4 is the single root cell — if empty, the entire chunk is air
        int lod = 4;
        int span = 1 << lod; // 16
        int cellMinX = 0, cellMinY = 0, cellMinZ = 0;

        int airEntry = AirEntry.toAirEntry(cellMinX, cellMinY, cellMinZ,
            cellMinX + span, cellMinY + span, cellMinZ + span);

        assertEquals(0, AirEntry.getX1(airEntry));
        assertEquals(0, AirEntry.getY1(airEntry));
        assertEquals(0, AirEntry.getZ1(airEntry));
        assertEquals(16, AirEntry.getX2(airEntry));
        assertEquals(16, AirEntry.getY2(airEntry));
        assertEquals(16, AirEntry.getZ2(airEntry));
    }

    @Test
    void shaderLookupReturnsMipAirForEmptyRegion() {
        // Simulate the shader's top-down mip lookup for a fully empty chunk.
        // The shader starts from LOD4 and works down; the first empty mip cell
        // should produce a 16x16x16 air AABB (the whole chunk).
        GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
        OctrayChunk chunk = new OctrayChunk();
        chunk.allocate(chunkMemory);
        chunk.finishUpdate(chunkMemory);

        IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();

        // Simulate shader lookup for position (7, 3, 11)
        int qx = 7, qy = 3, qz = 11;
        Integer resultAir = null;
        for (int lod = 4; lod >= 1; lod--) {
            int mipAddr = OctrayChunk.getSubChunkAddr(qx, qy, qz, lod);
            int mipEntry = ints.get(mipAddr);
            if (mipEntry == 0) {
                int cellMinX = ((qx & 15) >> lod) << lod;
                int cellMinY = ((qy & 15) >> lod) << lod;
                int cellMinZ = ((qz & 15) >> lod) << lod;
                int span = 1 << lod;
                resultAir = AirEntry.toAirEntry(cellMinX, cellMinY, cellMinZ,
                    cellMinX + span, cellMinY + span, cellMinZ + span);
                break;
            }
        }

        // LOD4 should be 0 (empty), yielding the whole-chunk air AABB
        assertTrue(resultAir != null, "Empty chunk must produce an air AABB from mip lookup");
        assertEquals(0, AirEntry.getX1(resultAir));
        assertEquals(0, AirEntry.getY1(resultAir));
        assertEquals(0, AirEntry.getZ1(resultAir));
        assertEquals(16, AirEntry.getX2(resultAir));
        assertEquals(16, AirEntry.getY2(resultAir));
        assertEquals(16, AirEntry.getZ2(resultAir));

        chunk.free(chunkMemory);
        chunkMemory.free();
    }

    @Test
    void shaderLookupSkipsOccupiedMipAndFallsToSmaller() {
        // Place a block at (0,0,0). Query position (12,12,12) in the same chunk.
        // LOD4 (root) will be occupied (block exists somewhere), but LOD3 cell
        // for (12,12,12) should be empty, yielding an 8x8x8 air AABB.
        GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
        GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_blk", PBlock.BYTE_SIZE * 4, true);
        OctrayChunk chunk = new OctrayChunk();
        PBlock block = new PBlock(5, () -> new Schematic(16, 16, 16));
        blockMemory.allocate(PBlock.BYTE_SIZE);
        block.allocate(blockMemory);
        chunk.allocate(chunkMemory);

        chunk.set(0, 0, 0, block, 0);
        chunk.finishUpdate(chunkMemory);

        IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();

        int qx = 12, qy = 12, qz = 12;
        Integer resultAir = null;
        int hitLod = -1;
        for (int lod = 4; lod >= 1; lod--) {
            int mipAddr = OctrayChunk.getSubChunkAddr(qx, qy, qz, lod);
            int mipEntry = ints.get(mipAddr);
            if (mipEntry == 0) {
                int cellMinX = ((qx & 15) >> lod) << lod;
                int cellMinY = ((qy & 15) >> lod) << lod;
                int cellMinZ = ((qz & 15) >> lod) << lod;
                int span = 1 << lod;
                resultAir = AirEntry.toAirEntry(cellMinX, cellMinY, cellMinZ,
                    cellMinX + span, cellMinY + span, cellMinZ + span);
                hitLod = lod;
                break;
            }
        }

        // LOD4 is occupied (block exists), so we should hit LOD3 or lower for (12,12,12)
        assertTrue(resultAir != null, "Query in empty region must yield air AABB");
        assertTrue(hitLod < 4, "Occupied LOD4 should be skipped; should hit LOD3 or lower");

        // Verify the AABB spans the expected region
        int span = 1 << hitLod;
        int expectedMinX = ((qx & 15) >> hitLod) << hitLod;
        int expectedMinY = ((qy & 15) >> hitLod) << hitLod;
        int expectedMinZ = ((qz & 15) >> hitLod) << hitLod;
        assertEquals(expectedMinX, AirEntry.getX1(resultAir));
        assertEquals(expectedMinY, AirEntry.getY1(resultAir));
        assertEquals(expectedMinZ, AirEntry.getZ1(resultAir));
        assertEquals(expectedMinX + span, AirEntry.getX2(resultAir));
        assertEquals(expectedMinY + span, AirEntry.getY2(resultAir));
        assertEquals(expectedMinZ + span, AirEntry.getZ2(resultAir));

        chunk.free(chunkMemory);
        block.free(blockMemory);
        chunkMemory.free();
        blockMemory.free();
    }
}
