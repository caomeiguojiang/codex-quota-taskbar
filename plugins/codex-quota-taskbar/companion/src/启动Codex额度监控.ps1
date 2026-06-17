# CODEX_QUOTA_MONITOR_ENTRY
param(
    [int]$PollSeconds = 2,
    [switch]$AllScreens,
    [string]$CodexExe = "",
    [switch]$NoConfig,
    [switch]$Once
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:overlayProcess = $null
$script:lastOverlayError = ""
$script:nextOverlayStartAt = [DateTime]::MinValue
$script:notifyIcon = $null
$script:statusMenuItem = $null
$script:pollTimer = $null
$script:language = ""
$script:settingsMenuItem = $null
$script:restartMenuItem = $null
$script:logMenuItem = $null
$script:exitMenuItem = $null

function Get-AppDataDirectory {
    $base = $env:APPDATA
    if (-not $base) {
        $base = $env:LOCALAPPDATA
    }
    if (-not $base) {
        $base = $scriptDir
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

$appDataDir = Get-AppDataDirectory
$localDataDir = Get-LocalDataDirectory
Ensure-Directory $appDataDir
Ensure-Directory $localDataDir
$settingsPath = Join-Path $appDataDir "settings.json"
$legacySettingsPath = Join-Path $scriptDir "CodexQuotaTaskbar.settings.json"
$logDir = Join-Path $localDataDir "logs"
Ensure-Directory $logDir
$monitorLogPath = Join-Path $logDir "monitor.log"
$overlayLogPath = Join-Path $logDir "overlay.log"
$overlayStdOutPath = Join-Path $logDir "overlay.stdout.log"
$overlayStdErrPath = Join-Path $logDir "overlay.stderr.log"

function Write-MonitorLog {
    param([string]$Message)

    try {
        $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff"), $Message
        Add-Content -LiteralPath $monitorLogPath -Value $line -Encoding UTF8
    }
    catch {
    }
}

function Show-UserError {
    param(
        [string]$Title,
        [string]$Message
    )

    Write-MonitorLog "${Title}: $Message"
    if ($script:notifyIcon) {
        $script:notifyIcon.BalloonTipTitle = $Title
        $script:notifyIcon.BalloonTipText = $Message
        $script:notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
        $script:notifyIcon.ShowBalloonTip(5000)
    }
    else {
        [void][System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
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
            "SettingsTitle" { return "Codex quota taskbar settings" }
            "Monitor" { return "Monitor" }
            "Primary" { return " primary" }
            "XOffset" { return "Horizontal offset" }
            "YOffset" { return "Vertical offset" }
            "Language" { return "Language" }
            "Hint" { return "Saving applies immediately." }
            "Save" { return "Save" }
            "Cancel" { return "Cancel" }
            "Starting" { return "Starting..." }
            "SettingsMenu" { return "Settings..." }
            "RefreshNow" { return "Refresh now" }
            "OpenLogs" { return "Open log folder" }
            "Exit" { return "Exit" }
            "Running" { return "Codex is open. Overlay is running." }
            "Waiting" { return "Waiting for Codex Desktop" }
            "Retry" { return "Codex is open. Retrying overlay startup." }
            "StartFailed" { return "Overlay startup failed. Retrying in 15 seconds." }
            "FailureTitle" { return "Codex quota monitor failed" }
            "StartupFailureTitle" { return "Codex quota monitor startup failed" }
            "OpenLogsFailed" { return "Cannot open log folder" }
        }
    }

    switch ($Key) {
        "SettingsTitle" { return "Codex 额度任务栏设置" }
        "Monitor" { return "显示器" }
        "Primary" { return " 主屏" }
        "XOffset" { return "水平偏移" }
        "YOffset" { return "垂直偏移" }
        "Language" { return "语言" }
        "Hint" { return "保存后立即应用。" }
        "Save" { return "保存" }
        "Cancel" { return "取消" }
        "Starting" { return "正在启动..." }
        "SettingsMenu" { return "设置..." }
        "RefreshNow" { return "立即刷新" }
        "OpenLogs" { return "打开日志目录" }
        "Exit" { return "退出" }
        "Running" { return "Codex 已打开，额度浮层运行中" }
        "Waiting" { return "等待 Codex Desktop 打开" }
        "Retry" { return "Codex 已打开，等待重试启动浮层" }
        "StartFailed" { return "浮层启动失败，15 秒后重试" }
        "FailureTitle" { return "Codex 额度监控失败" }
        "StartupFailureTitle" { return "Codex 额度监控启动失败" }
        "OpenLogsFailed" { return "无法打开日志目录" }
    }

    return $Key
}

$script:language = Get-DefaultLanguage
$settingsUiScript = Join-Path $PSScriptRoot "CodexQuotaSettingsUi.ps1"
if (Test-Path -LiteralPath $settingsUiScript) {
    . $settingsUiScript
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

function Find-SiblingScript {
    param([string]$Marker)

    $match = Get-ChildItem -LiteralPath $scriptDir -Filter "*.ps1" -File | Where-Object {
        Test-ScriptMarker $_.FullName $Marker
    } | Select-Object -First 1

    if (-not $match) {
        throw "Required script marker not found: $Marker"
    }
    return $match.FullName
}

$overlayScript = Find-SiblingScript "CODEX_QUOTA_OVERLAY_ENTRY"
$stopScript = Find-SiblingScript "CODEX_QUOTA_STOP_OVERLAY_ENTRY"

function Load-Settings {
    $defaultScreen = @([System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1)
    if ($defaultScreen.Count -eq 0) {
        $defaultScreen = @([System.Windows.Forms.Screen]::PrimaryScreen)
    }

    $settings = [pscustomobject]@{
        TargetMonitorDevice = $defaultScreen[0].DeviceName
        XOffset = 0
        VerticalOffset = 0
        Language = Get-DefaultLanguage
    }

    if (-not (Test-Path -LiteralPath $settingsPath) -and (Test-Path -LiteralPath $legacySettingsPath)) {
        try {
            Copy-Item -LiteralPath $legacySettingsPath -Destination $settingsPath -Force
            Write-MonitorLog "Migrated settings from $legacySettingsPath to $settingsPath"
        }
        catch {
            Write-MonitorLog "Settings migration failed: $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $saved = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.TargetMonitorDevice) { $settings.TargetMonitorDevice = [string]$saved.TargetMonitorDevice }
            if ($null -ne $saved.XOffset) { $settings.XOffset = [int]$saved.XOffset }
            if ($null -ne $saved.VerticalOffset) { $settings.VerticalOffset = [int]$saved.VerticalOffset }
            if ($saved.Language) { $settings.Language = Normalize-Language ([string]$saved.Language) }
        }
        catch {
            Write-MonitorLog "Settings load failed: $($_.Exception.Message)"
        }
    }

    return $settings
}

function Save-Settings {
    param($Settings)

    Ensure-Directory (Split-Path -Parent $settingsPath)
    [pscustomobject]@{
        TargetMonitorDevice = [string]$Settings.TargetMonitorDevice
        XOffset = [int]$Settings.XOffset
        VerticalOffset = [int]$Settings.VerticalOffset
        Language = Normalize-Language ([string]$Settings.Language)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    Write-MonitorLog "Settings saved to $settingsPath"
}

function Show-SettingsDialog {
    $settings = Load-Settings
    $script:language = Normalize-Language ([string]$settings.Language)
    $screens = @([System.Windows.Forms.Screen]::AllScreens)

    $wasPollTimerEnabled = $false
    if ($script:pollTimer) {
        $wasPollTimerEnabled = $script:pollTimer.Enabled
        if ($wasPollTimerEnabled) { $script:pollTimer.Stop() }
    }

    try {
        $result = Show-CodexQuotaSettingsDialog `
            -Screens $screens `
            -CurrentDevice ([string]$settings.TargetMonitorDevice) `
            -XOffset ([int]$settings.XOffset) `
            -VerticalOffset ([int]$settings.VerticalOffset) `
            -Language $script:language
    }
    finally {
        if ($wasPollTimerEnabled -and $script:pollTimer) {
            $script:pollTimer.Start()
        }
    }

    if (-not $result) {
        return $false
    }

    $settings.TargetMonitorDevice = [string]$result.TargetMonitorDevice
    $settings.XOffset = [int]$result.XOffset
    $settings.VerticalOffset = [int]$result.VerticalOffset
    $settings.Language = Normalize-Language ([string]$result.Language)
    $script:language = [string]$settings.Language
    Save-Settings $settings
    return $true
}
function Test-CodexDesktopOpen {
    try {
        $desktopProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'Codex.exe'" -ErrorAction Stop | Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*\app\Codex.exe*" -and
            $_.CommandLine -notlike "* --type=*"
        })
        return $desktopProcesses.Count -gt 0
    }
    catch {
        $desktopProcesses = @([System.Diagnostics.Process]::GetProcesses() | Where-Object {
            $_.ProcessName -ceq "Codex"
        })
        return $desktopProcesses.Count -gt 0
    }
}

function Test-OverlayAlive {
    param($Process)

    if (-not $Process) {
        return $false
    }

    try {
        $Process.Refresh()
        return -not $Process.HasExited
    }
    catch {
        return $false
    }
}

function Start-Overlay {
    Set-Content -LiteralPath $overlayStdOutPath -Value "" -Encoding UTF8
    Set-Content -LiteralPath $overlayStdErrPath -Value "" -Encoding UTF8

    $arguments = @(
        "-NoProfile",
        "-STA",
        "-ExecutionPolicy",
        "Bypass",
        "-WindowStyle",
        "Hidden",
        "-File",
        $overlayScript,
        "-LogPath",
        $overlayLogPath
    )

    if (-not $AllScreens) {
        $arguments += "-SecondaryOnly"
    }
    if ($CodexExe) {
        $arguments += @("-CodexExe", $CodexExe)
    }

    Write-MonitorLog "Starting overlay: $overlayScript"
    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList $arguments `
        -WindowStyle Hidden `
        -RedirectStandardOutput $overlayStdOutPath `
        -RedirectStandardError $overlayStdErrPath `
        -PassThru `
        -ErrorAction Stop

    Start-Sleep -Milliseconds 1200
    $process.Refresh()
    if ($process.HasExited) {
        $stderr = ""
        $stdout = ""
        if (Test-Path -LiteralPath $overlayStdErrPath) {
            $stderr = (Get-Content -LiteralPath $overlayStdErrPath -Raw -Encoding UTF8).Trim()
        }
        if (Test-Path -LiteralPath $overlayStdOutPath) {
            $stdout = (Get-Content -LiteralPath $overlayStdOutPath -Raw -Encoding UTF8).Trim()
        }
        $detail = @($stderr, $stdout) | Where-Object { $_ } | Select-Object -First 1
        if (-not $detail) {
            $detail = "No stderr/stdout was produced. See $overlayLogPath"
        }
        throw "浮层启动失败。退出码 $($process.ExitCode)。$detail"
    }

    Write-MonitorLog "Overlay started. PID=$($process.Id)"
    return $process
}

function Stop-Overlay {
    if (Test-Path -LiteralPath $stopScript) {
        Write-MonitorLog "Stopping overlay by $stopScript"
        & $stopScript | Out-Null
    }
}

function Stop-OtherMonitorInstances {
    $currentPid = $PID
    $others = Get-CimInstance Win32_Process | Where-Object {
        $filePath = Get-CommandLineFilePath $_.CommandLine
        $_.ProcessId -ne $currentPid -and
        (Test-QuotaScriptPathCandidate $filePath) -and
        (
            (Test-ScriptMarker $filePath "CODEX_QUOTA_MONITOR_ENTRY") -or
            ($filePath -like "*\启动Codex额度监控.ps1" -or $filePath -like "*\Start-CodexQuotaMonitor.ps1")
        )
    }

    foreach ($process in $others) {
        Write-MonitorLog "Stopping another monitor instance. PID=$($process.ProcessId)"
        Stop-Process -Id $process.ProcessId -Force
    }
}

function Update-TrayStatus {
    param([string]$Text)

    if ($script:statusMenuItem) {
        $script:statusMenuItem.Text = $Text
    }
    if ($script:notifyIcon) {
        $script:notifyIcon.Text = if ($Text.Length -gt 63) { $Text.Substring(0, 63) } else { $Text }
    }
}

function Update-TrayMenuLanguage {
    if ($script:settingsMenuItem) { $script:settingsMenuItem.Text = T "SettingsMenu" }
    if ($script:restartMenuItem) { $script:restartMenuItem.Text = T "RefreshNow" }
    if ($script:logMenuItem) { $script:logMenuItem.Text = T "OpenLogs" }
    if ($script:exitMenuItem) { $script:exitMenuItem.Text = T "Exit" }
}

function Invoke-MonitorTick {
    try {
        $codexOpen = Test-CodexDesktopOpen

        if ($codexOpen) {
            if (-not (Test-OverlayAlive $script:overlayProcess)) {
                if ((Get-Date) -lt $script:nextOverlayStartAt) {
                    Update-TrayStatus (T "Retry")
                    return
                }

                $script:overlayProcess = Start-Overlay
                $script:lastOverlayError = ""
                Update-TrayStatus (T "Running")
            }
            else {
                Update-TrayStatus (T "Running")
            }
        }
        else {
            if (Test-OverlayAlive $script:overlayProcess) {
                Stop-Overlay
                $script:overlayProcess = $null
            }
            Update-TrayStatus (T "Waiting")
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-MonitorLog "Monitor tick failed: $message"
        $script:overlayProcess = $null
        $script:nextOverlayStartAt = (Get-Date).AddSeconds(15)
        Update-TrayStatus (T "StartFailed")
        if ($script:lastOverlayError -ne $message) {
            $script:lastOverlayError = $message
            Show-UserError (T "FailureTitle") $message
        }
    }
}

function Restart-OverlayIfNeeded {
    if (Test-OverlayAlive $script:overlayProcess) {
        Stop-Overlay
        $script:overlayProcess = $null
    }
    $script:nextOverlayStartAt = [DateTime]::MinValue
    Invoke-MonitorTick
}

function Start-MonitorApplication {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Stop-OtherMonitorInstances

    if ($NoConfig) {
        $settings = Load-Settings
        $script:language = Normalize-Language ([string]$settings.Language)
    }
    else {
        if (-not (Show-SettingsDialog)) {
            return
        }
    }

    Stop-Overlay

    if ($Once) {
        Invoke-MonitorTick
        return
    }

    $context = [System.Windows.Forms.ApplicationContext]::new()
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()

    $script:statusMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("正在启动...")
    $script:statusMenuItem.Text = T "Starting"
    $script:statusMenuItem.Enabled = $false
    [void]$menu.Items.Add($script:statusMenuItem)
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())

    $settingsItem = [System.Windows.Forms.ToolStripMenuItem]::new((T "SettingsMenu"))
    $settingsItem.add_Click({
        if (Show-SettingsDialog) {
            Update-TrayMenuLanguage
            Restart-OverlayIfNeeded
        }
    })
    [void]$menu.Items.Add($settingsItem)
    $script:settingsMenuItem = $settingsItem

    $restartItem = [System.Windows.Forms.ToolStripMenuItem]::new((T "RefreshNow"))
    $restartItem.add_Click({ Restart-OverlayIfNeeded })
    [void]$menu.Items.Add($restartItem)
    $script:restartMenuItem = $restartItem

    $logItem = [System.Windows.Forms.ToolStripMenuItem]::new((T "OpenLogs"))
    $logItem.add_Click({
        try {
            Start-Process -FilePath $logDir -ErrorAction Stop | Out-Null
        }
        catch {
            Show-UserError (T "OpenLogsFailed") $_.Exception.Message
        }
    })
    [void]$menu.Items.Add($logItem)
    $script:logMenuItem = $logItem

    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $exitItem = [System.Windows.Forms.ToolStripMenuItem]::new((T "Exit"))
    $exitItem.add_Click({
        if ($script:pollTimer) {
            $script:pollTimer.Stop()
            $script:pollTimer.Dispose()
        }
        Stop-Overlay
        if ($script:notifyIcon) {
            $script:notifyIcon.Visible = $false
            $script:notifyIcon.Dispose()
        }
        $context.ExitThread()
    })
    [void]$menu.Items.Add($exitItem)
    $script:exitMenuItem = $exitItem

    $script:notifyIcon = [System.Windows.Forms.NotifyIcon]::new()
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    $script:notifyIcon.Text = "Codex 额度监控"
    $script:notifyIcon.ContextMenuStrip = $menu
    $script:notifyIcon.Visible = $true

    $script:pollTimer = [System.Windows.Forms.Timer]::new()
    $script:pollTimer.Interval = [Math]::Max(1, $PollSeconds) * 1000
    $script:pollTimer.add_Tick({ Invoke-MonitorTick })

    Invoke-MonitorTick
    $script:pollTimer.Start()

    try {
        [System.Windows.Forms.Application]::Run($context)
    }
    finally {
        if ($script:pollTimer) {
            $script:pollTimer.Stop()
            $script:pollTimer.Dispose()
        }
        Stop-Overlay
        if ($script:notifyIcon) {
            $script:notifyIcon.Visible = $false
            $script:notifyIcon.Dispose()
        }
    }
}

try {
    Write-MonitorLog "Monitor starting. Settings=$settingsPath Logs=$logDir"
    Start-MonitorApplication
}
catch {
    Show-UserError (T "StartupFailureTitle") $_.Exception.Message
    exit 1
}




