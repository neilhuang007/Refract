package at.redi2go.photonic.client.rendering;

import net.minecraft.util.math.Vec3d;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.world.ClientWorld;
import org.joml.Vector3f;

public class MinecraftAccessor {
   public static Vector3f getCameraPosition() {
      Vec3d position = MinecraftClient.getInstance().gameRenderer.getCamera().getPos();
      return new Vector3f((float)position.x, (float)position.y, (float)position.z);
   }

   public static ClientWorld getLevel() {
      return MinecraftClient.getInstance().world;
   }
}
