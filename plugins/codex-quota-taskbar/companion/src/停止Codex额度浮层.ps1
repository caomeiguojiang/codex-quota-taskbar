# CODEX_QUOTA_STOP_OVERLAY_ENTRY
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
    foreach ($filter in @("overlay-*.json", "native-*.json")) {
        Get-ChildItem -LiteralPath $runtimeDir -Filter $filter -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $state = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -ne $state.AppServerPid) {
                    $ids.Add([int]$state.AppServerPid)
                }
            }
            catch {
            }
        }
    }
    return @($ids | Select-Object -Unique)
}

function Get-OwnedNativeIdsFromState {
    $runtimeDir = Get-RuntimeDirectory
    if (-not (Test-Path -LiteralPath $runtimeDir)) {
        return @()
    }

    $ids = New-Object System.Collections.Generic.List[int]
    Get-ChildItem -LiteralPath $runtimeDir -Filter "native-*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $state = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $state.NativePid) {
                $ids.Add([int]$state.NativePid)
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

function Test-ProcessAlive {
    param([int]$ProcessId)

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return (-not $process.HasExited)
    }
    catch {
        return $false
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

    if (-not $Path) {
        return $false
    }

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $false
        }

        $firstLine = Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1 -ErrorAction Stop
        return ([string]$firstLine).Trim() -eq "# $Marker"
    }
    catch {
        return $false
    }
}

function Test-QuotaScriptPathCandidate {
    param([string]$Path)

    if (-not $Path) {
        return $false
    }

    return (
        $Path -like "*\CodexQuotaTaskbar\*" -or
        $Path -like "*\codex-quota-taskbar\*" -or
        $Path -like "*\Codex额度*.ps1" -or
        $Path -like "*\Start-CodexQuota*.ps1" -or
        $Path -like "*\Stop-CodexQuota*.ps1" -or
        $Path -like "*\CodexQuotaTaskbar.ps1"
    )
}

function Test-NativeProcessCandidate {
    param($Process)

    if ($Process.Name -ne "CodexQuotaTaskbar.exe") {
        return $false
    }

    return (
        $Process.ExecutablePath -like "*\CodexQuotaTaskbar\app\bin\CodexQuotaTaskbar.exe" -or
        $Process.ExecutablePath -like "*\codex-quota-taskbar\*\companion\bin\CodexQuotaTaskbar.exe" -or
        $Process.CommandLine -like "*CodexQuotaTaskbar.exe*"
    )
}

$currentPid = $PID
$ownedNativeIds = @(Get-OwnedNativeIdsFromState)
$nativeProcesses = @(Get-Win32Processes | Where-Object {
    $_.ProcessId -ne $currentPid -and
    (Test-ProcessAlive ([int]$_.ProcessId)) -and
    $_.Name -eq "CodexQuotaTaskbar.exe" -and
    ((Test-NativeProcessCandidate $_) -or ($ownedNativeIds -contains [int]$_.ProcessId))
})
$nativeProcessIds = @($nativeProcesses | ForEach-Object { [int]$_.ProcessId })

foreach ($process in $nativeProcesses) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

$quotaProcesses = @(Get-Win32Processes | Where-Object {
    $filePath = Get-CommandLineFilePath $_.CommandLine
    $_.ProcessId -ne $currentPid -and
    (Test-ProcessAlive ([int]$_.ProcessId)) -and
    (Test-QuotaScriptPathCandidate $filePath) -and
    (
        (Test-ScriptMarker $filePath "CODEX_QUOTA_OVERLAY_ENTRY") -or
        ($filePath -like "*\Codex额度浮层.ps1" -or $filePath -like "*\CodexQuotaTaskbar.ps1")
    )
})
$quotaProcessIds = @($quotaProcesses | ForEach-Object { [int]$_.ProcessId })
$ownedAppServerIds = @(Get-OwnedAppServerIdsFromState)

foreach ($process in $quotaProcesses) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Milliseconds 300

$appServers = @(Get-Win32Processes | Where-Object {
    $_.ProcessId -ne $currentPid -and
    (Test-ProcessAlive ([int]$_.ProcessId)) -and
    $_.Name -eq "codex.exe" -and
    $_.CommandLine -and
    $_.CommandLine -like "*app-server*--listen*ws://127.0.0.1:*" -and
    (
        ($quotaProcessIds -contains [int]$_.ParentProcessId) -or
        ($nativeProcessIds -contains [int]$_.ParentProcessId) -or
        ($ownedAppServerIds -contains [int]$_.ProcessId)
    )
})

foreach ($process in $appServers) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

$runtimeDir = Get-RuntimeDirectory
if (Test-Path -LiteralPath $runtimeDir) {
    foreach ($filter in @("overlay-*.json", "native-*.json")) {
        Get-ChildItem -LiteralPath $runtimeDir -Filter $filter -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $state = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if (
                    ($quotaProcessIds -contains [int]$state.OverlayPid) -or
                    ($nativeProcessIds -contains [int]$state.NativePid) -or
                    ($ownedNativeIds -contains [int]$state.NativePid) -or
                    ($ownedAppServerIds -contains [int]$state.AppServerPid)
                ) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
            }
        }
    }
}

$remainingQuota = @(Get-Win32Processes | Where-Object {
    $filePath = Get-CommandLineFilePath $_.CommandLine
    $_.ProcessId -ne $currentPid -and
    (Test-ProcessAlive ([int]$_.ProcessId)) -and
    (Test-QuotaScriptPathCandidate $filePath) -and
    (
        (Test-ScriptMarker $filePath "CODEX_QUOTA_OVERLAY_ENTRY") -or
        ($filePath -like "*\Codex额度浮层.ps1" -or $filePath -like "*\CodexQuotaTaskbar.ps1")
    )
})
$remainingNative = @(Get-Win32Processes | Where-Object {
    $_.ProcessId -ne $currentPid -and
    (Test-ProcessAlive ([int]$_.ProcessId)) -and
    $_.Name -eq "CodexQuotaTaskbar.exe" -and
    ((Test-NativeProcessCandidate $_) -or ($ownedNativeIds -contains [int]$_.ProcessId))
})
$remainingServers = @(Get-Win32Processes | Where-Object {
    $_.ProcessId -ne $currentPid -and
    (Test-ProcessAlive ([int]$_.ProcessId)) -and
    $_.Name -eq "codex.exe" -and
    $_.CommandLine -and
    $_.CommandLine -like "*app-server*--listen*ws://127.0.0.1:*" -and
    (
        ($quotaProcessIds -contains [int]$_.ParentProcessId) -or
        ($nativeProcessIds -contains [int]$_.ParentProcessId) -or
        ($ownedAppServerIds -contains [int]$_.ProcessId)
    )
})

Write-Output "Remaining quota overlay processes: $($remainingQuota.Count)"
Write-Output "Remaining native quota processes: $($remainingNative.Count)"
Write-Output "Remaining owned codex app-server processes: $($remainingServers.Count)"




