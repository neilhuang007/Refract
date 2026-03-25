$stdout = Join-Path (Get-Location) 'run/shaderGameTest.stdout.log'
$stderr = Join-Path (Get-Location) 'run/shaderGameTest.stderr.log'
$latestLog = Join-Path (Get-Location) 'run/logs/latest.log'
if (Test-Path $stdout) { Remove-Item $stdout -Force }
if (Test-Path $stderr) { Remove-Item $stderr -Force }
if (Test-Path $latestLog) { Remove-Item $latestLog -Force }
$proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','gradlew.bat cleanShaderGameTestArtifacts runShaderGameTestClient --no-daemon' -WorkingDirectory (Get-Location) -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$deadline = (Get-Date).AddSeconds(200)
$fatalPatterns = @('Failed to create shader rendering pipeline','Shader compilation log for','The shaderpack failed to load!')
$reason = 'completed'
while (-not $proc.HasExited) {
  Start-Sleep -Seconds 5
  $proc.Refresh()
  $remaining = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalSeconds)
  Write-Output ("watchdog: pid={0} remaining={1}s" -f $proc.Id, $remaining)
  if (Test-Path $latestLog) {
    $tail = Get-Content $latestLog -Tail 140 -ErrorAction SilentlyContinue
    $joined = ($tail -join "`n")
    $matchedFatal = @($fatalPatterns | Where-Object { $joined.Contains($_) })
    if ($matchedFatal.Count -gt 0) {
      $reason = "fatal:$($matchedFatal[0])"
      taskkill /PID $proc.Id /T /F | Out-Null
      break
    }
    $automation = $tail | Select-String -Pattern '\[Automation\] capture=|\[Automation\] reservoir capture=' | Select-Object -Last 4
    foreach ($line in $automation) { Write-Output $line.Line }
  }
  if ((Get-Date) -ge $deadline) {
    $reason = 'timeout'
    taskkill /PID $proc.Id /T /F | Out-Null
    break
  }
}
try { Wait-Process -Id $proc.Id -Timeout 10 -ErrorAction SilentlyContinue } catch {}
Write-Output "watchdogResult=$reason"
if (Test-Path $stdout) { Write-Output '--- stdout tail ---'; Get-Content $stdout -Tail 30 }
if (Test-Path $stderr) { Write-Output '--- stderr tail ---'; Get-Content $stderr -Tail 30 }
if (Test-Path $latestLog) { Write-Output '--- latest.log tail ---'; Get-Content $latestLog -Tail 140 }
if (Test-Path 'run/automation/shader-report.properties') { Write-Output '--- shader-report ---'; Get-Content 'run/automation/shader-report.properties' }
