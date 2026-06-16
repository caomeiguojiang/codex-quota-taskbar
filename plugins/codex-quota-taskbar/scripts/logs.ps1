# CODEX_QUOTA_PLUGIN_LOGS_ENTRY
param(
    [switch]$Open
)

. "$PSScriptRoot\common.ps1"

$logDir = Join-Path (Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar") "logs"
Write-Output "Log directory: $logDir"

if (Test-Path -LiteralPath $logDir) {
    Get-ChildItem -LiteralPath $logDir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 20 FullName, LastWriteTime, Length
}
else {
    Write-Output "No log directory exists yet."
}

if ($Open) {
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Start-Process -FilePath $logDir | Out-Null
}

