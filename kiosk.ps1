# Kiosk watchdog for the dashboard NUC.
#  - keeps Edge running in kiosk mode on index.html (from the folder this script lives in)
#  - every $PullEveryMinutes, pulls the repo and applies updates:
#      index.html changed -> restart the kiosk Edge so it reloads the page
#      kiosk.ps1 changed  -> hand over to the new copy of this script
#    Pull failures (e.g. no internet offshore) are logged and ignored.
$page       = ([System.Uri](Join-Path $PSScriptRoot 'index.html')).AbsoluteUri
$profileDir = Join-Path $env:LOCALAPPDATA 'kiosk-edge'
$edge       = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
$log        = Join-Path $PSScriptRoot 'kiosk.log'
$PullEveryMinutes = 5

function Write-Log($msg) { "$(Get-Date -Format s) $msg" | Add-Content $log }

function Get-KioskEdge {
  Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*kiosk-edge*' }
}

function Update-Repo {
  $before = git -C $PSScriptRoot rev-parse HEAD
  $out = git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 -C $PSScriptRoot pull --ff-only 2>&1
  if ($LASTEXITCODE -ne 0) { Write-Log "pull failed: $out"; return }
  $after = git -C $PSScriptRoot rev-parse HEAD
  if ($after -eq $before) { return }

  Write-Log "updated $before -> $after"
  $changed = git -C $PSScriptRoot diff --name-only $before $after
  if ($changed -contains 'kiosk.ps1') {
    Write-Log 'kiosk.ps1 changed, handing over to the new copy'
    & $PSCommandPath   # runs the new script (its own loop); never returns
    exit
  }
  if ($changed -contains 'index.html') {
    Write-Log 'index.html changed, restarting kiosk Edge'
    Get-KioskEdge | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  }
}

$haveGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if (-not $haveGit) { Write-Log 'git not found, auto-update disabled' }

Start-Sleep 30   # let the network come up
$nextPull = Get-Date
while ($true) {
  if ($haveGit -and (Get-Date) -ge $nextPull) {
    Update-Repo
    $nextPull = (Get-Date).AddMinutes($PullEveryMinutes)
  }
  # Edge can keep hidden background msedge.exe processes alive, so look for the
  # kiosk instance specifically (it has its own profile dir, so a background
  # instance can't swallow the launch).
  if (-not (Get-KioskEdge)) {
    Write-Log 'launching Edge'
    Start-Process $edge -ArgumentList "--kiosk `"$page`" --user-data-dir=`"$profileDir`" --edge-kiosk-type=fullscreen --no-first-run --disable-session-crashed-bubble"
  }
  Start-Sleep 30
}
