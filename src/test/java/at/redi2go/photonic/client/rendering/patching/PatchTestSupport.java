package at.redi2go.photonic.client.rendering.patching;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

final class PatchTestSupport {
   private PatchTestSupport() {
   }

   static String applyPatch(String patchContent, String source) {
      List<String> anchors = extractReplaceAnchors(patchContent);
      List<String> replacements = extractReplaceBlocks(patchContent);
      assertEquals(anchors.size(), replacements.size(), "Anchor/replacement mismatch");

      String result = normalize(source);
      for (int i = 0; i < anchors.size(); i++) {
         String before = result;
         result = result.replace(anchors.get(i), replacements.get(i));
         assertNotEquals(before, result, "Replacement had no effect for anchor: " + anchors.get(i));
      }
      return result;
   }

   static List<String> extractReplaceAnchors(String patchContent) {
      List<String> anchors = new ArrayList<>();
      List<String> lines = normalize(patchContent).lines().toList();
      for (int i = 0; i < lines.size(); i++) {
         String line = lines.get(i);
         if (line.startsWith("#replace ")) {
            String rest = line.substring("#replace ".length());
            if (rest.startsWith("\"") && rest.endsWith("\"") && rest.length() > 1) {
               anchors.add(rest.substring(1, rest.length() - 1));
            } else if (rest.startsWith("\"")) {
               StringBuilder anchor = new StringBuilder(rest.substring(1));
               for (int j = i + 1; j < lines.size(); j++) {
                  String next = lines.get(j);
                  if (next.endsWith("\"")) {
                     anchor.append("\n").append(next, 0, next.length() - 1);
                     break;
                  }
                  anchor.append("\n").append(next);
               }
               anchors.add(anchor.toString());
            }
         }
      }
      return anchors;
   }

   static List<String> extractReplaceBlocks(String patchContent) {
      List<String> blocks = new ArrayList<>();
      List<String> lines = normalize(patchContent).lines().toList();
      int i = 0;
      while (i < lines.size()) {
         String line = lines.get(i);
         if (line.startsWith("#replace ")) {
            String rest = line.substring("#replace ".length());
            if (rest.startsWith("\"") && rest.endsWith("\"") && rest.length() > 1) {
               i++;
            } else if (rest.startsWith("\"")) {
               i++;
               while (i < lines.size() && !lines.get(i).endsWith("\"")) {
                  i++;
               }
               i++;
            }
            StringBuilder current = new StringBuilder();
            while (i < lines.size() && !lines.get(i).equals("#endreplace")) {
               current.append(lines.get(i)).append("\n");
               i++;
            }
            String block = current.toString();
            if (block.endsWith("\n")) {
               block = block.substring(0, block.length() - 1);
            }
            blocks.add(block);
         }
         i++;
      }
      return blocks;
   }

   static int countOccurrences(String source, String needle) {
      int count = 0;
      int index = 0;
      while ((index = source.indexOf(needle, index)) >= 0) {
         count++;
         index += needle.length();
      }
      return count;
   }

   private static String normalize(String source) {
      return source.replace("\r\n", "\n");
   }
}
