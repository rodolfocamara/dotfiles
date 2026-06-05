# Requires -Version 5.1
<#
.SYNOPSIS
Inspects the Bluetooth LE GATT surface exposed by Soundcore earbuds.

.DESCRIPTION
Windows exposes only the aggregate headset battery through PnP/HFP for many
TWS earbuds. Left/right/case battery values are usually available only through
manufacturer-specific BLE services. This script enumerates the Soundcore BLE
endpoint and attempts to read each characteristic so the payload can be decoded.
#>

[CmdletBinding()]
param(
    [string]$NamePattern = 'soundcore',
    [int]$Retries = 5,
    [int]$DelaySeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.WindowsRuntime

function Await-WinRt {
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

function Convert-BufferToHex {
    param([object]$Buffer)

    if ($null -eq $Buffer) {
        return ''
    }

    $null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType=WindowsRuntime]
    $null = [Windows.Storage.Streams.IBuffer, Windows.Storage.Streams, ContentType=WindowsRuntime]
    $reader = [Windows.Storage.Streams.DataReader]::FromBuffer([Windows.Storage.Streams.IBuffer]$Buffer)
    $bytes = New-Object byte[] $reader.UnconsumedBufferLength
    $reader.ReadBytes($bytes)
    return ($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
}

$null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType=WindowsRuntime]
$null = [Windows.Devices.Enumeration.DeviceInformationKind, Windows.Devices.Enumeration, ContentType=WindowsRuntime]
$null = [Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType=WindowsRuntime]
$null = [Windows.Devices.Bluetooth.BluetoothCacheMode, Windows.Devices.Bluetooth, ContentType=WindowsRuntime]
$null = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult, Windows.Devices.Bluetooth, ContentType=WindowsRuntime]
$null = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicsResult, Windows.Devices.Bluetooth, ContentType=WindowsRuntime]
$null = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattReadResult, Windows.Devices.Bluetooth, ContentType=WindowsRuntime]

$props = [System.Collections.Generic.List[string]]::new()
@(
    'System.Devices.Aep.DeviceAddress',
    'System.Devices.Aep.IsConnected',
    'System.Devices.Aep.IsPaired',
    'System.Devices.Aep.Bluetooth.Le.IsConnectable'
) | ForEach-Object { [void]$props.Add($_) }

$selector = 'System.Devices.Aep.ProtocolId:="{BB7BB05E-5972-42B5-94FC-76EAA7084D49}"'
$kind = [Windows.Devices.Enumeration.DeviceInformationKind]::AssociationEndpoint
$devices = Await-WinRt `
    -AsyncOp ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($selector, $props, $kind)) `
    -ResultType ([Windows.Devices.Enumeration.DeviceInformationCollection])

$targets = foreach ($deviceInfo in $devices) {
    $ble = Await-WinRt `
        -AsyncOp ([Windows.Devices.Bluetooth.BluetoothLEDevice]::FromIdAsync($deviceInfo.Id)) `
        -ResultType ([Windows.Devices.Bluetooth.BluetoothLEDevice])

    if ($null -ne $ble -and ($deviceInfo.Name -match $NamePattern -or $ble.Name -match $NamePattern)) {
        [PSCustomObject]@{
            DeviceInfo = $deviceInfo
            Ble        = $ble
        }
    }
}

foreach ($target in $targets) {
    $ble = $target.Ble
    $deviceInfo = $target.DeviceInfo
    Write-Host "Device: $($ble.Name) / $($deviceInfo.Name)"
    Write-Host ("Address: {0:X12}" -f $ble.BluetoothAddress)
    Write-Host "Id: $($deviceInfo.Id)"

    $serviceResult = $null
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $serviceResult = Await-WinRt `
            -AsyncOp ($ble.GetGattServicesAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Uncached)) `
            -ResultType ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult])

        if ($serviceResult.Status -eq 'Success') {
            break
        }

        Write-Host "Attempt ${attempt}: services $($serviceResult.Status)"
        Start-Sleep -Seconds $DelaySeconds
    }

    if ($null -eq $serviceResult -or $serviceResult.Status -ne 'Success') {
        Write-Warning "Could not read GATT services for $($ble.Name): $($serviceResult.Status)"
        continue
    }

    foreach ($service in $serviceResult.Services) {
        Write-Host "Service $($service.Uuid)"
        $charResult = Await-WinRt `
            -AsyncOp ($service.GetCharacteristicsAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Uncached)) `
            -ResultType ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicsResult])

        $characteristics = @($charResult.Characteristics)
        Write-Host "  Characteristics: $($charResult.Status) count=$($characteristics.Count)"

        if ($charResult.Status -ne 'Success') {
            continue
        }

        foreach ($characteristic in $characteristics) {
            $readStatus = 'not-read'
            $hex = ''

            try {
                $read = Await-WinRt `
                    -AsyncOp ($characteristic.ReadValueAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Uncached)) `
                    -ResultType ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattReadResult])

                $readStatus = $read.Status
                if ($read.Status -eq 'Success') {
                    $hex = Convert-BufferToHex $read.Value
                } elseif ($read.ProtocolError) {
                    $readStatus = "$readStatus protocol=$($read.ProtocolError)"
                }
            } catch {
                $readStatus = "error: $($_.Exception.Message)"
            }

            Write-Host "  Characteristic $($characteristic.Uuid) props=$($characteristic.CharacteristicProperties) read=$readStatus hex=$hex"
        }
    }
}
