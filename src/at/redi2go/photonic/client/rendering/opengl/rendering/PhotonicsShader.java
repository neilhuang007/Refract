package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.function.Supplier;

public class PhotonicsShader {
   private List<Entry<Integer, GlMemoryManager>> foundGlMemories;
   private final String fragmentName;
   private final String vertexName;
   private final GLMemoryCollection memoryCollection;
   private final ColorFramebuffer framebuffer;

   public PhotonicsShader(String fragmentName, String vertexName, GLMemoryCollection memoryCollection, ColorFramebuffer framebuffer) {
      this.fragmentName = fragmentName;
      this.vertexName = vertexName;
      this.memoryCollection = memoryCollection;
      this.framebuffer = framebuffer;
   }

   public void bindFramebuffer() {
      Raytracer.CURRENT_FRAMEBUFFER = this.framebuffer;
   }

   public void bind(int shaderId) {
      if (this.foundGlMemories == null) {
         this.foundGlMemories = new ArrayList<>();

         for (Supplier<GlMemoryManager> glMemoryManagerSupplier : this.memoryCollection) {
            GlMemoryManager glMemoryManager = glMemoryManagerSupplier.get();
            int blockIndex = glMemoryManager.findInProgram(shaderId);
            if (blockIndex != -1) {
               this.foundGlMemories.add(Map.entry(blockIndex, glMemoryManager));
            }
         }
      }

      int bindingPointIndex = 0;

      for (Entry<Integer, GlMemoryManager> glMemoryManager : this.foundGlMemories) {
         glMemoryManager.getValue().bind(shaderId, glMemoryManager.getKey(), bindingPointIndex++);
      }

      if (this.framebuffer != null) {
         this.framebuffer.bind();
      }
   }

   public String getFragmentName() {
      return this.fragmentName;
   }

   public String getVertexName() {
      return this.vertexName;
   }
}
