# Requires -Version 5.1
<#
.SYNOPSIS
Finds Bluetooth headset battery information exposed by Windows.

.DESCRIPTION
Windows can expose Bluetooth battery data through more than one surface:
PnP device properties, Association Endpoint (AEP) WinRT properties, and
Bluetooth LE GATT Battery Service. This script probes the public Windows
surfaces that are practical from PowerShell and prints matching devices.
#>

[CmdletBinding()]
param(
    [string]$NamePattern = 'soundcore|Liberty|Headphones|Headset',
    [switch]$IncludeDiagnostics,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-PlainValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [byte[]]) {
        return ($Value | ForEach-Object { $_.ToString('X2') }) -join ' '
    }

    return $Value
}

function Get-PnpBatteryCandidates {
    $devices = Get-PnpDevice -ErrorAction Stop |
        Where-Object { $_.FriendlyName -match $NamePattern -or $_.InstanceId -match $NamePattern }

    $batteryKeys = @(
        'System.Devices.BatteryLife',
        '{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2'
    )

    $diagnosticKeys = @(
        'DEVPKEY_Device_PowerData',
        '{49CD1F76-5626-4B17-A4E8-18B4AA1A2213} 10'
    )

    foreach ($device in $devices) {
        $props = @()
        try {
            $props = Get-PnpDeviceProperty -InstanceId $device.InstanceId -ErrorAction Stop
        } catch {
            continue
        }

        foreach ($prop in $props) {
            $isInteresting = $batteryKeys -contains $prop.KeyName

            if ($IncludeDiagnostics) {
                $isInteresting =
                    $isInteresting -or
                    $diagnosticKeys -contains $prop.KeyName -or
                    $prop.KeyName -match 'Battery|Power|104EA319|49CD1F76' -or
                    ($prop.Type -eq 'Byte' -and $null -ne $prop.Data)
            }

            if (-not $isInteresting) {
                continue
            }

            [PSCustomObject]@{
                Source       = 'PnP'
                Class        = $device.Class
                Name         = $device.FriendlyName
                Key          = $prop.KeyName
                Type         = $prop.Type
                Value        = ConvertTo-PlainValue $prop.Data
                InstanceId   = $device.InstanceId
            }
        }
    }
}

function Invoke-WinRtAsync {
    param(
        [Parameter(Mandatory)]
        [object]$AsyncOp,

        [Parameter(Mandatory)]
        [Type]$ResultType
    )

    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethod -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOp))
    $task.Wait()
    Write-Output -NoEnumerate $task.Result
}

function Get-AepBatteryCandidates {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime

    $null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType=WindowsRuntime]
    $null = [Windows.Devices.Enumeration.DeviceInformationKind, Windows.Devices.Enumeration, ContentType=WindowsRuntime]
    $collectionType = [Windows.Devices.Enumeration.DeviceInformationCollection]

    # Bluetooth Classic protocol id used by Windows Association Endpoints.
    $selector = 'System.Devices.Aep.ProtocolId:="{E0CBF06C-CD8B-4647-BB8A-263B43F0F974}"'
    $props = [System.Collections.Generic.List[string]]::new()
    @(
        'System.Devices.Aep.DeviceAddress',
        'System.Devices.Aep.IsConnected',
        'System.Devices.Aep.IsPaired',
        'System.Devices.BatteryLife'
    ) | ForEach-Object { [void]$props.Add($_) }

    $kind = [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint
    $op = [Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($selector, $props, $kind)
    $devices = @(Invoke-WinRtAsync -AsyncOp $op -ResultType $collectionType)

    foreach ($device in $devices) {
        if ($device.Name -notmatch $NamePattern -and $device.Id -notmatch $NamePattern) {
            continue
        }

        [PSCustomObject]@{
            Source       = 'WinRT-AEP'
            Class        = 'AssociationEndpoint'
            Name         = $device.Name
            Key          = 'System.Devices.BatteryLife'
            Type         = $null
            Value        = $device.Properties['System.Devices.BatteryLife']
            InstanceId   = $device.Id
            Address      = $device.Properties['System.Devices.Aep.DeviceAddress']
            Paired       = $device.Properties['System.Devices.Aep.IsPaired']
            Connected    = $device.Properties['System.Devices.Aep.IsConnected']
        }
    }
}

$results = @()

try {
    $results += Get-PnpBatteryCandidates
} catch {
    Write-Warning "PnP probe failed: $($_.Exception.Message)"
}

try {
    $results += Get-AepBatteryCandidates
} catch {
    Write-Warning "WinRT AEP probe failed: $($_.Exception.Message)"
}

if ($Json) {
    $results | ConvertTo-Json -Depth 6
} else {
    $results |
        Sort-Object Source, Name, Key |
        Format-Table Source, Class, Name, Key, Type, Value, Connected -AutoSize -Wrap
}
