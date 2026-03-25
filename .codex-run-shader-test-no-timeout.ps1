$ErrorActionPreference = "Stop"

$repoRoot = Get-Location
$logPath = Join-Path $repoRoot "run/logs/latest.log"
$stdoutPath = Join-Path $repoRoot "run/shaderGameTest.stdout.log"
$stderrPath = Join-Path $repoRoot "run/shaderGameTest.stderr.log"
$fatalPatterns = @(
    "Failed to create shader rendering pipeline",
    "The shaderpack failed to load!"
)

function Stop-ProcessTree {
    param(
        [int[]]$ProcessIds
    )

    foreach ($processId in ($ProcessIds | Where-Object { $_ -and $_ -gt 0 } | Sort-Object -Unique)) {
        try {
            taskkill /PID $processId /T /F | Out-Null
        } catch {
        }
    }
}

function Read-NewLogContent {
    param(
        [string]$Path,
        [ref]$Position
    )

    if (!(Test-Path $Path)) {
        return ""
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

foreach ($path in @($stdoutPath, $stderrPath, $logPath)) {
    if (Test-Path $path) {
        try {
            Remove-Item $path -Force -ErrorAction Stop
        } catch {
            Write-Output "could not remove $path"
        }
    }
}

$process = Start-Process -FilePath ".\gradlew.bat" `
    -ArgumentList "shaderGameTest", "--no-daemon" `
    -WorkingDirectory $repoRoot `
    -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

$knownProcessIds = @($process.Id)
$lastPosition = 0L
$shaderCompilationLogActive = $false
$shaderCompilationLogFatal = $false

Write-Output "watchdog-start pid=$($process.Id)"

while (-not $process.HasExited) {
    $childJavaProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'javaw.exe' OR Name = 'java.exe'" |
        Where-Object { $_.ParentProcessId -eq $process.Id } |
        Select-Object -ExpandProperty ProcessId)
    if ($childJavaProcesses.Count -gt 0) {
        $knownProcessIds = @($knownProcessIds + $childJavaProcesses | Sort-Object -Unique)
    }

    $chunk = Read-NewLogContent -Path $logPath -Position ([ref]$lastPosition)
    if ($chunk.Length -gt 0) {
        $lines = @($chunk -split "\r?\n")
        foreach ($line in $lines) {
            if ($line.Contains("Shader compilation log for")) {
                $shaderCompilationLogActive = $true
                if ($line -match "ERROR:|error:") {
                    $shaderCompilationLogFatal = $true
                }
            } elseif ($shaderCompilationLogActive) {
                if ($line -match "^\s*ERROR:|error:") {
                    $shaderCompilationLogFatal = $true
                } elseif ($line -match "^\s*WARNING:") {
                    # Warning-only shader logs are noisy but not fatal.
                } elseif ($line -match "^\s*$" -or $line -match "^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]") {
                    $shaderCompilationLogActive = $false
                }
            }

            if ($line.Length -eq 0) {
                continue
            }

            if ($line -match "\[Startup\]|\[Automation\]|BUILD SUCCESSFUL|FAILURE: Build failed") {
                Write-Output $line
            }
        }

        if ($shaderCompilationLogFatal) {
            Write-Output "watchdog-fatal pattern=Shader compilation log for (error)"
            Stop-ProcessTree -ProcessIds $knownProcessIds
            break
        }

        foreach ($pattern in $fatalPatterns) {
            if ($chunk.Contains($pattern)) {
                Write-Output "watchdog-fatal pattern=$pattern"
                Stop-ProcessTree -ProcessIds $knownProcessIds
                break
            }
        }
    }

    Start-Sleep -Seconds 3
    $process.Refresh()
}

$remaining = Read-NewLogContent -Path $logPath -Position ([ref]$lastPosition)
if ($remaining.Length -gt 0) {
    $lines = @($remaining -split "\r?\n" | Where-Object { $_.Length -gt 0 })
    foreach ($line in $lines) {
        if ($line -match "\[Startup\]|\[Automation\]|BUILD SUCCESSFUL|FAILURE: Build failed") {
            Write-Output $line
        }
    }
}

Write-Output "watchdog-exit code=$($process.ExitCode)"
if (Test-Path "run/automation/shader-report.properties") {
    Write-Output "--- shader-report ---"
    Get-Content "run/automation/shader-report.properties"
}
if (Test-Path $stderrPath) {
    Write-Output "--- stderr tail ---"
    Get-Content $stderrPath -Tail 80
}
if (Test-Path $stdoutPath) {
    Write-Output "--- stdout tail ---"
    Get-Content $stdoutPath -Tail 80
}

exit $process.ExitCode
