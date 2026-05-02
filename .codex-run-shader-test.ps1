param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$GradleArgs
)

# Force console output to UTF-8 so Write-Output never hits
# "Windows stdio does not support writing non-UTF-8 byte sequences".
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

$stdout = Join-Path (Get-Location) 'run/shaderGameTest.stdout.log'
$stderr = Join-Path (Get-Location) 'run/shaderGameTest.stderr.log'
$latestLog = Join-Path (Get-Location) 'run/logs/latest.log'
$reportFile = Join-Path (Get-Location) 'run/automation/shader-report.properties'
$fatalPatterns = @(
  'Failed to create shader rendering pipeline',
  'The shaderpack failed to load!',
  'MixinApplyError',
  'InvalidMixinException',
  'ClassNotFoundException',
  'Could not execute entrypoint stage ''preLaunch''',
  'A mod crashed on startup!'
)

function Convert-ToCleanUtf8Text {
  param([string]$Text)

  if ([string]::IsNullOrEmpty($Text)) {
    return ''
  }

  # Keep only characters that are guaranteed safe for a UTF-8 console:
  #   - Tab (0x09), LF (0x0A), CR (0x0D)
  #   - Printable ASCII (0x20 .. 0x7E)
  # Everything else (high bytes from locale encodings, surrogates,
  # control chars) is replaced with '?' so the message stays readable
  # without ever producing non-UTF-8 byte sequences on output.
  $cleanBuilder = New-Object System.Text.StringBuilder($Text.Length)
  foreach ($char in $Text.ToCharArray()) {
    $code = [int][char]$char
    if ($char -eq "`r" -or $char -eq "`n" -or $char -eq "`t" -or ($code -ge 0x20 -and $code -le 0x7E)) {
      [void]$cleanBuilder.Append($char)
    } else {
      [void]$cleanBuilder.Append('?')
    }
  }

  return $cleanBuilder.ToString()
}

function Stop-ProcessTree {
  param([int[]]$ProcessIds)

  foreach ($processId in ($ProcessIds | Where-Object { $_ -and $_ -gt 0 } | Sort-Object -Unique)) {
    $taskkill = Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', $processId, '/T', '/F') -Wait -PassThru -WindowStyle Hidden
    if ($taskkill.ExitCode -ne 0 -and $taskkill.ExitCode -ne 128) {
      Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
  }
}

function Read-NewContent {
  param(
    [string]$Path,
    [ref]$Position
  )

  if (!(Test-Path $Path)) {
    return ''
  }

  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try {
    if ($Position.Value -gt $stream.Length) {
      $Position.Value = 0L
    }

    $null = $stream.Seek($Position.Value, [System.IO.SeekOrigin]::Begin)
    # Use Latin-1 (ISO-8859-1) so every byte round-trips without
    # throwing on invalid UTF-8 sequences produced by Java / native code.
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::GetEncoding('iso-8859-1'))
    try {
      $content = $reader.ReadToEnd()
      $Position.Value = $stream.Position
      return (Convert-ToCleanUtf8Text -Text $content)
    } finally {
      $reader.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Read-PropertiesMap {
  param([string]$Path)

  $properties = @{}
  if (!(Test-Path $Path)) {
    return $properties
  }

  foreach ($rawLine in Get-Content $Path -Encoding UTF8 -ErrorAction SilentlyContinue) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#')) {
      continue
    }

    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2) {
      $properties[$parts[0]] = ConvertFrom-JavaPropertiesValue -Value $parts[1]
    }
  }

  return $properties
}

function ConvertFrom-JavaPropertiesValue {
  param([string]$Value)

  if ($null -eq $Value) {
    return ''
  }

  $builder = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $Value.Length; $i++) {
    $char = $Value[$i]
    if ($char -ne '\') {
      [void]$builder.Append($char)
      continue
    }

    if ($i + 1 -ge $Value.Length) {
      [void]$builder.Append('\')
      break
    }

    $i++
    $escape = $Value[$i]
    switch ($escape) {
      't' { [void]$builder.Append("`t") }
      'r' { [void]$builder.Append("`r") }
      'n' { [void]$builder.Append("`n") }
      'f' { [void]$builder.Append([char]12) }
      'u' {
        if ($i + 4 -lt $Value.Length) {
          $hex = $Value.Substring($i + 1, 4)
          if ($hex -match '^[0-9A-Fa-f]{4}$') {
            [void]$builder.Append([char][Convert]::ToInt32($hex, 16))
            $i += 4
            break
          }
        }
        [void]$builder.Append('u')
      }
      default { [void]$builder.Append($escape) }
    }
  }

  return $builder.ToString()
}

function Get-PropertyValue {
  param(
    [hashtable]$Properties,
    [string]$Key,
    [string]$Default = ''
  )

  if ($null -ne $Properties -and $Properties.ContainsKey($Key)) {
    return [string]$Properties[$Key]
  }

  return $Default
}

function Write-ReuseDiagnostics {
  param(
    [string]$ReportPath,
    [string]$LatestLogPath
  )

  $report = Read-PropertiesMap -Path $ReportPath
  if ($report.Count -gt 0) {
    Write-Output '--- temporal reuse summary ---'
    Write-Output (
      'reuse-stage blendFactor={0} blendCompletions={1} blendRegionActivations={2} blendFullActivations={3} framesBlendActive={4} framesGlobalReloadActive={5} framesPendingWork={6}' -f
      (Get-PropertyValue -Properties $report -Key 'latestLightBlendFactor'),
      (Get-PropertyValue -Properties $report -Key 'latestBlendCompletions'),
      (Get-PropertyValue -Properties $report -Key 'latestBlendRegionActivations'),
      (Get-PropertyValue -Properties $report -Key 'latestBlendFullActivations'),
      (Get-PropertyValue -Properties $report -Key 'latestFramesBlendActive'),
      (Get-PropertyValue -Properties $report -Key 'latestFramesGlobalReloadActive'),
      (Get-PropertyValue -Properties $report -Key 'latestFramesPendingWork')
    )
    Write-Output (
      'reuse-reservoir previousCaptureLightBlendFactor={0} previousCaptureResolvedStrictValidFraction={1} previousCaptureResolvedMeanWeight={2} previousCaptureResolvedMeanM={3} latestResolvedMeanM={4} previousCaptureTracedLightCount={5} latestTracedLightCount={6} latestTotalLightCount={7} latestLightSelectionCapped={8}' -f
      (Get-PropertyValue -Properties $report -Key 'previousCaptureLightBlendFactor'),
      (Get-PropertyValue -Properties $report -Key 'previousCaptureResolvedStrictValidFraction'),
      (Get-PropertyValue -Properties $report -Key 'previousCaptureResolvedMeanWeight'),
      (Get-PropertyValue -Properties $report -Key 'previousCaptureResolvedMeanM'),
      (Get-PropertyValue -Properties $report -Key 'latestResolvedMeanM'),
      (Get-PropertyValue -Properties $report -Key 'previousCaptureTracedLightCount'),
      (Get-PropertyValue -Properties $report -Key 'latestTracedLightCount'),
      (Get-PropertyValue -Properties $report -Key 'latestTotalLightCount'),
      (Get-PropertyValue -Properties $report -Key 'latestLightSelectionCapped')
    )
    Write-Output (
      'reuse-stability directTemporalDeltaAvg={0} directTemporalDeltaMax={1} directTemporalMaxPixelDeltaAvg={2} motionRepeatDirectDeltaAvg={3} latestWholeLightFlashDirectDrop={4} latestWholeLightFlashResolvedValidDrop={5} latestWholeLightFlashResolvedMDrop={6} latestLightBlendRegionCount={7}' -f
      (Get-PropertyValue -Properties $report -Key 'directTemporalDeltaAvg'),
      (Get-PropertyValue -Properties $report -Key 'directTemporalDeltaMax'),
      (Get-PropertyValue -Properties $report -Key 'directTemporalMaxPixelDeltaAvg'),
      (Get-PropertyValue -Properties $report -Key 'motionRepeatDirectDeltaAvg'),
      (Get-PropertyValue -Properties $report -Key 'latestWholeLightFlashDirectDrop'),
      (Get-PropertyValue -Properties $report -Key 'latestWholeLightFlashResolvedValidDrop'),
      (Get-PropertyValue -Properties $report -Key 'latestWholeLightFlashResolvedMDrop'),
      (Get-PropertyValue -Properties $report -Key 'latestLightBlendRegionCount')
    )
    Write-Output (
      'reuse-compile latestCompileFramesLightWorkNeeded={0} latestCompileFramesLightCompiled={1} latestCompileFramesTracedLightDirty={2} latestCompileFramesWorldOffsetChanged={3} latestCompileFramesChunkTopologyChanged={4} latestCompileFramesChunkContentChanged={5}' -f
      (Get-PropertyValue -Properties $report -Key 'latestCompileFramesLightWorkNeeded'),
      (Get-PropertyValue -Properties $report -Key 'latestCompileFramesLightCompiled'),
      (Get-PropertyValue -Properties $report -Key 'latestCompileFramesTracedLightDirty'),
      (Get-PropertyValue -Properties $report -Key 'latestCompileFramesWorldOffsetChanged'),
      (Get-PropertyValue -Properties $report -Key 'latestCompileFramesChunkTopologyChanged'),
      (Get-PropertyValue -Properties $report -Key 'latestCompileFramesChunkContentChanged')
    )
  }

  if (!(Test-Path $LatestLogPath)) {
    return
  }

  $interestingLogLines = @(Get-Content $LatestLogPath -Tail 220 -Encoding UTF8 -ErrorAction SilentlyContinue |
    Where-Object { $_ -match '(?i)\b(automation|reservoir|reuse|temporal|gather|scatter|reproject|blend|previous)\b' } |
    Select-Object -Last 24)

  if ($interestingLogLines.Count -gt 0) {
    Write-Output '--- reuse log tail ---'
    $interestingLogLines | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ }
  }
}

function Get-ShaderCompileFailureMessage {
  param([string]$Content)

  if ([string]::IsNullOrWhiteSpace($Content)) {
    return $null
  }

  if ($Content -notmatch 'Failed to create shader rendering pipeline|The shaderpack failed to load!|Shader compilation log for') {
    return $null
  }

  $lines = $Content -split "\r?\n"
  for ($i = $lines.Length - 1; $i -ge 0; $i--) {
    $line = $lines[$i].Trim()
    if ($line -match 'ShaderCompileException') {
      return "Fatal shader compilation failure: $line"
    }
  }

  for ($i = $lines.Length - 1; $i -ge 0; $i--) {
    $line = $lines[$i].Trim()
    if ($line -match '(?i)error' -and $line -match '(?i)shader') {
      return "Fatal shader compilation failure: $line"
    }
  }

  if ($Content -match 'Failed to create shader rendering pipeline|The shaderpack failed to load!') {
    return 'Fatal shader compilation failure detected in latest.log'
  }

  return $null
}

function Get-ExplicitFailureMessage {
  param(
    [string]$ReportPath,
    [string]$LatestLogPath
  )

  $report = Read-PropertiesMap -Path $ReportPath
  $reportFailureReason = Get-PropertyValue -Properties $report -Key 'failureReason'
  if (-not [string]::IsNullOrWhiteSpace($reportFailureReason) -and $reportFailureReason -ne 'Automation still running') {
    if ($reportFailureReason -notmatch '^Client stopped before automation completed$') {
      return $reportFailureReason
    }
  }

  if (Test-Path $LatestLogPath) {
    $latestLogContent = Get-Content $LatestLogPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    $compileFailureMessage = Get-ShaderCompileFailureMessage -Content $latestLogContent
    if ($null -ne $compileFailureMessage) {
      return $compileFailureMessage
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($reportFailureReason) -and $reportFailureReason -ne 'Automation still running') {
    return $reportFailureReason
  }

  return $null
}

function Get-FatalReason {
  param(
    [string]$Content,
    [string]$ChunkName
  )

  foreach ($pattern in $fatalPatterns) {
    if ($Content.Contains($pattern)) {
      return "fatal:${pattern}:$ChunkName"
    }
  }

  if ($Content.Contains('Shader compilation log for') -and $Content -match '(?is)Shader compilation log for.*?\berror\b') {
    return "fatal:Shader compilation log for:$ChunkName"
  }

  return $null
}

function Write-FailureDiagnostics {
  param(
    [string]$Reason,
    [string]$FatalContent
  )

  Write-Output "watchdogResult=$Reason"
  Write-ReuseDiagnostics -ReportPath $reportFile -LatestLogPath $latestLog

  $explicitFailureMessage = Get-ExplicitFailureMessage -ReportPath $reportFile -LatestLogPath $latestLog
  if (-not [string]::IsNullOrWhiteSpace($explicitFailureMessage)) {
    Write-Output "failureReason=$explicitFailureMessage"
  }

  if (-not [string]::IsNullOrEmpty($FatalContent)) {
    Write-Output '--- fatal shader output ---'
    Write-Output $FatalContent
    return
  }

  # Only fall back to generic tails when there is no captured fatal chunk.
  if (Test-Path $stdout) { Write-Output '--- stdout tail ---'; Get-Content $stdout -Tail 60 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ } }
  if (Test-Path $stderr) { Write-Output '--- stderr tail ---'; Get-Content $stderr -Tail 60 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ } }
  if (Test-Path $latestLog) { Write-Output '--- latest.log tail ---'; Get-Content $latestLog -Tail 140 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ } }
}

foreach ($path in @($stdout, $stderr)) {
  if (Test-Path $path) {
    try {
      Remove-Item $path -Force -ErrorAction Stop
    } catch {
      Write-Output ("watchdog: log busy, reusing {0}" -f $path)
    }
  }
}

$logPosition = if (Test-Path $latestLog) { (Get-Item $latestLog).Length } else { 0L }
$stdoutPosition = 0L
$stderrPosition = 0L
$deadline = (Get-Date).AddSeconds(320)
$reason = 'completed'
$fatalChunkContent = ''

$gradleArgumentList = @('shaderGameTest', '--no-daemon')
if ($GradleArgs) {
  $gradleArgumentList += $GradleArgs
}

$proc = Start-Process -FilePath '.\gradlew.bat' -ArgumentList $gradleArgumentList -WorkingDirectory (Get-Location) -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$processIds = @($proc.Id)

while (-not $proc.HasExited) {
  Start-Sleep -Seconds 2
  $proc.Refresh()

  if ($processIds.Count -lt 2) {
    $childJavaProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'javaw.exe' OR Name = 'java.exe'" |
      Where-Object { $_.ParentProcessId -eq $proc.Id } |
      Select-Object -ExpandProperty ProcessId)
    if ($childJavaProcesses.Count -gt 0) {
      $processIds = @($processIds + $childJavaProcesses | Sort-Object -Unique)
    }
  }

  $chunks = @(
    @{ Name = 'stdout'; Content = (Read-NewContent -Path $stdout -Position ([ref]$stdoutPosition)) },
    @{ Name = 'stderr'; Content = (Read-NewContent -Path $stderr -Position ([ref]$stderrPosition)) },
    @{ Name = 'latest.log'; Content = (Read-NewContent -Path $latestLog -Position ([ref]$logPosition)) }
  )

  foreach ($chunk in $chunks) {
    if ([string]::IsNullOrEmpty($chunk.Content)) {
      continue
    }

    $fatalReason = Get-FatalReason -Content $chunk.Content -ChunkName $chunk.Name
    if ($null -ne $fatalReason) {
      $reason = $fatalReason
      $fatalChunkContent = $chunk.Content
      Stop-ProcessTree -ProcessIds $processIds
      break
    }
  }

  if ($reason -ne 'completed') {
    break
  }

  if ((Get-Date) -ge $deadline) {
    $reason = 'timeout'
    Stop-ProcessTree -ProcessIds $processIds
    break
  }
}

try { Wait-Process -Id $proc.Id -Timeout 10 -ErrorAction SilentlyContinue } catch {}

if ($reason -ne 'completed') {
  Write-FailureDiagnostics -Reason $reason -FatalContent $fatalChunkContent
  exit 1
}

if (-not (Test-Path $reportFile)) {
  Write-FailureDiagnostics -Reason 'missing-report'
  exit 1
}

$report = Read-PropertiesMap -Path $reportFile
$reportSuccess = (Get-PropertyValue -Properties $report -Key 'success').ToLowerInvariant()
if ($reportSuccess -ne 'true') {
  Write-FailureDiagnostics -Reason 'report-failure'
  exit 1
}

Write-ReuseDiagnostics -ReportPath $reportFile -LatestLogPath $latestLog

exit 0
