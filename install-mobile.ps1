<#
.SYNOPSIS
    Installs the built Mirroring Android Companion release APK onto a connected ADB device.

.DESCRIPTION
    Development/deployment helper only. Normal Mirroring LAN operation does not require ADB.
    Locates the latest release APK, inspects authorized devices via `adb devices -l`,
    auto-selects when a single authorized device is present, prompts when multiple
    devices are connected (or accepts -Serial), and installs via `adb -s <serial> install -r`.

.PARAMETER Serial
    Target ADB device serial (e.g. "192.168.1.50:5555" or USB serial).

.PARAMETER ApkPath
    Optional custom path to the APK file. Defaults to the Mirroring Mobile release APK.

.EXAMPLE
    .\install-mobile.ps1
    .\install-mobile.ps1 -Serial "192.168.1.50:5555"
#>
[CmdletBinding()]
param(
    [string]$Serial,
    [string]$ApkPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$ScriptDir)
    if (Test-Path (Join-Path $ScriptDir 'apps\mirroring_mobile\pubspec.yaml')) {
        return $ScriptDir
    }
    $parent = Split-Path -Parent $ScriptDir
    if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path (Join-Path $parent 'apps\mirroring_mobile\pubspec.yaml'))) {
        return $parent
    }
    return $ScriptDir
}

$RepoRoot = Resolve-RepoRoot -ScriptDir $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $RepoRoot 'apps\mirroring_mobile\build\app\outputs\flutter-apk\app-release.apk'
}

function Resolve-AdbExecutable {
    $cmd = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $sdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        if (Test-Path $sdkAdb) {
            return $sdkAdb
        }
    }
    $bundledAdb = Join-Path $RepoRoot 'apps\mirroring_windows\tools\scrcpy\adb.exe'
    if (Test-Path $bundledAdb) {
        return $bundledAdb
    }
    throw 'ADB executable was not found on PATH, Android SDK platform-tools, or apps/mirroring_windows/tools/scrcpy.'
}

try {
    if (-not (Test-Path $ApkPath)) {
        throw "Release APK not found at '$ApkPath'. Build it first by running: .\build-release.ps1 -MobileOnly"
    }

    $apkItem = Get-Item $ApkPath
    $apkSizeMb = [math]::Round($apkItem.Length / 1MB, 2)
    Write-Host "APK Path       : $($apkItem.FullName)"
    Write-Host "APK Size       : $apkSizeMb MB"
    Write-Host "APK Built Time : $($apkItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"

    $ageHours = ((Get-Date) - $apkItem.LastWriteTime).TotalHours
    if ($ageHours -gt 24) {
        Write-Warning "This APK is $([math]::Round($ageHours, 1)) hours old. Consider running .\build-release.ps1 -MobileOnly if you made recent changes."
    }

    $AdbExe = Resolve-AdbExecutable
    Write-Host "ADB Executable : $AdbExe"

    $rawDevices = & $AdbExe devices -l 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to run 'adb devices -l' (exit code $LASTEXITCODE): $($rawDevices -join ' ')"
    }

    $eligible = @()
    $ignored = @()

    foreach ($rawLine in $rawDevices) {
        $line = "$rawLine".Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('*') -or $line.StartsWith('List of devices')) { continue }

        $tokens = $line -split '\s+'
        if ($tokens.Count -lt 2) { continue }

        $devSerial = $tokens[0]
        $devState = $tokens[1].ToLowerInvariant()
        $modelToken = $tokens | Where-Object { $_.StartsWith('model:') } | Select-Object -First 1
        $modelName = if ($modelToken) { ($modelToken.Substring(6) -replace '_', ' ') } else { 'Unknown Model' }

        $entry = [PSCustomObject]@{
            Serial = $devSerial
            State  = $devState
            Model  = $modelName
            Raw    = $line
        }

        if ($devState -eq 'device') {
            $eligible += $entry
        } else {
            $ignored += $entry
        }
    }

    if ($ignored.Count -gt 0) {
        Write-Host ''
        Write-Host 'Ignored non-ready ADB devices:' -ForegroundColor Yellow
        foreach ($d in $ignored) {
            Write-Host "  - $($d.Serial) [$($d.State)]" -ForegroundColor Yellow
        }
    }

    if ($eligible.Count -eq 0) {
        throw 'No authorized ADB devices found. Connect a device via USB or already-paired Wireless Debugging (`adb connect <ip>:<port>`) and authorize RSA debugging on the phone.'
    }

    $selectedDevice = $null

    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $selectedDevice = $eligible | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
        if ($null -eq $selectedDevice) {
            $matchingIgnored = $ignored | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
            if ($null -ne $matchingIgnored) {
                throw "Device '$Serial' is currently '$($matchingIgnored.State)' and cannot be used for installation."
            }
            $availableSerials = ($eligible | ForEach-Object { $_.Serial }) -join ', '
            throw "Requested device serial '$Serial' was not found among authorized devices: $availableSerials"
        }
    } elseif ($eligible.Count -eq 1) {
        $selectedDevice = $eligible[0]
    } else {
        Write-Host ''
        Write-Host 'Multiple authorized ADB devices detected:' -ForegroundColor Cyan
        for ($i = 0; $i -lt $eligible.Count; $i++) {
            $d = $eligible[$i]
            Write-Host "  [$($i + 1)] $($d.Serial)  ($($d.Model))"
        }
        $choice = Read-Host "Select target device [1-$($eligible.Count)] or enter serial"
        $trimmedChoice = "$choice".Trim()
        $parsedIndex = 0
        if ([int]::TryParse($trimmedChoice, [ref]$parsedIndex) -and $parsedIndex -ge 1 -and $parsedIndex -le $eligible.Count) {
            $selectedDevice = $eligible[$parsedIndex - 1]
        } else {
            $selectedDevice = $eligible | Where-Object { $_.Serial -eq $trimmedChoice } | Select-Object -First 1
        }
        if ($null -eq $selectedDevice) {
            throw "Invalid selection '$trimmedChoice'. Aborting installation."
        }
    }

    Write-Host ''
    Write-Host "==> Installing APK to $($selectedDevice.Serial) ($($selectedDevice.Model))..." -ForegroundColor Cyan
    & $AdbExe -s $selectedDevice.Serial install -r $apkItem.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "ADB installation failed on '$($selectedDevice.Serial)' with exit code $LASTEXITCODE."
    }

    Write-Host ''
    Write-Host "Successfully installed Mirroring APK on $($selectedDevice.Serial) ($($selectedDevice.Model))." -ForegroundColor Green
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
