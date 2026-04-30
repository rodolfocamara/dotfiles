$dir = Join-Path $env:USERPROFILE "Pictures\Screenshots"
$latest = Get-ChildItem $dir -File -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1
if ($latest) { Set-Clipboard -Value $latest.FullName }
