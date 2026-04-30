#Requires AutoHotkey v2.0
#SingleInstance Force

; Ctrl+Shift+S: copy latest screenshot path to clipboard
^+s::Run('"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\rcamara\Repos\dotfiles\scripts\snip-path.ps1"', , "Hide")
