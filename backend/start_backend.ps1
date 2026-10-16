# VidSave backend launcher.
#
# Starts backend/server.py in the background unless it is already listening on
# 8787, so logging in twice never spawns a duplicate server.
$ErrorActionPreference = 'Stop'

$port = 8787
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = (Get-Command python -ErrorAction Stop).Source

# A named mutex guards the check-then-start window: two logons firing at the
# same moment would both see the port free and race to bind it, and the loser
# would die with "address already in use". The mutex serialises them so the
# second run sees the first server already listening.
$mutex = New-Object System.Threading.Mutex($false, "Global\VidSaveBackendLauncher")
$locked = $false
try {
  $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
  if (-not $locked) {
    Write-Host "VidSave backend: timed out waiting for another launcher to finish."
    exit 1
  }

  # Get-NetTCPConnection throws when nothing listens; -ErrorAction SilentlyContinue
  # turns that into an empty array, so the count is a plain boolean with no
  # exception control flow. A PowerShell -ne comparison would instead return a
  # filtered array, which is truthy but awkward to reason about.
  $listening = @(
    Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
  ).Count -gt 0

  if ($listening) {
    Write-Host "VidSave backend already listening on port $port."
    exit 0
  }

  Start-Process -FilePath $python `
    -ArgumentList "`"$root\server.py`"" `
    -WorkingDirectory $root `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$root\server.log" `
    -RedirectStandardError "$root\server.err"

  Write-Host "VidSave backend started on port $port."
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
