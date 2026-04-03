param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$GradleArgs
)

$stdout = Join-Path (Get-Location) 'run/shaderGameTest.stdout.log'
$stderr = Join-Path (Get-Location) 'run/shaderGameTest.stderr.log'
$latestLog = Join-Path (Get-Location) 'run/logs/latest.log'
$fatalPatterns = @('Failed to create shader rendering pipeline', 'The shaderpack failed to load!')

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
    $reader = New-Object System.IO.StreamReader($stream)
    try {
      $content = $reader.ReadToEnd()
      $Position.Value = $stream.Position
      return $content
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
$deadline = (Get-Date).AddSeconds(200)
$reason = 'completed'

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

  $remaining = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalSeconds)
  Write-Output ("watchdog: pid={0} remaining={1}s" -f $proc.Id, $remaining)

  $chunks = @(
    @{ Name = 'stdout'; Content = (Read-NewContent -Path $stdout -Position ([ref]$stdoutPosition)) },
    @{ Name = 'stderr'; Content = (Read-NewContent -Path $stderr -Position ([ref]$stderrPosition)) },
    @{ Name = 'latest.log'; Content = (Read-NewContent -Path $latestLog -Position ([ref]$logPosition)) }
  )

  foreach ($chunk in $chunks) {
    if ([string]::IsNullOrEmpty($chunk.Content)) {
      continue
    }

    $lines = @($chunk.Content -split "\r?\n" | Where-Object { $_.Length -gt 0 })
    $automation = $lines | Select-String -Pattern '\[Automation\] capture=|\[Automation\] reservoir capture='
    foreach ($line in ($automation | Select-Object -Last 4)) {
      Write-Output $line.Line
    }

    $fatalReason = Get-FatalReason -Content $chunk.Content -ChunkName $chunk.Name
    if ($null -ne $fatalReason) {
      $reason = $fatalReason
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
Write-Output "watchdogResult=$reason"
if (Test-Path $stdout) { Write-Output '--- stdout tail ---'; Get-Content $stdout -Tail 60 }
if (Test-Path $stderr) { Write-Output '--- stderr tail ---'; Get-Content $stderr -Tail 60 }
if (Test-Path $latestLog) { Write-Output '--- latest.log tail ---'; Get-Content $latestLog -Tail 140 }
if (Test-Path 'run/automation/shader-report.properties') { Write-Output '--- shader-report ---'; Get-Content 'run/automation/shader-report.properties' }
