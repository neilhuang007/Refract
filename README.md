# photonics

A Fabric mod for Minecraft 1.21.1 that adds real-time voxel ray tracing with ReSTIR direct illumination, SVGF denoising, and hierarchical Morton-coded traversal. Designed as a companion to Iris shader packs such as Complementary Reimagined and Euphoria Patches.

## Building

Requires Java 21. Build and run unit tests with Gradle:

```bash
./gradlew build
./gradlew test
```

## Shader Automation Testing

The project includes a runtime shader automation system that launches a Minecraft client, verifies the ray tracing pipeline is active with the expected shader pack, captures rendered attachment textures, and then shuts down the client automatically. This provides end-to-end validation that the mod initializes correctly, the raytracer produces visible lighting output, and no error patterns appear in the client log.

### Running the shader game test

The `shaderGameTest` Gradle task orchestrates the full automation cycle. It requires a pre-existing singleplayer world save at `run/saves/New World/` with the target shader pack already configured.

```bash
./gradlew shaderGameTest
```

This task performs the following steps in order:

1. Cleans prior automation artifacts from `run/automation/`.
2. Launches the `shaderGameTestClient` run configuration, which starts Minecraft with Quick Play pointing at the saved world and all `photonics.automation.*` system properties enabled.
3. After the client exits, validates the generated report at `run/automation/shader-report.properties` against pass/fail criteria.

### Automation output

The `ShaderAutomation` class writes its results to two locations under `run/automation/`:

- `shader-report.properties` -- a Java properties file recording tick counts, capture counts, shader pack name, raytracer activity, lighting signal detection, per-attachment max luminance values, and the overall success/failure status with a reason string.
- `captures/` -- PNG images of rendered attachment textures (direct, direct_soft, handheld) captured at configurable intervals during the automation run.

### Configurable system properties

All automation behavior is controlled through JVM system properties set in the `shaderGameTestClient` Loom run configuration in `build.gradle`:

| Property | Default | Purpose |
|----------|---------|---------|
| `photonics.automation.enabled` | `false` | Enables the automation system |
| `photonics.automation.worldName` | (empty) | World name recorded in the report |
| `photonics.automation.autoStartWorld` | `false` | Whether to auto-start the world (Quick Play handles this) |
| `photonics.automation.startDelayTicks` | `0` | Ticks to wait after raytracer activation before capturing |
| `photonics.automation.timeoutTicks` | `1200` | Maximum ticks before the automation times out |
| `photonics.automation.expectedShaderPack` | (empty) | Expected shader pack name for validation |
| `photonics.automation.expectedPatchIdPrefix` | (empty) | Optional required prefix for the runtime `patchId` (for example `OCTRAY:`) |
| `photonics.lightingMode` | shader pack/default | Overrides the effective Photonics lighting mode for automation or local testing |
| `photonics.automation.reportFile` | `run/automation/shader-report.properties` | Path for the report output |
| `photonics.automation.captureDir` | `run/automation/captures` | Directory for captured attachment images |
| `photonics.automation.captureEveryN` | `60` | Capture one frame every N rendered frames |
| `photonics.automation.captureCount` | `1` | Number of captures to take before finishing |
| `photonics.automation.autoStop` | `false` | Shuts down the client after automation completes |

### Pass/fail validation

The `shaderGameTest` task reads the report and fails the build if any of the following conditions are not met:

- The report file exists and indicates `success=true`.
- The expected shader pack was matched (normalized comparison handles version suffixes and Euphoria/Complementary aliases).
- The raytracer was active during the run.
- A lighting signal was detected (at least one attachment had non-zero luminance).
- The required number of frame captures were taken.
- If `photonics.automation.expectedPatchIdPrefix` is set, the runtime `patchId` begins with that prefix.
- The client log at `run/logs/latest.log` contains profiler evidence for both `[Profiler] compileWorld:` and `[Profiler] upload:` and does not contain forbidden error patterns such as `NullPointerException` or shader option resolution failures.

### Unit tests

The `ShaderAutomationTest` class covers the shader pack name matching logic (including normalization of version suffixes, punctuation, and the Euphoria/Complementary alias mapping) and the luminance computation against known pixel values.

## Additional Gradle tasks

| Task | Description |
|------|-------------|
| `test` | Runs all JUnit 5 unit tests |
| `patchValidationTest` | Runs shader patch validation tests only |
| `automationValidation` | Runs patch validation tests and a full build |
| `shaderGameTest` | Full shader runtime smoke test with report validation |
| `gameTest` | Alias for `shaderGameTest` |
| `renderdocPrepareClient` | Generates RenderDoc launch files for the default client |
| `renderdocPrepareShaderGameTest` | Generates RenderDoc launch files for the shader game test client |
| `renderdocClient` | Launches the default client through RenderDoc |
| `renderdocShaderGameTest` | Launches the shader game test client through RenderDoc |
