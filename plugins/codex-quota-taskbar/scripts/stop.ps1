# CODEX_QUOTA_PLUGIN_STOP_ENTRY
param(
    [switch]$OverlayOnly
)

. "$PSScriptRoot\common.ps1"

$srcDir = Join-Path $script:CompanionRoot "src"
if ($OverlayOnly) {
    $stopScript = Find-CodexQuotaScriptByMarker -Directory $srcDir -Marker "CODEX_QUOTA_STOP_OVERLAY_ENTRY"
}
else {
    $stopScript = Find-CodexQuotaScriptByMarker -Directory $srcDir -Marker "CODEX_QUOTA_STOP_MONITOR_ENTRY"
}

& $stopScript

