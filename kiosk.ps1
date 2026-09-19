# Serves index.html from the folder this script lives in, so the repo can be
# cloned anywhere on the NUC.
$page       = ([System.Uri](Join-Path $PSScriptRoot 'index.html')).AbsoluteUri
$profileDir = Join-Path $env:LOCALAPPDATA 'kiosk-edge'
$edge       = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
$log        = Join-Path $PSScriptRoot 'kiosk.log'

Start-Sleep 30   # let the network come up
while ($true) {
  # Edge can keep hidden background msedge.exe processes alive, so look for the
  # kiosk instance specifically (it has its own profile dir, so a background
  # instance can't swallow the launch).
  $running = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*kiosk-edge*' }
  if (-not $running) {
    "$(Get-Date -Format s) launching Edge" | Add-Content $log
    Start-Process $edge -ArgumentList "--kiosk `"$page`" --user-data-dir=`"$profileDir`" --edge-kiosk-type=fullscreen --no-first-run --disable-session-crashed-bubble"
  }
  Start-Sleep 30
}
