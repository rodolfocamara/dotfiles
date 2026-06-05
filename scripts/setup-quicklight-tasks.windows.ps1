# Requires -Version 5.1
<#
.SYNOPSIS
Registers (or removes) Task Scheduler entries that drive the Quiklight USB LED strip.

.DESCRIPTION
Sets up four tasks that call quicklight-static.windows.py to keep the LED strip
in sync with session state:

  1. Quiklight Static Color  — at logon (re-applies the static color on boot).
  2. Quiklight On Plug       — on PnP "device configured" event (best-effort
                                refresh when USB is re-plugged; the widget's
                                WM_DEVICECHANGE handler is the real fix).
  3. Quiklight Off On Lock   — when the workstation locks, run with --off.
  4. Quiklight On Unlock     — when the workstation unlocks, re-apply color.

Idempotent: re-running replaces existing tasks.

.PARAMETER Remove
Unregister all four tasks instead of (re)creating them.
#>

[CmdletBinding()]
param(
    [switch]$Remove
)

if (-not $IsWindows) {
    Write-Verbose "Skipping Quiklight tasks on non-Windows host"
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$user = "$env:USERDOMAIN\$env:USERNAME"
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'scripts\quicklight-static.windows.py'

$pythonw = Get-Command pythonw.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $pythonw) {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python313\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\pythonw.exe"
    )
    $pythonw = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $pythonw) {
    throw "pythonw.exe not found on PATH or in %LOCALAPPDATA%\Programs\Python\*. Install Python or adjust this script."
}

$tasks = @(
    [PSCustomObject]@{
        Name = 'Quiklight Static Color'
        ScriptArgs = ''
        TriggerXml = @"
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT10S</Delay>
      <UserId>$user</UserId>
    </LogonTrigger>
"@
    },
    [PSCustomObject]@{
        Name = 'Quiklight On Plug'
        ScriptArgs = ''
        TriggerXml = @"
    <EventTrigger>
      <Enabled>true</Enabled>
      <Delay>PT2S</Delay>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-Kernel-PnP/Configuration"&gt;&lt;Select Path="Microsoft-Windows-Kernel-PnP/Configuration"&gt;*[System[(EventID=400)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
"@
    },
    [PSCustomObject]@{
        Name = 'Quiklight Off On Lock'
        ScriptArgs = '--off'
        TriggerXml = @"
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionLock</StateChange>
      <UserId>$user</UserId>
    </SessionStateChangeTrigger>
"@
    },
    [PSCustomObject]@{
        Name = 'Quiklight On Unlock'
        ScriptArgs = ''
        TriggerXml = @"
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionUnlock</StateChange>
      <UserId>$user</UserId>
    </SessionStateChangeTrigger>
"@
    }
)

if ($Remove) {
    foreach ($t in $tasks) {
        if (Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false
            Write-Host "  [OK] Removed $($t.Name)"
        }
    }
    exit 0
}

if (-not (Test-Path $script)) {
    throw "quicklight-static.windows.py not found at $script"
}

foreach ($t in $tasks) {
    $argString = if ($t.ScriptArgs) { " $($t.ScriptArgs)" } else { '' }
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>$user</Author>
    <URI>\$($t.Name)</URI>
  </RegistrationInfo>
  <Triggers>
$($t.TriggerXml)
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$user</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$pythonw</Command>
      <Arguments>"$script"$argString</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    Register-ScheduledTask -TaskName $t.Name -Xml $xml -Force | Out-Null
    Write-Host "  [OK] Registered $($t.Name)"
}
