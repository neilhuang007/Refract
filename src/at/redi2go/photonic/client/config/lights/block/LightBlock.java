package at.redi2go.photonic.client.config.lights.block;

import at.redi2go.photonic.client.config.Variable;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import com.google.gson.TypeAdapter;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import com.google.gson.stream.JsonWriter;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import java.io.IOException;
import java.util.List;

public interface LightBlock {
   Variable.Type<LightBlock> TYPE = new Variable.Type<>("light_block");

   List<LightPredicate> listPredicates() throws CommandSyntaxException;

   class Adapter extends TypeAdapter<LightBlock> {
      public static String PRIORITY_NAME = "priority";
      public static String VALUE_NAME = "value";

      public void write(JsonWriter out, LightBlock lightBlock) throws IOException {
         if (lightBlock instanceof DefaultLightBlock dlb) {
            out.value(dlb.value());
         } else if (lightBlock instanceof LightBlockWithPriority lbwp) {
            out.beginObject();
            out.name(PRIORITY_NAME);
            out.value(lbwp.priority());
            out.name(VALUE_NAME);
            out.value(lbwp.value());
            out.endObject();
         } else {
            out.nullValue();
         }
      }

      public LightBlock read(JsonReader in) throws IOException {
         switch (in.peek()) {
            case STRING:
               String str = in.nextString();
               if (!str.isEmpty() && str.charAt(0) == '*') {
                  return new LightBlockVariable(str.substring(1), Integer.MIN_VALUE);
               }
               return new DefaultLightBlock(str);
            case BEGIN_OBJECT:
               in.beginObject();
               String value = null;
               int priority = Integer.MIN_VALUE;
               while (in.hasNext() && in.peek() != JsonToken.END_OBJECT) {
                  String name = in.nextName();
                  switch (name) {
                     case "priority":
                        priority = in.nextInt();
                        break;
                     case "value":
                        value = in.nextString();
                        break;
                     default:
                        throw new IOException("unexpected name '" + name + "'");
                  }
               }
               in.endObject();
               if (value == null) {
                  throw new IOException("missing value for block");
               }
               if (!value.isEmpty() && value.charAt(0) == '*') {
                  return new LightBlockVariable(value.substring(1), priority);
               }
               return new LightBlockWithPriority(value, priority);
            default:
               throw new IOException("unexpected token " + in.peek());
         }
      }
   }
}
