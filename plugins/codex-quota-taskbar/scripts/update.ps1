# CODEX_QUOTA_PLUGIN_UPDATE_ENTRY
param(
    [string]$InstallDir = "",
    [switch]$NoAutoStart,
    [switch]$StartNow
)

. "$PSScriptRoot\common.ps1"

& (Join-Path $PSScriptRoot "stop.ps1") | Out-Null

$installArgs = @{}
if ($InstallDir) {
    $installArgs.InstallDir = $InstallDir
}
if ($NoAutoStart) {
    $installArgs.NoAutoStart = $true
}
if ($StartNow) {
    $installArgs.StartNow = $true
}

& (Join-Path $PSScriptRoot "install.ps1") @installArgs
