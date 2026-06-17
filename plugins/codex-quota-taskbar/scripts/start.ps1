# CODEX_QUOTA_PLUGIN_START_ENTRY
param(
    [switch]$Installed,
    [string]$InstallDir = "",
    [switch]$Configure,
    [int]$PollSeconds = 2,
    [switch]$AllScreens,
    [string]$CodexExe = ""
)

. "$PSScriptRoot\common.ps1"

if ($Installed) {
    $root = Get-CodexQuotaInstallRoot -InstallDir $InstallDir
}
else {
    $root = $script:CompanionRoot
}

$nativeExe = Join-Path $root "bin\CodexQuotaTaskbar.exe"
if (Test-Path -LiteralPath $nativeExe) {
    $nativeArgs = @(
        "--poll-seconds",
        ([string]$PollSeconds)
    )

    if ($Configure) {
        $nativeArgs += "--configure"
    }
    else {
        $nativeArgs += "--no-config"
    }
    if ($AllScreens) {
        $nativeArgs += "--all-screens"
    }
    if ($CodexExe) {
        $nativeArgs += @("--codex-exe", $CodexExe)
    }

    Start-Process -FilePath $nativeExe -ArgumentList (Join-CodexQuotaCommandArguments $nativeArgs) -WindowStyle Hidden | Out-Null
    Write-Output "Started native Codex quota monitor from: $root"
    return
}

$srcDir = Join-Path $root "src"
$monitorScript = Find-CodexQuotaScriptByMarker -Directory $srcDir -Marker "CODEX_QUOTA_MONITOR_ENTRY"
$powershell = Get-CodexQuotaPowerShell

$monitorArgs = @(
    "-NoProfile",
    "-STA",
    "-ExecutionPolicy",
    "Bypass",
    "-WindowStyle",
    "Hidden",
    "-File",
    $monitorScript,
    "-PollSeconds",
    ([string]$PollSeconds)
)

if (-not $Configure) {
    $monitorArgs += "-NoConfig"
}
if ($AllScreens) {
    $monitorArgs += "-AllScreens"
}
if ($CodexExe) {
    $monitorArgs += @("-CodexExe", $CodexExe)
}

Start-Process -FilePath $powershell -ArgumentList (Join-CodexQuotaCommandArguments $monitorArgs) -WindowStyle Hidden | Out-Null
Write-Output "Started Codex quota monitor from: $root"
