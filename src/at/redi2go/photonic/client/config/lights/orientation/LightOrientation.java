package at.redi2go.photonic.client.config.lights.orientation;

import com.google.gson.TypeAdapter;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import com.google.gson.stream.JsonWriter;
import java.io.IOException;
import org.joml.Vector3f;

public record LightOrientation(Vector3f axis, float orientationSpread, float emissionSpread) {
   public static final LightOrientation OMNI = new LightOrientation(new Vector3f(0.0F, 1.0F, 0.0F), (float) Math.PI, (float) (Math.PI * 0.5));

   public LightOrientation {
      axis = axis == null ? new Vector3f(0.0F, 1.0F, 0.0F) : new Vector3f(axis);
      if (axis.lengthSquared() <= 1.0e-8F) {
         axis.set(0.0F, 1.0F, 0.0F);
      } else {
         axis.normalize();
      }
   }

   public static final class Adapter extends TypeAdapter<LightOrientation> {
      @Override
      public void write(JsonWriter out, LightOrientation value) throws IOException {
         if (value == null) {
            out.nullValue();
            return;
         }
         out.beginObject();
         out.name("axis");
         out.beginArray();
         out.value(value.axis.x);
         out.value(value.axis.y);
         out.value(value.axis.z);
         out.endArray();
         out.name("orientation_spread");
         out.value(value.orientationSpread);
         out.name("emission_spread");
         out.value(value.emissionSpread);
         out.endObject();
      }

      @Override
      public LightOrientation read(JsonReader in) throws IOException {
         if (in.peek() == JsonToken.NULL) {
            in.nextNull();
            return LightOrientation.OMNI;
         }
         Vector3f axis = new Vector3f(0.0F, 1.0F, 0.0F);
         float orientationSpread = (float) Math.PI;
         float emissionSpread = (float) (Math.PI * 0.5);
         in.beginObject();
         while (in.hasNext() && in.peek() != JsonToken.END_OBJECT) {
            String name = in.nextName();
            switch (name) {
               case "axis" -> {
                  in.beginArray();
                  axis.x = (float) in.nextDouble();
                  axis.y = (float) in.nextDouble();
                  axis.z = (float) in.nextDouble();
                  in.endArray();
               }
               case "orientation_spread" -> orientationSpread = (float) in.nextDouble();
               case "emission_spread" -> emissionSpread = (float) in.nextDouble();
               default -> in.skipValue();
            }
         }
         in.endObject();
         return new LightOrientation(axis, orientationSpread, emissionSpread);
      }
   }
}
