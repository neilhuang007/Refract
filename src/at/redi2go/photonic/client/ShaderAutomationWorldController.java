package at.redi2go.photonic.client;

import java.util.function.IntConsumer;
import net.minecraft.client.MinecraftClient;

public final class ShaderAutomationWorldController {
   private final long[] timeOfDaySequence;
   private final int timeOfDayStartActiveTick;
   private final int timeOfDayStepTicks;
   private final int blockToggleStartActiveTick;
   private final int blockTogglePeriodTicks;
   private final int blockToggleCount;
   private final int worldPrepActiveTick;
   private final IntConsumer burstCaptureCallback;

   private int automationBlockX = Integer.MIN_VALUE;
   private int automationBlockY = Integer.MIN_VALUE;
   private int automationBlockZ = Integer.MIN_VALUE;
   private int timeOfDayCommandsIssued = 0;
   private int blockToggleCommandsIssued = 0;
   private int lastAutomationCommandActiveTick = Integer.MIN_VALUE;
   private boolean worldAutomationPrepared = false;

   public ShaderAutomationWorldController(
      long[] timeOfDaySequence,
      int timeOfDayStartActiveTick,
      int timeOfDayStepTicks,
      int blockToggleStartActiveTick,
      int blockTogglePeriodTicks,
      int blockToggleCount,
      int worldPrepActiveTick,
      IntConsumer burstCaptureCallback
   ) {
      this.timeOfDaySequence = timeOfDaySequence;
      this.timeOfDayStartActiveTick = timeOfDayStartActiveTick;
      this.timeOfDayStepTicks = timeOfDayStepTicks;
      this.blockToggleStartActiveTick = blockToggleStartActiveTick;
      this.blockTogglePeriodTicks = blockTogglePeriodTicks;
      this.blockToggleCount = blockToggleCount;
      this.worldPrepActiveTick = worldPrepActiveTick;
      this.burstCaptureCallback = burstCaptureCallback;
   }

   public void applyWorldAutomation(int activeTicks, MinecraftClient client) {
      if (client.world == null || client.player == null || client.getServer() == null) {
         return;
      }

      this.prepareWorldAutomation(activeTicks, client);
      this.applyTimeOfDayAutomation(activeTicks, client);
      this.applyBlockToggleAutomation(activeTicks, client);
   }

   private void prepareWorldAutomation(int activeTicks, MinecraftClient client) {
      if (this.worldAutomationPrepared || activeTicks < this.worldPrepActiveTick) {
         return;
      }

      boolean prepared = true;
      prepared &= this.executeServerCommand(activeTicks, client, "gamerule doDaylightCycle false");
      prepared &= this.executeServerCommand(activeTicks, client, "gamerule doWeatherCycle false");
      prepared &= this.executeServerCommand(activeTicks, client, "gamerule randomTickSpeed 0");
      prepared &= this.executeServerCommand(activeTicks, client, "gamerule doMobSpawning false");
      prepared &= this.executeServerCommand(activeTicks, client, "gamerule doFireTick false");
      prepared &= this.executeServerCommand(activeTicks, client, "weather clear");
      if (prepared) {
         this.worldAutomationPrepared = true;
         this.burstCaptureCallback.accept(2);
      }
   }

   private void applyTimeOfDayAutomation(int activeTicks, MinecraftClient client) {
      if (this.timeOfDaySequence.length == 0 || activeTicks < this.timeOfDayStartActiveTick) {
         return;
      }

      int sequenceIndex = (activeTicks - this.timeOfDayStartActiveTick) / this.timeOfDayStepTicks;
      if (sequenceIndex < 0 || sequenceIndex >= this.timeOfDaySequence.length || sequenceIndex < this.timeOfDayCommandsIssued) {
         return;
      }

      long timeOfDay = this.timeOfDaySequence[sequenceIndex];
      if (this.executeServerCommand(activeTicks, client, "time set " + timeOfDay)) {
         this.timeOfDayCommandsIssued = sequenceIndex + 1;
         this.burstCaptureCallback.accept(3);
      }
   }

   private void applyBlockToggleAutomation(int activeTicks, MinecraftClient client) {
      if (this.blockToggleCount <= 0 || activeTicks < this.blockToggleStartActiveTick) {
         return;
      }

      int toggleIndex = (activeTicks - this.blockToggleStartActiveTick) / this.blockTogglePeriodTicks;
      if (toggleIndex < 0 || toggleIndex >= this.blockToggleCount || toggleIndex < this.blockToggleCommandsIssued) {
         return;
      }

      this.ensureAutomationBlockTarget(client);
      if (this.automationBlockX == Integer.MIN_VALUE) {
         return;
      }

      String command = (toggleIndex & 1) == 0
         ? "setblock " + this.automationBlockX + " " + this.automationBlockY + " " + this.automationBlockZ + " minecraft:glowstone replace"
         : "setblock " + this.automationBlockX + " " + this.automationBlockY + " " + this.automationBlockZ + " minecraft:air destroy";
      if (this.executeServerCommand(activeTicks, client, command)) {
         this.blockToggleCommandsIssued = toggleIndex + 1;
         this.burstCaptureCallback.accept(3);
      }
   }

   private void ensureAutomationBlockTarget(MinecraftClient client) {
      if (this.automationBlockX != Integer.MIN_VALUE || client.player == null) {
         return;
      }

      double yawRadians = Math.toRadians(client.player.getYaw());
      this.automationBlockX = (int)Math.floor(client.player.getX() - Math.sin(yawRadians) * 3.0);
      this.automationBlockY = (int)Math.floor(client.player.getY());
      this.automationBlockZ = (int)Math.floor(client.player.getZ() + Math.cos(yawRadians) * 3.0);
   }

   private boolean executeServerCommand(int activeTicks, MinecraftClient client, String command) {
      if (client.getServer() == null) {
         return false;
      }

      try {
         client.getServer().execute(() -> client.getServer().getCommandManager().executeWithPrefix(client.getServer().getCommandSource(), command));
         this.lastAutomationCommandActiveTick = activeTicks;
         Photonic.info("[Automation] command activeTicks={} command={}", activeTicks, command);
         return true;
      } catch (RuntimeException e) {
         Photonic.warn("[Automation] command failed activeTicks={} command={} error={}", activeTicks, command, e.toString());
         return false;
      }
   }

   public int getTimeOfDayCommandsIssued() {
      return this.timeOfDayCommandsIssued;
   }

   public int getBlockToggleCommandsIssued() {
      return this.blockToggleCommandsIssued;
   }

   public boolean isWorldAutomationPrepared() {
      return this.worldAutomationPrepared;
   }

   public long[] getTimeOfDaySequence() {
      return this.timeOfDaySequence;
   }

   public int getTimeOfDayStartActiveTick() {
      return this.timeOfDayStartActiveTick;
   }

   public int getTimeOfDayStepTicks() {
      return this.timeOfDayStepTicks;
   }

   public int getBlockToggleStartActiveTick() {
      return this.blockToggleStartActiveTick;
   }

   public int getBlockTogglePeriodTicks() {
      return this.blockTogglePeriodTicks;
   }

   public int getBlockToggleCount() {
      return this.blockToggleCount;
   }

   public int getWorldPrepActiveTick() {
      return this.worldPrepActiveTick;
   }

   public int ticksSinceLastCommand(int activeTicks) {
      return this.lastAutomationCommandActiveTick == Integer.MIN_VALUE
         ? Integer.MAX_VALUE
         : Math.max(0, activeTicks - this.lastAutomationCommandActiveTick);
   }
}
