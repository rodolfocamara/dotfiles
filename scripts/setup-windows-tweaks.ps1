# Requires -Version 5.1
<#
.SYNOPSIS
Run after a fresh install or when restoring dotfiles.
#>

if (-not $IsWindows) {
    Write-Verbose "Skipping Windows tweaks on non-Windows host"
    exit 0
}

Write-Host "Applying Windows tweaks..."

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

Write-Host ""
Write-Host "Restart Explorer to apply changes:"
Write-Host "  Stop-Process -Name explorer -Force"
