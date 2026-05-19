package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import net.minecraft.block.BlockState;
import net.minecraft.util.math.BlockPos;
import org.jetbrains.annotations.Nullable;

/**
 * Immutable snapshot of a block state captured at the time a block-update notification arrives.
 * Shared between {@link WorldRegistry} and {@link BlockUpdateQueue}.
 */
record BlockUpdateSnapshot(BlockPos blockPos, BlockState blockState, @Nullable BlockLightInfo lightInfo) {
}
