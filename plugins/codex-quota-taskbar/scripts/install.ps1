# CODEX_QUOTA_PLUGIN_INSTALL_ENTRY
param(
    [string]$InstallDir = "",
    [switch]$NoAutoStart,
    [switch]$StartNow
)

. "$PSScriptRoot\common.ps1"

$installScript = Find-CodexQuotaScriptByMarker -Directory $script:CompanionRoot -Marker "CODEX_QUOTA_INSTALL_ENTRY"

$invokeArgs = @{}
if ($InstallDir) {
    $invokeArgs.InstallDir = $InstallDir
}
if ($NoAutoStart) {
    $invokeArgs.NoAutoStart = $true
}
if ($StartNow) {
    $invokeArgs.StartNow = $true
}

& $installScript @invokeArgs
