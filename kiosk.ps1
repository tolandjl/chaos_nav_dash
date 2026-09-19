# Serves index.html from the folder this script lives in, so the repo can be
# cloned anywhere on the NUC.
$page = ([System.Uri](Join-Path $PSScriptRoot 'index.html')).AbsoluteUri

Start-Sleep 30   # let the network come up
while ($true) {
  if (-not (Get-Process msedge -ErrorAction SilentlyContinue)) {
    Start-Process msedge -ArgumentList "--kiosk `"$page`" --edge-kiosk-type=fullscreen --no-first-run --disable-session-crashed-bubble"
  }
  Start-Sleep 30
}
