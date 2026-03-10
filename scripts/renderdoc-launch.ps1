[CmdletBinding()]
param(
    [ValidateSet("All", "Client", "ShaderGameTestClient")]
    [string]$Target = "All",
    [string]$JavaExe = "",
    [string]$OutputDir = "",
    [string]$RenderDocCmd = "",
    [switch]$Launch,
    [switch]$WaitForExit
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot "run"
$launchCfg = Join-Path $repoRoot ".gradle/loom-cache/launch.cfg"
$buildGradle = Join-Path $repoRoot "build.gradle"

if (-not (Test-Path $launchCfg)) {
    throw "Missing Loom launch config at '$launchCfg'. Run a Loom client task first."
}

if (-not (Test-Path $buildGradle)) {
    throw "Missing build.gradle at '$buildGradle'."
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot "build/renderdoc"
}

function Get-JavaExecutable {
    param([string]$RequestedJavaExe)

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($RequestedJavaExe)) {
        $candidates.Add($RequestedJavaExe)
    }

    $candidates.Add("C:\Program Files\Zulu\zulu-21\bin\javaw.exe")
    $candidates.Add("C:\Users\neil_\.jdks\graalvm-jdk-21.0.7\bin\javaw.exe")

    try {
        $javaw = Get-Command javaw.exe -ErrorAction Stop
        $candidates.Add($javaw.Source)
    } catch {
        # Keep the fallback candidates only.
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Could not find a Java 21 javaw.exe. Pass -JavaExe explicitly."
}

function Get-RenderDocCommand {
    param([string]$RequestedRenderDocCmd)

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($RequestedRenderDocCmd)) {
        $candidates.Add($RequestedRenderDocCmd)
    }

    $candidates.Add("C:\Program Files\RenderDoc\renderdoccmd.exe")
    $candidates.Add("C:\Program Files (x86)\RenderDoc\renderdoccmd.exe")

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Could not find renderdoccmd.exe. Pass -RenderDocCmd explicitly."
}

function Format-JavaArg {
    param([string]$Arg)

    if ($Arg -match '[\s"]') {
        $escaped = $Arg.Replace('\', '\\').Replace('"', '\"')
        return '"' + $escaped + '"'
    }

    return $Arg
}

function Resolve-GradleInterpolation {
    param(
        [string]$Arg,
        [string]$RepoRoot
    )

    return [regex]::Replace(
        $Arg,
        "\$\{project\.projectDir\.toPath\(\)\.resolve\('([^']+)'\)\}",
        {
            param($match)
            $relativePath = $match.Groups[1].Value -replace '/', '\'
            return (Join-Path $RepoRoot $relativePath)
        }
    )
}

function Get-ShaderGameTestLaunchSettings {
    param(
        [string]$BuildGradlePath,
        [string]$RepoRoot
    )

    $programArgs = New-Object System.Collections.Generic.List[string]
    $vmArgs = New-Object System.Collections.Generic.List[string]
    $insideBlock = $false
    $braceDepth = 0

    foreach ($line in Get-Content $BuildGradlePath) {
        if (-not $insideBlock) {
            if ($line -match '^\s*shaderGameTestClient\s*\{') {
                $insideBlock = $true
                $braceDepth = ([regex]::Matches($line, '\{')).Count - ([regex]::Matches($line, '\}')).Count
            }
            continue
        }

        if ($line -match '^\s*programArg\s+"([^"]*)"\s*$') {
            $programArgs.Add($matches[1])
        } elseif ($line -match '^\s*vmArg\s+"([^"]*)"\s*$') {
            $vmArgs.Add((Resolve-GradleInterpolation -Arg $matches[1] -RepoRoot $RepoRoot))
        }

        $braceDepth += ([regex]::Matches($line, '\{')).Count - ([regex]::Matches($line, '\}')).Count
        if ($braceDepth -le 0) {
            break
        }
    }

    if ($programArgs.Count -eq 0 -and $vmArgs.Count -eq 0) {
        throw "Could not find the shaderGameTestClient run block in '$BuildGradlePath'."
    }

    return [PSCustomObject]@{
        ProgramArgs = $programArgs
        VmArgs = $vmArgs
    }
}

function New-RenderDocArgsFile {
    param(
        [string]$TaskName,
        [string[]]$AdditionalVmArgs,
        [string[]]$ProgramArgs,
        [string]$RepoRoot,
        [string]$LaunchCfg,
        [string]$DestinationDir
    )

    $loomArgFile = Join-Path $RepoRoot "build/loom-cache/argFiles/$TaskName"
    if (-not (Test-Path $loomArgFile)) {
        throw "Missing Loom arg file '$loomArgFile'. Run '.\gradlew.bat $TaskName' once first."
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content $loomArgFile) {
        $lines.Add($line)
    }

    $lines.Add("-Dfabric.dli.config=$LaunchCfg")
    $lines.Add("-Dfabric.dli.env=client")
    $lines.Add("-Dfabric.dli.main=net.fabricmc.loader.impl.launch.knot.KnotClient")

    foreach ($vmArg in $AdditionalVmArgs) {
        $lines.Add($vmArg)
    }

    $lines.Add("net.fabricmc.devlaunchinjector.Main")

    foreach ($programArg in $ProgramArgs) {
        $lines.Add($programArg)
    }

    $formattedLines = foreach ($line in $lines) {
        Format-JavaArg -Arg $line
    }

    $destinationPath = Join-Path $DestinationDir "$TaskName.args.txt"
    Set-Content -Path $destinationPath -Value $formattedLines -Encoding ASCII

    return $destinationPath
}

$resolvedJavaExe = Get-JavaExecutable -RequestedJavaExe $JavaExe
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$targets = @()
switch ($Target) {
    "All" {
        $targets += "runClient"
        $targets += "runShaderGameTestClient"
    }
    "Client" {
        $targets += "runClient"
    }
    "ShaderGameTestClient" {
        $targets += "runShaderGameTestClient"
    }
}

$shaderGameTestSettings = $null
if ($targets -contains "runShaderGameTestClient") {
    $shaderGameTestSettings = Get-ShaderGameTestLaunchSettings -BuildGradlePath $buildGradle -RepoRoot $repoRoot
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($taskName in $targets) {
    $additionalVmArgs = @()
    $programArgs = @()

    if ($taskName -eq "runShaderGameTestClient") {
        $additionalVmArgs = $shaderGameTestSettings.VmArgs
        $programArgs = $shaderGameTestSettings.ProgramArgs
    }

    $argsPath = New-RenderDocArgsFile `
        -TaskName $taskName `
        -AdditionalVmArgs $additionalVmArgs `
        -ProgramArgs $programArgs `
        -RepoRoot $repoRoot `
        -LaunchCfg $launchCfg `
        -DestinationDir $OutputDir

    $results.Add([PSCustomObject]@{
        TaskName = $taskName
        ArgsPath = $argsPath
    })
}

$summaryPath = Join-Path $OutputDir "renderdoc-launch.txt"
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("RenderDoc launch settings for photonics")
$summary.Add("")
$summary.Add("Executable")
$summary.Add($resolvedJavaExe)
$summary.Add("")
$summary.Add("Working directory")
$summary.Add($runDir)
$summary.Add("")
$summary.Add("Command line arguments")
foreach ($result in $results) {
    $summary.Add("$($result.TaskName): @$($result.ArgsPath)")
}
$summary.Add("")
$summary.Add("Notes")
$summary.Add("- runShaderGameTestClient mirrors the current Fabric Loom shaderGameTestClient block in build.gradle.")
$summary.Add("- Re-run scripts/renderdoc-launch.ps1 after changing dependencies or Loom run settings.")

Set-Content -Path $summaryPath -Value $summary -Encoding ASCII

foreach ($result in $results) {
    Write-Host ""
    Write-Host "$($result.TaskName)"
    Write-Host "  Executable: $resolvedJavaExe"
    Write-Host "  Working dir: $runDir"
    Write-Host "  Args: @$($result.ArgsPath)"
}

Write-Host ""
Write-Host "Summary written to $summaryPath"

if ($Launch) {
    if ($results.Count -ne 1) {
        throw "Launching requires exactly one target. Use -Target Client or -Target ShaderGameTestClient."
    }

    $resolvedRenderDocCmd = Get-RenderDocCommand -RequestedRenderDocCmd $RenderDocCmd
    $captureDir = Join-Path $OutputDir "captures"
    New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

    $selected = $results[0]
    $captureTemplate = Join-Path $captureDir $selected.TaskName
    $renderDocArgs = @(
        "capture",
        "--working-dir", $runDir,
        "--capture-file", $captureTemplate
    )

    if ($WaitForExit) {
        $renderDocArgs += "--wait-for-exit"
    }

    $renderDocArgs += $resolvedJavaExe
    $renderDocArgs += "@$($selected.ArgsPath)"

    Write-Host "Launching $($selected.TaskName) through RenderDoc..."
    Write-Host "RenderDoc command: $resolvedRenderDocCmd"
    Write-Host "Capture output prefix: $captureTemplate"
    Write-Host "Press F12 in Minecraft to capture a frame."

    & $resolvedRenderDocCmd @renderDocArgs
}
