$ErrorActionPreference = "Stop"

# Force console output to UTF-8 so Write-Output never hits
# "Windows stdio does not support writing non-UTF-8 byte sequences".
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

$repoRoot = Get-Location
$logPath = Join-Path $repoRoot "run/logs/latest.log"
$stdoutPath = Join-Path $repoRoot "run/shaderGameTest.stdout.log"
$stderrPath = Join-Path $repoRoot "run/shaderGameTest.stderr.log"
$fatalPatterns = @(
    "Failed to create shader rendering pipeline",
    "The shaderpack failed to load!"
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
$fatalChunkContent = ''

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
                Write-Output (Convert-ToCleanUtf8Text -Text $line)
            }
        }

        if ($shaderCompilationLogFatal) {
            Write-Output "watchdog-fatal pattern=Shader compilation log for (error)"
            $fatalChunkContent = $chunk
            Stop-ProcessTree -ProcessIds $knownProcessIds
            break
        }

        foreach ($pattern in $fatalPatterns) {
            if ($chunk.Contains($pattern)) {
                Write-Output "watchdog-fatal pattern=$pattern"
                $fatalChunkContent = $chunk
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
            Write-Output (Convert-ToCleanUtf8Text -Text $line)
        }
    }
}

Write-Output "watchdog-exit code=$($process.ExitCode)"

# When we caught a fatal shader error the chunk that triggered it is
# far more useful than a generic tail of the log files.  Print it
# first so it is immediately visible.
if (-not [string]::IsNullOrEmpty($fatalChunkContent)) {
    Write-Output '--- fatal shader output ---'
    Write-Output $fatalChunkContent
} else {
    # Only fall back to generic tails when there is no captured fatal chunk.
    if (Test-Path "run/automation/shader-report.properties") {
        Write-Output "--- shader-report ---"
        Get-Content "run/automation/shader-report.properties" -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ }
    }
    if (Test-Path $stderrPath) {
        Write-Output "--- stderr tail ---"
        Get-Content $stderrPath -Tail 80 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ }
    }
    if (Test-Path $stdoutPath) {
        Write-Output "--- stdout tail ---"
        Get-Content $stdoutPath -Tail 80 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Convert-ToCleanUtf8Text -Text $_ }
    }
}

exit $process.ExitCode
