param(
    [switch]$NoBuild,
    [switch]$CaptureFrames,
    [int]$CaptureEveryN = 120,
    [int]$CaptureCount = 5,
    [string]$CaptureDir = "run/automation-captures",
    [string]$QuickPlayWorld = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "[1/3] Running patch validation tests..."
& .\gradlew.bat patchValidationTest

if (-not $NoBuild) {
    Write-Host "[2/3] Running clean build..."
    & .\gradlew.bat clean build
} else {
    Write-Host "[2/3] Skipping clean build (-NoBuild)."
}

if ($CaptureFrames) {
    Write-Host "[3/3] Starting runClient with automated frame capture."
    Write-Host "Captures are written to $CaptureDir"
    $runArgs = @(
        "-Dphotonics.automation.captureDir=$CaptureDir",
        "-Dphotonics.automation.captureEveryN=$CaptureEveryN",
        "-Dphotonics.automation.captureCount=$CaptureCount"
    )
    if (-not [string]::IsNullOrWhiteSpace($QuickPlayWorld)) {
        $runArgs += "--args=--quickPlaySingleplayer $QuickPlayWorld"
        Write-Host "Quick Play world: $QuickPlayWorld"
    }
    & .\gradlew.bat runClient @runArgs
} else {
    if (-not [string]::IsNullOrWhiteSpace($QuickPlayWorld)) {
        Write-Host "[3/3] Starting runClient with Quick Play world: $QuickPlayWorld"
        & .\gradlew.bat runClient "--args=--quickPlaySingleplayer $QuickPlayWorld"
    } else {
        Write-Host "[3/3] Frame capture launch skipped. Use -CaptureFrames to enable it."
    }
}
