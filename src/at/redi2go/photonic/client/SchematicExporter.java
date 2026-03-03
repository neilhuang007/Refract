package at.redi2go.photonic.client;

import at.redi2go.photonic.client.magicavoxel.VoxWriter;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.stream.StreamSupport;
import java.util.zip.ZipOutputStream;
import net.minecraft.block.Block;
import net.minecraft.block.BlockState;
import net.minecraft.state.property.Property;
import net.minecraft.util.Pair;
import net.minecraft.registry.Registries;

public class SchematicExporter {
   private final BlockState[] blockStates;
   private final Map<Long, Pair<BlockState, Schematic>> baseCases = new HashMap<>();
   private final ZipWriteContext writeContext;
   private int index;

   public SchematicExporter(File folder) throws FileNotFoundException {
      File zipFile = new File(folder, "schematics.zip");
      if (zipFile.exists()) {
         zipFile.delete();
      }

      this.blockStates = StreamSupport.<Block>stream(Registries.BLOCK.spliterator(), false)
         .flatMap(block -> block.getStateManager().getStates().stream())
         .map(BlockRegistry::cleanUpBlockState)
         .filter(Objects::nonNull)
         .distinct()
         .toArray(BlockState[]::new);
      this.writeContext = new ZipWriteContext(new ZipOutputStream(new FileOutputStream(zipFile)), 16384);
   }

   public boolean exportOne() {
      if (this.index >= this.blockStates.length) {
         try {
            this.writeContext.getZipOutputStream().close();
            return false;
         } catch (IOException var5) {
            throw new RuntimeException(var5);
         }
      } else {
         BlockState blockState = this.blockStates[this.index++];
         BlockState defaultBlockState = blockState.getBlock().getDefaultState();

         for (Property<?> property : blockState.getProperties()) {
            if (BlockRegistry.DEFAULT_PROPERTIES.contains(property) && !blockState.get(property).equals(defaultBlockState.get(property))) {
               return true;
            }
         }

         exportBlockState(this.writeContext, blockState, this.baseCases);
         return true;
      }
   }

   public float getProgress() {
      return (float)this.index / this.blockStates.length;
   }

   private static void exportBlockState(ZipWriteContext writeContext, BlockState blockState, Map<Long, Pair<BlockState, Schematic>> baseCases) {
      if (!blockState.isAir()) {
         Schematic schematic = BlockBuilder.buildBlockSchematic(blockState);
         schematic.calcRotationHash();
         int[] targetHash = schematic.getHashVector();
         int ax = Math.abs(targetHash[0]);
         int ay = Math.abs(targetHash[1]);
         int az = Math.abs(targetHash[2]);
         long hash = (long)ax * ax + (long)ay * ay + (long)az * az;
         Pair<BlockState, Schematic> baseCase = baseCases.get(hash);
         if (baseCase != null) {
            writeContext.write(
               BlockRegistry.encodeBlockState(blockState) + ".alias",
               new String[]{
                  BlockRegistry.encodeBlockState((BlockState)baseCase.getLeft()),
                  BlockRegistry.encodeTransformation(((Schematic)baseCase.getRight()).getHashVector(), targetHash)
               }
            );
         } else {
            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            VoxWriter.writeFromSchematic(schematic, byteArrayOutputStream);
            writeContext.write(BlockRegistry.encodeBlockState(blockState) + ".vox", byteArrayOutputStream.toByteArray());
            baseCases.put(hash, new Pair(blockState, schematic));
         }
      }
   }
}
