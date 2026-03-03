package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.Set;
import org.joml.Matrix4f;
import org.joml.Vector3f;

public interface IRenderDispatcher {
   TextureObject getTextureObject(String var1);

   Set<PChunkPos> getInboundChunks();

   boolean isChunkEmpty(PChunkPos var1);

   Matrix4f getModelViewProjectionMatrix(Vector3f var1);

   Vector3f getHandheldColor();

   boolean isLeftHanded();

   void onChunkLoad();
}
