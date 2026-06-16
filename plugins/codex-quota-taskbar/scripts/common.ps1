# Shared helpers for Codex Quota Taskbar plugin scripts.
$ErrorActionPreference = "Stop"

$script:PluginScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:PluginRoot = Split-Path -Parent $script:PluginScriptDir
$script:CompanionRoot = Join-Path $script:PluginRoot "companion"

function Get-CodexQuotaPowerShell {
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $powershell)) {
        throw "Windows PowerShell 5.1 was not found: $powershell"
    }
    return $powershell
}

function Find-CodexQuotaScriptByMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Marker
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        throw "Directory not found: $Directory"
    }

    $match = Get-ChildItem -LiteralPath $Directory -Filter "*.ps1" -File | Where-Object {
        $firstLine = Get-Content -LiteralPath $_.FullName -Encoding UTF8 -TotalCount 1
        ([string]$firstLine).Trim() -eq "# $Marker"
    } | Select-Object -First 1

    if (-not $match) {
        throw "Required script marker not found: $Marker in $Directory"
    }

    return $match.FullName
}

function ConvertTo-CodexQuotaCommandArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Join-CodexQuotaCommandArguments {
    param([string[]]$Arguments)

    return (($Arguments | ForEach-Object { ConvertTo-CodexQuotaCommandArgument $_ }) -join " ")
}

function Get-CodexQuotaInstallRoot {
    param([string]$InstallDir = "")

    if ($InstallDir) {
        return [System.IO.Path]::GetFullPath($InstallDir)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "CodexQuotaTaskbar\app"))
}

