<#
.SYNOPSIS
    Builds release artifacts for Mirroring Windows and Mirroring Android Companion.

.DESCRIPTION
    Resolves the repository root regardless of the caller's working directory,
    verifies Flutter and project manifests, resolves dependencies, runs static
    analysis (unless -SkipAnalyze is set), and builds Windows and/or Android
    release outputs with strict exit-code validation.

.PARAMETER WindowsOnly
    Build only apps/mirroring_windows.

.PARAMETER MobileOnly
    Build only apps/mirroring_mobile.

.PARAMETER SkipAnalyze
    Skip `flutter analyze` before building.

.EXAMPLE
    .\build-release.ps1
    .\build-release.ps1 -WindowsOnly
    .\build-release.ps1 -MobileOnly -SkipAnalyze
#>
[CmdletBinding()]
param(
    [switch]$WindowsOnly,
    [switch]$MobileOnly,
    [switch]$SkipAnalyze
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($WindowsOnly -and $MobileOnly) {
    Write-Error 'Cannot specify both -WindowsOnly and -MobileOnly.'
    exit 1
}

function Resolve-RepoRoot {
    param([string]$ScriptDir)
    if (Test-Path (Join-Path $ScriptDir 'apps\mirroring_windows\pubspec.yaml')) {
        return $ScriptDir
    }
    $parent = Split-Path -Parent $ScriptDir
    if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path (Join-Path $parent 'apps\mirroring_windows\pubspec.yaml'))) {
        return $parent
    }
    return $ScriptDir
}

$RepoRoot = Resolve-RepoRoot -ScriptDir $PSScriptRoot
$ProtocolDir = Join-Path $RepoRoot 'packages\mirroring_protocol'
$WindowsAppDir = Join-Path $RepoRoot 'apps\mirroring_windows'
$MobileAppDir = Join-Path $RepoRoot 'apps\mirroring_mobile'

function Resolve-FlutterExecutable {
    $cmd = Get-Command 'flutter' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }
    $localBat = Join-Path $RepoRoot 'flutter.bat'
    if (Test-Path $localBat) {
        return $localBat
    }
    throw 'Flutter CLI was not found on PATH. Install Flutter SDK and ensure `flutter` is available.'
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$StepName
    )

    Write-Host "==> $StepName" -ForegroundColor Cyan
    Push-Location $WorkingDirectory
    try {
        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$StepName failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

try {
    $FlutterExe = Resolve-FlutterExecutable
    Write-Host "Repository root : $RepoRoot"
    Write-Host "Flutter CLI     : $FlutterExe"

    & $FlutterExe --version
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to invoke Flutter CLI (exit code $LASTEXITCODE)."
    }

    if (-not (Test-Path (Join-Path $ProtocolDir 'pubspec.yaml'))) {
        throw "Missing shared package manifest: $ProtocolDir\pubspec.yaml"
    }
    if (-not (Test-Path (Join-Path $WindowsAppDir 'pubspec.yaml'))) {
        throw "Missing Windows app manifest: $WindowsAppDir\pubspec.yaml"
    }
    if (-not (Test-Path (Join-Path $MobileAppDir 'pubspec.yaml'))) {
        throw "Missing Mobile app manifest: $MobileAppDir\pubspec.yaml"
    }

    # Resolve shared protocol package dependencies first
    Invoke-CheckedCommand -WorkingDirectory $ProtocolDir -Executable $FlutterExe -Arguments @('pub', 'get') -StepName 'Resolving mirroring_protocol dependencies'
    if (-not $SkipAnalyze) {
        Invoke-CheckedCommand -WorkingDirectory $ProtocolDir -Executable $FlutterExe -Arguments @('analyze') -StepName 'Analyzing mirroring_protocol'
    }

    $buildWindows = -not $MobileOnly
    $buildMobile = -not $WindowsOnly

    $windowsReleaseDir = Join-Path $WindowsAppDir 'build\windows\x64\runner\Release'
    $mobileApkPath = Join-Path $MobileAppDir 'build\app\outputs\flutter-apk\app-release.apk'

    if ($buildWindows) {
        Invoke-CheckedCommand -WorkingDirectory $WindowsAppDir -Executable $FlutterExe -Arguments @('pub', 'get') -StepName 'Resolving mirroring_windows dependencies'
        if (-not $SkipAnalyze) {
            Invoke-CheckedCommand -WorkingDirectory $WindowsAppDir -Executable $FlutterExe -Arguments @('analyze') -StepName 'Analyzing mirroring_windows'
        }
        Invoke-CheckedCommand -WorkingDirectory $WindowsAppDir -Executable $FlutterExe -Arguments @('build', 'windows', '--release') -StepName 'Building Mirroring Windows (Release)'

        $exePath = Join-Path $windowsReleaseDir 'Mirroring.exe'
        if (-not (Test-Path $exePath)) {
            throw "Expected Windows release executable not found at: $exePath"
        }
    }

    if ($buildMobile) {
        Invoke-CheckedCommand -WorkingDirectory $MobileAppDir -Executable $FlutterExe -Arguments @('pub', 'get') -StepName 'Resolving mirroring_mobile dependencies'
        if (-not $SkipAnalyze) {
            Invoke-CheckedCommand -WorkingDirectory $MobileAppDir -Executable $FlutterExe -Arguments @('analyze') -StepName 'Analyzing mirroring_mobile'
        }
        Invoke-CheckedCommand -WorkingDirectory $MobileAppDir -Executable $FlutterExe -Arguments @('build', 'apk', '--release') -StepName 'Building Mirroring Mobile APK (Release)'

        if (-not (Test-Path $mobileApkPath)) {
            throw "Expected Android release APK not found at: $mobileApkPath"
        }
    }

    Write-Host ''
    Write-Host 'Release build completed successfully.' -ForegroundColor Green
    if ($buildWindows) {
        Write-Host "  Windows Release Dir : $windowsReleaseDir"
        Write-Host "  Windows Executable  : $(Join-Path $windowsReleaseDir 'Mirroring.exe')"
    }
    if ($buildMobile) {
        $apkItem = Get-Item $mobileApkPath
        $apkMb = [math]::Round($apkItem.Length / 1MB, 2)
        Write-Host "  Android Release APK : $mobileApkPath ($apkMb MB, built $($apkItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))"
    }
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
