# CODEX_QUOTA_INSTALL_ENTRY
param(
    [string]$InstallDir = "",
    [switch]$NoAutoStart,
    [switch]$StartNow
)

$ErrorActionPreference = "Stop"

function Find-ScriptByMarker {
    param(
        [string]$Directory,
        [string]$Marker
    )

    $match = Get-ChildItem -LiteralPath $Directory -Filter "*.ps1" -File | Where-Object {
        $firstLine = Get-Content -LiteralPath $_.FullName -Encoding UTF8 -TotalCount 1
        ([string]$firstLine).Trim() -eq "# $Marker"
    } | Select-Object -First 1

    if (-not $match) {
        throw "Required script marker not found: $Marker"
    }
    return $match.FullName
}

function New-Shortcut {
    param(
        [string]$Path,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$Description
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.Save()
}

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceSrcDir = Join-Path $sourceDir "src"
$sourceBinDir = Join-Path $sourceDir "bin"
$sourceNativeDir = Join-Path $sourceDir "native"
if (-not (Test-Path -LiteralPath $sourceSrcDir)) {
    throw "src directory not found: $sourceSrcDir"
}

if (-not $InstallDir) {
    $InstallDir = Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar\app"
}

$installRoot = [System.IO.Path]::GetFullPath($InstallDir)
$installSrcDir = Join-Path $installRoot "src"
New-Item -ItemType Directory -Path $installSrcDir -Force | Out-Null

foreach ($name in @("README.md", "AGENTS.md", "VERSION")) {
    $sourcePath = Join-Path $sourceDir $name
    if (Test-Path -LiteralPath $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $installRoot $name) -Force
    }
}

Get-ChildItem -LiteralPath $sourceDir -Filter "*.cmd" -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $installRoot $_.Name) -Force
}

Get-ChildItem -LiteralPath $sourceDir -Filter "*.ps1" -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $installRoot $_.Name) -Force
}

Get-ChildItem -LiteralPath $sourceSrcDir -Filter "*.ps1" -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $installSrcDir $_.Name) -Force
}

if (Test-Path -LiteralPath $sourceBinDir) {
    Copy-Item -LiteralPath $sourceBinDir -Destination $installRoot -Recurse -Force
}
if (Test-Path -LiteralPath $sourceNativeDir) {
    Copy-Item -LiteralPath $sourceNativeDir -Destination $installRoot -Recurse -Force
}

$monitorScript = Find-ScriptByMarker $installSrcDir "CODEX_QUOTA_MONITOR_ENTRY"
$stopScript = Find-ScriptByMarker $installSrcDir "CODEX_QUOTA_STOP_MONITOR_ENTRY"
$uninstallScript = Find-ScriptByMarker $installRoot "CODEX_QUOTA_UNINSTALL_ENTRY"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$monitorArgs = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$monitorScript`" -NoConfig"
$nativeExe = Join-Path $installRoot "bin\CodexQuotaTaskbar.exe"
$startTarget = $powershell
$startArgs = $monitorArgs
$runValue = "`"$powershell`" $monitorArgs"
if (Test-Path -LiteralPath $nativeExe) {
    $startTarget = $nativeExe
    $startArgs = "--no-config"
    $runValue = "`"$nativeExe`" --no-config"
}

if (-not $NoAutoStart) {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    New-Item -Path $runKey -Force | Out-Null
    Set-ItemProperty -Path $runKey -Name "CodexQuotaTaskbar" -Value $runValue
}

$programsDir = [Environment]::GetFolderPath("Programs")
$shortcutDir = Join-Path $programsDir "Codex Quota Monitor"
New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null
New-Shortcut `
    -Path (Join-Path $shortcutDir "Start Codex Quota Monitor.lnk") `
    -TargetPath $startTarget `
    -Arguments $startArgs `
    -WorkingDirectory $installRoot `
    -Description "Start Codex quota taskbar monitor"
New-Shortcut `
    -Path (Join-Path $shortcutDir "Stop Codex Quota Monitor.lnk") `
    -TargetPath $powershell `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$stopScript`"" `
    -WorkingDirectory $installRoot `
    -Description "Stop Codex quota taskbar monitor"
New-Shortcut `
    -Path (Join-Path $shortcutDir "Uninstall Codex Quota Monitor.lnk") `
    -TargetPath $powershell `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`"" `
    -WorkingDirectory $installRoot `
    -Description "Uninstall Codex quota taskbar monitor"

if ($StartNow) {
    Start-Process -FilePath $startTarget -ArgumentList $startArgs -WindowStyle Hidden | Out-Null
}

Write-Output "Installed to: $installRoot"
if ($NoAutoStart) {
    Write-Output "Auto start: disabled"
}
else {
    Write-Output "Auto start: HKCU Run\CodexQuotaTaskbar"
}
Write-Output "Settings: %APPDATA%\CodexQuotaTaskbar\settings.json"
Write-Output "Logs: %LOCALAPPDATA%\CodexQuotaTaskbar\logs"
if (Test-Path -LiteralPath $nativeExe) {
    Write-Output "Runtime: native exe"
}
else {
    Write-Output "Runtime: PowerShell fallback"
}
