# CODEX_QUOTA_OVERLAY_ENTRY
param(
    [int]$RefreshSeconds = 60,
    [string]$CodexExe = "",
    [switch]$Once,
    [switch]$SecondaryOnly,
    [int]$ClockReservePx = 96,
    [int]$OverlayWidth = 245,
    [int]$OverlayHeight = 42,
    [int]$TaskbarVerticalOffsetPx = 0,
    [string]$LogPath = "",
    [switch]$MockQuota,
    [switch]$VisualQa,
    [string]$VisualQaOutputDir = ""
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class CodexQuotaDpi
{
    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("shcore.dll")]
    private static extern int SetProcessDpiAwareness(int value);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    public static void Enable()
    {
        try
        {
            if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) return;
        }
        catch {}

        try
        {
            if (SetProcessDpiAwareness(2) == 0) return;
        }
        catch {}

        try
        {
            SetProcessDPIAware();
        }
        catch {}
    }
}
"@

[CodexQuotaDpi]::Enable()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

function Get-AppDataDirectory {
    $base = $env:APPDATA
    if (-not $base) {
        $base = $env:LOCALAPPDATA
    }
    if (-not $base) {
        $base = $PSScriptRoot
    }
    return Join-Path $base "CodexQuotaTaskbar"
}

function Get-LocalDataDirectory {
    $base = $env:LOCALAPPDATA
    if (-not $base) {
        $base = Get-AppDataDirectory
    }
    return Join-Path $base "CodexQuotaTaskbar"
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
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

function Find-SiblingScript {
    param([string]$Marker)

    $match = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File | Where-Object {
        Test-ScriptMarker $_.FullName $Marker
    } | Select-Object -First 1

    if (-not $match) {
        return ""
    }
    return $match.FullName
}

$script:appDataDir = Get-AppDataDirectory
$script:localDataDir = Get-LocalDataDirectory
Ensure-Directory $script:appDataDir
Ensure-Directory $script:localDataDir
$script:runtimeDir = Join-Path $script:localDataDir "runtime"
Ensure-Directory $script:runtimeDir
if (-not $LogPath) {
    $logDir = Join-Path $script:localDataDir "logs"
    Ensure-Directory $logDir
    $LogPath = Join-Path $logDir "overlay.log"
}
$script:logPath = $LogPath
$script:runtimeStatePath = Join-Path $script:runtimeDir ("overlay-{0}.json" -f $PID)
$script:language = ""

function Write-OverlayLog {
    param([string]$Message)

    try {
        $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff"), $Message
        Add-Content -LiteralPath $script:logPath -Value $line -Encoding UTF8
    }
    catch {
    }
}

function Get-DefaultLanguage {
    return Normalize-Language ([System.Globalization.CultureInfo]::CurrentUICulture.Name)
}

function Normalize-Language {
    param([string]$Language)

    if ($Language -and $Language -like "zh*") {
        return "zh-CN"
    }
    if ($Language -and $Language -like "en*") {
        return "en-US"
    }
    return "en-US"
}

function T {
    param([string]$Key)

    $lang = Normalize-Language $script:language
    if ($lang -eq "en-US") {
        switch ($Key) {
            "Unknown" { return "unknown" }
            "FiveLeft" { return "5H left" }
            "WeekLeft" { return "Week left" }
            "Reset" { return "reset" }
            "QuotaRemaining" { return "Remaining" }
            "SettingsTitle" { return "Codex quota taskbar settings" }
            "Monitor" { return "Monitor" }
            "Primary" { return " primary" }
            "XOffset" { return "Horizontal offset" }
            "YOffset" { return "Vertical offset" }
            "Language" { return "Language" }
            "Hint" { return "Saving applies immediately." }
            "Save" { return "Save" }
            "Cancel" { return "Cancel" }
            "Loading" { return "Loading..." }
            "RefreshQuota" { return "Refresh quota" }
            "SettingsMenu" { return "Settings..." }
            "OpenCodex" { return "Open Codex" }
            "SwitchMonitor" { return "Switch monitor" }
            "Screen" { return "Screen" }
            "PrimaryShort" { return " primary" }
            "Exit" { return "Exit" }
            "Unavailable" { return "Unavailable" }
            "QuotaUnavailable" { return "Codex quota unavailable" }
        }
    }

    switch ($Key) {
        "Unknown" { return "未知" }
        "FiveLeft" { return "5H 剩余" }
        "WeekLeft" { return "本周剩余" }
        "Reset" { return "重置" }
        "QuotaRemaining" { return "剩余可用额度" }
        "SettingsTitle" { return "Codex 额度任务栏设置" }
        "Monitor" { return "显示器" }
        "Primary" { return " 主屏" }
        "XOffset" { return "水平偏移" }
        "YOffset" { return "垂直偏移" }
        "Language" { return "语言" }
        "Hint" { return "保存后立即应用到当前浮层。" }
        "Save" { return "保存" }
        "Cancel" { return "取消" }
        "Loading" { return "加载中..." }
        "RefreshQuota" { return "刷新额度" }
        "SettingsMenu" { return "设置..." }
        "OpenCodex" { return "打开 Codex" }
        "SwitchMonitor" { return "切换显示器" }
        "Screen" { return "屏幕" }
        "PrimaryShort" { return " 主" }
        "Exit" { return "退出" }
        "Unavailable" { return "不可用" }
        "QuotaUnavailable" { return "Codex 额度不可用" }
    }

    return $Key
}

$script:language = Get-DefaultLanguage
$settingsUiScript = Join-Path $PSScriptRoot "CodexQuotaSettingsUi.ps1"
if (Test-Path -LiteralPath $settingsUiScript) {
    . $settingsUiScript
}

function Get-CodexExe {
    param([string]$Override)

    if ($Override -and (Test-Path -LiteralPath $Override)) {
        return (Resolve-Path -LiteralPath $Override).Path
    }

    $localBin = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    if (Test-Path -LiteralPath $localBin) {
        $candidate = Get-ChildItem -LiteralPath $localBin -Recurse -Filter "codex.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    $command = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $command = Get-Command codex -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "codex.exe was not found. Install/open Codex Desktop first, or pass -CodexExe."
}

function Get-FreeLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Start-CodexAppServer {
    param([string]$Exe)

    $port = Get-FreeLoopbackPort
    Write-OverlayLog "Starting Codex app-server. Exe=$Exe Port=$port"
    $proc = Start-Process `
        -FilePath $Exe `
        -ArgumentList @("app-server", "--listen", "ws://127.0.0.1:$port") `
        -WindowStyle Hidden `
        -PassThru `
        -ErrorAction Stop
    Start-Sleep -Milliseconds 900
    $proc.Refresh()
    if ($proc.HasExited) {
        throw "codex app-server exited during startup. ExitCode=$($proc.ExitCode)"
    }

    $server = [pscustomobject]@{
        Port = $port
        Process = $proc
    }
    Write-RuntimeState $server
    return $server
}

function Stop-CodexAppServer {
    param($Server)

    if ($Server -and $Server.Process -and -not $Server.Process.HasExited) {
        Stop-Process -Id $Server.Process.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-RuntimeState
}

function Request-CompanionExit {
    $stopMonitorScript = Find-SiblingScript "CODEX_QUOTA_STOP_MONITOR_ENTRY"
    if (-not $stopMonitorScript) {
        Write-OverlayLog "Stop monitor script not found. Falling back to overlay-only exit."
        return $false
    }

    try {
        $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path -LiteralPath $powershell)) {
            $powershell = "powershell.exe"
        }
        Write-OverlayLog "Requesting full companion exit by $stopMonitorScript"
        Start-Process `
            -FilePath $powershell `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $stopMonitorScript) `
            -WindowStyle Hidden `
            -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-OverlayLog "Full companion exit request failed: $($_.Exception.Message)"
        return $false
    }
}

function Write-RuntimeState {
    param($Server)

    if (-not $Server -or -not $Server.Process) {
        return
    }

    try {
        [pscustomobject]@{
            OverlayPid = [int]$PID
            AppServerPid = [int]$Server.Process.Id
            Port = [int]$Server.Port
            CodexExe = [string]$script:resolvedCodexExe
            StartedAt = (Get-Date).ToString("o")
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:runtimeStatePath -Encoding UTF8
    }
    catch {
        Write-OverlayLog "Runtime state write failed: $($_.Exception.Message)"
    }
}

function Remove-RuntimeState {
    try {
        if (Test-Path -LiteralPath $script:runtimeStatePath) {
            Remove-Item -LiteralPath $script:runtimeStatePath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
    }
}

function Wait-Task {
    param(
        [System.Threading.Tasks.Task]$Task,
        [int]$TimeoutMs,
        [string]$Operation
    )

    if (-not $Task.Wait($TimeoutMs)) {
        throw "$Operation timed out."
    }
    if ($Task.IsFaulted) {
        throw $Task.Exception.InnerException
    }
}

function Send-WebSocketJson {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [object]$Message,
        [int]$TimeoutMs = 5000
    )

    $json = $Message | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = [ArraySegment[byte]]::new($bytes)
    $task = $Socket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [System.Threading.CancellationToken]::None
    )
    Wait-Task $task $TimeoutMs "WebSocket send"
}

function Receive-WebSocketJson {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [int]$TimeoutMs = 8000
    )

    $buffer = New-Object byte[] 65536
    $stream = [System.IO.MemoryStream]::new()
    try {
        do {
            $segment = [ArraySegment[byte]]::new($buffer)
            $task = $Socket.ReceiveAsync($segment, [System.Threading.CancellationToken]::None)
            Wait-Task $task $TimeoutMs "WebSocket receive"
            $result = $task.Result

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "WebSocket closed before response."
            }

            $stream.Write($buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)

        $text = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
        return $text | ConvertFrom-Json
    }
    finally {
        $stream.Dispose()
    }
}

function Read-CodexRateLimits {
    param([int]$Port)

    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $connectTask = $socket.ConnectAsync(
            [Uri]::new("ws://127.0.0.1:$Port"),
            [System.Threading.CancellationToken]::None
        )
        Wait-Task $connectTask 5000 "WebSocket connect"

        Send-WebSocketJson $socket @{
            id = 1
            method = "initialize"
            params = @{
                clientInfo = @{
                    name = "codex-quota-taskbar"
                    version = "0.3.1"
                }
                capabilities = @{
                    experimentalApi = $true
                }
            }
        }

        while ($true) {
            $message = Receive-WebSocketJson $socket 8000
            if ($message.id -eq 1) {
                Send-WebSocketJson $socket @{ method = "initialized" }
                break
            }
        }

        Send-WebSocketJson $socket @{
            id = 2
            method = "account/rateLimits/read"
            params = $null
        }

        while ($true) {
            $message = Receive-WebSocketJson $socket 10000
            if ($message.id -eq 2) {
                if ($message.error) {
                    throw $message.error.message
                }
                return $message.result
            }
        }
    }
    finally {
        if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            try {
                $closeTask = $socket.CloseAsync(
                    [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                    "done",
                    [System.Threading.CancellationToken]::None
                )
                [void]$closeTask.Wait(500)
            }
            catch {
            }
        }
        $socket.Dispose()
    }
}

function Read-CodexRateLimitsWithRestart {
    try {
        return Read-CodexRateLimits $script:server.Port
    }
    catch {
        $firstError = $_.Exception.Message
        Write-OverlayLog "Quota read failed; restarting Codex app-server once: $firstError"
        Stop-CodexAppServer $script:server
        $script:resolvedCodexExe = Get-CodexExe $CodexExe
        $script:server = Start-CodexAppServer $script:resolvedCodexExe
        try {
            return Read-CodexRateLimits $script:server.Port
        }
        catch {
            throw "Codex quota refresh failed after app-server restart. First: $firstError Retry: $($_.Exception.Message)"
        }
    }
}

function Convert-Window {
    param($Window)

    if ($null -eq $Window) {
        return $null
    }

    $used = [double]$Window.usedPercent
    $remaining = [Math]::Max(0, [Math]::Min(100, 100 - $used))
    $reset = $null
    if ($Window.resetsAt) {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Window.resetsAt).LocalDateTime
    }

    return [pscustomobject]@{
        UsedPercent = $used
        RemainingPercent = $remaining
        WindowMinutes = $Window.windowDurationMins
        ResetsAt = $reset
    }
}

function Convert-RateLimitSummary {
    param($Result)

    $snapshot = $Result.rateLimits
    return [pscustomobject]@{
        LimitId = $snapshot.limitId
        PlanType = $snapshot.planType
        FiveHour = Convert-Window $snapshot.primary
        Weekly = Convert-Window $snapshot.secondary
        Credits = $snapshot.credits
        IndividualLimit = $snapshot.individualLimit
        ReachedType = $snapshot.rateLimitReachedType
        CheckedAt = Get-Date
    }
}

function New-MockRateLimitSummary {
    $now = Get-Date
    return [pscustomobject]@{
        LimitId = "visual-qa"
        PlanType = "mock"
        FiveHour = [pscustomobject]@{
            UsedPercent = 27.6
            RemainingPercent = 72.4
            WindowMinutes = 300
            ResetsAt = $now.AddHours(2.5)
        }
        Weekly = [pscustomobject]@{
            UsedPercent = 58.2
            RemainingPercent = 41.8
            WindowMinutes = 10080
            ResetsAt = $now.AddDays(2)
        }
        Credits = $null
        IndividualLimit = $null
        ReachedType = $null
        CheckedAt = $now
    }
}

function Format-Reset {
    param($DateTime)

    if ($null -eq $DateTime) {
        return T "Unknown"
    }
    return $DateTime.ToString("MM-dd HH:mm")
}

function Format-OverlayText {
    param($Summary)

    $five = [Math]::Round($Summary.FiveHour.RemainingPercent)
    $week = [Math]::Round($Summary.Weekly.RemainingPercent)
    return "5h ${five}% | W ${week}%"
}

function Format-RefreshTime {
    param($DateTime)

    if ($null -eq $DateTime) {
        return "--:--"
    }
    return $DateTime.ToString("HH:mm")
}

function Format-ResetTime {
    param($DateTime)

    if ($null -eq $DateTime) {
        return "--:--"
    }

    if (($DateTime - (Get-Date)).TotalHours -gt 24) {
        return $DateTime.ToString("MM-dd")
    }
    return $DateTime.ToString("HH:mm")
}

function Format-DetailText {
    param($Summary)

    $five = [Math]::Round($Summary.FiveHour.RemainingPercent, 1)
    $week = [Math]::Round($Summary.Weekly.RemainingPercent, 1)
    return "$(T "FiveLeft"): ${five}% $(T "Reset") $(Format-Reset $Summary.FiveHour.ResetsAt)`r`n$(T "WeekLeft"): ${week}% $(T "Reset") $(Format-Reset $Summary.Weekly.ResetsAt)"
}

function Format-OnceText {
    param($Summary)

    $five = [Math]::Round($Summary.FiveHour.RemainingPercent, 1)
    $week = [Math]::Round($Summary.Weekly.RemainingPercent, 1)
    return "$(T "FiveLeft"): ${five}% ($(T "Reset") $(Format-Reset $Summary.FiveHour.ResetsAt)); $(T "WeekLeft"): ${week}% ($(T "Reset") $(Format-Reset $Summary.Weekly.ResetsAt))"
}

function Get-TaskbarEdge {
    param([System.Windows.Forms.Screen]$Screen)

    $bounds = $Screen.Bounds
    $work = $Screen.WorkingArea

    if ($work.Bottom -lt $bounds.Bottom) {
        return "Bottom"
    }
    if ($work.Top -gt $bounds.Top) {
        return "Top"
    }
    if ($work.Right -lt $bounds.Right) {
        return "Right"
    }
    if ($work.Left -gt $bounds.Left) {
        return "Left"
    }

    return "Bottom"
}

function Get-TaskbarThickness {
    param([System.Windows.Forms.Screen]$Screen)

    $bounds = $Screen.Bounds
    $work = $Screen.WorkingArea
    $edge = Get-TaskbarEdge $Screen

    switch ($edge) {
        "Bottom" { return [Math]::Max(0, $bounds.Bottom - $work.Bottom) }
        "Top" { return [Math]::Max(0, $work.Top - $bounds.Top) }
        "Right" { return [Math]::Max(0, $bounds.Right - $work.Right) }
        "Left" { return [Math]::Max(0, $work.Left - $bounds.Left) }
    }

    return 0
}

function Get-OverlayLayout {
    param([System.Windows.Forms.Screen]$Screen)

    $taskbarThickness = Get-TaskbarThickness $Screen
    if ($taskbarThickness -le 0) {
        $taskbarThickness = 48
    }

    $scale = $taskbarThickness / 48.0
    $scale = [Math]::Max(0.72, [Math]::Min(1.22, $scale))

    $height = [int][Math]::Round($script:overlayHeight * $scale)
    $maxHeight = [Math]::Max(22, $taskbarThickness - 4)
    $height = [int][Math]::Max(22, [Math]::Min($height, $maxHeight))
    $scale = $height / [double]$script:overlayHeight

    return [pscustomobject]@{
        Scale = $scale
        Width = [int][Math]::Round($script:overlayWidth * $scale)
        Height = $height
        Margin = [Math]::Max(1, [Math]::Round(1 * $scale, 1))
        PaddingX = [Math]::Max(4, [Math]::Round(7 * $scale, 1))
        PaddingY = [Math]::Max(1, [Math]::Round(3 * $scale, 1))
        CornerRadius = [Math]::Max(4, [Math]::Round(7 * $scale, 1))
        RowHeight = [Math]::Max(11, [Math]::Round(16 * $scale, 1))
        TagColumn = [Math]::Max(16, [Math]::Round(23 * $scale, 1))
        LabelColumn = [Math]::Max(52, [Math]::Round(70 * $scale, 1))
        BarColumn = [Math]::Max(40, [Math]::Round(55 * $scale, 1))
        PercentColumn = [Math]::Max(27, [Math]::Round(32 * $scale, 1))
        TimeColumn = [Math]::Max(37, [Math]::Round(47 * $scale, 1))
        BarWidth = [Math]::Max(38, [Math]::Round(55 * $scale, 1))
        BarHeight = [Math]::Max(5, [Math]::Round(8 * $scale, 1))
        TagFontSize = [Math]::Max(8.4, [Math]::Round(11.2 * $scale, 1))
        LabelFontSize = [Math]::Max(8.0, [Math]::Round(10.4 * $scale, 1))
        PercentFontSize = [Math]::Max(8.2, [Math]::Round(10.6 * $scale, 1))
        TimeFontSize = [Math]::Max(7.5, [Math]::Round(9.6 * $scale, 1))
    }
}

function Get-OverlayBounds {
    param(
        [System.Windows.Forms.Screen]$Screen,
        [int]$Width,
        [int]$Height,
        [int]$ClockReserve,
        [int]$XOffset = 0,
        [int]$VerticalOffset = 0
    )

    $bounds = $Screen.Bounds
    $work = $Screen.WorkingArea
    $edge = Get-TaskbarEdge $Screen
    $margin = 8

    switch ($edge) {
        "Bottom" {
            $taskbarHeight = [Math]::Max($Height + 4, (Get-TaskbarThickness $Screen))
            $x = $bounds.Right - $ClockReserve - $Width
            $y = $work.Bottom + [int][Math]::Round(($taskbarHeight - $Height) / 2) + $VerticalOffset
        }
        "Top" {
            $taskbarHeight = [Math]::Max($Height + 4, (Get-TaskbarThickness $Screen))
            $x = $bounds.Right - $ClockReserve - $Width
            $y = $bounds.Top + [int][Math]::Round(($taskbarHeight - $Height) / 2) - $VerticalOffset
        }
        "Right" {
            $taskbarWidth = [Math]::Max(56, (Get-TaskbarThickness $Screen))
            $x = $work.Right + [int](($taskbarWidth - $Width) / 2)
            $y = $bounds.Bottom - $ClockReserve - $Height + $VerticalOffset
        }
        "Left" {
            $taskbarWidth = [Math]::Max(56, (Get-TaskbarThickness $Screen))
            $x = $bounds.Left + [int](($taskbarWidth - $Width) / 2)
            $y = $bounds.Bottom - $ClockReserve - $Height + $VerticalOffset
        }
    }

    $x = $x + $XOffset
    $x = [Math]::Max($bounds.Left + $margin, [Math]::Min($x, $bounds.Right - $Width - $margin))
    switch ($edge) {
        "Bottom" {
            $y = [Math]::Max($work.Bottom, [Math]::Min($y, $bounds.Bottom - $Height))
        }
        "Top" {
            $y = [Math]::Max($bounds.Top, [Math]::Min($y, $work.Top - $Height))
        }
        default {
            $y = [Math]::Max($bounds.Top + $margin, [Math]::Min($y, $bounds.Bottom - $Height - $margin))
        }
    }
    return [System.Drawing.Rectangle]::new($x, $y, $Width, $Height)
}

function Get-SettingsPath {
    return Join-Path $script:appDataDir "settings.json"
}

function Get-LegacySettingsPath {
    $base = $PSScriptRoot
    if ($base) {
        return Join-Path $base "CodexQuotaTaskbar.settings.json"
    }
    return ""
}

function Load-OverlaySettings {
    $script:xOffset = 0
    $script:targetMonitorDevice = ""
    $script:language = Get-DefaultLanguage
    $path = Get-SettingsPath

    $legacyPath = Get-LegacySettingsPath
    if (-not (Test-Path -LiteralPath $path) -and $legacyPath -and (Test-Path -LiteralPath $legacyPath)) {
        try {
            Copy-Item -LiteralPath $legacyPath -Destination $path -Force
            Write-OverlayLog "Migrated settings from $legacyPath to $path"
        }
        catch {
            Write-OverlayLog "Settings migration failed: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    try {
        $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $settings.XOffset) {
            $script:xOffset = [int]$settings.XOffset
        }
        if ($null -ne $settings.VerticalOffset) {
            $script:taskbarVerticalOffsetPx = [int]$settings.VerticalOffset
        }
        if ($settings.TargetMonitorDevice) {
            $script:targetMonitorDevice = [string]$settings.TargetMonitorDevice
        }
        if ($settings.Language) {
            $script:language = Normalize-Language ([string]$settings.Language)
        }
    }
    catch {
        Write-OverlayLog "Settings load failed: $($_.Exception.Message)"
        $script:xOffset = 0
        $script:targetMonitorDevice = ""
        $script:language = Get-DefaultLanguage
    }
}

function Save-OverlaySettings {
    $path = Get-SettingsPath
    Ensure-Directory (Split-Path -Parent $path)
    [pscustomobject]@{
        TargetMonitorDevice = [string]$script:targetMonitorDevice
        XOffset = [int]$script:xOffset
        VerticalOffset = [int]$script:taskbarVerticalOffsetPx
        Language = Normalize-Language ([string]$script:language)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-OverlayLog "Settings saved to $path"
}

function Show-OverlaySettingsDialog {
    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    if ($screens.Count -eq 0) {
        return $false
    }

    $currentDevice = $script:targetMonitorDevice
    if (-not $currentDevice) {
        $target = @(Get-TargetScreens)
        if ($target.Count -gt 0) {
            $currentDevice = $target[0].DeviceName
        }
    }

    $wasPositionTimerEnabled = $false
    if ($script:positionTimer) {
        $wasPositionTimerEnabled = $script:positionTimer.IsEnabled
        if ($wasPositionTimerEnabled) { $script:positionTimer.Stop() }
    }

    Ensure-AllOverlaysTopmost
    try {
        $result = Show-CodexQuotaSettingsDialog `
            -Screens $screens `
            -CurrentDevice $currentDevice `
            -XOffset $script:xOffset `
            -VerticalOffset $script:taskbarVerticalOffsetPx `
            -Language $script:language `
            -OnShown { Ensure-AllOverlaysTopmost }
    }
    finally {
        if ($wasPositionTimerEnabled -and $script:positionTimer) {
            $script:positionTimer.Start()
        }
        Update-OverlayPositions
        Ensure-AllOverlaysTopmost
    }

    if (-not $result) {
        return $false
    }

    $script:targetMonitorDevice = [string]$result.TargetMonitorDevice
    $script:xOffset = [int]$result.XOffset
    $script:taskbarVerticalOffsetPx = [int]$result.VerticalOffset
    $script:language = Normalize-Language ([string]$result.Language)
    Save-OverlaySettings
    return $true
}
function Get-DipDeltaX {
    param(
        $Window,
        [double]$Pixels
    )

    $source = [System.Windows.PresentationSource]::FromVisual($Window)
    if ($source -and $source.CompositionTarget) {
        return $Pixels * $source.CompositionTarget.TransformFromDevice.M11
    }
    return $Pixels
}

function Set-DraggedOverlayLeft {
    param(
        $Window,
        [double]$Left
    )

    $screen = $script:dragScreen
    if (-not $screen) {
        $center = [System.Drawing.Point]::new([int]($Window.Left + ($Window.Width / 2)), [int]($Window.Top + ($Window.Height / 2)))
        $screen = [System.Windows.Forms.Screen]::FromPoint($center)
    }

    $bounds = $screen.Bounds
    $margin = 8
    $minLeft = $bounds.Left + $margin
    $maxLeft = $bounds.Right - $Window.Width - $margin
    $Window.Left = [Math]::Max($minLeft, [Math]::Min($Left, $maxLeft))
}

function Save-OverlayDragOffset {
    param($Window)

    $center = [System.Drawing.Point]::new([int]($Window.Left + ($Window.Width / 2)), [int]($Window.Top + ($Window.Height / 2)))
    $screen = [System.Windows.Forms.Screen]::FromPoint($center)
    $layout = Get-OverlayLayout $screen
    $baseRect = Get-OverlayBounds $screen $layout.Width $layout.Height $script:clockReservePx 0 $script:taskbarVerticalOffsetPx
    $script:targetMonitorDevice = $screen.DeviceName
    $script:xOffset = [int][Math]::Round($Window.Left - $baseRect.X)
    Save-OverlaySettings
}

function Get-TargetScreens {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($script:targetMonitorDevice) {
        $target = @($screens | Where-Object { $_.DeviceName -eq $script:targetMonitorDevice })
        if ($target.Count -gt 0) {
            return @($target[0])
        }
    }
    if ($script:secondaryOnly) {
        return @($screens | Where-Object { -not $_.Primary })
    }
    return @($screens)
}

function New-MediaBrush {
    param(
        [byte]$R,
        [byte]$G,
        [byte]$B,
        [byte]$A = 255
    )

    $brush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb($A, $R, $G, $B))
    $brush.Freeze()
    return $brush
}

function Set-ModernContextMenuStyle {
    param([System.Windows.Controls.ContextMenu]$Menu)

    $xaml = @"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Style x:Key="ModernContextMenu" TargetType="{x:Type ContextMenu}">
        <Setter Property="OverridesDefaultStyle" Value="True"/>
        <Setter Property="HasDropShadow" Value="True"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type ContextMenu}">
                    <Border Background="#F0181C24"
                            BorderBrush="#48FFFFFF"
                            BorderThickness="1"
                            CornerRadius="8"
                            Padding="4">
                        <StackPanel IsItemsHost="True"/>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="{x:Type MenuItem}">
        <Setter Property="Foreground" Value="#EAF1F8"/>
        <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
        <Setter Property="FontSize" Value="11.5"/>
        <Setter Property="Padding" Value="5,5"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type MenuItem}">
                    <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}">
                        <Grid MinWidth="108">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="20"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="{TemplateBinding Icon}" Foreground="#9BE7B8" HorizontalAlignment="Center" TextAlignment="Center" VerticalAlignment="Center"/>
                            <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" Margin="3,0,0,0" VerticalAlignment="Center"/>
                        </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsHighlighted" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="#273446"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Foreground" Value="#9AA6B2"/>
                            <Setter TargetName="Bd" Property="Opacity" Value="0.72"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="{x:Type Separator}">
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type Separator}">
                    <Border Height="1" Margin="7,4" Background="#344050"/>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $resources = [System.Windows.Markup.XamlReader]::Load($reader)
    $Menu.Resources.MergedDictionaries.Add($resources) | Out-Null
    $Menu.Style = $resources["ModernContextMenu"]
}

function New-ModernMenuItem {
    param(
        [string]$Header,
        [string]$Icon = "",
        [bool]$Enabled = $true
    )

    $item = [System.Windows.Controls.MenuItem]::new()
    $item.Header = $Header
    $item.Icon = $Icon
    $item.IsEnabled = $Enabled
    return $item
}

function New-TextBlock {
    param(
        [string]$Text,
        [double]$FontSize,
        [System.Windows.Media.Brush]$Foreground,
        [string]$FontFamily = "Segoe UI",
        [System.Windows.FontWeight]$FontWeight = [System.Windows.FontWeights]::Normal,
        [System.Windows.TextAlignment]$Alignment = [System.Windows.TextAlignment]::Left
    )

    $tb = [System.Windows.Controls.TextBlock]::new()
    $tb.Text = $Text
    $tb.FontSize = $FontSize
    $tb.FontFamily = [System.Windows.Media.FontFamily]::new($FontFamily)
    $tb.FontWeight = $FontWeight
    $tb.Foreground = $Foreground
    $tb.TextAlignment = $Alignment
    $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $tb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    return $tb
}

function Add-Column {
    param(
        [System.Windows.Controls.Grid]$Grid,
        [double]$Width
    )

    $column = [System.Windows.Controls.ColumnDefinition]::new()
    $column.Width = [System.Windows.GridLength]::new($Width)
    [void]$Grid.ColumnDefinitions.Add($column)
    return $column
}

function New-QuotaRow {
    param(
        [string]$Tag,
        [System.Windows.Media.Brush]$Accent,
        [int]$BarWidth
    )

    $row = [System.Windows.Controls.Grid]::new()
    $row.Height = 16
    $row.SnapsToDevicePixels = $true
    $tagColumn = Add-Column $row 23
    $labelColumn = Add-Column $row 70
    $barColumn = Add-Column $row 55
    $percentColumn = Add-Column $row 32
    $timeColumn = Add-Column $row 47

    $tagBlock = New-TextBlock $Tag 11.2 $Accent "Segoe UI" ([System.Windows.FontWeights]::Bold)
    [System.Windows.Controls.Grid]::SetColumn($tagBlock, 0)
    [void]$row.Children.Add($tagBlock)

    $labelBlock = New-TextBlock (T "QuotaRemaining") 10.4 (New-MediaBrush 235 241 248 255) "Microsoft YaHei UI"
    [System.Windows.Controls.Grid]::SetColumn($labelBlock, 1)
    [void]$row.Children.Add($labelBlock)

    $track = [System.Windows.Controls.Border]::new()
    $track.Width = $BarWidth
    $track.Height = 8
    $track.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $track.Background = New-MediaBrush 78 86 98 255
    $track.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $track.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $trackGrid = [System.Windows.Controls.Grid]::new()
    $fill = [System.Windows.Controls.Border]::new()
    $fill.Width = 0
    $fill.Height = 8
    $fill.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $fill.Background = $Accent
    $fill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $trackGrid.Children.Add($fill) | Out-Null
    $track.Child = $trackGrid
    [System.Windows.Controls.Grid]::SetColumn($track, 2)
    [void]$row.Children.Add($track)

    $percent = New-TextBlock "0%" 10.6 (New-MediaBrush 235 241 248 255) "Segoe UI" ([System.Windows.FontWeights]::Bold) ([System.Windows.TextAlignment]::Right)
    [System.Windows.Controls.Grid]::SetColumn($percent, 3)
    [void]$row.Children.Add($percent)

    $time = New-TextBlock "--:--" 9.6 (New-MediaBrush 202 211 222 255) "Segoe UI" ([System.Windows.FontWeights]::Normal) ([System.Windows.TextAlignment]::Right)
    [System.Windows.Controls.Grid]::SetColumn($time, 4)
    [void]$row.Children.Add($time)

    return [pscustomobject]@{
        Row = $row
        Tag = $tagBlock
        Label = $labelBlock
        Track = $track
        Percent = $percent
        Time = $time
        Fill = $fill
        Columns = @($tagColumn, $labelColumn, $barColumn, $percentColumn, $timeColumn)
    }
}

function Set-ColumnWidth {
    param(
        [System.Windows.Controls.ColumnDefinition]$Column,
        [double]$Width
    )

    $Column.Width = [System.Windows.GridLength]::new($Width)
}

function Set-QuotaRowLayout {
    param(
        $Row,
        $Layout
    )

    $Row.Row.Height = $Layout.RowHeight
    Set-ColumnWidth ($Row.Columns[0]) $Layout.TagColumn
    Set-ColumnWidth ($Row.Columns[1]) $Layout.LabelColumn
    Set-ColumnWidth ($Row.Columns[2]) $Layout.BarColumn
    Set-ColumnWidth ($Row.Columns[3]) $Layout.PercentColumn
    Set-ColumnWidth ($Row.Columns[4]) $Layout.TimeColumn

    $Row.Tag.FontSize = $Layout.TagFontSize
    $Row.Label.FontSize = $Layout.LabelFontSize
    $Row.Percent.FontSize = $Layout.PercentFontSize
    $Row.Time.FontSize = $Layout.TimeFontSize
    $Row.Track.Width = $Layout.BarWidth
    $Row.Track.Height = $Layout.BarHeight
    $Row.Track.CornerRadius = [System.Windows.CornerRadius]::new($Layout.BarHeight / 2)
    $Row.Fill.Height = $Layout.BarHeight
    $Row.Fill.CornerRadius = [System.Windows.CornerRadius]::new($Layout.BarHeight / 2)
}

function Set-OverlayLayout {
    param(
        $Entry,
        $Layout
    )

    $Entry.Window.Width = $Layout.Width
    $Entry.Window.Height = $Layout.Height
    $Entry.RootBorder.CornerRadius = [System.Windows.CornerRadius]::new($Layout.CornerRadius)
    $Entry.RootBorder.Margin = [System.Windows.Thickness]::new($Layout.Margin)
    $Entry.RootBorder.Padding = [System.Windows.Thickness]::new($Layout.PaddingX, $Layout.PaddingY, $Layout.PaddingX, $Layout.PaddingY)
    $Entry.RowDefinitions[0].Height = [System.Windows.GridLength]::new($Layout.RowHeight)
    $Entry.RowDefinitions[1].Height = [System.Windows.GridLength]::new($Layout.RowHeight)
    Set-QuotaRowLayout $Entry.FiveRow $Layout
    Set-QuotaRowLayout $Entry.WeekRow $Layout
    $Entry.BarWidth = $Layout.BarWidth
}

function Ensure-OverlayTopmost {
    param($Window)

    if (-not $Window -or -not $Window.IsVisible) {
        return
    }

    if (-not $Window.Topmost) {
        $Window.Topmost = $true
    }
    $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
    if ($helper.Handle -ne [IntPtr]::Zero) {
        [void][CodexQuotaWin32]::SetWindowPos(
            $helper.Handle,
            [CodexQuotaWin32]::HWND_TOPMOST,
            0,
            0,
            0,
            0,
            [CodexQuotaWin32]::SWP_NOMOVE -bor [CodexQuotaWin32]::SWP_NOSIZE -bor [CodexQuotaWin32]::SWP_NOACTIVATE -bor [CodexQuotaWin32]::SWP_SHOWWINDOW
        )
    }
}

function Ensure-AllOverlaysTopmost {
    foreach ($entry in $script:forms) {
        Ensure-OverlayTopmost $entry.Window
    }
}

function Configure-OverlayWindow {
    param($Window)

    $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
    if ($helper.Handle -eq [IntPtr]::Zero) {
        return
    }

    $style = [CodexQuotaWin32]::GetWindowLongPtr($helper.Handle, [CodexQuotaWin32]::GWL_EXSTYLE).ToInt64()
    $style = $style -bor [CodexQuotaWin32]::WS_EX_TOOLWINDOW
    $style = $style -band (-bnot [CodexQuotaWin32]::WS_EX_NOACTIVATE)
    [void][CodexQuotaWin32]::SetWindowLongPtr($helper.Handle, [CodexQuotaWin32]::GWL_EXSTYLE, [IntPtr]::new($style))
    [void][CodexQuotaWin32]::SetWindowPos(
        $helper.Handle,
        [CodexQuotaWin32]::HWND_TOPMOST,
        0,
        0,
        0,
        0,
        [CodexQuotaWin32]::SWP_NOMOVE -bor [CodexQuotaWin32]::SWP_NOSIZE -bor [CodexQuotaWin32]::SWP_NOACTIVATE -bor [CodexQuotaWin32]::SWP_SHOWWINDOW -bor [CodexQuotaWin32]::SWP_FRAMECHANGED
    )
}

function Set-OverlayStyle {
    param(
        $Entry,
        [string]$Text,
        [string]$Detail,
        [double]$FiveRemaining,
        [double]$WeekRemaining,
        [string]$FiveTime,
        [string]$WeekTime,
        [bool]$ErrorState = $false
    )

    if ($ErrorState) {
        $Entry.RootBorder.Background = New-MediaBrush 25 18 20 245
        $Entry.FiveLabel.Text = T "QuotaUnavailable"
        $Entry.FivePercent.Text = "!"
        $Entry.FiveTime.Text = ""
        $Entry.WeekLabel.Text = $Detail
        $Entry.WeekPercent.Text = ""
        $Entry.WeekTime.Text = ""
        $Entry.FiveFill.Width = 0
        $Entry.WeekFill.Width = 0
    }
    else {
        $Entry.RootBorder.Background = New-MediaBrush 17 20 25 245
        $Entry.FiveLabel.Text = T "QuotaRemaining"
        $Entry.WeekLabel.Text = $Entry.FiveLabel.Text
        $Entry.FivePercent.Text = ("{0:0}%" -f [Math]::Round($FiveRemaining))
        $Entry.WeekPercent.Text = ("{0:0}%" -f [Math]::Round($WeekRemaining))
        $Entry.FiveTime.Text = $FiveTime
        $Entry.WeekTime.Text = $WeekTime
        $Entry.FiveFill.Width = [Math]::Max(0, [Math]::Round($Entry.BarWidth * [Math]::Max(0, [Math]::Min(100, $FiveRemaining)) / 100))
        $Entry.WeekFill.Width = [Math]::Max(0, [Math]::Round($Entry.BarWidth * [Math]::Max(0, [Math]::Min(100, $WeekRemaining)) / 100))
    }

    $Entry.Window.ToolTip = $null
    $Entry.RootBorder.ToolTip = $null
}

function New-OverlayForm {
    param(
        [System.Windows.Controls.ContextMenu]$Menu
    )

    $barWidth = 55
    $window = [System.Windows.Window]::new()
    $window.WindowStyle = [System.Windows.WindowStyle]::None
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Transparent
    $window.ShowInTaskbar = $false
    $window.Topmost = $true
    $window.ShowActivated = $false
    $window.Width = $script:overlayWidth
    $window.Height = $script:overlayHeight
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $window.UseLayoutRounding = $false
    $window.SnapsToDevicePixels = $false
    $window.add_SourceInitialized({
        param($sender, $eventArgs)
        Configure-OverlayWindow $sender
    })

    $root = [System.Windows.Controls.Border]::new()
    $root.CornerRadius = [System.Windows.CornerRadius]::new(7)
    $root.Background = New-MediaBrush 17 20 25 245
    $root.BorderBrush = New-MediaBrush 255 255 255 54
    $root.BorderThickness = [System.Windows.Thickness]::new(1)
    $root.Margin = [System.Windows.Thickness]::new(1)
    $root.Padding = [System.Windows.Thickness]::new(7, 3, 7, 3)
    $root.ContextMenu = $Menu
    $root.SnapsToDevicePixels = $false
    [System.Windows.Media.TextOptions]::SetTextFormattingMode($root, [System.Windows.Media.TextFormattingMode]::Display)
    [System.Windows.Media.TextOptions]::SetTextRenderingMode($root, [System.Windows.Media.TextRenderingMode]::ClearType)

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $row1 = [System.Windows.Controls.RowDefinition]::new()
    $row1.Height = [System.Windows.GridLength]::new(16)
    $row2 = [System.Windows.Controls.RowDefinition]::new()
    $row2.Height = [System.Windows.GridLength]::new(16)
    [void]$grid.RowDefinitions.Add($row1)
    [void]$grid.RowDefinitions.Add($row2)
    $root.Child = $grid
    $window.Content = $root

    $five = New-QuotaRow "5H" (New-MediaBrush 98 230 154 255) $barWidth
    $week = New-QuotaRow "W" (New-MediaBrush 97 198 255 255) $barWidth
    [System.Windows.Controls.Grid]::SetRow($five.Row, 0)
    [System.Windows.Controls.Grid]::SetRow($week.Row, 1)
    [void]$grid.Children.Add($five.Row)
    [void]$grid.Children.Add($week.Row)

    $root.add_MouseEnter({
        param($sender, $eventArgs)
        $sender.Background = New-MediaBrush 24 29 37 250
        $sender.BorderBrush = New-MediaBrush 255 255 255 86
    })
    $root.add_MouseLeave({
        param($sender, $eventArgs)
        $sender.Background = New-MediaBrush 17 20 25 245
        $sender.BorderBrush = New-MediaBrush 255 255 255 54
    })
    $root.add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        $activeWindow = [System.Windows.Window]::GetWindow($sender)
        if (-not $activeWindow) {
            return
        }
        if ($eventArgs.ClickCount -ge 2) {
            $script:dragWindow = $null
            $script:dragScreen = $null
            $script:isDragging = $false
            [void](Show-CodexWindow)
            Ensure-OverlayTopmost $activeWindow
            $eventArgs.Handled = $true
            return
        }
        $script:dragWindow = $activeWindow
        $script:dragStartX = [System.Windows.Forms.Cursor]::Position.X
        $script:dragStartLeft = $activeWindow.Left
        $script:dragStartedAt = Get-Date
        $script:isDragging = $false
        $center = [System.Drawing.Point]::new([int]($activeWindow.Left + ($activeWindow.Width / 2)), [int]($activeWindow.Top + ($activeWindow.Height / 2)))
        $script:dragScreen = [System.Windows.Forms.Screen]::FromPoint($center)
        [void]$sender.CaptureMouse()
        $eventArgs.Handled = $true
    })
    $root.add_MouseMove({
        param($sender, $eventArgs)
        $activeWindow = [System.Windows.Window]::GetWindow($sender)
        if (-not $activeWindow -or $script:dragWindow -ne $activeWindow -or $eventArgs.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) {
            return
        }

        $dxPixels = [System.Windows.Forms.Cursor]::Position.X - $script:dragStartX
        $elapsedMs = ((Get-Date) - $script:dragStartedAt).TotalMilliseconds
        if (-not $script:isDragging -and ($elapsedMs -ge 220 -or [Math]::Abs($dxPixels) -ge 6)) {
            $script:isDragging = $true
        }

        if ($script:isDragging) {
            $dx = Get-DipDeltaX $activeWindow $dxPixels
            Set-DraggedOverlayLeft $activeWindow ($script:dragStartLeft + $dx)
            Ensure-OverlayTopmost $activeWindow
            $eventArgs.Handled = $true
        }
    })
    $root.add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $activeWindow = [System.Windows.Window]::GetWindow($sender)
        if ($activeWindow -and $script:dragWindow -eq $activeWindow) {
            [void]$sender.ReleaseMouseCapture()
            if ($script:isDragging) {
                Save-OverlayDragOffset $activeWindow
            }
            else {
                Refresh-QuotaAndForms
            }
            $script:dragWindow = $null
            $script:dragScreen = $null
            $script:isDragging = $false
            $eventArgs.Handled = $true
        }
    })
    $root.add_MouseRightButtonUp({
        param($sender, $eventArgs)
        $script:menu.PlacementTarget = $sender
        $script:menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::MousePoint
        $script:menu.IsOpen = $true
        $eventArgs.Handled = $true
    })

    return [pscustomobject]@{
        Window = $window
        RootBorder = $root
        RowDefinitions = @($row1, $row2)
        FiveRow = $five
        FiveLabel = $five.Label
        FivePercent = $five.Percent
        FiveTime = $five.Time
        FiveFill = $five.Fill
        WeekRow = $week
        WeekLabel = $week.Label
        WeekPercent = $week.Percent
        WeekTime = $week.Time
        WeekFill = $week.Fill
        BarWidth = $barWidth
    }
}

function Save-VisualElementPng {
    param(
        [System.Windows.Media.Visual]$Visual,
        [string]$Path
    )

    $element = $Visual -as [System.Windows.FrameworkElement]
    if (-not $element) {
        return
    }

    $width = [int][Math]::Ceiling($element.ActualWidth)
    $height = [int][Math]::Ceiling($element.ActualHeight)
    if ($width -le 0) {
        $width = [int][Math]::Ceiling($element.Width)
    }
    if ($height -le 0) {
        $height = [int][Math]::Ceiling($element.Height)
    }
    if ($width -le 0 -or $height -le 0) {
        throw "Cannot capture visual with empty size."
    }

    $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        $width,
        $height,
        96,
        96,
        [System.Windows.Media.PixelFormats]::Pbgra32
    )
    $bitmap.Render($Visual)

    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
    try {
        $encoder.Save($stream)
    }
    finally {
        $stream.Dispose()
    }
}

function Save-VisualQaArtifacts {
    if (-not $VisualQaOutputDir) {
        $VisualQaOutputDir = Join-Path $script:localDataDir "visual-qa"
    }
    Ensure-Directory $VisualQaOutputDir
    Write-OverlayLog "Visual QA saving to $VisualQaOutputDir"

    $screens = @(Get-TargetScreens)
    $captures = @()
    for ($i = 0; $i -lt $script:forms.Count; $i++) {
        $entry = $script:forms[$i]
        if (-not $entry.Window.IsVisible) {
            continue
        }

        $fileName = "overlay-{0}.png" -f ($i + 1)
        $path = Join-Path $VisualQaOutputDir $fileName
        Write-OverlayLog "Visual QA capture start: $fileName"
        Save-VisualElementPng $entry.Window $path
        Write-OverlayLog "Visual QA capture saved: $fileName"

        $screen = $null
        if ($i -lt $screens.Count) {
            $screen = $screens[$i]
        }
        $screenInfo = $null
        if ($screen) {
            $screenInfo = [pscustomobject]@{
                DeviceName = $screen.DeviceName
                Primary = [bool]$screen.Primary
                Bounds = [pscustomobject]@{
                    X = $screen.Bounds.X
                    Y = $screen.Bounds.Y
                    Width = $screen.Bounds.Width
                    Height = $screen.Bounds.Height
                }
                WorkingArea = [pscustomobject]@{
                    X = $screen.WorkingArea.X
                    Y = $screen.WorkingArea.Y
                    Width = $screen.WorkingArea.Width
                    Height = $screen.WorkingArea.Height
                }
                TaskbarEdge = Get-TaskbarEdge $screen
                TaskbarThickness = Get-TaskbarThickness $screen
            }
        }

        $captures += [pscustomobject]@{
            File = $fileName
            Window = [pscustomobject]@{
                Left = [double]$entry.Window.Left
                Top = [double]$entry.Window.Top
                Width = [double]$entry.Window.Width
                Height = [double]$entry.Window.Height
            }
            Screen = $screenInfo
        }
        Write-OverlayLog "Visual QA capture metadata added: $fileName"
    }

    $menuItems = @()
    foreach ($item in $script:menu.Items) {
        if ($item -is [System.Windows.Controls.MenuItem]) {
            $menuItems += [string]$item.Header
        }
    }

    Write-OverlayLog "Visual QA writing metadata JSON"
    [pscustomobject]@{
        CapturedAt = (Get-Date).ToString("o")
        MockQuota = [bool]$MockQuota
        MenuItems = $menuItems
        Captures = $captures
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $VisualQaOutputDir "visual-qa.json") -Encoding UTF8

    Write-OverlayLog "Visual QA metadata JSON saved"
    Write-Output "Visual QA artifacts: $VisualQaOutputDir"
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class CodexQuotaWin32
{
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public const UInt32 EVENT_SYSTEM_FOREGROUND = 0x0003;
    public const UInt32 EVENT_OBJECT_SHOW = 0x8002;
    public const UInt32 EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
    public const UInt32 WINEVENT_OUTOFCONTEXT = 0x0000;
    public const UInt32 WINEVENT_SKIPOWNPROCESS = 0x0002;
    public const UInt32 GA_ROOT = 2;
    public const Int32 OBJID_WINDOW = 0;
    public const Int32 GWL_EXSTYLE = -20;
    public const Int32 WS_EX_TOOLWINDOW = 0x00000080;
    public const Int32 WS_EX_NOACTIVATE = 0x08000000;
    public const UInt32 SWP_NOSIZE = 0x0001;
    public const UInt32 SWP_NOMOVE = 0x0002;
    public const UInt32 SWP_NOACTIVATE = 0x0010;
    public const UInt32 SWP_FRAMECHANGED = 0x0020;
    public const UInt32 SWP_SHOWWINDOW = 0x0040;
    public const Int32 SW_RESTORE = 9;

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public delegate void WinEventDelegate(IntPtr hWinEventHook, UInt32 eventType, IntPtr hWnd, Int32 idObject, Int32 idChild, UInt32 dwEventThread, UInt32 dwmsEventTime);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, UInt32 uFlags);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWinEventHook(UInt32 eventMin, UInt32 eventMax, IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc, UInt32 idProcess, UInt32 idThread, UInt32 dwFlags);

    [DllImport("user32.dll")]
    public static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hWnd, UInt32 gaFlags);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern UInt32 GetWindowThreadProcessId(IntPtr hWnd, out UInt32 lpdwProcessId);

    public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex)
    {
        if (IntPtr.Size == 8)
        {
            return GetWindowLongPtr64(hWnd, nIndex);
        }
        return new IntPtr(GetWindowLong32(hWnd, nIndex));
    }

    public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong)
    {
        if (IntPtr.Size == 8)
        {
            return SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
        }
        return new IntPtr(SetWindowLong32(hWnd, nIndex, dwNewLong.ToInt32()));
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
}
"@

function Show-CodexWindow {
    $targetProcessIds = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -eq "Codex" -or $_.ProcessName -eq "codex" } |
            Select-Object -ExpandProperty Id
    )

    if ($targetProcessIds.Count -eq 0) {
        return $false
    }

    $script:codexWindowToActivate = [IntPtr]::Zero
    $callback = [CodexQuotaWin32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [CodexQuotaWin32]::IsWindowVisible($hWnd)) {
            return $true
        }

        [UInt32]$windowProcessId = 0
        [void][CodexQuotaWin32]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId)
        if ($targetProcessIds -contains [int]$windowProcessId) {
            $script:codexWindowToActivate = $hWnd
            return $false
        }

        return $true
    }

    [void][CodexQuotaWin32]::EnumWindows($callback, [IntPtr]::Zero)
    if ($script:codexWindowToActivate -eq [IntPtr]::Zero) {
        return $false
    }

    [void][CodexQuotaWin32]::ShowWindow($script:codexWindowToActivate, [CodexQuotaWin32]::SW_RESTORE)
    [void][CodexQuotaWin32]::SetForegroundWindow($script:codexWindowToActivate)
    return $true
}

function Get-WindowClassName {
    param([IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) {
        return ""
    }

    $builder = [System.Text.StringBuilder]::new(256)
    $length = [CodexQuotaWin32]::GetClassName($Handle, $builder, $builder.Capacity)
    if ($length -le 0) {
        return ""
    }

    return $builder.ToString()
}

function Test-IsTaskbarRelatedWindow {
    param([IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) {
        return $false
    }

    $taskbarClasses = @("Shell_TrayWnd", "Shell_SecondaryTrayWnd")
    $className = Get-WindowClassName $Handle
    if ($taskbarClasses -contains $className) {
        return $true
    }

    $rootHandle = [CodexQuotaWin32]::GetAncestor($Handle, [CodexQuotaWin32]::GA_ROOT)
    if ($rootHandle -ne [IntPtr]::Zero -and $rootHandle -ne $Handle) {
        $rootClassName = Get-WindowClassName $rootHandle
        if ($taskbarClasses -contains $rootClassName) {
            return $true
        }
    }

    return $false
}

function Request-OverlayTopmostRefresh {
    if ($script:topmostEventPending) {
        return
    }

    if (-not $script:wpfApp -or -not $script:wpfApp.Dispatcher) {
        Ensure-AllOverlaysTopmost
        return
    }

    $script:topmostEventPending = $true
    try {
        [void]$script:wpfApp.Dispatcher.BeginInvoke(
            [Action]{
                try {
                    Ensure-AllOverlaysTopmost
                }
                finally {
                    $script:topmostEventPending = $false
                }
            },
            [System.Windows.Threading.DispatcherPriority]::Send
        )
    }
    catch {
        $script:topmostEventPending = $false
        Write-OverlayLog "Topmost event dispatch failed: $($_.Exception.Message)"
    }
}

function Register-TaskbarWinEventHooks {
    if ($script:taskbarWinEventHooks -and $script:taskbarWinEventHooks.Count -gt 0) {
        return
    }

    $script:taskbarWinEventHooks = @()
    $script:taskbarWinEventCallback = [CodexQuotaWin32+WinEventDelegate]{
        param(
            [IntPtr]$hook,
            [uint32]$eventType,
            [IntPtr]$windowHandle,
            [int]$idObject,
            [int]$idChild,
            [uint32]$eventThread,
            [uint32]$eventTime
        )

        try {
            if ($windowHandle -eq [IntPtr]::Zero -or $idObject -ne [CodexQuotaWin32]::OBJID_WINDOW) {
                return
            }
            if (Test-IsTaskbarRelatedWindow $windowHandle) {
                Request-OverlayTopmostRefresh
            }
        }
        catch {
            Write-OverlayLog "Taskbar WinEvent callback failed: $($_.Exception.Message)"
        }
    }

    $flags = [CodexQuotaWin32]::WINEVENT_OUTOFCONTEXT -bor [CodexQuotaWin32]::WINEVENT_SKIPOWNPROCESS
    $ranges = @(
        [pscustomobject]@{ Name = "foreground"; Min = [CodexQuotaWin32]::EVENT_SYSTEM_FOREGROUND; Max = [CodexQuotaWin32]::EVENT_SYSTEM_FOREGROUND },
        [pscustomobject]@{ Name = "show"; Min = [CodexQuotaWin32]::EVENT_OBJECT_SHOW; Max = [CodexQuotaWin32]::EVENT_OBJECT_SHOW },
        [pscustomobject]@{ Name = "location"; Min = [CodexQuotaWin32]::EVENT_OBJECT_LOCATIONCHANGE; Max = [CodexQuotaWin32]::EVENT_OBJECT_LOCATIONCHANGE }
    )

    foreach ($range in $ranges) {
        $handle = [CodexQuotaWin32]::SetWinEventHook([uint32]$range.Min, [uint32]$range.Max, [IntPtr]::Zero, $script:taskbarWinEventCallback, 0, 0, [uint32]$flags)
        if ($handle -eq [IntPtr]::Zero) {
            Write-OverlayLog "Taskbar WinEvent hook registration failed: $($range.Name)"
        }
        else {
            $script:taskbarWinEventHooks += $handle
        }
    }

    Write-OverlayLog "Taskbar WinEvent hooks active: $($script:taskbarWinEventHooks.Count)"
}

function Unregister-TaskbarWinEventHooks {
    if ($script:taskbarWinEventHooks) {
        foreach ($handle in @($script:taskbarWinEventHooks)) {
            if ($handle -ne [IntPtr]::Zero) {
                [void][CodexQuotaWin32]::UnhookWinEvent($handle)
            }
        }
    }

    $script:taskbarWinEventHooks = @()
    $script:taskbarWinEventCallback = $null
    $script:topmostEventPending = $false
}

try {
    Write-OverlayLog "Overlay starting. PID=$PID"
    if ($MockQuota) {
        $resolvedCodexExe = ""
    }
    else {
        $resolvedCodexExe = Get-CodexExe $CodexExe
    }
    $server = $null
    $script:resolvedCodexExe = $resolvedCodexExe
    $script:server = $null
    $script:forms = @()
    $script:summary = $null
    $script:timer = $null
    $script:positionTimer = $null
    $script:topmostTimer = $null
    $script:taskbarWinEventHooks = @()
    $script:taskbarWinEventCallback = $null
    $script:topmostEventPending = $false
    $script:clockReservePx = $ClockReservePx
    $script:overlayWidth = $OverlayWidth
    $script:overlayHeight = $OverlayHeight
    $script:taskbarVerticalOffsetPx = $TaskbarVerticalOffsetPx
    $script:secondaryOnly = [bool]$SecondaryOnly
    $script:xOffset = 0
    $script:targetMonitorDevice = ""
    $script:dragWindow = $null
    $script:dragScreen = $null
    $script:isDragging = $false
    Load-OverlaySettings

    if ($MockQuota) {
        $script:summary = New-MockRateLimitSummary
    }
    else {
        $server = Start-CodexAppServer $resolvedCodexExe
        $script:server = $server
        $result = Read-CodexRateLimitsWithRestart
        $script:summary = Convert-RateLimitSummary $result
    }

    if ($Once) {
        Write-Output (Format-OnceText $script:summary)
        return
    }

    $app = [System.Windows.Application]::Current
    if ($null -eq $app) {
        $app = [System.Windows.Application]::new()
    }
    $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    $script:wpfApp = $app

    $menu = [System.Windows.Controls.ContextMenu]::new()
    Set-ModernContextMenuStyle $menu
    $statusFiveItem = New-ModernMenuItem (T "Loading") "5H" $false
    $statusWeekItem = New-ModernMenuItem (T "Loading") "W" $false
    $refreshItem = New-ModernMenuItem (T "RefreshQuota") "R"
    $settingsItem = New-ModernMenuItem (T "SettingsMenu") "S"
    $openItem = New-ModernMenuItem (T "OpenCodex") "O"
    $monitorTitleItem = New-ModernMenuItem (T "SwitchMonitor") "M" $false
    $exitItem = New-ModernMenuItem (T "Exit") "X"
    [void]$menu.Items.Add($statusFiveItem)
    [void]$menu.Items.Add($statusWeekItem)
    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    [void]$menu.Items.Add($refreshItem)
    [void]$menu.Items.Add($settingsItem)
    [void]$menu.Items.Add($openItem)
    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    [void]$menu.Items.Add($monitorTitleItem)

    $script:screenMenuItems = @()
    $screensForMenu = @([System.Windows.Forms.Screen]::AllScreens)
    for ($screenIndex = 0; $screenIndex -lt $screensForMenu.Count; $screenIndex++) {
        $screen = $screensForMenu[$screenIndex]
        $primaryText = if ($screen.Primary) { T "PrimaryShort" } else { "" }
        $label = "{0} {1}{2}" -f (T "Screen"), ($screenIndex + 1), $primaryText
        $screenItem = New-ModernMenuItem $label "-"
        $screenItem.Tag = $screen.DeviceName
        $screenItem.add_Click({
            param($sender, $eventArgs)
            $script:targetMonitorDevice = [string]$sender.Tag
            $script:xOffset = 0
            Save-OverlaySettings
            Update-OverlayPositions
            if ($script:summary) {
                Apply-SummaryToForms $script:summary
            }
            foreach ($item in $script:screenMenuItems) {
                $item.Icon = if ([string]$item.Tag -eq $script:targetMonitorDevice) { ">" } else { "-" }
            }
        })
        [void]$menu.Items.Add($screenItem)
        $script:screenMenuItems += $screenItem
    }

    $menu.add_Opened({
        $currentDevice = $script:targetMonitorDevice
        if (-not $currentDevice) {
            $target = @(Get-TargetScreens)
            if ($target.Count -gt 0) {
                $currentDevice = $target[0].DeviceName
            }
        }
        foreach ($item in $script:screenMenuItems) {
            $item.Icon = if ([string]$item.Tag -eq $currentDevice) { ">" } else { "-" }
        }
    })

    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    [void]$menu.Items.Add($exitItem)

    $script:statusFiveItem = $statusFiveItem
    $script:statusWeekItem = $statusWeekItem

    function Update-OverlayPositions {
        $screens = Get-TargetScreens

        while ($script:forms.Count -lt $screens.Count) {
            $entry = New-OverlayForm $script:menu
            $script:forms += $entry
        }

        if ($screens.Count -eq 0) {
            foreach ($entry in $script:forms) {
                $entry.Window.Hide()
            }
            return
        }

        for ($i = 0; $i -lt $script:forms.Count; $i++) {
            $entry = $script:forms[$i]
            if ($i -lt $screens.Count) {
                $layout = Get-OverlayLayout $screens[$i]
                Set-OverlayLayout $entry $layout
                $rect = Get-OverlayBounds $screens[$i] $layout.Width $layout.Height $script:clockReservePx $script:xOffset $script:taskbarVerticalOffsetPx
                $entry.Window.Width = $rect.Width
                $entry.Window.Height = $rect.Height
                $entry.Window.Left = $rect.X
                $entry.Window.Top = $rect.Y
                if (-not $entry.Window.IsVisible) {
                    $entry.Window.Show()
                    Configure-OverlayWindow $entry.Window
                }
                if ($script:summary) {
                    Set-OverlayStyle $entry "" "" $script:summary.FiveHour.RemainingPercent $script:summary.Weekly.RemainingPercent (Format-ResetTime $script:summary.FiveHour.ResetsAt) (Format-ResetTime $script:summary.Weekly.ResetsAt) $false
                }
                Ensure-OverlayTopmost $entry.Window
            }
            else {
                $entry.Window.Hide()
            }
        }
    }

    function Apply-SummaryToForms {
        param($Summary)

        $text = Format-OverlayText $Summary
        $detail = Format-DetailText $Summary
        $five = $Summary.FiveHour.RemainingPercent
        $week = $Summary.Weekly.RemainingPercent
        $fiveReset = Format-ResetTime $Summary.FiveHour.ResetsAt
        $weekReset = Format-ResetTime $Summary.Weekly.ResetsAt

        foreach ($entry in $script:forms) {
            Set-OverlayStyle $entry $text $detail $five $week $fiveReset $weekReset $false
            Ensure-OverlayTopmost $entry.Window
        }
        $script:statusFiveItem.Header = ("{0:0}% {1} {2}" -f [Math]::Round($five), (T "Reset"), $fiveReset)
        $script:statusWeekItem.Header = ("{0:0}% {1} {2}" -f [Math]::Round($week), (T "Reset"), $weekReset)
    }

    function Set-OverlayError {
        param([string]$Message)

        foreach ($entry in $script:forms) {
            Set-OverlayStyle $entry "Codex 额度不可用" $Message 0 0 "--:--" "--:--" $true
            Ensure-OverlayTopmost $entry.Window
        }
        $script:statusFiveItem.Header = T "Unavailable"
        $script:statusWeekItem.Header = $Message
    }

    function Refresh-QuotaAndForms {
        try {
            if ($MockQuota) {
                $script:summary = New-MockRateLimitSummary
            }
            else {
                if ($script:server.Process.HasExited) {
                    $script:server = Start-CodexAppServer $script:resolvedCodexExe
                }
                $result = Read-CodexRateLimitsWithRestart
                $script:summary = Convert-RateLimitSummary $result
            }
            Update-OverlayPositions
            Apply-SummaryToForms $script:summary
        }
        catch {
            Write-OverlayLog "Refresh failed: $($_.Exception.Message)"
            Update-OverlayPositions
            Set-OverlayError $_.Exception.Message
        }
    }

    $script:menu = $menu
    $refreshItem.add_Click({ Refresh-QuotaAndForms })
    $settingsItem.add_Click({
        if (Show-OverlaySettingsDialog) {
            $refreshItem.Header = T "RefreshQuota"
            $settingsItem.Header = T "SettingsMenu"
            $openItem.Header = T "OpenCodex"
            $monitorTitleItem.Header = T "SwitchMonitor"
            $exitItem.Header = T "Exit"
            for ($screenIndex = 0; $screenIndex -lt $script:screenMenuItems.Count; $screenIndex++) {
                $item = $script:screenMenuItems[$screenIndex]
                $screen = $screensForMenu[$screenIndex]
                $primaryText = if ($screen.Primary) { T "PrimaryShort" } else { "" }
                $item.Header = "{0} {1}{2}" -f (T "Screen"), ($screenIndex + 1), $primaryText
            }
            Update-OverlayPositions
            if ($script:summary) {
                Apply-SummaryToForms $script:summary
            }
        }
    })
    $openItem.add_Click({
        [void](Show-CodexWindow)
    })
    $exitItem.add_Click({
        if (Request-CompanionExit) {
            return
        }
        if ($script:timer) { $script:timer.Stop() }
        if ($script:positionTimer) { $script:positionTimer.Stop() }
        if ($script:topmostTimer) { $script:topmostTimer.Stop() }
        Unregister-TaskbarWinEventHooks
        foreach ($entry in $script:forms) {
            $entry.Window.Close()
        }
        Stop-CodexAppServer $script:server
        $script:wpfApp.Shutdown()
    })

    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:timer = $timer
    $timer.Interval = [TimeSpan]::FromSeconds([Math]::Max(15, $RefreshSeconds))
    $timer.add_Tick({ Refresh-QuotaAndForms })

    $positionTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:positionTimer = $positionTimer
    $positionTimer.Interval = [TimeSpan]::FromSeconds(10)
    $positionTimer.add_Tick({
        if (-not $script:isDragging) {
            Update-OverlayPositions
            if ($script:summary) {
                Apply-SummaryToForms $script:summary
            }
        }
    })

    $topmostTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:topmostTimer = $topmostTimer
    $topmostTimer.Interval = [TimeSpan]::FromSeconds(2)
    $topmostTimer.add_Tick({
        Ensure-AllOverlaysTopmost
    })

    Update-OverlayPositions
    Apply-SummaryToForms $script:summary
    Register-TaskbarWinEventHooks

    if ($VisualQa) {
        $visualQaTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $visualQaTimer.Interval = [TimeSpan]::FromMilliseconds(700)
        $visualQaTimer.add_Tick({
            $visualQaTimer.Stop()
            try {
                Save-VisualQaArtifacts
            }
            catch {
                Write-OverlayLog "Visual QA failed: $($_.Exception.ToString())"
                throw
            }
            finally {
                if ($script:timer) { $script:timer.Stop() }
                if ($script:positionTimer) { $script:positionTimer.Stop() }
                if ($script:topmostTimer) { $script:topmostTimer.Stop() }
                Unregister-TaskbarWinEventHooks
                foreach ($entry in $script:forms) {
                    $entry.Window.Close()
                }
                $script:wpfApp.Shutdown()
            }
        })
        $visualQaTimer.Start()
    }

    $timer.Start()
    $positionTimer.Start()
    $topmostTimer.Start()
    [void]$app.Run()
}
catch {
    $message = $_.Exception.Message
    Write-OverlayLog "Fatal overlay error: $message"
    if ($_.ScriptStackTrace) {
        Write-OverlayLog $_.ScriptStackTrace
    }
    [Console]::Error.WriteLine($message)
    if ($Once) {
        throw
    }
    exit 1
}
finally {
    Unregister-TaskbarWinEventHooks
    Stop-CodexAppServer $script:server
}



