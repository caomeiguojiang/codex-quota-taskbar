# CODEX_QUOTA_PLUGIN_STATUS_ENTRY
. "$PSScriptRoot\common.ps1"

$installRoot = Get-CodexQuotaInstallRoot
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runValue = ""
try {
    $runValue = (Get-ItemProperty -Path $runKey -Name "CodexQuotaTaskbar" -ErrorAction Stop).CodexQuotaTaskbar
}
catch {
    $runValue = ""
}

function Test-CodexQuotaProcessAlive {
    param([int]$ProcessId)

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return (-not $process.HasExited)
    }
    catch {
        return $false
    }
}

function Get-CodexQuotaCommandLineFilePath {
    param([string]$CommandLine)

    if (-not $CommandLine) {
        return ""
    }
    if ($CommandLine -match '(?i)-File\s+(?:"([^"]+)"|(\S+))') {
        if ($matches[1]) {
            return $matches[1]
        }
        return $matches[2]
    }
    return ""
}

function Test-CodexQuotaScriptMarker {
    param(
        [string]$Path,
        [string]$Marker
    )

    if (-not $Path) {
        return $false
    }

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $false
        }

        $firstLine = Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1 -ErrorAction Stop
        return ([string]$firstLine).Trim() -eq "# $Marker"
    }
    catch {
        return $false
    }
}

function Test-CodexQuotaScriptPathCandidate {
    param([string]$Path)

    if (-not $Path) {
        return $false
    }

    return (
        $Path -like "*\CodexQuotaTaskbar\*" -or
        $Path -like "*\codex-quota-taskbar\*" -or
        $Path -like "*\Codex额度*.ps1" -or
        $Path -like "*\Start-CodexQuota*.ps1" -or
        $Path -like "*\CodexQuotaTaskbar.ps1"
    )
}

$monitorProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue | Where-Object {
    if (Test-CodexQuotaProcessAlive ([int]$_.ProcessId)) {
        $filePath = Get-CodexQuotaCommandLineFilePath $_.CommandLine
        (Test-CodexQuotaScriptPathCandidate $filePath) -and
        (Test-CodexQuotaScriptMarker $filePath "CODEX_QUOTA_MONITOR_ENTRY")
    }
    else {
        $false
    }
})

$pluginNativeExe = Join-Path $script:CompanionRoot "bin\CodexQuotaTaskbar.exe"
$installedNativeExe = Join-Path $installRoot "bin\CodexQuotaTaskbar.exe"
$nativeProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'CodexQuotaTaskbar.exe'" -ErrorAction SilentlyContinue | Where-Object {
    if (Test-CodexQuotaProcessAlive ([int]$_.ProcessId)) {
        $_.ExecutablePath -like "*\CodexQuotaTaskbar\app\bin\CodexQuotaTaskbar.exe" -or
        $_.ExecutablePath -like "*\codex-quota-taskbar\*\companion\bin\CodexQuotaTaskbar.exe" -or
        $_.CommandLine -like "*CodexQuotaTaskbar.exe*"
    }
    else {
        $false
    }
})
$runtimeDir = Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar\runtime"
$nativeStateFiles = @()
if (Test-Path -LiteralPath $runtimeDir) {
    $nativeStateFiles = @(Get-ChildItem -LiteralPath $runtimeDir -Filter "native-*.json" -File -ErrorAction SilentlyContinue)
}

[pscustomobject]@{
    PluginRoot = $script:PluginRoot
    CompanionRoot = $script:CompanionRoot
    DefaultInstallRoot = $installRoot
    Installed = (Test-Path -LiteralPath $installRoot)
    PluginNativeExe = $pluginNativeExe
    InstalledNativeExe = $installedNativeExe
    NativeAvailable = ((Test-Path -LiteralPath $pluginNativeExe) -or (Test-Path -LiteralPath $installedNativeExe))
    AutoStart = [bool]$runValue
    AutoStartCommand = $runValue
    SettingsPath = (Join-Path $env:APPDATA "CodexQuotaTaskbar\settings.json")
    LogsPath = (Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar\logs")
    CandidatePowerShellProcesses = $monitorProcesses.Count
    CandidateNativeProcesses = $nativeProcesses.Count
    NativeRuntimeStateFiles = $nativeStateFiles.Count
}
