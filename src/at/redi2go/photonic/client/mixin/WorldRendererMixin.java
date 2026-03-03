package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import net.minecraft.text.Text;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.Camera;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.client.render.GameRenderer;
import net.minecraft.client.render.WorldRenderer;
import net.minecraft.client.render.LightmapTextureManager;
import net.minecraft.client.render.RenderTickCounter;
import net.minecraft.text.Text.Serialization;
import org.jetbrains.annotations.Nullable;
import org.joml.Matrix4f;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(WorldRenderer.class)
public abstract class WorldRendererMixin {
   @Shadow
   @Nullable
   private ClientWorld world;
   @Unique
   private static boolean initialMessageSent = false;

   @Inject(
      method = "renderLevel",
      at = @At(
         value = "INVOKE",
         target = "Lnet/minecraft/client/renderer/LevelRenderer;renderSectionLayer(Lnet/minecraft/client/renderer/RenderType;DDDLorg/joml/Matrix4f;Lorg/joml/Matrix4f;)V",
         ordinal = 0
      )
   )
   public void renderSectionLayer0(
      RenderTickCounter deltaTracker,
      boolean bl,
      Camera camera,
      GameRenderer gameRenderer,
      LightmapTextureManager lightTexture,
      Matrix4f matrix4f,
      Matrix4f matrix4f2,
      CallbackInfo ci
   ) {
      if (!Raytracer.isDisabled()) {
         Raytracer.INSTANCE.getMainRenderer().setup();
      }
   }

   @Inject(method = "renderLevel", at = @At("TAIL"))
   public void renderLevelTail(
      RenderTickCounter deltaTracker,
      boolean bl,
      Camera camera,
      GameRenderer gameRenderer,
      LightmapTextureManager lightTexture,
      Matrix4f matrix4f,
      Matrix4f matrix4f2,
      CallbackInfo ci
   ) {
      if (!Raytracer.isDisabled() && !initialMessageSent && this.world != null) {
         String initialMessage = "[\"\",{\"text\":\"Thank you for trying out \"},{\"text\":\"Photonics\",\"color\":\"red\"},{\"text\":\"!\\nRemember that this is a \"},{\"text\":\"Beta\",\"color\":\"dark_aqua\"},{\"text\":\" version of my raytracing mod, bugs are expected! If you experience a bug, please report them on my Github. Thank you! (I'm using my freetime to develop this mod and it took me 3 years to get to this point, so please be friendly and leave feedback)\\n\\nReminder:\\n- You can enable \"},{\"text\":\"Multi-Threading\",\"color\":\"green\"},{\"text\":\" for increased loading speeds in the mod settings, might break some things, though\\n\\nHave fun!\"}]";
         Text initialMessageText = Serialization.fromJson(initialMessage, this.world.getRegistryManager());
         if (initialMessageText != null) {
            MinecraftClient.getInstance().inGameHud.getChatHud().addMessage(initialMessageText);
         }

         initialMessageSent = true;
      }
   }
}
