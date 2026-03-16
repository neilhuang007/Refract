package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.world.LightBlock;
import at.redi2go.photonic.client.rendering.world.LightType;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.Map.Entry;
import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.block.Block;
import net.minecraft.util.Identifier;
import net.minecraft.registry.Registries;
import org.joml.Vector2f;
import org.joml.Vector3f;

public class StorageIO {
   public static final File STORAGE_FILE = resolveStorageFile();

   private static File resolveStorageFile() {
      try {
         Path gameDir = FabricLoader.getInstance().getGameDir();
         if (gameDir != null) {
            return gameDir.resolve("ph_config.txt").toFile();
         }
      } catch (Throwable ignored) {
      }

      return new File("ph_config.txt");
   }

   public static boolean readBoolean(String[] booleanString, boolean elseBoolean) {
      return booleanString == null ? elseBoolean : Boolean.parseBoolean(booleanString[0]);
   }

   public static String[] writeBoolean(boolean bool) {
      return new String[]{Boolean.toString(bool)};
   }

   public static float readFloat(String[] floatString, float elseFloat) {
      if (floatString == null) {
         return elseFloat;
      }

      try {
         return Float.parseFloat(floatString[0]);
      } catch (NumberFormatException var3) {
         return elseFloat;
      }
   }

   public static String[] writeFloat(float value) {
      return new String[]{Float.toString(value)};
   }

   public static String readString(String[] valueString, String elseValue) {
      return valueString == null || valueString.length == 0 ? elseValue : valueString[0];
   }

   public static String[] writeString(String value) {
      return value == null || value.isBlank() ? new String[0] : new String[]{value};
   }

   public static Collection<Block> readBlocks(String[] blocksString, Collection<Block> elseBlocks) {
      return (Collection<Block>)(blocksString == null
         ? elseBlocks
         : Arrays.stream(blocksString).map(blockString -> (Block)Registries.BLOCK.get(Identifier.of(blockString))).toList());
   }

   public static String[] writeBlocks(Collection<Block> blocks) {
      return blocks.stream().map(block -> Registries.BLOCK.getId(block).toString()).toList().toArray(new String[0]);
   }

   public static Collection<LightBlock> readLightBlocks(String[] lightBlocksString, Collection<LightBlock> defaultLightBlocks) {
      return (Collection<LightBlock>)(lightBlocksString == null
         ? defaultLightBlocks
         : Arrays.stream(lightBlocksString)
            .map(
               lightBlockString -> {
                  String[] blockStringSplit = lightBlockString.split(";");
                  return new LightBlock(
                     (Block)Registries.BLOCK.get(Identifier.of(blockStringSplit[0])),
                     new LightType(
                        new Vector3f(Float.parseFloat(blockStringSplit[1]), Float.parseFloat(blockStringSplit[2]), Float.parseFloat(blockStringSplit[3])),
                        new Vector2f(Float.parseFloat(blockStringSplit[4]), Float.parseFloat(blockStringSplit[5])),
                        Boolean.parseBoolean(blockStringSplit[6])
                     )
                  );
               }
            )
            .toList());
   }

   public static String[] writeLightBlocks(Set<LightBlock> lightBlocks) {
      return lightBlocks.stream()
         .map(
            lightBlock -> Registries.BLOCK.getId(lightBlock.block)
               + ";"
               + lightBlock.lightType.getColor().x
               + ";"
               + lightBlock.lightType.getColor().y
               + ";"
               + lightBlock.lightType.getColor().z
               + ";"
               + lightBlock.lightType.getAttenuation().x
               + ";"
               + lightBlock.lightType.getAttenuation().y
               + ";"
               + lightBlock.lightType.isTraced()
         )
         .toList()
         .toArray(new String[0]);
   }

   public static Map<String, String[]> readConfig() {
      Map<String, String[]> config = new HashMap<>();

      try {
         for (String line : Files.readAllLines(STORAGE_FILE.toPath())) {
            int keyValueSeparator = line.indexOf("=");
            if (keyValueSeparator != -1) {
               String key = line.substring(0, keyValueSeparator);
               String[] value = line.substring(keyValueSeparator + 1).split(" ");
               config.put(key, value);
            }
         }
      } catch (IOException var7) {
      }

      return config;
   }

   public static void writeConfig(Map<String, String[]> config) {
      StringBuilder configStringBuilder = new StringBuilder();

      for (Entry<String, String[]> entry : config.entrySet()) {
         if (entry.getValue().length != 0) {
            configStringBuilder.append(entry.getKey()).append("=").append(String.join(" ", entry.getValue())).append("\n");
         }
      }

      try {
         Files.writeString(STORAGE_FILE.toPath(), configStringBuilder.toString());
      } catch (IOException var4) {
      }
   }
}
