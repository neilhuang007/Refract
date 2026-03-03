package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import java.util.List;

public interface CompositeRendererExt {
   List<PhotonicsShader> photonic$getPhotonicsShaders();

   void photonic$setPhotonicsShaders(List<PhotonicsShader> var1);
}
