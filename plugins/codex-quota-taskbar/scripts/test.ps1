# CODEX_QUOTA_PLUGIN_TEST_ENTRY
param(
    [switch]$SkipVisual,
    [switch]$KeepArtifacts
)

. "$PSScriptRoot\common.ps1"

$manifestPath = Join-Path $script:PluginRoot ".codex-plugin\plugin.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Plugin manifest not found: $manifestPath"
}

$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
if ($manifestBytes.Length -ge 3 -and $manifestBytes[0] -eq 0xEF -and $manifestBytes[1] -eq 0xBB -and $manifestBytes[2] -eq 0xBF) {
    throw "Plugin manifest must be UTF-8 without BOM: $manifestPath"
}

$null = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$testScript = Join-Path $script:CompanionRoot "scripts\Test-CodexQuotaTaskbar.ps1"
if (-not (Test-Path -LiteralPath $testScript)) {
    throw "Companion test script not found: $testScript"
}

try {
    if ($SkipVisual) {
        & $testScript -SkipVisual
    }
    else {
        & $testScript
    }
}
finally {
    if (-not $KeepArtifacts) {
        $testProfile = Join-Path $script:CompanionRoot ".test-profile"
        if (Test-Path -LiteralPath $testProfile) {
            Remove-Item -LiteralPath $testProfile -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
