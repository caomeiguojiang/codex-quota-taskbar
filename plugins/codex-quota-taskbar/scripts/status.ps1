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

$monitorProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*CODEX_QUOTA_MONITOR_ENTRY*" -or $_.CommandLine -like "*CodexQuotaTaskbar*"
})

[pscustomobject]@{
    PluginRoot = $script:PluginRoot
    CompanionRoot = $script:CompanionRoot
    DefaultInstallRoot = $installRoot
    Installed = (Test-Path -LiteralPath $installRoot)
    AutoStart = [bool]$runValue
    AutoStartCommand = $runValue
    SettingsPath = (Join-Path $env:APPDATA "CodexQuotaTaskbar\settings.json")
    LogsPath = (Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar\logs")
    CandidatePowerShellProcesses = $monitorProcesses.Count
}

