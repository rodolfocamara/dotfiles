# Requires -Version 5.1
<#
.SYNOPSIS
Applies Windows system tweaks and installs window-management utilities (AltSnap, AHK).
Run after a fresh install or when restoring dotfiles.
#>

if (-not $IsWindows) {
    Write-Verbose "Skipping Windows tweaks on non-Windows host"
    exit 0
}

Write-Host "Applying Windows tweaks..."

# ── Disable Snap Assist ──────────────────────────────────────────
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $adv -Name "EnableSnapAssistFlyout" -Value 0
Set-ItemProperty -Path $adv -Name "EnableSnapBar" -Value 0
Set-ItemProperty -Path $adv -Name "DITest" -Value 0
Write-Host "  [OK] Snap Assist disabled"

# ── Disable window animations ────────────────────────────────────
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00))
Write-Host "  [OK] Window animations disabled"

# ── Auto-hide taskbar ────────────────────────────────────────────
$taskbar = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
$settings = (Get-ItemProperty -Path $taskbar).Settings
if ($settings -and $settings.Length -gt 8) {
    $settings[8] = $settings[8] -bor 0x01
    Set-ItemProperty -Path $taskbar -Name "Settings" -Value $settings
    Write-Host "  [OK] Taskbar set to auto-hide"
}

# ── AltSnap (Alt+drag to move/resize windows; not in winget) ─────
$altSnapDir = "$env:LOCALAPPDATA\AltSnap"
$altSnapExe = Join-Path $altSnapDir "AltSnap.exe"
if (-not (Test-Path $altSnapExe)) {
    $rel = Invoke-RestMethod "https://api.github.com/repos/RamonUnch/AltSnap/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -like "*bin_x64.zip" } | Select-Object -First 1
    $zip = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    New-Item -ItemType Directory -Path $altSnapDir -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $altSnapDir -Force
    Remove-Item $zip
    Write-Host "  [OK] AltSnap $($rel.tag_name) installed at $altSnapDir"
} else {
    Write-Host "  [SKIP] AltSnap already present"
}

# ── Startup shortcuts (AltSnap + AHK hotkeys) ────────────────────
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$WshShell = New-Object -ComObject WScript.Shell

$altSnapLnk = Join-Path $startupDir "AltSnap.lnk"
$lnk = $WshShell.CreateShortcut($altSnapLnk)
$lnk.TargetPath = $altSnapExe
$lnk.WorkingDirectory = $altSnapDir
$lnk.Description = "AltSnap - Alt+drag to move/resize windows"
$lnk.Save()
Write-Host "  [OK] AltSnap startup shortcut"

$ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$ahkScript = Join-Path $PSScriptRoot "hotkeys.ahk"
if ((Test-Path $ahkExe) -and (Test-Path $ahkScript)) {
    $hotkeysLnk = Join-Path $startupDir "Hotkeys.lnk"
    $lnk = $WshShell.CreateShortcut($hotkeysLnk)
    $lnk.TargetPath = $ahkExe
    $lnk.Arguments = "`"$ahkScript`""
    $lnk.WorkingDirectory = Split-Path $ahkScript
    $lnk.Description = "AHK hotkeys"
    $lnk.Save()
    Write-Host "  [OK] AHK hotkeys startup shortcut"
} else {
    Write-Host "  [WARN] AHK or hotkeys.ahk missing — install AHK via winget then re-run"
}

Write-Host ""
Write-Host "Restart Explorer to apply changes:"
Write-Host "  Stop-Process -Name explorer -Force"
