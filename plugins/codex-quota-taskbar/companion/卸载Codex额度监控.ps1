# CODEX_QUOTA_UNINSTALL_ENTRY
param(
    [string]$InstallDir = "",
    [switch]$KeepSettings
)

$ErrorActionPreference = "Stop"

function Find-ScriptByMarker {
    param(
        [string]$Directory,
        [string]$Marker
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        return ""
    }

    $match = Get-ChildItem -LiteralPath $Directory -Filter "*.ps1" -File | Where-Object {
        $firstLine = Get-Content -LiteralPath $_.FullName -Encoding UTF8 -TotalCount 1
        ([string]$firstLine).Trim() -eq "# $Marker"
    } | Select-Object -First 1

    if (-not $match) {
        return ""
    }
    return $match.FullName
}

if (-not $InstallDir) {
    $InstallDir = Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar\app"
}

$installRoot = [System.IO.Path]::GetFullPath($InstallDir)
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runKey -Name "CodexQuotaTaskbar" -ErrorAction SilentlyContinue

$stopScript = Find-ScriptByMarker (Join-Path $installRoot "src") "CODEX_QUOTA_STOP_MONITOR_ENTRY"
if ($stopScript) {
    & $stopScript | Out-Null
}

$programsDir = [Environment]::GetFolderPath("Programs")
$shortcutDir = Join-Path $programsDir "Codex Quota Monitor"
if (Test-Path -LiteralPath $shortcutDir) {
    Remove-Item -LiteralPath $shortcutDir -Recurse -Force
}

if (Test-Path -LiteralPath $installRoot) {
    $localRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar"))
    if ($installRoot.StartsWith($localRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $installRoot -Recurse -Force
    }
    else {
        Write-Output "InstallDir is outside %LOCALAPPDATA%\CodexQuotaTaskbar. Remove manually if desired: $installRoot"
    }
}

if (-not $KeepSettings) {
    $appDataDir = Join-Path $env:APPDATA "CodexQuotaTaskbar"
    $localDataDir = Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar"
    if (Test-Path -LiteralPath $appDataDir) {
        Remove-Item -LiteralPath $appDataDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $localDataDir) {
        Remove-Item -LiteralPath $localDataDir -Recurse -Force
    }
}

Write-Output "Uninstalled Codex quota monitor."
