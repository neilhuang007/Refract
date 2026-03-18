package at.redi2go.photonic.client.config.lights;

import at.redi2go.photonic.client.config.lights.color.RgbColor;
import at.redi2go.photonic.client.config.lights.orientation.LightOrientation;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import org.joml.Vector3f;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class BlockLightInfoTest {
   @Test
   void luminanceAndRadiusScaleWithIntensity() {
      BlockLightInfo dim = createLightInfo(10.0F);
      BlockLightInfo bright = createLightInfo(100.0F);

      Vector3f lightPosition = new Vector3f(0.5F, 0.5F, 0.5F);
      Vector3f samplePosition = new Vector3f(4.5F, 0.5F, 0.5F);

      assertTrue(bright.luminanceFrom(lightPosition, samplePosition) > dim.luminanceFrom(lightPosition, samplePosition));
      assertTrue(bright.radiusInBlocks() > dim.radiusInBlocks());
   }

   private static BlockLightInfo createLightInfo(float intensity) {
      return new BlockLightInfo(
         new LightPredicate() {
            @Override
            public Block block() {
               return null;
            }

            @Override
            public int priority() {
               return LightPredicate.NORMAL_PRIORITY;
            }

            @Override
            public boolean test(CachedBlockPosition block) {
               return false;
            }
         },
         new RgbColor(255, 128, 64),
         intensity,
         16.0F,
         1.0F,
         true,
         true,
         LightOrientation.OMNI
      );
   }
}
