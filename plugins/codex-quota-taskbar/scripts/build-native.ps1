param(
    [switch]$SyncPlugin,
    [switch]$SyncInstalled,
    [switch]$RestartInstalled,
    [string]$PluginRoot,
    [string]$InstallRoot = "$env:LOCALAPPDATA\CodexQuotaTaskbar\app"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([String]::IsNullOrWhiteSpace($PluginRoot)) {
    $PluginRoot = $repoRoot
}
$PluginRoot = [System.IO.Path]::GetFullPath($PluginRoot)
$source = Join-Path $repoRoot "companion\native\CodexQuotaTaskbar.cs"
$outDir = Join-Path $repoRoot "companion\bin"
$outExe = Join-Path $outDir "CodexQuotaTaskbar.exe"
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$wpf = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\WPF"

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Native source not found: $source"
}
if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
    throw "csc.exe not found: $csc"
}

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

& $csc /nologo /target:winexe /out:$outExe `
    /r:System.dll `
    /r:System.Core.dll `
    /r:System.Drawing.dll `
    /r:System.Windows.Forms.dll `
    /r:System.Web.Extensions.dll `
    /r:System.Xaml.dll `
    /r:$(Join-Path $wpf "WindowsBase.dll") `
    /r:$(Join-Path $wpf "PresentationCore.dll") `
    /r:$(Join-Path $wpf "PresentationFramework.dll") `
    $source

if ($LASTEXITCODE -ne 0) {
    throw "Native compilation failed with exit code $LASTEXITCODE"
}

$selfTest = Start-Process -FilePath $outExe -ArgumentList "--self-test" -Wait -PassThru -WindowStyle Hidden
if ($selfTest.ExitCode -ne 0) {
    throw "Native self-test failed with exit code $($selfTest.ExitCode)"
}

function Copy-NativeBuild {
    param(
        [string]$Root
    )

    $nativeDir = Join-Path $Root "native"
    $binDir = Join-Path $Root "bin"
    if (-not (Test-Path -LiteralPath $nativeDir -PathType Container)) {
        throw "Native target directory not found: $nativeDir"
    }
    if (-not (Test-Path -LiteralPath $binDir -PathType Container)) {
        throw "Native bin directory not found: $binDir"
    }

    $targetSource = Join-Path $nativeDir "CodexQuotaTaskbar.cs"
    $targetExe = Join-Path $binDir "CodexQuotaTaskbar.exe"
    if (-not ([System.IO.Path]::GetFullPath($source)).Equals([System.IO.Path]::GetFullPath($targetSource), [System.StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $source -Destination $targetSource -Force
    }
    if (-not ([System.IO.Path]::GetFullPath($outExe)).Equals([System.IO.Path]::GetFullPath($targetExe), [System.StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $outExe -Destination $targetExe -Force
    }
}

function Stop-InstalledNative {
    param([string]$Root)

    $installedExe = [System.IO.Path]::GetFullPath((Join-Path $Root "bin\CodexQuotaTaskbar.exe"))
    Get-Process -Name CodexQuotaTaskbar -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and ([System.IO.Path]::GetFullPath($_.Path)).Equals($installedExe, [System.StringComparison]::OrdinalIgnoreCase)
    } | ForEach-Object {
        Stop-Process -Id $_.Id -Force
    }
}

if ($SyncPlugin) {
    Copy-NativeBuild -Root (Join-Path $PluginRoot "companion")
}

if ($SyncInstalled -or $RestartInstalled) {
    Stop-InstalledNative -Root $InstallRoot
    Start-Sleep -Milliseconds 500
    Copy-NativeBuild -Root $InstallRoot
}

if ($RestartInstalled) {
    $startScript = Join-Path $PluginRoot "scripts\start.ps1"
    if (-not (Test-Path -LiteralPath $startScript -PathType Leaf)) {
        throw "Plugin start script not found: $startScript"
    }
    & $startScript -Installed
}

$hash = Get-FileHash -LiteralPath $outExe -Algorithm SHA256
Write-Output "Native build succeeded: $outExe"
Write-Output "SHA256: $($hash.Hash)"
