param(
    [switch]$SkipVisual
)

$ErrorActionPreference = "Stop"

function Find-ScriptByMarker {
    param(
        [string]$Directory,
        [string]$Marker
    )

    $match = Get-ChildItem -LiteralPath $Directory -Filter "*.ps1" -File | Where-Object {
        $firstLine = Get-Content -LiteralPath $_.FullName -Encoding UTF8 -TotalCount 1
        ([string]$firstLine).Trim() -eq "# $Marker"
    } | Select-Object -First 1

    if (-not $match) {
        throw "Required script marker not found: $Marker"
    }
    return $match.FullName
}

function Assert-PowerShellParse {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $messages = $errors | ForEach-Object { "{0}:{1} {2}" -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message }
        throw "Parse failed for $Path`n$($messages -join "`n")"
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
$srcDir = Join-Path $root "src"

if (-not (Test-Path -LiteralPath $srcDir)) {
    throw "src directory not found: $srcDir"
}

Get-ChildItem -LiteralPath $root -Filter "*.ps1" -File | ForEach-Object {
    Assert-PowerShellParse $_.FullName
}
Get-ChildItem -LiteralPath $srcDir -Filter "*.ps1" -File | ForEach-Object {
    Assert-PowerShellParse $_.FullName
}

$sourceSettings = Join-Path $srcDir "CodexQuotaTaskbar.settings.json"
if (Test-Path -LiteralPath $sourceSettings) {
    throw "Machine-local settings file must not be in src: $sourceSettings"
}

$overlayScript = Find-ScriptByMarker $srcDir "CODEX_QUOTA_OVERLAY_ENTRY"
$stopOverlayScript = Find-ScriptByMarker $srcDir "CODEX_QUOTA_STOP_OVERLAY_ENTRY"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$nativeExe = Join-Path $root "bin\CodexQuotaTaskbar.exe"

$oldAppData = $env:APPDATA
$oldLocalAppData = $env:LOCALAPPDATA
$testProfileRoot = Join-Path $root ".test-profile"
$env:APPDATA = Join-Path $testProfileRoot "AppData\Roaming"
$env:LOCALAPPDATA = Join-Path $testProfileRoot "AppData\Local"
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null

try {
    $onceOutput = & $powershell -NoProfile -STA -ExecutionPolicy Bypass -File $overlayScript -Once -MockQuota 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Mock -Once failed: $onceOutput"
    }
    if (($onceOutput -join "`n") -notmatch "5H") {
        throw "Mock -Once output did not include expected quota text: $onceOutput"
    }

    if (Test-Path -LiteralPath $nativeExe) {
        $nativeOnce = Start-Process -FilePath $nativeExe -ArgumentList @("--once", "--mock-quota") -Wait -PassThru -WindowStyle Hidden
        if ($nativeOnce.ExitCode -ne 0) {
            throw "Native mock -Once failed with exit code $($nativeOnce.ExitCode)"
        }
    }

    if (-not $SkipVisual) {
        $qaRoot = Join-Path $root "visual-qa"
        $qaDir = Join-Path $qaRoot (Get-Date -Format "yyyyMMdd-HHmmss")
        New-Item -ItemType Directory -Path $qaDir -Force | Out-Null

        $visualOutput = & $powershell -NoProfile -STA -ExecutionPolicy Bypass -File $overlayScript -MockQuota -VisualQa -VisualQaOutputDir $qaDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Visual QA failed: $visualOutput"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $qaDir "visual-qa.json"))) {
            throw "Visual QA metadata was not created: $qaDir"
        }
        if (@(Get-ChildItem -LiteralPath $qaDir -Filter "*.png" -File).Count -eq 0) {
            throw "Visual QA PNG was not created: $qaDir"
        }

        if (Test-Path -LiteralPath $nativeExe) {
            $nativeQaDir = Join-Path $qaRoot ("native-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
            New-Item -ItemType Directory -Path $nativeQaDir -Force | Out-Null

            $nativeVisual = Start-Process -FilePath $nativeExe -ArgumentList @("--visual-qa", "--mock-quota", "--visual-qa-output-dir", $nativeQaDir) -Wait -PassThru -WindowStyle Hidden
            if ($nativeVisual.ExitCode -ne 0) {
                throw "Native visual QA failed with exit code $($nativeVisual.ExitCode)"
            }
            if (-not (Test-Path -LiteralPath (Join-Path $nativeQaDir "native-visual-qa.json"))) {
                throw "Native visual QA metadata was not created: $nativeQaDir"
            }
            if (@(Get-ChildItem -LiteralPath $nativeQaDir -Filter "*.png" -File).Count -eq 0) {
                throw "Native visual QA PNG was not created: $nativeQaDir"
            }
        }
    }

    & $powershell -NoProfile -ExecutionPolicy Bypass -File $stopOverlayScript | Out-Null
}
finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalAppData
}
Write-Output "Codex quota taskbar tests passed."
