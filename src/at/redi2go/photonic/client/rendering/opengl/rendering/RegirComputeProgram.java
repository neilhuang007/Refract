package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import org.joml.Vector3f;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL42;
import org.lwjgl.opengl.GL43;

public class RegirComputeProgram {

    // -----------------------------------------------------------------------
    // ReGIR build program (regir_build.glsl)
    // -----------------------------------------------------------------------
    private int programId = 0;
    private boolean compiled = false;

    private int locGridCenter = -1;
    private int locGridResolution = -1;
    private int locLightsPerCell = -1;
    private int locCellSize = -1;
    private int locLightCount = -1;
    private int locFrameSeed = -1;
    private int locTileSize = -1;
    private int locTileCount = -1;
    private int locBuildSamples = -1;
    private int locSamplingJitter = -1;

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

    // -----------------------------------------------------------------------
    // PDF mipmap texture (RTXDI 2D R32F texture for light flux)
    // -----------------------------------------------------------------------
    private int pdfTextureId = 0;
    private int pdfTextureSize = 0;   // width = height (square, power of 2)
    private int pdfTextureMipLevels = 0;
    private static final int bindPdfTextureUnit = 0; // texture unit for sampler2D

    // -----------------------------------------------------------------------
    // SSBO binding points
    // -----------------------------------------------------------------------
    private static final int bindLightList     = 0;
    private static final int bindLightCdf      = 1;
    // binding 2 unused — no cell counts SSBO (RTXDI uses fixed-position writes)
    private static final int bindRegirOutput   = 3;  // uvec2 ReGIR output buffer (replaces indices+pdfs)
    // binding 4 unused — merged into bindRegirOutput
    private static final int bindRisTileBuffer = 5;

    // -----------------------------------------------------------------------
    // RIS tile buffer parameters
    // RTXDI defaults: tileSize = 1024, tileCount = 128.
    // We use tileSize = 256 to keep dispatch count at 128*256/256 = 128 groups.
    // -----------------------------------------------------------------------
    private static final int tileSize  = 256;
    private static final int tileCount = 128;

    // GPU-side RIS tile buffer SSBO
    private int tileBufferId = 0;

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
        this.locGridCenter     = GL20.glGetUniformLocation(this.programId, "ph_regir_grid_center");
        this.locGridResolution = GL20.glGetUniformLocation(this.programId, "ph_regir_grid_resolution");
        this.locLightsPerCell  = GL20.glGetUniformLocation(this.programId, "ph_regir_lights_per_cell");
        this.locCellSize       = GL20.glGetUniformLocation(this.programId, "ph_regir_cell_size");
        this.locLightCount     = GL20.glGetUniformLocation(this.programId, "ph_light_count");
        this.locFrameSeed      = GL20.glGetUniformLocation(this.programId, "ph_ris_frame_index");
        this.locTileSize       = GL20.glGetUniformLocation(this.programId, "ph_ris_tile_size");
        this.locTileCount      = GL20.glGetUniformLocation(this.programId, "ph_ris_tile_count");
        this.locBuildSamples   = GL20.glGetUniformLocation(this.programId, "ph_regir_build_samples");
        this.locSamplingJitter = GL20.glGetUniformLocation(this.programId, "ph_regir_sampling_jitter");
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
        this.createTileBuffer();

        Photonic.info("[RegirCompute] Presample shader compiled (programId={})", program);
    }

    private void cachePresampleUniformLocations() {
        this.presampleLocLightCount      = GL20.glGetUniformLocation(this.presampleProgramId, "ph_light_count");
        this.presampleLocTileSize        = GL20.glGetUniformLocation(this.presampleProgramId, "ph_ris_tile_size");
        this.presampleLocTileCount       = GL20.glGetUniformLocation(this.presampleProgramId, "ph_ris_tile_count");
        this.presampleLocFrameSeed       = GL20.glGetUniformLocation(this.presampleProgramId, "ph_ris_frame_index");
        this.presampleLocPdfTextureSize  = GL20.glGetUniformLocation(this.presampleProgramId, "ph_pdf_texture_size");
    }

    // -----------------------------------------------------------------------
    // RIS tile buffer creation
    // -----------------------------------------------------------------------
    private void createTileBuffer() {
        if (this.tileBufferId != 0) return;
        this.tileBufferId = GL15.glGenBuffers();
        int bufferSize = tileCount * tileSize * 8; // 8 bytes per uvec2
        GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, this.tileBufferId);
        GL15.glBufferData(GL43.GL_SHADER_STORAGE_BUFFER, bufferSize, GL15.GL_DYNAMIC_DRAW);
        GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, 0);
        Photonic.info("[RegirCompute] RIS tile buffer created ({}×{} entries, {} bytes)",
                tileCount, tileSize, bufferSize);
    }

    // -----------------------------------------------------------------------
    // PDF texture helpers (matching RTXDI ComputePdfTextureSize / Z-curve)
    // -----------------------------------------------------------------------
    private static int computePdfTextureSize(int maxLights) {
        double w = Math.max(1.0, Math.ceil(Math.sqrt(maxLights)));
        w = Math.pow(2, Math.ceil(Math.log(w) / Math.log(2)));
        return (int) w; // square power-of-2
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

    // -----------------------------------------------------------------------
    // PDF texture creation / update
    // -----------------------------------------------------------------------
    public void createPdfTexture(int maxLights) {
        if (this.pdfTextureId != 0) return;
        this.pdfTextureSize = computePdfTextureSize(maxLights);
        this.pdfTextureMipLevels = (int) (Math.log(this.pdfTextureSize) / Math.log(2)) + 1;

        this.pdfTextureId = GL11.glGenTextures();
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, this.pdfTextureId);
        // Immutable storage with all mip levels
        GL42.glTexStorage2D(GL11.GL_TEXTURE_2D, this.pdfTextureMipLevels, GL30.GL_R32F, this.pdfTextureSize, this.pdfTextureSize);
        // Nearest filtering — we need exact texel values, no interpolation
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST_MIPMAP_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL13.GL_CLAMP_TO_EDGE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL13.GL_CLAMP_TO_EDGE);
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, 0);

        Photonic.info("[RegirCompute] PDF texture created ({}x{}, {} mip levels, textureId={})",
                this.pdfTextureSize, this.pdfTextureSize, this.pdfTextureMipLevels, this.pdfTextureId);
    }

    public void updatePdfTexture(float[] lightPowers, int lightCount) {
        if (this.pdfTextureId == 0) return;

        // Fill a zero-initialised buffer (texture may be larger than lightCount)
        int texelCount = this.pdfTextureSize * this.pdfTextureSize;
        float[] texData = new float[texelCount];

        // Write each light's power at its Z-curve position
        for (int i = 0; i < lightCount && i < texelCount; i++) {
            int[] zc = linearToZCurve(i);
            int x = zc[0];
            int y = zc[1];
            if (x < this.pdfTextureSize && y < this.pdfTextureSize) {
                texData[y * this.pdfTextureSize + x] = lightPowers[i];
            }
        }

        // Upload to mip 0 and generate the full mip chain
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, this.pdfTextureId);
        GL11.glTexSubImage2D(GL11.GL_TEXTURE_2D, 0, 0, 0,
                this.pdfTextureSize, this.pdfTextureSize,
                GL11.GL_RED, GL11.GL_FLOAT, texData);
        GL30.glGenerateMipmap(GL11.GL_TEXTURE_2D);
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, 0);
    }

    // -----------------------------------------------------------------------
    // Dispatch — runs presample tiles then ReGIR build
    // -----------------------------------------------------------------------
    /**
     * Dispatches the presample-tiles pass followed by the ReGIR build pass.
     *
     * @param regirOutput   uvec2 SSBO — merged ReGIR output buffer (replaces separate index+pdf SSBOs)
     * @param gridCenter    world-space center of the ReGIR grid (= camera position)
     * @param numBuildSamples RTXDI default = 8 (ReGIR.h:141)
     * @param samplingJitter  RTXDI default = 1.0
     */
    public void dispatch(
            GlMemoryManager lightList,
            GlMemoryManager lightCdf,
            GlMemoryManager regirOutput,
            Vector3f gridCenter,
            int gridResolution,
            int lightsPerCell,
            float cellSize,
            int lightCount,
            int frameCounter,
            int numBuildSamples,
            float samplingJitter) {

        if (!this.compiled) return;

        // RTXDI: both passes receive the raw frame index as frameIndex
        // (no LCG hashing — Jenkins hash inside the shader handles decorrelation)

        // Pass 1: presample tiles (RTXDI_PresampleLocalLights)
        if (this.presampleCompiled && this.tileBufferId != 0) {
            GL20.glUseProgram(this.presampleProgramId);

            GL20.glUniform1i(this.presampleLocLightCount, lightCount);
            GL20.glUniform1i(this.presampleLocTileSize,   tileSize);
            GL20.glUniform1i(this.presampleLocTileCount,  tileCount);
            GL30.glUniform1ui(this.presampleLocFrameSeed, frameCounter);

            GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindRisTileBuffer, this.tileBufferId);

            // Bind PDF mipmap texture and set its uniforms
            if (this.pdfTextureId != 0) {
                GL13.glActiveTexture(GL13.GL_TEXTURE0 + bindPdfTextureUnit);
                GL11.glBindTexture(GL11.GL_TEXTURE_2D, this.pdfTextureId);
                GL20.glUniform1i(
                        GL20.glGetUniformLocation(this.presampleProgramId, "u_LocalLightPdfTexture"),
                        bindPdfTextureUnit);
                GL20.glUniform2i(this.presampleLocPdfTextureSize, this.pdfTextureSize, this.pdfTextureSize);
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

        this.setUniforms(gridCenter, gridResolution, lightsPerCell, cellSize, lightCount, frameCounter, numBuildSamples, samplingJitter);
        this.bindBuildSsbos(lightList, lightCdf, regirOutput);
        this.clearRegirOutputBuffer(regirOutput);

        GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);

        int totalSlots    = gridResolution * gridResolution * gridResolution * lightsPerCell;
        int workGroupSize = 256; // matches layout(local_size_x = 256) in regir_build.glsl
        int numGroups     = (totalSlots + workGroupSize - 1) / workGroupSize;
        GL43.glDispatchCompute(numGroups, 1, 1);

        GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);

        GL20.glUseProgram(0);
    }

    private void setUniforms(Vector3f gridCenter, int gridResolution, int lightsPerCell,
                              float cellSize, int lightCount, int frameSeed,
                              int numBuildSamples, float samplingJitter) {
        GL20.glUniform3f(this.locGridCenter,     gridCenter.x, gridCenter.y, gridCenter.z);
        GL20.glUniform1i(this.locGridResolution, gridResolution);
        GL20.glUniform1i(this.locLightsPerCell,  lightsPerCell);
        GL20.glUniform1f(this.locCellSize,        cellSize);
        GL20.glUniform1i(this.locLightCount,      lightCount);
        GL30.glUniform1ui(this.locFrameSeed,      frameSeed);
        GL20.glUniform1i(this.locTileSize,        tileSize);
        GL20.glUniform1i(this.locTileCount,       tileCount);
        GL30.glUniform1ui(this.locBuildSamples,   numBuildSamples);
        GL20.glUniform1f(this.locSamplingJitter,  samplingJitter);
    }

    private void bindBuildSsbos(
            GlMemoryManager lightList,
            GlMemoryManager lightCdf,
            GlMemoryManager regirOutput) {
        GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindLightList,   lightList.getId());
        GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindLightCdf,    lightCdf.getId());
        // Unified uvec2 ReGIR output buffer (replaces separate indices + pdfs)
        GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindRegirOutput, regirOutput.getId());
        if (this.presampleCompiled && this.tileBufferId != 0) {
            GL30.glBindBufferBase(GL43.GL_SHADER_STORAGE_BUFFER, bindRisTileBuffer, this.tileBufferId);
        }
    }

    // RTXDI: each thread writes to its fixed slot.
    // Clear the unified uvec2 output buffer to zeros before dispatch.
    // A zero-clear is sufficient: the build shader writes every slot it owns (RTXDI
    // fixed-position model), and any slot NOT written stays as uvec2(0,0) which the
    // per-pixel reader treats as invalid because invSourcePdf (y) == 0.
    // glClearBufferData with GL_R32UI fills every 32-bit word with 0, covering both
    // components of each uvec2 entry.
    private void clearRegirOutputBuffer(GlMemoryManager regirOutput) {
        GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, regirOutput.getId());
        GL43.glClearBufferData(GL43.GL_SHADER_STORAGE_BUFFER, GL30.GL_R32UI, GL11.GL_RED, GL11.GL_UNSIGNED_INT, new int[]{0});
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
        if (this.tileBufferId != 0) {
            GL15.glDeleteBuffers(this.tileBufferId);
        }
        if (this.pdfTextureId != 0) {
            GL11.glDeleteTextures(this.pdfTextureId);
        }

        this.programId          = 0;
        this.compiled           = false;
        this.presampleProgramId = 0;
        this.presampleCompiled  = false;
        this.tileBufferId       = 0;
        this.pdfTextureId       = 0;
        this.pdfTextureSize     = 0;
        this.pdfTextureMipLevels = 0;

        this.locGridCenter      = -1;
        this.locGridResolution  = -1;
        this.locLightsPerCell   = -1;
        this.locCellSize        = -1;
        this.locLightCount      = -1;
        this.locFrameSeed       = -1;
        this.locTileSize        = -1;
        this.locTileCount       = -1;
        this.locBuildSamples    = -1;
        this.locSamplingJitter  = -1;

        this.presampleLocLightCount     = -1;
        this.presampleLocTileSize       = -1;
        this.presampleLocTileCount      = -1;
        this.presampleLocFrameSeed      = -1;
        this.presampleLocPdfTextureSize = -1;
    }
}
