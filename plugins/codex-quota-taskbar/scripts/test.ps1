# CODEX_QUOTA_PLUGIN_TEST_ENTRY
param(
    [switch]$SkipVisual,
    [switch]$KeepArtifacts
)

. "$PSScriptRoot\common.ps1"

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
