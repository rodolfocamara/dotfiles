# Requires -Version 5.1
<#
.SYNOPSIS
Applies Windows system tweaks and installs window-management utilities (AHK).
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

# ── Startup shortcuts (AHK hotkeys) ──────────────────────────────
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$WshShell = New-Object -ComObject WScript.Shell

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
