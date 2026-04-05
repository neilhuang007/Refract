package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL42;
import org.lwjgl.opengl.GL43;
import org.lwjgl.system.MemoryUtil;

import java.nio.FloatBuffer;

public class RegirComputeProgram {

    // -----------------------------------------------------------------------
    // ReGIR build program (regir_build.glsl)
    // -----------------------------------------------------------------------
    private int programId = 0;
    private boolean compiled = false;

    private int locGridCenter = -1;
    private int locGridCells = -1;
    private int locLightsPerCell = -1;
    private int locCellSize = -1;
    private int locLightCount = -1;
    private int locFrameSeed = -1;
    private int locTileSize = -1;
    private int locTileCount = -1;
    private int locBuildSamples = -1;
    private int locSamplingJitter = -1;
    private int locRegirRisBufferOffset = -1;
    private int locRisTileBufferOffset = -1;

    // -----------------------------------------------------------------------
    // Presample tiles program (regir_presample_tiles.glsl)
    // -----------------------------------------------------------------------
    private int presampleProgramId = 0;
    private boolean presampleCompiled = false;

    private int presampleLocLightCount = -1;
    private int presampleLocTileSize = -1;
    private int presampleLocTileCount = -1;
    private int presampleLocFrameSeed = -1;
    private int presampleLocPdfTextureSize = -1;
    private int presampleLocRisTileBufferOffset = -1;

    // -----------------------------------------------------------------------
    // PDF mipmap texture (RTXDI 2D R32F texture for light flux)
    // -----------------------------------------------------------------------
    private int pdfTextureId = 0;
    private int pdfTextureWidth = 0;
    private int pdfTextureHeight = 0;
    private int pdfTextureMipLevels = 0;
    private FloatBuffer pdfUploadBuffer = null;
    private static final int bindPdfTextureUnit = 0; // texture unit for sampler2D

    // -----------------------------------------------------------------------
    // SSBO binding points
    // -----------------------------------------------------------------------
    private static final int bindLightList          = 0;
    private static final int bindLightCdf           = 1;
    // binding 2 unused — no cell counts SSBO (RTXDI uses fixed-position writes)
    // binding 3 removed — merged into unified ph_ris_buffer at binding 5
    // binding 4 unused
    private static final int bindRisBuffer          = 5;  // RTXDI_RIS_BUFFER: tiles at [0], ReGIR at [tileCount*tileSize]
    private static final int bindCompactLightData   = 6;  // RTXDI companion buffer: packed light data alongside RIS entries

    // -----------------------------------------------------------------------
    // RIS tile buffer parameters
    // RTXDI defaults: tileSize = 1024, tileCount = 128.
    // -----------------------------------------------------------------------
    public static final int tileSize  = 1024;
    public static final int tileCount = 128;


    // -----------------------------------------------------------------------
    // Build program compilation
    // -----------------------------------------------------------------------
    public void compile(String shaderSource) {
        int shader = GL20.glCreateShader(GL43.GL_COMPUTE_SHADER);
        GL20.glShaderSource(shader, shaderSource);
        GL20.glCompileShader(shader);

        if (GL20.glGetShaderi(shader, GL20.GL_COMPILE_STATUS) == GL11.GL_FALSE) {
            String log = GL20.glGetShaderInfoLog(shader);
            Photonic.warn("[RegirCompute] Build shader compile failed: {}", log);
            GL20.glDeleteShader(shader);
            return;
        }

        int program = GL20.glCreateProgram();
        GL20.glAttachShader(program, shader);
        GL20.glLinkProgram(program);

        if (GL20.glGetProgrami(program, GL20.GL_LINK_STATUS) == GL11.GL_FALSE) {
            String log = GL20.glGetProgramInfoLog(program);
            Photonic.warn("[RegirCompute] Build shader link failed: {}", log);
            GL20.glDeleteProgram(program);
            GL20.glDeleteShader(shader);
            return;
        }

        GL20.glDetachShader(program, shader);
        GL20.glDeleteShader(shader);

        this.programId = program;
        this.cacheUniformLocations();
        this.compiled = true;

        Photonic.info("[RegirCompute] Build shader compiled (programId={})", program);
    }

    private void cacheUniformLocations() {
        this.locGridCenter            = GL20.glGetUniformLocation(this.programId, "ph_regir_grid_center");
        this.locGridCells             = GL20.glGetUniformLocation(this.programId, "ph_regir_grid_cells");
        this.locLightsPerCell         = GL20.glGetUniformLocation(this.programId, "ph_regir_lights_per_cell");
        this.locCellSize              = GL20.glGetUniformLocation(this.programId, "ph_regir_cell_size");
        this.locLightCount            = GL20.glGetUniformLocation(this.programId, "ph_light_count");
        this.locFrameSeed             = GL20.glGetUniformLocation(this.programId, "ph_ris_frame_index");
        this.locTileSize              = GL20.glGetUniformLocation(this.programId, "ph_ris_tile_size");
        this.locTileCount             = GL20.glGetUniformLocation(this.programId, "ph_ris_tile_count");
        this.locBuildSamples          = GL20.glGetUniformLocation(this.programId, "ph_regir_build_samples");
        this.locSamplingJitter        = GL20.glGetUniformLocation(this.programId, "ph_regir_sampling_jitter");
        this.locRisTileBufferOffset   = GL20.glGetUniformLocation(this.programId, "ph_ris_tile_buffer_offset");
        this.locRegirRisBufferOffset  = GL20.glGetUniformLocation(this.programId, "ph_regir_ris_buffer_offset");
    }

    // -----------------------------------------------------------------------
    // Presample program compilation
    // -----------------------------------------------------------------------
    public void compilePresample(String shaderSource) {
        int shader = GL20.glCreateShader(GL43.GL_COMPUTE_SHADER);
        GL20.glShaderSource(shader, shaderSource);
        GL20.glCompileShader(shader);

        if (GL20.glGetShaderi(shader, GL20.GL_COMPILE_STATUS) == GL11.GL_FALSE) {
            String log = GL20.glGetShaderInfoLog(shader);
            Photonic.warn("[RegirCompute] Presample shader compile failed: {}", log);
            GL20.glDeleteShader(shader);
            return;
        }

        int program = GL20.glCreateProgram();
        GL20.glAttachShader(program, shader);
        GL20.glLinkProgram(program);

        if (GL20.glGetProgrami(program, GL20.GL_LINK_STATUS) == GL11.GL_FALSE) {
            String log = GL20.glGetProgramInfoLog(program);
            Photonic.warn("[RegirCompute] Presample shader link failed: {}", log);
            GL20.glDeleteProgram(program);
            GL20.glDeleteShader(shader);
            return;
        }

        GL20.glDetachShader(program, shader);
        GL20.glDeleteShader(shader);

        this.presampleProgramId = program;
        this.cachePresampleUniformLocations();
        this.presampleCompiled = true;

        Photonic.info("[RegirCompute] Presample shader compiled (programId={})", program);
    }

    private void cachePresampleUniformLocations() {
        this.presampleLocLightCount      = GL20.glGetUniformLocation(this.presampleProgramId, "ph_light_count");
        this.presampleLocTileSize        = GL20.glGetUniformLocation(this.presampleProgramId, "ph_ris_tile_size");
        this.presampleLocTileCount       = GL20.glGetUniformLocation(this.presampleProgramId, "ph_ris_tile_count");
        this.presampleLocFrameSeed       = GL20.glGetUniformLocation(this.presampleProgramId, "ph_ris_frame_index");
        this.presampleLocPdfTextureSize  = GL20.glGetUniformLocation(this.presampleProgramId, "ph_pdf_texture_size");
        this.presampleLocRisTileBufferOffset = GL20.glGetUniformLocation(this.presampleProgramId, "ph_ris_tile_buffer_offset");
    }

    // -----------------------------------------------------------------------
    // PDF texture helpers (matching RTXDI ComputePdfTextureSize / Z-curve)
    // -----------------------------------------------------------------------
    private record PdfTextureLayout(int width, int height, int mipLevels) {
    }

    private static PdfTextureLayout computePdfTextureSize(int maxLights) {
        double textureWidth = Math.max(1.0, Math.ceil(Math.sqrt(Math.max(maxLights, 1))));
        textureWidth = Math.pow(2.0, Math.ceil(Math.log(textureWidth) / Math.log(2.0)));
        double textureHeight = Math.max(1.0, Math.ceil(Math.max(maxLights, 1) / textureWidth));
        textureHeight = Math.pow(2.0, Math.ceil(Math.log(textureHeight) / Math.log(2.0)));
        double textureMips = Math.max(1.0, Math.log(Math.max(textureWidth, textureHeight)) / Math.log(2.0) + 1.0);
        return new PdfTextureLayout((int) textureWidth, (int) textureHeight, (int) textureMips);
    }

    private static int integerCompact(int x) {
        x = (x & 0x11111111) | ((x & 0x44444444) >> 1);
        x = (x & 0x03030303) | ((x & 0x30303030) >> 2);
        x = (x & 0x000F000F) | ((x & 0x0F000F00) >> 4);
        x = (x & 0x000000FF) | ((x & 0x00FF0000) >> 8);
        return x;
    }

    // RTXDI_LinearIndexToZCurve — returns {x, y}
    private static int[] linearToZCurve(int index) {
        return new int[]{ integerCompact(index), integerCompact(index >> 1) };
    }

    private void ensurePdfUploadBufferCapacity(int texelCount) {
        if (this.pdfUploadBuffer != null && this.pdfUploadBuffer.capacity() >= texelCount) {
            return;
        }

        if (this.pdfUploadBuffer != null) {
            MemoryUtil.memFree(this.pdfUploadBuffer);
        }

        this.pdfUploadBuffer = MemoryUtil.memAllocFloat(texelCount);
    }

    private void releasePdfUploadBuffer() {
        if (this.pdfUploadBuffer != null) {
            MemoryUtil.memFree(this.pdfUploadBuffer);
            this.pdfUploadBuffer = null;
        }
    }

    // -----------------------------------------------------------------------
    // PDF texture creation / update
    // -----------------------------------------------------------------------
    public void createPdfTexture(int maxLights) {
        PdfTextureLayout layout = computePdfTextureSize(maxLights);
        if (this.pdfTextureId != 0
            && this.pdfTextureWidth == layout.width()
            && this.pdfTextureHeight == layout.height()
            && this.pdfTextureMipLevels == layout.mipLevels()) {
            return;
        }

        if (this.pdfTextureId != 0) {
            GL11.glDeleteTextures(this.pdfTextureId);
            this.pdfTextureId = 0;
        }

        this.pdfTextureWidth = layout.width();
        this.pdfTextureHeight = layout.height();
        this.pdfTextureMipLevels = layout.mipLevels();

        this.pdfTextureId = GL11.glGenTextures();
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, this.pdfTextureId);
        // Immutable storage with all mip levels
        GL42.glTexStorage2D(GL11.GL_TEXTURE_2D, this.pdfTextureMipLevels, GL30.GL_R32F, this.pdfTextureWidth, this.pdfTextureHeight);
        // Nearest filtering — we need exact texel values, no interpolation
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST_MIPMAP_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL13.GL_CLAMP_TO_EDGE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL13.GL_CLAMP_TO_EDGE);
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, 0);

        Photonic.info("[RegirCompute] PDF texture created ({}x{}, {} mip levels, textureId={})",
                this.pdfTextureWidth, this.pdfTextureHeight, this.pdfTextureMipLevels, this.pdfTextureId);
    }

    public void updatePdfTexture(float[] lightPowers, int lightCount) {
        if (this.pdfTextureId == 0) return;

        int texelCount = this.pdfTextureWidth * this.pdfTextureHeight;
        this.ensurePdfUploadBufferCapacity(texelCount);
        this.pdfUploadBuffer.clear();
        for (int i = 0; i < texelCount; i++) {
            this.pdfUploadBuffer.put(i, 0.0f);
        }

        int availableLightCount = Math.min(lightCount, lightPowers.length);

        // Write each light's power at its Z-curve position
        for (int i = 0; i < availableLightCount && i < texelCount; i++) {
            int[] zc = linearToZCurve(i);
            int x = zc[0];
            int y = zc[1];
            if (x < this.pdfTextureWidth && y < this.pdfTextureHeight) {
                this.pdfUploadBuffer.put(y * this.pdfTextureWidth + x, lightPowers[i]);
            }
        }

        this.pdfUploadBuffer.limit(texelCount);
        this.pdfUploadBuffer.position(0);

        // Upload to mip 0 and generate the full mip chain.
        // Reset all unpack state that can reinterpret the direct buffer layout,
        // because other texture paths may leave row-length / skip state behind.
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, this.pdfTextureId);
        GL11.glPixelStorei(GL11.GL_UNPACK_ALIGNMENT, Float.BYTES);
        GL11.glPixelStorei(GL11.GL_UNPACK_ROW_LENGTH, 0);
        GL11.glPixelStorei(GL11.GL_UNPACK_SKIP_ROWS, 0);
        GL11.glPixelStorei(GL11.GL_UNPACK_SKIP_PIXELS, 0);
        GL11.glTexSubImage2D(GL11.GL_TEXTURE_2D, 0, 0, 0,
                this.pdfTextureWidth, this.pdfTextureHeight,
                GL11.GL_RED, GL11.GL_FLOAT, this.pdfUploadBuffer);
        GL30.glGenerateMipmap(GL11.GL_TEXTURE_2D);
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, 0);
    }

    // -----------------------------------------------------------------------
    // Dispatch — runs presample tiles then ReGIR build
    // -----------------------------------------------------------------------
    /**
     * Dispatches the presample-tiles pass followed by the ReGIR build pass.
     *
     * @param risBuffer     uvec2 SSBO — unified RIS buffer (tiles at [0..tileCount*tileSize), ReGIR after).
     *                      Must be sized: (tileCount*tileSize + gridRes^3*lightsPerCell) * 8 bytes.
     * @param gridCenter    world-space center of the ReGIR grid (= camera position)
     * @param numBuildSamples RTXDI default = 8 (ReGIR.h:141)
     * @param samplingJitter  RTXDI FullSample uploads 2.0 here for the default UI jitter of 1.0
     */
    public void dispatch(
            GlMemoryManager lightList,
            GlMemoryManager lightCdf,
            GlMemoryManager risBuffer,
            GlMemoryManager compactLightData,
            Vector3f gridCenter,
            Vector3i gridCells,
            int lightsPerCell,
            float cellSize,
            int lightCount,
            int presampleFrameCounter,
            int buildFrameCounter,
            int numBuildSamples,
            float samplingJitter) {

        if (!this.compiled) return;

        // RTXDI: both passes receive the raw frame index as frameIndex
        // (no LCG hashing — Jenkins hash inside the shader handles decorrelation)

        // Tile buffer offset is always 0 (tiles start at the beginning of the buffer).
        // ReGIR output follows the tiles: offset = tileCount * tileSize.
        int risTileBufferOffset   = 0;
        int regirRisBufferOffset  = tileCount * tileSize;

        // Clear the compact light data buffer before any dispatch so stale data cannot
        // be read when a slot was not written this frame (e.g. build-samples == 0).
        this.clearCompactLightDataBuffer(compactLightData);
        GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);

        // Pass 1: presample tiles (RTXDI_PresampleLocalLights)
        if (this.presampleCompiled) {
            GL20.glUseProgram(this.presampleProgramId);

            GL20.glUniform1i(this.presampleLocLightCount, lightCount);
            GL20.glUniform1i(this.presampleLocTileSize,   tileSize);
            GL20.glUniform1i(this.presampleLocTileCount,  tileCount);
            GL30.glUniform1ui(this.presampleLocFrameSeed, presampleFrameCounter);
            GL30.glUniform1ui(this.presampleLocRisTileBufferOffset, risTileBufferOffset);

            GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindLightList,        lightList.getId());
            GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindRisBuffer,        risBuffer.getId());
            GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindCompactLightData, compactLightData.getId());

            // Bind PDF mipmap texture and set its uniforms
            if (this.pdfTextureId != 0) {
                GL13.glActiveTexture(GL13.GL_TEXTURE0 + bindPdfTextureUnit);
                GL11.glBindTexture(GL11.GL_TEXTURE_2D, this.pdfTextureId);
                GL20.glUniform1i(
                        GL20.glGetUniformLocation(this.presampleProgramId, "u_LocalLightPdfTexture"),
                        bindPdfTextureUnit);
                GL20.glUniform2i(this.presampleLocPdfTextureSize, this.pdfTextureWidth, this.pdfTextureHeight);
            }

            // RTXDI 2D dispatch: Dispatch(tileSize/GROUP_SIZE, tileCount, 1)
            // gl_GlobalInvocationID.x = sampleInTile, .y = tileIndex
            int groupsX = tileSize / 256; // local_size_x = 256
            GL43.glDispatchCompute(groupsX, tileCount, 1);

            // Unbind texture after dispatch
            if (this.pdfTextureId != 0) {
                GL13.glActiveTexture(GL13.GL_TEXTURE0 + bindPdfTextureUnit);
                GL11.glBindTexture(GL11.GL_TEXTURE_2D, 0);
            }

            // RTXDI: memory barrier between presample and build passes
            GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);
        }

        // Pass 2: ReGIR build (RTXDI_PresampleLocalLightsForReGIR)
        GL20.glUseProgram(this.programId);

        this.setUniforms(gridCenter, gridCells, lightsPerCell, cellSize, lightCount, buildFrameCounter,
                numBuildSamples, samplingJitter, risTileBufferOffset, regirRisBufferOffset);
        this.bindBuildSsbos(lightList, lightCdf, risBuffer, compactLightData);
        this.clearRegirRegion(risBuffer, regirRisBufferOffset, gridCells.x * gridCells.y * gridCells.z, lightsPerCell);

        GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);

        int totalSlots    = gridCells.x * gridCells.y * gridCells.z * lightsPerCell;
        int workGroupSize = 256; // matches layout(local_size_x = 256) in regir_build.glsl
        int numGroups     = (totalSlots + workGroupSize - 1) / workGroupSize;
        GL43.glDispatchCompute(numGroups, 1, 1);

        GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);

        GL20.glUseProgram(0);
    }

    private void setUniforms(Vector3f gridCenter, Vector3i gridCells, int lightsPerCell,
                              float cellSize, int lightCount, int frameSeed,
                              int numBuildSamples, float samplingJitter,
                              int risTileBufferOffset, int regirRisBufferOffset) {
        GL20.glUniform3f(this.locGridCenter,              gridCenter.x, gridCenter.y, gridCenter.z);
        GL20.glUniform3i(this.locGridCells,               gridCells.x, gridCells.y, gridCells.z);
        GL20.glUniform1i(this.locLightsPerCell,           lightsPerCell);
        GL20.glUniform1f(this.locCellSize,                cellSize);
        GL20.glUniform1i(this.locLightCount,              lightCount);
        GL30.glUniform1ui(this.locFrameSeed,              frameSeed);
        GL20.glUniform1i(this.locTileSize,                tileSize);
        GL20.glUniform1i(this.locTileCount,               tileCount);
        GL30.glUniform1ui(this.locBuildSamples,           numBuildSamples);
        GL20.glUniform1f(this.locSamplingJitter,          samplingJitter);
        GL30.glUniform1ui(this.locRisTileBufferOffset,    risTileBufferOffset);
        GL30.glUniform1ui(this.locRegirRisBufferOffset,   regirRisBufferOffset);
    }

    private void bindBuildSsbos(
            GlMemoryManager lightList,
            GlMemoryManager lightCdf,
            GlMemoryManager risBuffer,
            GlMemoryManager compactLightData) {
        GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindLightList,        lightList.getId());
        GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindLightCdf,         lightCdf.getId());
        // Single unified RIS buffer at binding 5 — tiles in [0, tileCount*tileSize), ReGIR after.
        GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindRisBuffer,        risBuffer.getId());
        // Compact light data companion buffer at binding 6 — parallels the RIS buffer.
        GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindCompactLightData, compactLightData.getId());
    }

    // RTXDI: each build thread writes to its fixed slot.
    // Clear only the ReGIR region before dispatch — the presample pass already
    // filled the tile region.  A zero-clear is sufficient: build threads write
    // every owned slot, and any unwritten slot stays uvec2(0,0) (invalid).
    // glClearBufferSubData clears only the ReGIR sub-range.
    private void clearRegirRegion(GlMemoryManager risBuffer, int regirEntryOffset, int totalCells, int lightsPerCell) {
        long regirByteOffset = (long) regirEntryOffset * 8L; // 8 bytes per uvec2
        long regirByteSize   = (long) totalCells * lightsPerCell * 8L;
        GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, risBuffer.getId());
        GL43.glClearBufferSubData(GL43.GL_SHADER_STORAGE_BUFFER, GL30.GL_R32UI,
                regirByteOffset, regirByteSize, GL30.GL_RED_INTEGER, GL11.GL_UNSIGNED_INT, new int[]{0});
        GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, 0);
    }

    // Clear the entire compact light data buffer to zero before each frame's presample pass.
    // This ensures the compact-bit load path never reads leftover data from a previous frame.
    private void clearCompactLightDataBuffer(GlMemoryManager compactLightData) {
        GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, compactLightData.getId());
        GL43.glClearBufferData(GL43.GL_SHADER_STORAGE_BUFFER, GL30.GL_R32UI,
                GL30.GL_RED_INTEGER, GL11.GL_UNSIGNED_INT, new int[]{0});
        GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, 0);
    }

    // -----------------------------------------------------------------------
    // State queries
    // -----------------------------------------------------------------------
    public boolean isCompiled() {
        return this.compiled;
    }

    public boolean isPresampleCompiled() {
        return this.presampleCompiled;
    }

    // -----------------------------------------------------------------------
    // Cleanup
    // -----------------------------------------------------------------------
    public void destroy() {
        if (this.programId != 0) {
            GL20.glDeleteProgram(this.programId);
        }
        if (this.presampleProgramId != 0) {
            GL20.glDeleteProgram(this.presampleProgramId);
        }
        if (this.pdfTextureId != 0) {
            GL11.glDeleteTextures(this.pdfTextureId);
        }
        this.releasePdfUploadBuffer();

        this.programId          = 0;
        this.compiled           = false;
        this.presampleProgramId = 0;
        this.presampleCompiled  = false;
        this.pdfTextureId       = 0;
        this.pdfTextureWidth    = 0;
        this.pdfTextureHeight   = 0;
        this.pdfTextureMipLevels = 0;

        this.locGridCenter             = -1;
        this.locGridCells              = -1;
        this.locLightsPerCell          = -1;
        this.locCellSize               = -1;
        this.locLightCount             = -1;
        this.locFrameSeed              = -1;
        this.locTileSize               = -1;
        this.locTileCount              = -1;
        this.locBuildSamples           = -1;
        this.locSamplingJitter         = -1;
        this.locRisTileBufferOffset    = -1;
        this.locRegirRisBufferOffset   = -1;

        this.presampleLocLightCount     = -1;
        this.presampleLocTileSize       = -1;
        this.presampleLocTileCount      = -1;
        this.presampleLocFrameSeed      = -1;
        this.presampleLocPdfTextureSize = -1;
        this.presampleLocRisTileBufferOffset = -1;
    }
}
