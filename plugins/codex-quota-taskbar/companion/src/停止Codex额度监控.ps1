# CODEX_QUOTA_STOP_MONITOR_ENTRY
$ErrorActionPreference = "Stop"

function Get-LocalDataDirectory {
    $base = $env:LOCALAPPDATA
    if (-not $base) {
        $base = $env:APPDATA
    }
    if (-not $base) {
        $base = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    return Join-Path $base "CodexQuotaTaskbar"
}

function Get-RuntimeDirectory {
    return Join-Path (Get-LocalDataDirectory) "runtime"
}

function Get-OwnedAppServerIdsFromState {
    $runtimeDir = Get-RuntimeDirectory
    if (-not (Test-Path -LiteralPath $runtimeDir)) {
        return @()
    }

    $ids = New-Object System.Collections.Generic.List[int]
    Get-ChildItem -LiteralPath $runtimeDir -Filter "overlay-*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $state = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $state.AppServerPid) {
                $ids.Add([int]$state.AppServerPid)
            }
        }
        catch {
        }
    }
    return @($ids | Select-Object -Unique)
}

function Get-Win32Processes {
    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop)
    }
    catch {
        Write-Warning "Cannot query Win32_Process: $($_.Exception.Message)"
        return @()
    }
}

function Get-CommandLineFilePath {
    param([string]$CommandLine)

    if (-not $CommandLine) {
        return ""
    }
    if ($CommandLine -match '(?i)-File\s+(?:"([^"]+)"|(\S+))') {
        if ($matches[1]) {
            return $matches[1]
        }
        return $matches[2]
    }
    return ""
}

function Test-ScriptMarker {
    param(
        [string]$Path,
        [string]$Marker
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $firstLine = Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1
    return ([string]$firstLine).Trim() -eq "# $Marker"
}

$currentPid = $PID
$monitorProcesses = @(Get-Win32Processes | Where-Object {
    $filePath = Get-CommandLineFilePath $_.CommandLine
    $_.ProcessId -ne $currentPid -and
    (
        (Test-ScriptMarker $filePath "CODEX_QUOTA_MONITOR_ENTRY") -or
        ($filePath -like "*\启动Codex额度监控.ps1" -or $filePath -like "*\Start-CodexQuotaMonitor.ps1")
    )
})

foreach ($process in $monitorProcesses) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

$overlayProcesses = @(Get-Win32Processes | Where-Object {
    $filePath = Get-CommandLineFilePath $_.CommandLine
    $_.ProcessId -ne $currentPid -and
    (
        (Test-ScriptMarker $filePath "CODEX_QUOTA_OVERLAY_ENTRY") -or
        ($filePath -like "*\Codex额度浮层.ps1" -or $filePath -like "*\CodexQuotaTaskbar.ps1")
    )
})
$overlayProcessIds = @($overlayProcesses | ForEach-Object { [int]$_.ProcessId })
$ownedAppServerIds = @(Get-OwnedAppServerIdsFromState)

foreach ($process in $overlayProcesses) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Milliseconds 300

$appServers = @(Get-Win32Processes | Where-Object {
    $_.ProcessId -ne $currentPid -and
    $_.Name -eq "codex.exe" -and
    $_.CommandLine -and
    $_.CommandLine -like "*app-server*--listen*ws://127.0.0.1:*" -and
    (
        ($overlayProcessIds -contains [int]$_.ParentProcessId) -or
        ($ownedAppServerIds -contains [int]$_.ProcessId)
    )
})

foreach ($process in $appServers) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

$runtimeDir = Get-RuntimeDirectory
if (Test-Path -LiteralPath $runtimeDir) {
    Get-ChildItem -LiteralPath $runtimeDir -Filter "overlay-*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $state = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if (($overlayProcessIds -contains [int]$state.OverlayPid) -or ($ownedAppServerIds -contains [int]$state.AppServerPid)) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
        }
    }
}

$remainingMonitors = @(Get-Win32Processes | Where-Object {
    $filePath = Get-CommandLineFilePath $_.CommandLine
    $_.ProcessId -ne $currentPid -and
    (
        (Test-ScriptMarker $filePath "CODEX_QUOTA_MONITOR_ENTRY") -or
        ($filePath -like "*\启动Codex额度监控.ps1" -or $filePath -like "*\Start-CodexQuotaMonitor.ps1")
    )
})
$remainingOverlays = @(Get-Win32Processes | Where-Object {
    $filePath = Get-CommandLineFilePath $_.CommandLine
    $_.ProcessId -ne $currentPid -and
    (
        (Test-ScriptMarker $filePath "CODEX_QUOTA_OVERLAY_ENTRY") -or
        ($filePath -like "*\Codex额度浮层.ps1" -or $filePath -like "*\CodexQuotaTaskbar.ps1")
    )
})
$remainingServers = @(Get-Win32Processes | Where-Object {
    $_.ProcessId -ne $currentPid -and
    $_.Name -eq "codex.exe" -and
    $_.CommandLine -and
    $_.CommandLine -like "*app-server*--listen*ws://127.0.0.1:*" -and
    (
        ($overlayProcessIds -contains [int]$_.ParentProcessId) -or
        ($ownedAppServerIds -contains [int]$_.ProcessId)
    )
})

Write-Output "Remaining quota monitor processes: $($remainingMonitors.Count)"
Write-Output "Remaining quota overlay processes: $($remainingOverlays.Count)"
Write-Output "Remaining owned codex app-server processes: $($remainingServers.Count)"




