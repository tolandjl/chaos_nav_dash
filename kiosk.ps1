# Kiosk watchdog for the dashboard NUC.
#  - keeps Edge running in kiosk mode on index.html (from the folder this script lives in)
#  - every $PullEveryMinutes, checks the repo for updates and applies them:
#      index.html changed -> restart the kiosk Edge so it reloads the page
#      kiosk.ps1 changed  -> hand over to the new copy of this script
#    Fetch failures (e.g. no internet offshore) are logged and ignored.
#  - this clone is deploy-only (no local edits), so updates are applied with
#    `git reset --hard origin/main`, and it repairs the damage a power cut can
#    leave behind (zeroed .git\index, stale index.lock) before retrying.
$page       = ([System.Uri](Join-Path $PSScriptRoot 'index.html')).AbsoluteUri
$profileDir = Join-Path $env:LOCALAPPDATA 'kiosk-edge'
$edge       = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
$log        = Join-Path $PSScriptRoot 'kiosk.log'
$gitDir     = Join-Path $PSScriptRoot '.git'
$PullEveryMinutes = 5

function Write-Log($msg) { "$(Get-Date -Format s) $msg" | Add-Content $log }

function Get-KioskEdge {
  Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*kiosk-edge*' }
}

# If git's error output shows a damaged index or a stale lock, fix it.
# Returns $true when it repaired something (so the caller should retry).
# The message varies with how the file was damaged ("bad signature",
# "index file smaller than expected", "index file corrupt").
function Repair-Git($text) {
  if ($text -match 'index\.lock') {
    if (Get-Process git -ErrorAction SilentlyContinue) { return $false }   # a real git is running
    Write-Log 'stale index.lock, removing it'
    Remove-Item (Join-Path $gitDir 'index.lock') -Force -ErrorAction SilentlyContinue
    return $true
  }
  if ($text -match 'index file|bad signature') {
    Write-Log 'git index is damaged, rebuilding it from HEAD'
    Remove-Item (Join-Path $gitDir 'index') -Force -ErrorAction SilentlyContinue
    git -C $PSScriptRoot reset --quiet 2>&1 | Out-Null
    return $true
  }
  return $false
}

function Invoke-Fetch {
  git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 -C $PSScriptRoot fetch --quiet origin 2>&1 | Out-String
}

function Sync-Repo {
  $text = git -C $PSScriptRoot reset --hard origin/main 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -and (Repair-Git $text)) {
    $text = git -C $PSScriptRoot reset --hard origin/main 2>&1 | Out-String
  }
  if ($LASTEXITCODE -ne 0) { Write-Log "reset failed: $text"; return $false }
  return $true
}

function Update-Repo {
  $before = git -C $PSScriptRoot rev-parse HEAD
  # fetch reads the index too, so a damaged one has to be repaired first.
  $text = Invoke-Fetch
  if ($LASTEXITCODE -ne 0 -and (Repair-Git $text)) { $text = Invoke-Fetch }
  if ($LASTEXITCODE -ne 0) { Write-Log "fetch failed: $text"; return }
  $after = git -C $PSScriptRoot rev-parse origin/main
  if ($after -eq $before) { return }

  if (-not (Sync-Repo)) { return }
  Write-Log "updated $before -> $after"
  $changed = git -C $PSScriptRoot diff --name-only $before $after
  # Restart Edge before any hand-over: the hand-over never returns, and the
  # new copy would see HEAD == origin/main and not know the page changed.
  if ($changed -contains 'index.html') {
    Write-Log 'index.html changed, restarting kiosk Edge'
    Get-KioskEdge | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  }
  if ($changed -contains 'kiosk.ps1') {
    Write-Log 'kiosk.ps1 changed, handing over to the new copy'
    & $PSCommandPath   # runs the new script (its own loop); never returns
    exit
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
