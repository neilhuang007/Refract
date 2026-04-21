package at.redi2go.photonics.api.gpu.systems;

import at.redi2go.photonics.api.gpu.buffers.BufferUsage;
import at.redi2go.photonics.api.gpu.buffers.IGpuBuffer;
import at.redi2go.photonics.api.gpu.buffers.IGpuBufferSlice;
import at.redi2go.photonics.api.gpu.buffers.heap.DefaultGpuBufferHeap;
import at.redi2go.photonics.api.gpu.buffers.heap.IGpuBufferHeap;
import at.redi2go.photonics.api.gpu.textures.IAddressMode;
import at.redi2go.photonics.api.gpu.textures.IFilterMode;
import at.redi2go.photonics.api.gpu.textures.IGpuSampler;
import at.redi2go.photonics.api.gpu.textures.IGpuTexture;
import at.redi2go.photonics.api.gpu.textures.ITextureFormat;
import at.redi2go.photonics.api.gpu.textures.TextureUsage;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.OptionalDouble;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Supplier;
import org.jetbrains.annotations.Nullable;
import org.lwjgl.opengl.GL15;

public final class IRenderSystem {
    private static final IGpuDevice DEVICE = new GlGpuDevice();

    private IRenderSystem() {
    }

    public static IGpuDevice getDevice() {
        return DEVICE;
    }

    private static final class GlGpuDevice implements IGpuDevice {
        @Override
        public ICommandEncoder createCommandEncoder() {
            return new GlCommandEncoder();
        }

        @Override
        public IGpuSampler createSampler(
                IAddressMode addressModeU,
                IAddressMode addressModeV,
                IFilterMode minFilter,
                IFilterMode magFilter,
                int maxAnisotropy,
                OptionalDouble maxLod
        ) {
            return new NoopGpuSampler(addressModeU, addressModeV, minFilter, magFilter, maxAnisotropy, maxLod);
        }

        @Override
        public IGpuTexture createTexture(
                @Nullable Supplier<String> label,
                @TextureUsage int usage,
                ITextureFormat textureFormat,
                int width,
                int height,
                int depthOrLayers,
                int mipLevels
        ) {
            return new NoopGpuTexture(label == null ? "" : label.get(), usage, textureFormat, width, height, depthOrLayers, mipLevels);
        }

        @Override
        public IGpuBuffer createBuffer(
                @Nullable Supplier<String> label,
                long byteSize,
                @BufferUsage int usage
        ) {
            return new GlGpuBuffer(label, byteSize, usage);
        }

        @Override
        public IGpuBufferHeap createBufferHeap(
                @Nullable Supplier<String> label,
                long byteSize,
                @BufferUsage int usage
        ) {
            return new DefaultGpuBufferHeap(this, label, byteSize, usage);
        }
    }

    private static final class GlCommandEncoder implements ICommandEncoder {
        @Override
        public void clearColorTexture(IGpuTexture gpuTexture, int clearColor) {
        }

        @Override
        public void writeToBuffer(IGpuBuffer buffer, ByteBuffer byteBuffer) {
            if (!(buffer instanceof GlGpuBuffer glBuffer)) {
                throw new IllegalArgumentException("Unsupported buffer implementation: " + buffer.getClass().getName());
            }
            glBuffer.write(0, byteBuffer);
        }

        @Override
        public void writeToBuffer(IGpuBufferSlice slice, ByteBuffer byteBuffer) {
            if (!(slice instanceof GlGpuBufferSlice glSlice)) {
                throw new IllegalArgumentException("Unsupported buffer slice implementation: " + slice.getClass().getName());
            }
            glSlice.buffer.write(glSlice.offset, byteBuffer);
        }

        @Override
        public IGpuBuffer.MappedView mapBuffer(IGpuBuffer buffer, boolean readable, boolean writeable) {
            if (!(buffer instanceof GlGpuBuffer glBuffer)) {
                throw new IllegalArgumentException("Unsupported buffer implementation: " + buffer.getClass().getName());
            }
            return glBuffer.map(0, glBuffer.size());
        }

        @Override
        public IGpuBuffer.MappedView mapBuffer(IGpuBufferSlice bufferSlice, boolean readable, boolean writeable) {
            if (!(bufferSlice instanceof GlGpuBufferSlice glSlice)) {
                throw new IllegalArgumentException("Unsupported buffer slice implementation: " + bufferSlice.getClass().getName());
            }
            return glSlice.buffer.map(glSlice.offset, glSlice.length);
        }

        @Override
        public void copyToBuffer(IGpuBufferSlice slice1, IGpuBufferSlice slice2) {
            if (!(slice1 instanceof GlGpuBufferSlice src) || !(slice2 instanceof GlGpuBufferSlice dst)) {
                throw new IllegalArgumentException("Unsupported buffer slice implementation");
            }
            ByteBuffer copy = src.buffer.copyRange(src.offset, Math.min(src.length, dst.length));
            dst.buffer.write(dst.offset, copy);
        }

        @Override
        public void writeToTexture(
                IGpuTexture gpuTexture,
                ByteBuffer data,
                ITextureFormat format,
                int mipLevels,
                int cubeMapTarget,
                int offsetX,
                int offsetY,
                int width,
                int height
        ) {
        }
    }

    private static final class GlGpuBuffer implements IGpuBuffer {
        private static final AtomicLong NEXT_LABEL_ID = new AtomicLong();

        private final String label;
        private final long byteSize;
        private final int usage;
        private final ByteBuffer shadowBuffer;
        private int id;
        private boolean closed;

        private GlGpuBuffer(@Nullable Supplier<String> labelSupplier, long byteSize, int usage) {
            this.label = (labelSupplier == null ? "buffer" : labelSupplier.get()) + '-' + NEXT_LABEL_ID.incrementAndGet();
            this.byteSize = byteSize;
            this.usage = usage;
            this.shadowBuffer = ByteBuffer.allocateDirect(Math.toIntExact(byteSize)).order(ByteOrder.nativeOrder());
        }

        @Override
        public long size() {
            return byteSize;
        }

        @Override
        public int usage() {
            return usage;
        }

        @Override
        public boolean isClosed() {
            return closed;
        }

        @Override
        public IGpuBufferSlice slice(long offset, long length) {
            return new GlGpuBufferSlice(this, offset, length);
        }

        @Override
        public void close() {
            if (closed) {
                return;
            }
            closed = true;
            if (id != 0) {
                GL15.glDeleteBuffers(id);
                id = 0;
            }
        }

        private void ensureAllocated() {
            if (closed) {
                throw new IllegalStateException("Buffer already closed: " + label);
            }
            if (id != 0) {
                return;
            }
            id = GL15.glGenBuffers();
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, id);
            GL15.glBufferData(GL15.GL_ARRAY_BUFFER, shadowBuffer.capacity(), usageHint());
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        }

        private int usageHint() {
            return (usage & BufferUsage.MAP_WRITE) != 0 || (usage & BufferUsage.COPY_DST) != 0 ? GL15.GL_DYNAMIC_DRAW : GL15.GL_STATIC_DRAW;
        }

        private void write(long offset, ByteBuffer source) {
            ensureAllocated();
            int length = source.remaining();
            if (offset < 0 || offset + length > byteSize) {
                throw new IndexOutOfBoundsException("Write out of bounds");
            }

            ByteBuffer src = source.duplicate();
            ByteBuffer dst = shadowBuffer.duplicate().order(shadowBuffer.order());
            dst.position(Math.toIntExact(offset));
            dst.put(src);

            ByteBuffer upload = shadowBuffer.duplicate().order(shadowBuffer.order());
            upload.position(Math.toIntExact(offset));
            upload.limit(Math.toIntExact(offset + length));
            upload = upload.slice().order(shadowBuffer.order());

            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, id);
            GL15.glBufferSubData(GL15.GL_ARRAY_BUFFER, offset, upload);
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        }

        private IGpuBuffer.MappedView map(long offset, long length) {
            ByteBuffer duplicate = shadowBuffer.duplicate().order(shadowBuffer.order());
            duplicate.position(Math.toIntExact(offset));
            duplicate.limit(Math.toIntExact(offset + length));
            ByteBuffer slice = duplicate.slice().order(shadowBuffer.order());
            return new GlMappedView(slice);
        }

        private ByteBuffer copyRange(long offset, long length) {
            ByteBuffer duplicate = shadowBuffer.duplicate().order(shadowBuffer.order());
            duplicate.position(Math.toIntExact(offset));
            duplicate.limit(Math.toIntExact(offset + length));
            ByteBuffer copy = ByteBuffer.allocateDirect(Math.toIntExact(length)).order(shadowBuffer.order());
            copy.put(duplicate.slice().order(shadowBuffer.order()));
            copy.flip();
            return copy;
        }
    }

    private static final class GlMappedView implements IGpuBuffer.MappedView {
        private final ByteBuffer data;

        private GlMappedView(ByteBuffer data) {
            this.data = data;
        }

        @Override
        public ByteBuffer data() {
            return data;
        }

        @Override
        public void close() {
        }
    }

    private static final class GlGpuBufferSlice implements IGpuBufferSlice {
        private final GlGpuBuffer buffer;
        private final long offset;
        private final long length;

        private GlGpuBufferSlice(GlGpuBuffer buffer, long offset, long length) {
            this.buffer = buffer;
            this.offset = offset;
            this.length = length;
        }

        @Override
        public IGpuBuffer buffer() {
            return buffer;
        }

        @Override
        public long offset() {
            return offset;
        }

        @Override
        public long length() {
            return length;
        }

        @Override
        public IGpuBufferSlice slice(long offset, long length) {
            return new GlGpuBufferSlice(buffer, this.offset + offset, length);
        }
    }

    private record NoopGpuTexture(String label, int usage, ITextureFormat format, int width, int height, int depthOrLayers, int mipLevels) implements IGpuTexture {
        @Override
        public int getWidth(int mipLevel) {
            return Math.max(1, width >> mipLevel);
        }

        @Override
        public int getHeight(int mipLevel) {
            return Math.max(1, height >> mipLevel);
        }

        @Override
        public int getDepthOrLayers() {
            return depthOrLayers;
        }

        @Override
        public int mipLevels() {
            return mipLevels;
        }

        @Override
        public int usage() {
            return usage;
        }

        @Override
        public boolean isClosed() {
            return false;
        }

        @Override
        public void close() {
        }
    }

    private record NoopGpuSampler(
            IAddressMode addressModeU,
            IAddressMode addressModeV,
            IFilterMode minFilter,
            IFilterMode magFilter,
            int maxAnisotropy,
            OptionalDouble maxLod
    ) implements IGpuSampler {
        @Override
        public void close() {
        }
    }
}
