package at.redi2go.photonic.client.rendering.validation;

import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class OfflineShaderValidationTest {
   @Test
   void validatesPhotonicsShaderEntrypointsWithExternalGlslValidator() throws IOException, InterruptedException {
      Path projectDir = requiredPathProperty("photonics.projectDir");
      Path buildDir = requiredPathProperty("photonics.buildDir");
      String validatorExecutable = requiredStringProperty("photonics.glslangValidator");

      OfflineShaderValidator validator = new OfflineShaderValidator(projectDir, buildDir, validatorExecutable);
      List<OfflineShaderValidator.ValidationFailure> failures;
      try {
         failures = validator.validateAll();
      } catch (IllegalStateException exception) {
         assumeTrue(false, exception.getMessage());
         return;
      }

      assertTrue(
         failures.isEmpty(),
         () -> failures.stream()
            .map(OfflineShaderValidationTest::formatFailure)
            .reduce((left, right) -> left + System.lineSeparator() + System.lineSeparator() + right)
            .orElse("Unknown shader validation failure")
      );
   }

   private static Path requiredPathProperty(String name) {
      String value = requiredStringProperty(name);
      return Path.of(value).toAbsolutePath().normalize();
   }

   private static String requiredStringProperty(String name) {
      String value = System.getProperty(name);
      assumeTrue(value != null && !value.isBlank(), "Missing required system property: " + name);
      return value;
   }

   private static String formatFailure(OfflineShaderValidator.ValidationFailure failure) {
      StringBuilder builder = new StringBuilder("Shader validation failed");
      for (Map.Entry<String, String> entry : failure.asReportFields().entrySet()) {
         builder.append(System.lineSeparator())
            .append("- ")
            .append(entry.getKey())
            .append(": ")
            .append(entry.getValue());
      }
      return builder.toString();
   }
}
