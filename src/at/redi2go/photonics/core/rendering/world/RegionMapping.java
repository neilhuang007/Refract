package at.redi2go.photonics.core.rendering.world;

import at.redi2go.photonics.core.model.VoxelModel;
import at.redi2go.photonics.core.util.IntPacking;
import it.unimi.dsi.fastutil.shorts.ShortSet;
import it.unimi.dsi.fastutil.shorts.Short2ShortMap;
import it.unimi.dsi.fastutil.shorts.Short2ShortOpenHashMap;

import java.util.Arrays;

/**
 * Keeps track of which voxels belong to which region while trying to minimize memory usage as much as possible.
 * This works on the assumption that most blocks will only belong to one region, and the ones that don't likely only have a few regions.
 */
public abstract class RegionMapping {
    private static final int LOWER_SHORT_MASK = 65535;
    private static final int INLINE_REGION_LIMIT = 8;

    // Has 3 purposes:
    //
    // 1) to store the current number of unique regions
    // 2) store the region when count is 1 (avoids allocating length 1 array)
    // 3) Stores the current shift for voxelMapping
    //
    // Lower 16 bits are used for #1, while the upper 16 are used for 2 & 3.
    private int state;

    // A mapping of indexes to regions.
    //
    // Will be:
    //
    // - Null when count is 1
    // - A short array when count is <= 8
    // - A Short2ShortMap when count is > 8
    private Object regions;

    // Tracks which voxel maps to which region.
    private int[] voxelMapping;

    public RegionMapping() {
        this.state = 0;
        this.regions = null;
        this.voxelMapping = null;
    }

    public RegionMapping(RegionMapping other) {
        this.state = other.state;
        this.regions = copyRegions(other.regions, other.regionCount());
        this.voxelMapping = other.voxelMapping == null ? null : Arrays.copyOf(other.voxelMapping, other.voxelMapping.length);
    }

    public RegionMapping(RegionMapping other, ShortSet removedRegions) {
        this();

        int uniqueCount = other.regionCount();
        if (uniqueCount == 0) {
            return;
        }

        short[] remappedRegions = new short[Math.max(uniqueCount, 1)];
        int[] remap = new int[Math.max(uniqueCount, 1)];
        Arrays.fill(remap, -1);

        int nextIndex = 0;
        for (int i = 0; i < uniqueCount; i++) {
            short region = other.regionAt(i);
            if (removedRegions.contains(region)) {
                continue;
            }

            remappedRegions[nextIndex] = region;
            remap[i] = nextIndex;
            nextIndex++;
        }

        if (nextIndex == 0) {
            return;
        }

        if (nextIndex == 1) {
            state = ((int) remappedRegions[0] << 16) | 1;
            return;
        }

        initializeRegions(remappedRegions, nextIndex);
        initVoxelArray(nextIndex);

        for (int voxelIndex = 0; voxelIndex < RtVoxel.ENTRIES_SIZE; voxelIndex++) {
            int previousIndex = other.getRegionIndex(voxelIndex, uniqueCount);
            if (previousIndex < 0) {
                continue;
            }

            int newIndex = remap[previousIndex];
            if (newIndex >= 0) {
                setVoxel(voxelIndex, newIndex);
            }
        }
    }

    protected int regionCount() {
        return state & LOWER_SHORT_MASK;
    }

    protected void setRegion(int voxelIndex, short region) {
        int count = state & LOWER_SHORT_MASK;

        if (singleAppendRegion(count, region)) return;

        if (count == 1) {
            singleAppend(region);
            setVoxel(voxelIndex, 1);
            return;
        }

        int newIndex = appendRegion(region);
        setVoxel(voxelIndex, newIndex);
    }

    protected short getRegion(int voxelIndex) {
        int count = state & LOWER_SHORT_MASK;
        if (count < 2) return singleGetRegion();

        return regionAt(getRegionIndex(voxelIndex, count));
    }

    // Voxel array handling

    private int setVoxelShift(int capacity) {
        int shift = IntPacking.shiftFactor(capacity - 1);
        state = state & LOWER_SHORT_MASK | shift << 16;

        return shift;
    }

    private int getVoxelShift() {
        return (state >>> 16) & LOWER_SHORT_MASK;
    }

    private void initVoxelArray(int capacity) {
        int shift = setVoxelShift(capacity);
        voxelMapping = new int[RtVoxel.ENTRIES_SIZE >> shift];
    }

    private void growVoxelArray(int newCapacity) {
        int oldShift = getVoxelShift();
        int newShift = setVoxelShift(newCapacity);
        if (oldShift == newShift) return;

        int[] newData = new int[RtVoxel.ENTRIES_SIZE >> newShift];

        int oldSectionLength = IntPacking.sectionLength(oldShift);
        int newSectionLength = IntPacking.sectionLength(newShift);

        for (int i = 0; i < newData.length; i++) {
            int offset = (i & 1) == 0 ? 0 : oldSectionLength;
            int value = 0;

            for (int s = 0; s < newSectionLength; s++) {
                value = IntPacking.setValue(
                        value,
                        s,
                        IntPacking.getValue(voxelMapping[i >> 1], s + offset, oldShift),
                        newShift
                );
            }

            newData[i] = value;
        }

        voxelMapping = newData;
    }

    private void setVoxel(int voxelIndex, int regionIndex) {
        int shift = getVoxelShift();
        int offset = IntPacking.dataOffset(voxelIndex, shift);
        int sectionIndex = IntPacking.sectionIndex(voxelIndex, shift);

        voxelMapping[offset] = IntPacking.setValue(voxelMapping[offset], sectionIndex, regionIndex, shift);
    }

    private int getVoxel(int voxelIndex) {
        int shift = getVoxelShift();
        int offset = IntPacking.dataOffset(voxelIndex, shift);
        int sectionIndex = IntPacking.sectionIndex(voxelIndex, shift);

        return IntPacking.getValue(voxelMapping[offset], sectionIndex, shift);
    }

    // Single region handling

    private boolean singleAppendRegion(int count, short region) {
        if (count == 0) {
            state = ((int) region << 16) | 1;
            return true;
        }

        return count == 1 && (state >>> 16) == ((int) region & LOWER_SHORT_MASK);
    }

    protected short singleGetRegion() {
        return (short) (state >>> 16);
    }

    private void singleAppend(short region) {
        regions = new short[]{singleGetRegion(), region};
        state = 2;
        initVoxelArray(2);
    }

    // Region storage handling

    private int appendRegion(short region) {
        int count = regionCount();

        if (count <= INLINE_REGION_LIMIT) {
            int index = arrayAppend(region);
            if (index != -1) {
                return index;
            }

            growVoxelArray(INLINE_REGION_LIMIT + 1);
            convertArrayToMap();
            count = regionCount();
        }

        return mapAppend(region, count);
    }

    private int getRegionIndex(int voxelIndex, int count) {
        if (count == 0) {
            return -1;
        }
        if (count == 1) {
            return 0;
        }
        return getVoxel(voxelIndex);
    }

    private short regionAt(int index) {
        int count = regionCount();
        if (count == 1) {
            return singleGetRegion();
        }
        if (count <= INLINE_REGION_LIMIT) {
            return arrayGetRegion(index);
        }
        return mapGetRegion(index);
    }

    private void initializeRegions(short[] source, int count) {
        if (count == 1) {
            state = ((int) source[0] << 16) | 1;
            regions = null;
            return;
        }

        state = count;
        if (count <= INLINE_REGION_LIMIT) {
            regions = Arrays.copyOf(source, count);
            return;
        }

        Short2ShortOpenHashMap map = new Short2ShortOpenHashMap(count);
        map.defaultReturnValue((short) -1);
        for (short i = 0; i < count; i++) {
            map.put(i, source[i]);
        }
        regions = map;
    }

    private Object copyRegions(Object source, int count) {
        if (source == null || count <= 1) {
            return source;
        }
        if (count <= INLINE_REGION_LIMIT) {
            return Arrays.copyOf((short[]) source, ((short[]) source).length);
        }

        Short2ShortOpenHashMap copy = new Short2ShortOpenHashMap((Short2ShortMap) source);
        copy.defaultReturnValue((short) -1);
        return copy;
    }

    private void convertArrayToMap() {
        short[] arr = (short[]) regions;
        int count = regionCount();

        Short2ShortOpenHashMap map = new Short2ShortOpenHashMap(count + 1);
        map.defaultReturnValue((short) -1);
        for (short i = 0; i < count; i++) {
            map.put(i, arr[i]);
        }
        regions = map;
    }

    private int arrayAppend(short region) {
        int count = state & LOWER_SHORT_MASK;
        short[] arr = (short[]) regions;

        for (int i = 0; i < count; i++) {
            if (arr[i] == region) {
                return i;
            }
        }

        if (count == INLINE_REGION_LIMIT) {
            return -1;
        }

        if (count >= arr.length) {
            int newSize = Math.min(INLINE_REGION_LIMIT, count << 1);
            growVoxelArray(newSize);
            arr = Arrays.copyOf(arr, newSize);
            regions = arr;
        }

        arr[count] = region;
        state = (state & ~LOWER_SHORT_MASK) | (count + 1);
        return count;
    }

    private short arrayGetRegion(int index) {
        return ((short[]) regions)[index];
    }

    private int mapAppend(short region, int count) {
        Short2ShortMap map = (Short2ShortMap) regions;
        for (Short2ShortMap.Entry entry : map.short2ShortEntrySet()) {
            if (entry.getShortValue() == region) {
                return entry.getShortKey();
            }
        }

        map.put((short) count, region);
        state = (state & ~LOWER_SHORT_MASK) | (count + 1);
        growVoxelArray(count + 1);
        return count;
    }

    private short mapGetRegion(int index) {
        return ((Short2ShortMap) regions).get((short) index);
    }
}
