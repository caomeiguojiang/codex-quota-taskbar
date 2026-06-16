# CODEX_QUOTA_PLUGIN_UNINSTALL_ENTRY
param(
    [string]$InstallDir = "",
    [switch]$KeepSettings
)

. "$PSScriptRoot\common.ps1"

$uninstallScript = Find-CodexQuotaScriptByMarker -Directory $script:CompanionRoot -Marker "CODEX_QUOTA_UNINSTALL_ENTRY"

$invokeArgs = @{}
if ($InstallDir) {
    $invokeArgs.InstallDir = $InstallDir
}
if ($KeepSettings) {
    $invokeArgs.KeepSettings = $true
}

& $uninstallScript @invokeArgs
