package at.redi2go.photonic.client.rendering.validation;

import at.redi2go.photonic.client.rendering.opengl.rendering.ShaderUtil;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

final class OfflineShaderValidator {
   private static final Pattern INCLUDE_PATTERN = Pattern.compile("(?m)^\\s*#include\\s+\"([^\"]+)\"\\s*$");

   private final Path projectDir;
   private final Path buildDir;
   private final String validatorExecutable;
   private final Path shaderRoot;
   private final Path outputRoot;

   OfflineShaderValidator(Path projectDir, Path buildDir, String validatorExecutable) {
      this.projectDir = Objects.requireNonNull(projectDir, "projectDir").toAbsolutePath().normalize();
      this.buildDir = Objects.requireNonNull(buildDir, "buildDir").toAbsolutePath().normalize();
      this.validatorExecutable = Objects.requireNonNull(validatorExecutable, "validatorExecutable").trim();
      this.shaderRoot = this.projectDir.resolve("assets/photonic/shaders");
      this.outputRoot = this.buildDir.resolve("shader-validation/resolved");
   }

   List<ValidationFailure> validateAll() throws IOException, InterruptedException {
      if (validatorExecutable.isBlank()) {
         throw new IllegalStateException("Missing GLSL validator executable. Set -PglslangValidator=/path/to/glslangValidator(.exe) or GLSLANG_VALIDATOR.");
      }

      if (Files.notExists(shaderRoot)) {
         throw new IllegalStateException("Shader root does not exist: " + shaderRoot);
      }

      Files.createDirectories(outputRoot);
      List<Path> entrypoints = discoverEntrypoints();
      List<ValidationFailure> failures = new ArrayList<>();
      for (Path entrypoint : entrypoints) {
         String resolvedSource = resolveFile(entrypoint, new ArrayDeque<>(), new LinkedHashSet<>());
         Path outputFile = writeResolvedSource(entrypoint, resolvedSource);
         ValidationFailure failure = validateResolvedSource(entrypoint, outputFile);
         if (failure != null) {
            failures.add(failure);
         }
      }
      return failures;
   }

   private List<Path> discoverEntrypoints() throws IOException {
      try (Stream<Path> paths = Files.walk(shaderRoot)) {
         return paths
            .filter(Files::isRegularFile)
            .filter(path -> {
               String relative = toUnix(shaderRoot.relativize(path));
               return !relative.startsWith("patches/") && (relative.endsWith(".vsh") || relative.endsWith(".fsh"));
            })
            .sorted(Comparator.comparing(path -> toUnix(shaderRoot.relativize(path))))
            .toList();
      }
   }

   private String resolveFile(Path file, Deque<Path> includeStack, LinkedHashSet<Path> visitedIncludes) throws IOException {
      Path normalized = file.toAbsolutePath().normalize();
      if (!normalized.startsWith(shaderRoot)) {
         throw new IllegalArgumentException("Include escapes shader root: " + normalized);
      }
      if (includeStack.contains(normalized)) {
         throw new IllegalStateException("Cyclic shader include: " + renderIncludeStack(includeStack, normalized));
      }

      includeStack.addLast(normalized);
      String source = preprocessSource(normalized, Files.readString(normalized, StandardCharsets.UTF_8));
      Matcher matcher = INCLUDE_PATTERN.matcher(source);
      StringBuilder flattened = new StringBuilder();
      int cursor = 0;
      while (matcher.find()) {
         flattened.append(source, cursor, matcher.start());
         String includeTarget = matcher.group(1);
         Path includeFile = resolveIncludeTarget(normalized, includeTarget);
         String includeKey = toUnix(shaderRoot.relativize(includeFile));
         flattened.append("// begin include ").append(includeKey).append('\n');
         flattened.append(resolveFile(includeFile, includeStack, visitedIncludes));
         if (!flattened.isEmpty() && flattened.charAt(flattened.length() - 1) != '\n') {
            flattened.append('\n');
         }
         flattened.append("// end include ").append(includeKey).append('\n');
         visitedIncludes.add(includeFile);
         cursor = matcher.end();
      }
      flattened.append(source.substring(cursor));
      includeStack.removeLast();
      return flattened.toString();
   }

   private String preprocessSource(Path file, String source) {
      String processed = source.replace("\r\n", "\n");
      String relative = toUnix(shaderRoot.relativize(file));
      if ("shader_interface.glsl".equals(relative)) {
         String biasedSurfacePosition = "world_pos = load_world_position() - 0.01f * world_normal;";
         if (processed.contains(biasedSurfacePosition)) {
            processed = processed.replace(
               biasedSurfacePosition,
               "// RTXDI expects the reconstructed surface position here; visibility offsets happen later.\n"
                  + "    world_pos = load_world_position();"
            );
         }
      }
      return ShaderUtil.preprocessForward(processed);
   }

   private Path resolveIncludeTarget(Path includingFile, String includeTarget) {
      Path resolved;
      if (includeTarget.startsWith("/")) {
         if (includeTarget.startsWith("/photonics/")) {
            resolved = shaderRoot.resolve(includeTarget.substring("/photonics/".length()));
         } else {
            resolved = shaderRoot.resolve(includeTarget.substring(1));
         }
      } else {
         resolved = includingFile.getParent().resolve(includeTarget);
      }
      resolved = resolved.normalize().toAbsolutePath();
      if (!resolved.startsWith(shaderRoot) || Files.notExists(resolved)) {
         throw new IllegalStateException("Unable to resolve include " + includeTarget + " from " + includingFile + " to an existing file under " + shaderRoot);
      }
      return resolved;
   }

   private Path writeResolvedSource(Path entrypoint, String resolvedSource) throws IOException {
      Path relative = shaderRoot.relativize(entrypoint);
      Path outputFile = outputRoot.resolve(relative.toString()).normalize();
      Files.createDirectories(outputFile.getParent());
      Files.writeString(outputFile, resolvedSource, StandardCharsets.UTF_8);
      return outputFile;
   }

   private ValidationFailure validateResolvedSource(Path originalFile, Path resolvedFile) throws IOException, InterruptedException {
      String stage = shaderStage(originalFile);
      ProcessBuilder processBuilder = new ProcessBuilder(validatorExecutable, "-S", stage, resolvedFile.toString());
      processBuilder.directory(projectDir.toFile());
      processBuilder.redirectErrorStream(true);
      Process process;
      try {
         process = processBuilder.start();
      } catch (IOException exception) {
         throw new IllegalStateException(
            "Failed to start GLSL validator '" + validatorExecutable + "'. Set -PglslangValidator=/path/to/glslangValidator(.exe) or GLSLANG_VALIDATOR.",
            exception
         );
      }

      String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
      int exitCode = process.waitFor();
      if (exitCode == 0) {
         return null;
      }

      return new ValidationFailure(toUnix(shaderRoot.relativize(originalFile)), resolvedFile, output.strip());
   }

   private static String shaderStage(Path file) {
      String name = file.getFileName().toString();
      if (name.endsWith(".vsh")) {
         return "vert";
      }
      if (name.endsWith(".fsh")) {
         return "frag";
      }
      throw new IllegalArgumentException("Unsupported shader entrypoint extension: " + file);
   }

   private static String renderIncludeStack(Deque<Path> includeStack, Path next) {
      List<String> chain = new ArrayList<>();
      for (Path path : includeStack) {
         chain.add(path.toString());
      }
      chain.add(next.toString());
      return String.join(" -> ", chain);
   }

   private static String toUnix(Path path) {
      return path.toString().replace('\\', '/');
   }

   record ValidationFailure(String shaderPath, Path resolvedFile, String diagnostics) {
      Map<String, String> asReportFields() {
         Map<String, String> fields = new LinkedHashMap<>();
         fields.put("shader", shaderPath);
         fields.put("resolvedFile", resolvedFile.toString());
         fields.put("diagnostics", diagnostics);
         return fields;
      }
   }
}
