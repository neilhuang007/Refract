package at.redi2go.photonic.client.config.adapter;

import com.google.gson.TypeAdapter;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonWriter;
import java.io.IOException;
import net.minecraft.block.Block;
import net.minecraft.registry.Registries;
import net.minecraft.util.Identifier;

public class BlockAdapter extends TypeAdapter<Block> {
   public void write(JsonWriter out, Block value) throws IOException {
      out.value(toString(value));
   }

   public Block read(JsonReader in) throws IOException {
      return fromString(in.nextString());
   }

   public static String toString(Block block) {
      return Registries.BLOCK.getId(block).toString();
   }

   public static Block fromString(String str) {
      return Registries.BLOCK.get(Identifier.of(str));
   }
}
