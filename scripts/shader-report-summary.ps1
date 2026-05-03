param(
  [string]$LogPath = (Join-Path (Get-Location) 'run/shaderGameTest.stdout.log'),
  [string]$ReportPath = (Join-Path (Get-Location) 'run/automation/shader-report.properties'),
  [string]$BaselinePath = (Join-Path (Get-Location) 'run/automation/shader-report-summary-baseline.json'),
  [string]$LatestSummaryPath = (Join-Path (Get-Location) 'run/automation/shader-report-summary-latest.json'),
  [switch]$NoWriteBaseline
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$passNames = @(
  'LightTreeSamplingStage', 'InitialCandidates', 'DITemporalResampling', 'DISpatialResampling', 'DIShadeSamples',
  'NRDClassifyTiles', 'NRDHitDistReconstruction', 'NRDPrepass',
  'RELAXTemporalAccumulation', 'RELAXHistoryFix', 'RELAXHistoryClamping',
  'NRDCopy', 'RELAXAntiFirefly', 'RELAXAtrousSmem', 'RELAXAtrous',
  'ReSTIRGI', 'IndirectDenoise', 'LightingAccumulation', 'IndirectComposite'
)

function Read-PropertiesMap {
  param([string]$Path)

  $properties = @{}
  if (!(Test-Path $Path)) {
    return $properties
  }

  foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#')) {
      continue
    }

    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2) {
      $properties[$parts[0]] = $parts[1]
    }
  }

  return $properties
}

function Get-Percentile {
  param(
    [double[]]$Values,
    [double]$Percentile
  )

  if ($Values.Count -eq 0) {
    return 0.0
  }

  $sorted = @($Values | Sort-Object)
  $index = [Math]::Ceiling(($Percentile / 100.0) * $sorted.Count) - 1
  $index = [Math]::Max(0, [Math]::Min($sorted.Count - 1, $index))
  return [double]$sorted[$index]
}

function New-Stats {
  param([double[]]$Values)

  if ($Values.Count -eq 0) {
    return [ordered]@{ count = 0; avgMs = 0.0; p95Ms = 0.0; maxMs = 0.0 }
  }

  $sum = 0.0
  $max = 0.0
  foreach ($value in $Values) {
    $sum += $value
    $max = [Math]::Max($max, $value)
  }

  return [ordered]@{
    count = $Values.Count
    avgMs = [Math]::Round($sum / $Values.Count, 3)
    p95Ms = [Math]::Round((Get-Percentile -Values $Values -Percentile 95.0), 3)
    maxMs = [Math]::Round($max, 3)
  }
}

function Get-MapValue {
  param(
    [hashtable]$Map,
    [string]$Key,
    [string]$Default = '0'
  )

  if ($Map.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$Map[$Key])) {
    return [string]$Map[$Key]
  }

  return $Default
}

$passSamples = @{}
foreach ($name in $passNames) {
  $passSamples[$name] = New-Object System.Collections.Generic.List[double]
}

$fpsSamples = New-Object System.Collections.Generic.List[double]
if (Test-Path $LogPath) {
  $content = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
  $normalizedLines = ($content -replace "`r", '') -replace "`n(?!(\[[0-9]{2}:|.*\[Profiler\]))", ' '
  foreach ($line in ($normalizedLines -split "`n")) {
    if ($line -match '\[Profiler\] RTXDI/NRD GPU passes:') {
      foreach ($name in $passNames) {
        $match = [regex]::Match($line, [regex]::Escape($name) + '=([0-9]+)us')
        if ($match.Success) {
          $passSamples[$name].Add(([double]$match.Groups[1].Value) / 1000.0)
        }
      }
    } elseif ($line -match '\[Profiler\] FPS: current=([0-9.]+)') {
      $fpsSamples.Add([double]$matches[1])
    }
  }
}

$passes = [ordered]@{}
foreach ($name in $passNames) {
  $passes[$name] = New-Stats -Values ([double[]]$passSamples[$name].ToArray())
}

$props = Read-PropertiesMap -Path $ReportPath
$totalSamples = New-Object System.Collections.Generic.List[double]
$sampleCount = 0
if ($passNames.Count -gt 0) {
  $sampleCount = $passSamples[$passNames[0]].Count
}
for ($i = 0; $i -lt $sampleCount; $i++) {
  $total = 0.0
  foreach ($name in $passNames) {
    $total += $passSamples[$name][$i]
  }
  $totalSamples.Add($total)
}

$summary = [ordered]@{
  generatedAt = (Get-Date).ToString('o')
  logPath = $LogPath
  reportPath = $ReportPath
  success = ($props['success'] -eq 'true')
  fps = [ordered]@{
    current = [double](Get-MapValue -Map $props -Key 'currentFps')
    avg = [double](Get-MapValue -Map $props -Key 'avgFps')
    min = [double](Get-MapValue -Map $props -Key 'minFps')
    max = [double](Get-MapValue -Map $props -Key 'maxFps')
    profilerAvg = (New-Stats -Values ([double[]]$fpsSamples.ToArray())).avgMs
  }
  gpuTotal = New-Stats -Values ([double[]]$totalSamples.ToArray())
  passes = $passes
  scene = [ordered]@{
    fullscreen = $props['fullscreen']
    fullscreenApplied = $props['fullscreenApplied']
    renderedFrames = [int](Get-MapValue -Map $props -Key 'renderedFrames')
    capturesTaken = [int](Get-MapValue -Map $props -Key 'capturesTaken')
    latestTracedLightCount = [int](Get-MapValue -Map $props -Key 'latestTracedLightCount')
    latestTotalLightCount = [int](Get-MapValue -Map $props -Key 'latestTotalLightCount')
    latestLightSelectionCapped = $props['latestLightSelectionCapped']
  }
}

Write-Output '--- shader performance summary ---'
Write-Output ("success={0} fps(avg={1:n2}, min={2:n2}, max={3:n2}) gpuTotal(avg={4:n3}ms, p95={5:n3}ms, max={6:n3}ms, samples={7})" -f
  $summary.success,
  $summary.fps.avg,
  $summary.fps.min,
  $summary.fps.max,
  $summary.gpuTotal.avgMs,
  $summary.gpuTotal.p95Ms,
  $summary.gpuTotal.maxMs,
  $summary.gpuTotal.count)

$topPasses = @($passNames | Sort-Object { -$passes[$_].avgMs } | Select-Object -First 8)
foreach ($name in $topPasses) {
  $stat = $passes[$name]
  Write-Output ("pass {0}: avg={1:n3}ms p95={2:n3}ms max={3:n3}ms samples={4}" -f $name, $stat.avgMs, $stat.p95Ms, $stat.maxMs, $stat.count)
}

if (Test-Path $BaselinePath) {
  try {
    $baseline = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $deltaTotal = $summary.gpuTotal.avgMs - [double]$baseline.gpuTotal.avgMs
    $deltaFps = $summary.fps.avg - [double]$baseline.fps.avg
    Write-Output ("baseline delta: gpuTotalAvg={0:+0.000;-0.000;0.000}ms fpsAvg={1:+0.00;-0.00;0.00}" -f $deltaTotal, $deltaFps)
  } catch {
    Write-Output "baseline delta: unreadable baseline $BaselinePath"
  }
} else {
  Write-Output "baseline delta: none ($BaselinePath not found)"
}

$summaryJson = $summary | ConvertTo-Json -Depth 8
$summaryParent = Split-Path -Parent $LatestSummaryPath
if ($summaryParent -and !(Test-Path $summaryParent)) {
  New-Item -ItemType Directory -Path $summaryParent | Out-Null
}
Set-Content -LiteralPath $LatestSummaryPath -Value $summaryJson -Encoding UTF8

if (!(Test-Path $BaselinePath) -and !$NoWriteBaseline) {
  Set-Content -LiteralPath $BaselinePath -Value $summaryJson -Encoding UTF8
  Write-Output "baseline initialized: $BaselinePath"
}
