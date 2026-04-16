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
$fatalPatterns = @('Failed to create shader rendering pipeline', 'The shaderpack failed to load!')

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

  if (-not [string]::IsNullOrEmpty($FatalContent)) {
    Write-Output '--- fatal shader output ---'
    Write-Output $FatalContent
    return
  }

  # Only fall back to generic tails when there is no captured fatal chunk.
  if (Test-Path $stdout) { Write-Output '--- stdout tail ---'; Get-Content $stdout -Tail 60 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ } }
  if (Test-Path $stderr) { Write-Output '--- stderr tail ---'; Get-Content $stderr -Tail 60 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ } }
  if (Test-Path $latestLog) { Write-Output '--- latest.log tail ---'; Get-Content $latestLog -Tail 140 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ } }
  if (Test-Path $reportFile) { Write-Output '--- shader-report ---'; Get-Content $reportFile -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ } }
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

exit 0
