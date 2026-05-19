package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import org.joml.Vector2f;
import org.joml.Vector3f;

import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.function.Consumer;

/**
 * Owns the 5 non-ReGIR GPU buffer managers (SSBOs) for the light pipeline:
 * lights, previousLights, lightMapping, lightReverseMapping, neighborOffsets.
 */
class LightStorageManager {

    private static final int LIGHT_BYTE_SIZE = 64;
    private static final int NEIGHBOR_OFFSET_COUNT = 8192;

    // -------------------------------------------------------------------------
    // Mutable fields (re-created on resize, same as in LightRegistry)
    // -------------------------------------------------------------------------
    private GlMemoryManager lightsMemoryManager;
    private MemoryOwner lightsMemory;
    private GlMemoryManager previousLightsMemoryManager;
    private SimpleMemoryOwner previousLightsMemory;
    private GlMemoryManager lightMappingMemoryManager;
    private MemoryOwner lightMappingMemory;
    private GlMemoryManager lightReverseMappingMemoryManager;
    private MemoryOwner lightReverseMappingMemory;

    // Immutable (fixed at construction)
    private final GlMemoryManager neighborOffsetMemoryManager;
    private final SimpleMemoryOwner neighborOffsetMemory;

    public LightStorageManager(int initialCapacity) {
        this.lightsMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list", initialCapacity * LIGHT_BYTE_SIZE + 4, true);
        this.lightsMemory = new SimpleMemoryOwner(this.lightsMemoryManager, this.lightsMemoryManager.getCapacity());
        this.previousLightsMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list_previous", initialCapacity * LIGHT_BYTE_SIZE + 4, true);
        this.previousLightsMemory = new SimpleMemoryOwner(this.previousLightsMemoryManager, this.previousLightsMemoryManager.getCapacity());
        this.lightMappingMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list_mapping", initialCapacity * 4, false);
        this.lightMappingMemory = new SimpleMemoryOwner(this.lightMappingMemoryManager, this.lightMappingMemoryManager.getCapacity());
        this.lightReverseMappingMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_reverse_mapping", initialCapacity * 4, false);
        this.lightReverseMappingMemory = new SimpleMemoryOwner(this.lightReverseMappingMemoryManager, this.lightReverseMappingMemoryManager.getCapacity());
        this.neighborOffsetMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_neighbor_offsets", NEIGHBOR_OFFSET_COUNT * 2, false);
        this.neighborOffsetMemory = new SimpleMemoryOwner(this.neighborOffsetMemoryManager, this.neighborOffsetMemoryManager.getCapacity());
        this.fillNeighborOffsets();
    }

    // -------------------------------------------------------------------------
    // Resize (called by LightRegistry.resizeLightStorage)
    // -------------------------------------------------------------------------

    /**
     * Replaces the 4 capacity-dependent buffers with newly sized ones.
     * Mirrors the logic from LightRegistry.resizeLightStorage for the storage subset.
     */
    public void resize(int newCapacity) {
        this.lightsMemoryManager = replaceManager(
            this.lightsMemoryManager, "ph_light_list", newCapacity * LIGHT_BYTE_SIZE + 4, true,
            this.lightsMemory, true, owner -> this.lightsMemory = owner);
        this.previousLightsMemoryManager = replaceManager(
            this.previousLightsMemoryManager, "ph_light_list_previous", newCapacity * LIGHT_BYTE_SIZE + 4, true,
            this.previousLightsMemory, true, owner -> this.previousLightsMemory = owner);
        this.lightMappingMemoryManager = replaceManager(
            this.lightMappingMemoryManager, "ph_light_list_mapping", newCapacity * Integer.BYTES, false,
            this.lightMappingMemory, false, owner -> this.lightMappingMemory = owner);
        this.lightReverseMappingMemoryManager = replaceManager(
            this.lightReverseMappingMemoryManager, "ph_light_reverse_mapping", newCapacity * Integer.BYTES, false,
            this.lightReverseMappingMemory, false, owner -> this.lightReverseMappingMemory = owner);
    }

    public void free() {
        this.lightsMemoryManager.free();
        this.previousLightsMemoryManager.free();
        this.lightMappingMemoryManager.free();
        this.lightReverseMappingMemoryManager.free();
        this.neighborOffsetMemoryManager.free();
    }

    // -------------------------------------------------------------------------
    // Serialization helpers
    // -------------------------------------------------------------------------

    /**
     * Serializes lights[0..tracedCount-1] into lightsMemory.
     *
     * @param lights            the current traced-light array
     * @param compileCount      used for periodic debug logging (passed from LightRegistry)
     * @param loggedColors      whether automation color logging has already been emitted
     * @return true if the automation color log was emitted this call (LightRegistry should
     *         set loggedAutomationLightColors = true when this returns true)
     */
    public boolean storeLights(LightInstance[] lights, int compileCount, boolean loggedColors) {
        FloatBuffer buffer = this.lightsMemory.getMemory().getBuffer().asFloatBuffer();
        Vector3f colorSum = Photonic.automationEnabled() && !loggedColors ? new Vector3f() : null;
        StringBuilder sampleLights = Photonic.automationEnabled() && !loggedColors ? new StringBuilder() : null;
        int sampledLights = 0;
        for (LightInstance light : lights) {
            buffer.position(16 * light.index());
            BlockLightInfo lightInfo = light.type();
            Vector3f rawColor = lightInfo.getRawColorAsVector();
            float lightIntensity = light.active() ? lightInfo.adjustedIntensity() : 0.0F;
            store(light.position(), buffer);                       // vec4[0].xyz = position
            buffer.put(Float.intBitsToFloat(light.blockId()));     // vec4[0].w = blockId
            store(rawColor, buffer);                               // vec4[1].xyz = color
            buffer.put(lightIntensity);                            // vec4[1].w = intensity
            store(lightInfo.getAttenuationAsVector(), buffer);     // vec4[2].xy = attenuation
            buffer.put(lightInfo.falloff());                       // vec4[2].z = falloff
            buffer.put(lightInfo.radiusInBlocks());                // vec4[2].w = block_radius
            store(lightInfo.emissionAxis(), buffer);               // vec4[3].xyz = emissionAxis
            buffer.put(lightInfo.orientationSpread() + lightInfo.emissionSpread()); // vec4[3].w = orientationSpread + emissionSpread

            if (colorSum != null) {
                colorSum.add(rawColor.x * lightIntensity, rawColor.y * lightIntensity, rawColor.z * lightIntensity);
                if (sampledLights < 5) {
                    sampleLights.append(" idx=")
                        .append(light.index())
                        .append(" blockId=")
                        .append(light.blockId())
                        .append(" pos=")
                        .append(light.position())
                        .append(" color=")
                        .append(rawColor)
                        .append(" intensity=")
                        .append(lightIntensity);
                    sampledLights++;
                }
            }
        }

        // Always log first 3 lights for brightness debugging
        if (lights.length > 0 && compileCount % 60 == 0) {
            StringBuilder debugLights = new StringBuilder();
            int debugCount = Math.min(3, lights.length);
            for (int i = 0; i < debugCount; i++) {
                LightInstance dl = lights[i];
                BlockLightInfo dli = dl.type();
                Vector3f dc = dli.getRawColorAsVector();
                debugLights.append(String.format(
                    " [%d] pos=%s rawColor=(%.4f,%.4f,%.4f) intensity=%.4f attenuation=(%.4f,%.4f) falloff=%.4f radius=%.2f",
                    dl.index(), dl.position(), dc.x, dc.y, dc.z, dli.adjustedIntensity(),
                    dli.getAttenuationAsVector().x, dli.getAttenuationAsVector().y, dli.falloff(), dli.radiusInBlocks()
                ));
            }
            Photonic.info("[LightDebug] tracedLights={} lights:{}", lights.length, debugLights);
        }

        if (colorSum != null && lights.length > 0) {
            colorSum.div((float) lights.length);
            Photonic.info(
                "[LightRegistryDebug] uploadedLights={} meanColor={}{}",
                lights.length,
                colorSum,
                sampleLights == null || sampleLights.isEmpty() ? "" : sampleLights.toString()
            );
            return true;
        }
        return false;
    }

    /**
     * Writes prev->curr index mappings into lightMappingMemory.
     *
     * @param newLightIndices forward mapping array (index = previous index, value = current index)
     * @param capacity        number of entries to write
     */
    public void storeLightMappings(short[] newLightIndices, int capacity) {
        IntBuffer buffer = this.lightMappingMemory.getMemory().getBuffer().asIntBuffer();
        for (int i = 0; i < capacity; i++) {
            buffer.put(i, newLightIndices[i]);
        }
    }

    /**
     * Writes curr->prev index mappings into lightReverseMappingMemory.
     *
     * @param newLightIndices forward mapping array used to derive the reverse
     * @param capacity        number of entries to write
     */
    public void storeLightReverseMappings(short[] newLightIndices, int capacity) {
        IntBuffer buffer = this.lightReverseMappingMemory.getMemory().getBuffer().asIntBuffer();
        for (int i = 0; i < capacity; i++) {
            buffer.put(i, -1);
        }
        for (int previousIndex = 0; previousIndex < capacity; previousIndex++) {
            int currentIndex = newLightIndices[previousIndex];
            if (currentIndex >= 0 && currentIndex < capacity) {
                buffer.put(currentIndex, previousIndex);
            }
        }
    }

    /**
     * Writes identity mappings (i->i) into both mapping buffers.
     *
     * @param capacity number of entries to write
     */
    public void storeIdentityLightMappings(int capacity) {
        IntBuffer forwardBuffer = this.lightMappingMemory.getMemory().getBuffer().asIntBuffer();
        IntBuffer reverseBuffer = this.lightReverseMappingMemory.getMemory().getBuffer().asIntBuffer();
        for (int i = 0; i < capacity; i++) {
            forwardBuffer.put(i, i);
            reverseBuffer.put(i, i);
        }
    }

    public void copyCurrentLightsToPrevious() {
        java.nio.ByteBuffer src = this.lightsMemory.getMemory().getBuffer();
        java.nio.ByteBuffer dst = this.previousLightsMemory.getMemory().getBuffer();
        int copyLength = Math.min(src.capacity(), dst.capacity());
        src.rewind();
        dst.rewind();
        for (int i = 0; i < copyLength; i++) {
            dst.put(src.get());
        }
        src.rewind();
        dst.rewind();
    }

    /**
     * Port of RTXDI's FillNeighborOffsetBuffer (RtxdiUtils.cpp lines 48-69).
     * Called once at construction — never per-frame.
     */
    private void fillNeighborOffsets() {
        float phi2 = 1.0f / 1.3247179572447f;
        float u = 0.5f;
        float v = 0.5f;
        int num = 0;
        java.nio.ByteBuffer buf = this.neighborOffsetMemory.getMemory().getBuffer();
        buf.order(ByteOrder.nativeOrder());
        while (num < NEIGHBOR_OFFSET_COUNT * 2) {
            u += phi2;
            v += phi2 * phi2;
            if (u >= 1.0f) u -= 1.0f;
            if (v >= 1.0f) v -= 1.0f;
            float rSq = (u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f);
            if (rSq > 0.25f) continue;
            buf.put(num++, (byte) ((u - 0.5f) * 250.0f));
            buf.put(num++, (byte) ((v - 0.5f) * 250.0f));
        }
        this.neighborOffsetMemoryManager.queueUpload(this.neighborOffsetMemory);
    }

    // -------------------------------------------------------------------------
    // Queue-upload helpers (called from LightRegistry.compileRegistry)
    // -------------------------------------------------------------------------

    public void queueUploadLights() {
        this.lightsMemoryManager.queueUpload(this.lightsMemory);
    }

    public void queueUploadPreviousLights() {
        this.previousLightsMemoryManager.queueUpload(this.previousLightsMemory);
    }

    public void queueUploadLightMappings() {
        this.lightMappingMemoryManager.queueUpload(this.lightMappingMemory);
    }

    public void queueUploadLightReverseMappings() {
        this.lightReverseMappingMemoryManager.queueUpload(this.lightReverseMappingMemory);
    }

    // -------------------------------------------------------------------------
    // Upload — only the 5 storage buffers
    // -------------------------------------------------------------------------

    /**
     * Uploads the 5 storage buffers to the GPU.
     *
     * @return true if all uploads succeeded
     */
    public boolean upload() {
        boolean uploadDone = true;
        uploadDone &= this.lightsMemoryManager.upload();
        uploadDone &= this.previousLightsMemoryManager.upload();
        uploadDone &= this.lightMappingMemoryManager.upload();
        uploadDone &= this.lightReverseMappingMemoryManager.upload();
        uploadDone &= this.neighborOffsetMemoryManager.upload();
        return uploadDone;
    }

    // -------------------------------------------------------------------------
    // Accessors (delegated through LightRegistry for external callers)
    // -------------------------------------------------------------------------

    public GlMemoryManager getLightsMemoryManager() {
        return this.lightsMemoryManager;
    }

    public GlMemoryManager getPreviousLightsMemoryManager() {
        return this.previousLightsMemoryManager;
    }

    public GlMemoryManager getLightMappingMemoryManager() {
        return this.lightMappingMemoryManager;
    }

    public GlMemoryManager getLightReverseMappingMemoryManager() {
        return this.lightReverseMappingMemoryManager;
    }

    public GlMemoryManager getNeighborOffsetMemoryManager() {
        return this.neighborOffsetMemoryManager;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    static GlMemoryManager replaceManager(
        GlMemoryManager previousManager,
        String name,
        int byteSize,
        boolean staticData,
        MemoryOwner previousOwner,
        boolean preserveContents,
        Consumer<SimpleMemoryOwner> ownerSetter
    ) {
        GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, name, byteSize, staticData);
        SimpleMemoryOwner owner = new SimpleMemoryOwner(manager, manager.getCapacity());
        if (preserveContents && previousOwner != null && previousOwner.getMemory() != null) {
            copyMemory(previousOwner.getMemory(), owner.getMemory());
        }
        ownerSetter.accept(owner);
        if (previousManager != null) {
            previousManager.free();
        }
        return manager;
    }

    private static void copyMemory(MemoryRegion src, MemoryRegion dst) {
        java.nio.ByteBuffer srcBuffer = src.getBuffer();
        java.nio.ByteBuffer dstBuffer = dst.getBuffer();
        int copyLength = Math.min(srcBuffer.capacity(), dstBuffer.capacity());
        srcBuffer.position(0);
        srcBuffer.limit(copyLength);
        dstBuffer.position(0);
        dstBuffer.put(srcBuffer);
        dstBuffer.position(0);
        dstBuffer.limit(dstBuffer.capacity());
    }

    private static void store(Vector3f vector3f, FloatBuffer buffer) {
        buffer.put(vector3f.x);
        buffer.put(vector3f.y);
        buffer.put(vector3f.z);
    }

    private static void store(Vector2f vector2f, FloatBuffer buffer) {
        buffer.put(vector2f.x);
        buffer.put(vector2f.y);
    }
}
