package at.redi2go.photonic.client;

import java.util.function.BooleanSupplier;
import net.minecraft.client.MinecraftClient;

public final class ShaderAutomationCameraController {
   private final String cameraMotionMode;
   private final int cameraMotionStartActiveTick;
   private final int cameraMotionPeriodTicks;
   private final float cameraYawAmplitudeDegrees;
   private final float cameraPitchAmplitudeDegrees;
   private final BooleanSupplier stableSceneCheck;

   private float baselineCameraYaw = 0.0f;
   private float baselineCameraPitch = 0.0f;
   private float motionYawOffsetMin = 0.0f;
   private float motionYawOffsetMax = 0.0f;
   private float motionPitchOffsetMin = 0.0f;
   private float motionPitchOffsetMax = 0.0f;
   private int cameraMotionAppliedTicks = 0;
   private boolean cameraBaselineCaptured = false;

   public ShaderAutomationCameraController(
      String cameraMotionMode,
      int cameraMotionStartActiveTick,
      int cameraMotionPeriodTicks,
      float cameraYawAmplitudeDegrees,
      float cameraPitchAmplitudeDegrees,
      BooleanSupplier stableSceneCheck
   ) {
      this.cameraMotionMode = cameraMotionMode;
      this.cameraMotionStartActiveTick = cameraMotionStartActiveTick;
      this.cameraMotionPeriodTicks = cameraMotionPeriodTicks;
      this.cameraYawAmplitudeDegrees = cameraYawAmplitudeDegrees;
      this.cameraPitchAmplitudeDegrees = cameraPitchAmplitudeDegrees;
      this.stableSceneCheck = stableSceneCheck;
   }

   public boolean isEnabled() {
      return !"none".equals(this.cameraMotionMode)
         && this.cameraMotionPeriodTicks > 0
         && (this.cameraYawAmplitudeDegrees > 0.0f || this.cameraPitchAmplitudeDegrees > 0.0f);
   }

   public void applyCameraMotion(int activeTicks, MinecraftClient client) {
      if (!this.isEnabled() || client.player == null || !this.stableSceneCheck.getAsBoolean()) {
         return;
      }

      if (!this.cameraBaselineCaptured) {
         this.cameraBaselineCaptured = true;
         this.baselineCameraYaw = client.player.getYaw();
         this.baselineCameraPitch = client.player.getPitch();
      }

      float yawOffset = ShaderAutomationValidators.computeSineMotionOffset(activeTicks, this.cameraMotionStartActiveTick, this.cameraMotionPeriodTicks, this.cameraYawAmplitudeDegrees);
      float pitchOffset = ShaderAutomationValidators.computeSineMotionOffset(
         activeTicks + Math.max(this.cameraMotionPeriodTicks / 4, 1),
         this.cameraMotionStartActiveTick,
         this.cameraMotionPeriodTicks,
         this.cameraPitchAmplitudeDegrees
      );
      float targetYaw = this.baselineCameraYaw + yawOffset;
      float targetPitch = clampPitch(this.baselineCameraPitch + pitchOffset);

      client.player.setYaw(targetYaw);
      client.player.setPitch(targetPitch);
      client.player.setHeadYaw(targetYaw);
      client.player.setBodyYaw(targetYaw);

      if (activeTicks >= this.cameraMotionStartActiveTick) {
         this.cameraMotionAppliedTicks++;
         this.motionYawOffsetMin = Math.min(this.motionYawOffsetMin, yawOffset);
         this.motionYawOffsetMax = Math.max(this.motionYawOffsetMax, yawOffset);
         this.motionPitchOffsetMin = Math.min(this.motionPitchOffsetMin, pitchOffset);
         this.motionPitchOffsetMax = Math.max(this.motionPitchOffsetMax, pitchOffset);
      }
   }

   private static float clampPitch(float pitch) {
      return Math.max(-89.0f, Math.min(89.0f, pitch));
   }

   public String getCameraMotionMode() {
      return this.cameraMotionMode;
   }

   public int getCameraMotionStartActiveTick() {
      return this.cameraMotionStartActiveTick;
   }

   public int getCameraMotionPeriodTicks() {
      return this.cameraMotionPeriodTicks;
   }

   public float getCameraYawAmplitudeDegrees() {
      return this.cameraYawAmplitudeDegrees;
   }

   public float getCameraPitchAmplitudeDegrees() {
      return this.cameraPitchAmplitudeDegrees;
   }

   public float getBaselineCameraYaw() {
      return this.baselineCameraYaw;
   }

   public float getBaselineCameraPitch() {
      return this.baselineCameraPitch;
   }

   public float getMotionYawOffsetMin() {
      return this.motionYawOffsetMin;
   }

   public float getMotionYawOffsetMax() {
      return this.motionYawOffsetMax;
   }

   public float getMotionPitchOffsetMin() {
      return this.motionPitchOffsetMin;
   }

   public float getMotionPitchOffsetMax() {
      return this.motionPitchOffsetMax;
   }

   public int getCameraMotionAppliedTicks() {
      return this.cameraMotionAppliedTicks;
   }
}
