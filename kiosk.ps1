Start-Sleep 30   # let the network come up
while ($true) {
  if (-not (Get-Process msedge -ErrorAction SilentlyContinue)) {
    Start-Process msedge -ArgumentList '--kiosk "file:///C:/dashboard/index.html" --edge-kiosk-type=fullscreen --no-first-run --disable-session-crashed-bubble'
  }
  Start-Sleep 30
}
