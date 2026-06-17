# Shared native-control settings dialog for Codex Quota Taskbar.
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

if (-not (Get-Command Normalize-Language -CommandType Function -ErrorAction SilentlyContinue)) {
    function Normalize-Language {
        param([string]$Language)

        if ($Language -and $Language -like 'zh*') {
            return 'zh-CN'
        }
        if ($Language -and $Language -like 'en*') {
            return 'en-US'
        }
        return 'en-US'
    }
}

if (-not (Get-Command Get-DefaultLanguage -CommandType Function -ErrorAction SilentlyContinue)) {
    function Get-DefaultLanguage {
        return Normalize-Language ([System.Globalization.CultureInfo]::CurrentUICulture.Name)
    }
}

function Get-CodexQuotaSettingsText {
    param(
        [string]$Key,
        [string]$Language
    )

    $lang = Normalize-Language $Language
    if ($lang -eq 'en-US') {
        switch ($Key) {
            'SettingsTitle' { return 'Codex quota taskbar settings' }
            'General' { return 'General' }
            'Display' { return 'Display' }
            'About' { return 'About' }
            'DisplayLanguage' { return 'Display language:' }
            'Monitor' { return 'Monitor:' }
            'Primary' { return ' primary' }
            'SelectedMonitor' { return 'Selected monitor' }
            'Device' { return 'Device:' }
            'Bounds' { return 'Bounds:' }
            'WorkingArea' { return 'Working area:' }
            'SettingsFile' { return 'Settings file' }
            'Path' { return 'Path:' }
            'OpenFolder' { return 'Open folder' }
            'OpenLogs' { return 'Open log folder' }
            'RuntimeInfo' { return 'Runtime information' }
            'Version' { return 'Version:' }
            'InstallPath' { return 'Install path:' }
            'Save' { return 'Save' }
            'Cancel' { return 'Cancel' }
            'RestoreDefault' { return 'Restore default' }
            'OpenFailed' { return 'Cannot open folder' }
            default { return $Key }
        }
    }

    switch ($Key) {
        'SettingsTitle' { return 'Codex 额度任务栏设置' }
        'General' { return '常规' }
        'Display' { return '显示' }
        'About' { return '关于' }
        'DisplayLanguage' { return '显示语言:' }
        'Monitor' { return '显示器:' }
        'Primary' { return ' 主屏' }
        'SelectedMonitor' { return '选中的显示器' }
        'Device' { return '设备:' }
        'Bounds' { return '边界:' }
        'WorkingArea' { return '工作区:' }
        'SettingsFile' { return '配置文件位置' }
        'Path' { return '路径:' }
        'OpenFolder' { return '打开所在文件夹' }
        'OpenLogs' { return '打开日志文件夹' }
        'RuntimeInfo' { return '运行时信息' }
        'Version' { return '版本:' }
        'InstallPath' { return '安装路径:' }
        'Save' { return '保存' }
        'Cancel' { return '取消' }
        'RestoreDefault' { return '恢复默认' }
        'OpenFailed' { return '无法打开文件夹' }
        default { return $Key }
    }
}

function Get-CodexQuotaSettingsVersion {
    $versionPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'
    if (Test-Path -LiteralPath $versionPath) {
        try {
            return (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
        }
        catch {
        }
    }
    return 'unknown'
}

function Get-CodexQuotaSettingsPath {
    $base = $env:APPDATA
    if (-not $base) { $base = $env:LOCALAPPDATA }
    if (-not $base) { $base = Split-Path -Parent $PSScriptRoot }
    return Join-Path $base 'CodexQuotaTaskbar\settings.json'
}

function Get-CodexQuotaLogsPath {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = $env:APPDATA }
    if (-not $base) { $base = Split-Path -Parent $PSScriptRoot }
    return Join-Path $base 'CodexQuotaTaskbar\logs'
}

function Invoke-CodexQuotaOpenFolder {
    param(
        [string]$Path,
        [string]$Language
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            [void](New-Item -ItemType Directory -Path $Path -Force)
        }
        Start-Process -FilePath $Path -ErrorAction Stop | Out-Null
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            (Get-CodexQuotaSettingsText 'OpenFailed' $Language),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
}

function Convert-CodexQuotaMonitorIdText {
    param([object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $chars = @()
    foreach ($code in @($Value)) {
        $number = [int]$code
        if ($number -gt 0) {
            $chars += [char]$number
        }
    }
    return (-join $chars).Trim()
}

function Resolve-CodexQuotaMonitorManufacturer {
    param([string]$Code)

    if ([string]::IsNullOrWhiteSpace($Code)) {
        return ''
    }

    $normalized = $Code.Trim().ToUpperInvariant()
    $manufacturerNames = @{
        ACI = 'ASUS'
        ACR = 'Acer'
        AOC = 'AOC'
        APP = 'Apple'
        AUS = 'ASUS'
        BNQ = 'BenQ'
        DEL = 'DELL'
        GSM = 'LG'
        HWP = 'HP'
        LEN = 'Lenovo'
        LGD = 'LG'
        PHL = 'Philips'
        SAM = 'Samsung'
        SEC = 'Samsung'
        SNY = 'Sony'
        VSC = 'ViewSonic'
    }

    if ($manufacturerNames.ContainsKey($normalized)) {
        return $manufacturerNames[$normalized]
    }
    return $normalized
}

function Get-CodexQuotaMonitorHardwareId {
    param([string]$InstanceName)

    if ([string]::IsNullOrWhiteSpace($InstanceName)) {
        return ''
    }

    $match = [regex]::Match($InstanceName.ToUpperInvariant(), '(?:DISPLAY|MONITOR)\\([^\\]+)')
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return ''
}

function Get-CodexQuotaWmiMonitorName {
    param([object]$Monitor)

    $manufacturer = Resolve-CodexQuotaMonitorManufacturer (Convert-CodexQuotaMonitorIdText $Monitor.ManufacturerName)
    $friendlyName = Convert-CodexQuotaMonitorIdText $Monitor.UserFriendlyName
    $productCode = Convert-CodexQuotaMonitorIdText $Monitor.ProductCodeID

    if (-not [string]::IsNullOrWhiteSpace($friendlyName)) {
        if (-not [string]::IsNullOrWhiteSpace($manufacturer) -and -not $friendlyName.ToUpperInvariant().StartsWith($manufacturer.ToUpperInvariant())) {
            return ('{0} {1}' -f $manufacturer, $friendlyName).Trim()
        }
        return $friendlyName
    }

    if (-not [string]::IsNullOrWhiteSpace($manufacturer) -and -not [string]::IsNullOrWhiteSpace($productCode)) {
        return ('{0} {1}' -f $manufacturer, $productCode).Trim()
    }

    return $manufacturer
}

function Get-CodexQuotaDisplayMonitorDeviceIds {
    $displayMonitorIds = @{}

    try {
        if (-not ([System.Management.Automation.PSTypeName]'CodexQuotaNativeDisplay').Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CodexQuotaNativeDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
}
'@
        }

        for ($adapterIndex = 0; $adapterIndex -lt 32; $adapterIndex++) {
            $adapter = [CodexQuotaNativeDisplay+DISPLAY_DEVICE]::new()
            $adapter.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($adapter)
            if (-not [CodexQuotaNativeDisplay]::EnumDisplayDevices($null, [uint32]$adapterIndex, [ref]$adapter, 0)) {
                break
            }
            if ([string]::IsNullOrWhiteSpace($adapter.DeviceName)) {
                continue
            }

            for ($monitorIndex = 0; $monitorIndex -lt 16; $monitorIndex++) {
                $monitor = [CodexQuotaNativeDisplay+DISPLAY_DEVICE]::new()
                $monitor.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($monitor)
                if (-not [CodexQuotaNativeDisplay]::EnumDisplayDevices($adapter.DeviceName, [uint32]$monitorIndex, [ref]$monitor, 0)) {
                    break
                }
                if (-not [string]::IsNullOrWhiteSpace($monitor.DeviceID)) {
                    $displayMonitorIds[[string]$adapter.DeviceName] = [string]$monitor.DeviceID
                    break
                }
            }
        }
    }
    catch {
    }

    return $displayMonitorIds
}

function Get-CodexQuotaMonitorDisplayNames {
    param([object[]]$Screens)

    $namesByDevice = @{}
    $namesByHardwareId = @{}
    $namesInOrder = [System.Collections.ArrayList]::new()

    try {
        $monitors = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | Where-Object { $_.Active })
    }
    catch {
        try {
            $monitors = @(Get-WmiObject -Namespace root\wmi -Class WmiMonitorID -ErrorAction Stop | Where-Object { $_.Active })
        }
        catch {
            $monitors = @()
        }
    }

    foreach ($monitor in $monitors) {
        $name = Get-CodexQuotaWmiMonitorName $monitor
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $hardwareId = Get-CodexQuotaMonitorHardwareId ([string]$monitor.InstanceName)
        if (-not [string]::IsNullOrWhiteSpace($hardwareId) -and -not $namesByHardwareId.ContainsKey($hardwareId)) {
            $namesByHardwareId[$hardwareId] = $name
        }
        [void]$namesInOrder.Add($name)
    }

    $displayMonitorIds = Get-CodexQuotaDisplayMonitorDeviceIds
    for ($i = 0; $i -lt $Screens.Count; $i++) {
        $screen = $Screens[$i]
        $deviceName = [string]$screen.DeviceName
        $displayName = ''

        if ($displayMonitorIds.ContainsKey($deviceName)) {
            $hardwareId = Get-CodexQuotaMonitorHardwareId ([string]$displayMonitorIds[$deviceName])
            if (-not [string]::IsNullOrWhiteSpace($hardwareId) -and $namesByHardwareId.ContainsKey($hardwareId)) {
                $displayName = [string]$namesByHardwareId[$hardwareId]
            }
        }

        if ([string]::IsNullOrWhiteSpace($displayName) -and $i -lt $namesInOrder.Count) {
            $displayName = [string]$namesInOrder[$i]
        }
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = $deviceName
        }

        $namesByDevice[$deviceName] = $displayName
    }

    return $namesByDevice
}

function Format-CodexQuotaMonitorListItem {
    param(
        [int]$Index,
        [string]$DisplayName,
        [string]$Language
    )

    $name = if ([string]::IsNullOrWhiteSpace($DisplayName)) { "DISPLAY$Index" } else { $DisplayName.Trim() }
    if ((Normalize-Language $Language) -eq 'en-US') {
        return 'Display {0}: {1}' -f $Index, $name
    }
    return '显示器 {0}: {1}' -f $Index, $name
}

function New-CodexQuotaAutoLabel {
    param([string]$Text)

    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $label.Margin = [System.Windows.Forms.Padding]::new(0, 6, 10, 6)
    return $label
}

function New-CodexQuotaDockedTextBox {
    param([string]$Text = '')

    $textBox = [System.Windows.Forms.TextBox]::new()
    $textBox.Text = $Text
    $textBox.ReadOnly = $true
    $textBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $textBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $textBox.Margin = [System.Windows.Forms.Padding]::new(0, 3, 0, 3)
    return $textBox
}

function New-CodexQuotaAutoButton {
    param([string]$Text)

    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.AutoSize = $true
    $button.MinimumSize = [System.Drawing.Size]::new(86, 28)
    $button.Margin = [System.Windows.Forms.Padding]::new(6, 0, 0, 0)
    return $button
}

function Show-CodexQuotaSettingsDialog {
    param(
        [object[]]$Screens,
        [string]$CurrentDevice = '',
        [int]$XOffset = 0,
        [int]$VerticalOffset = 0,
        [string]$Language = '',
        [scriptblock]$OnShown = $null
    )

    if (-not $Screens -or $Screens.Count -eq 0) {
        return $null
    }

    [System.Windows.Forms.Application]::EnableVisualStyles()
    $state = @{
        Language = if ([string]::IsNullOrWhiteSpace($Language)) { Get-DefaultLanguage } else { Normalize-Language $Language }
    }
    $settingsPath = Get-CodexQuotaSettingsPath
    $logsPath = Get-CodexQuotaLogsPath
    $installPath = Split-Path -Parent $PSScriptRoot
    $monitorDisplayNames = Get-CodexQuotaMonitorDisplayNames $Screens

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = Get-CodexQuotaSettingsText 'SettingsTitle' $state.Language
    $form.ClientSize = [System.Drawing.Size]::new(540, 360)
    $form.MinimumSize = [System.Drawing.Size]::new(520, 350)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $false
    $form.Font = [System.Drawing.SystemFonts]::MessageBoxFont
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font

    $root = [System.Windows.Forms.TableLayoutPanel]::new()
    $root.Dock = [System.Windows.Forms.DockStyle]::Fill
    $root.Padding = [System.Windows.Forms.Padding]::new(12)
    $root.ColumnCount = 1
    $root.RowCount = 2
    [void]$root.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$form.Controls.Add($root)

    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = [System.Windows.Forms.DockStyle]::Fill

    $generalTab = [System.Windows.Forms.TabPage]::new((Get-CodexQuotaSettingsText 'General' $state.Language))
    $displayTab = [System.Windows.Forms.TabPage]::new((Get-CodexQuotaSettingsText 'Display' $state.Language))
    $aboutTab = [System.Windows.Forms.TabPage]::new((Get-CodexQuotaSettingsText 'About' $state.Language))
    $generalTab.Padding = [System.Windows.Forms.Padding]::new(10)
    $displayTab.Padding = [System.Windows.Forms.Padding]::new(10)
    $aboutTab.Padding = [System.Windows.Forms.Padding]::new(10)
    [void]$tabs.TabPages.Add($generalTab)
    [void]$tabs.TabPages.Add($displayTab)
    [void]$tabs.TabPages.Add($aboutTab)
    [void]$root.Controls.Add($tabs, 0, 0)

    $generalLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $generalLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $generalLayout.ColumnCount = 2
    $generalLayout.RowCount = 3
    [void]$generalLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$generalLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$generalLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$generalLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$generalLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$generalTab.Controls.Add($generalLayout)

    $languageLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'DisplayLanguage' $state.Language)
    [void]$generalLayout.Controls.Add($languageLabel, 0, 0)

    $languageBox = [System.Windows.Forms.ComboBox]::new()
    $languageBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $languageBox.Width = 180
    $languageBox.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $languageBox.Margin = [System.Windows.Forms.Padding]::new(0, 3, 0, 8)
    [void]$languageBox.Items.Add('简体中文')
    [void]$languageBox.Items.Add('English')
    $languageBox.SelectedIndex = if ($state.Language -eq 'en-US') { 1 } else { 0 }
    [void]$generalLayout.Controls.Add($languageBox, 1, 0)

    $settingsGroup = [System.Windows.Forms.GroupBox]::new()
    $settingsGroup.Text = Get-CodexQuotaSettingsText 'SettingsFile' $state.Language
    $settingsGroup.Dock = [System.Windows.Forms.DockStyle]::Top
    $settingsGroup.AutoSize = $true
    $settingsGroup.Padding = [System.Windows.Forms.Padding]::new(10, 8, 10, 10)
    $settingsGroup.Margin = [System.Windows.Forms.Padding]::new(0, 6, 0, 0)
    [void]$generalLayout.Controls.Add($settingsGroup, 0, 1)
    $generalLayout.SetColumnSpan($settingsGroup, 2)

    $settingsTable = [System.Windows.Forms.TableLayoutPanel]::new()
    $settingsTable.Dock = [System.Windows.Forms.DockStyle]::Top
    $settingsTable.AutoSize = $true
    $settingsTable.ColumnCount = 2
    $settingsTable.RowCount = 2
    [void]$settingsTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$settingsTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$settingsTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$settingsTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$settingsGroup.Controls.Add($settingsTable)

    $settingsPathLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'Path' $state.Language)
    [void]$settingsTable.Controls.Add($settingsPathLabel, 0, 0)
    $settingsText = New-CodexQuotaDockedTextBox $settingsPath
    [void]$settingsTable.Controls.Add($settingsText, 1, 0)

    $settingsButtons = [System.Windows.Forms.FlowLayoutPanel]::new()
    $settingsButtons.AutoSize = $true
    $settingsButtons.Dock = [System.Windows.Forms.DockStyle]::Fill
    $settingsButtons.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $settingsButtons.WrapContents = $false
    $settingsButtons.Margin = [System.Windows.Forms.Padding]::new(0, 5, 0, 0)
    [void]$settingsTable.Controls.Add($settingsButtons, 1, 1)

    $openSettingsButton = New-CodexQuotaAutoButton (Get-CodexQuotaSettingsText 'OpenFolder' $state.Language)
    $openSettingsButton.add_Click({
        Invoke-CodexQuotaOpenFolder (Split-Path -Parent $settingsPath) $state.Language
    }.GetNewClosure())
    [void]$settingsButtons.Controls.Add($openSettingsButton)

    $openLogsButton = New-CodexQuotaAutoButton (Get-CodexQuotaSettingsText 'OpenLogs' $state.Language)
    $openLogsButton.add_Click({
        Invoke-CodexQuotaOpenFolder $logsPath $state.Language
    }.GetNewClosure())
    [void]$settingsButtons.Controls.Add($openLogsButton)

    $displayLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $displayLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $displayLayout.ColumnCount = 2
    $displayLayout.RowCount = 3
    [void]$displayLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$displayLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$displayLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$displayLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$displayLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$displayTab.Controls.Add($displayLayout)

    $monitorLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'Monitor' $state.Language)
    [void]$displayLayout.Controls.Add($monitorLabel, 0, 0)

    $monitorBox = [System.Windows.Forms.ComboBox]::new()
    $monitorBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $monitorBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $monitorBox.IntegralHeight = $false
    $monitorBox.Margin = [System.Windows.Forms.Padding]::new(0, 3, 0, 8)
    $monitorBox.add_DropDown({
        $monitorBox.DropDownWidth = [Math]::Max($monitorBox.Width, 360)
    }.GetNewClosure())
    $screenDevices = [System.Collections.ArrayList]::new()
    $rebuildMonitorItems = {
        param([string]$PreferredDevice)

        if (-not $PreferredDevice -and $monitorBox.SelectedIndex -ge 0 -and $monitorBox.SelectedIndex -lt $screenDevices.Count) {
            $PreferredDevice = [string]$screenDevices[$monitorBox.SelectedIndex]
        }

        [void]$monitorBox.BeginUpdate()
        try {
            $monitorBox.Items.Clear()
            $screenDevices.Clear()
            $selectedIndex = -1

            for ($i = 0; $i -lt $Screens.Count; $i++) {
                $screen = $Screens[$i]
                $deviceName = [string]$screen.DeviceName
                $displayName = if ($monitorDisplayNames.ContainsKey($deviceName)) { [string]$monitorDisplayNames[$deviceName] } else { $deviceName }
                $label = Format-CodexQuotaMonitorListItem ($i + 1) $displayName $state.Language
                [void]$monitorBox.Items.Add($label)
                [void]$screenDevices.Add($deviceName)
                if ($deviceName -eq $PreferredDevice) {
                    $selectedIndex = $i
                }
            }

            if ($selectedIndex -lt 0 -and $monitorBox.Items.Count -gt 0) {
                $selectedIndex = 0
            }
            if ($selectedIndex -ge 0) {
                $monitorBox.SelectedIndex = $selectedIndex
            }
            $monitorBox.DropDownWidth = [Math]::Max($monitorBox.Width, 360)
        }
        finally {
            [void]$monitorBox.EndUpdate()
        }
    }.GetNewClosure()
    & $rebuildMonitorItems $CurrentDevice
    [void]$displayLayout.Controls.Add($monitorBox, 1, 0)

    $monitorGroup = [System.Windows.Forms.GroupBox]::new()
    $monitorGroup.Text = Get-CodexQuotaSettingsText 'SelectedMonitor' $state.Language
    $monitorGroup.Dock = [System.Windows.Forms.DockStyle]::Top
    $monitorGroup.AutoSize = $true
    $monitorGroup.Padding = [System.Windows.Forms.Padding]::new(10, 8, 10, 10)
    $monitorGroup.Margin = [System.Windows.Forms.Padding]::new(0, 6, 0, 0)
    [void]$displayLayout.Controls.Add($monitorGroup, 0, 1)
    $displayLayout.SetColumnSpan($monitorGroup, 2)

    $monitorTable = [System.Windows.Forms.TableLayoutPanel]::new()
    $monitorTable.Dock = [System.Windows.Forms.DockStyle]::Top
    $monitorTable.AutoSize = $true
    $monitorTable.ColumnCount = 2
    $monitorTable.RowCount = 3
    [void]$monitorTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$monitorTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$monitorTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$monitorTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$monitorTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$monitorGroup.Controls.Add($monitorTable)

    $deviceLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'Device' $state.Language)
    [void]$monitorTable.Controls.Add($deviceLabel, 0, 0)
    $deviceText = New-CodexQuotaDockedTextBox
    [void]$monitorTable.Controls.Add($deviceText, 1, 0)

    $boundsLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'Bounds' $state.Language)
    [void]$monitorTable.Controls.Add($boundsLabel, 0, 1)
    $boundsText = New-CodexQuotaDockedTextBox
    [void]$monitorTable.Controls.Add($boundsText, 1, 1)

    $workLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'WorkingArea' $state.Language)
    [void]$monitorTable.Controls.Add($workLabel, 0, 2)
    $workText = New-CodexQuotaDockedTextBox
    [void]$monitorTable.Controls.Add($workText, 1, 2)

    $updateMonitorFields = {
        $index = $monitorBox.SelectedIndex
        if ($index -lt 0 -or $index -ge $Screens.Count) { return }
        $screen = $Screens[$index]
        $deviceText.Text = [string]$screen.DeviceName
        $boundsText.Text = '{0}x{1}, {2},{3}' -f $screen.Bounds.Width, $screen.Bounds.Height, $screen.Bounds.X, $screen.Bounds.Y
        $workText.Text = '{0}x{1}, {2},{3}' -f $screen.WorkingArea.Width, $screen.WorkingArea.Height, $screen.WorkingArea.X, $screen.WorkingArea.Y
    }.GetNewClosure()
    $monitorBox.add_SelectedIndexChanged($updateMonitorFields)
    & $updateMonitorFields

    $aboutLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $aboutLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $aboutLayout.ColumnCount = 1
    $aboutLayout.RowCount = 2
    [void]$aboutLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$aboutLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$aboutLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$aboutTab.Controls.Add($aboutLayout)

    $aboutGroup = [System.Windows.Forms.GroupBox]::new()
    $aboutGroup.Text = Get-CodexQuotaSettingsText 'RuntimeInfo' $state.Language
    $aboutGroup.Dock = [System.Windows.Forms.DockStyle]::Top
    $aboutGroup.AutoSize = $true
    $aboutGroup.Padding = [System.Windows.Forms.Padding]::new(10, 8, 10, 10)
    [void]$aboutLayout.Controls.Add($aboutGroup, 0, 0)

    $aboutTable = [System.Windows.Forms.TableLayoutPanel]::new()
    $aboutTable.Dock = [System.Windows.Forms.DockStyle]::Top
    $aboutTable.AutoSize = $true
    $aboutTable.ColumnCount = 2
    $aboutTable.RowCount = 3
    [void]$aboutTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$aboutTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$aboutTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$aboutTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$aboutTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$aboutGroup.Controls.Add($aboutTable)

    $productLabel = New-CodexQuotaAutoLabel 'Codex Quota Taskbar'
    [void]$aboutTable.Controls.Add($productLabel, 0, 0)
    $aboutTable.SetColumnSpan($productLabel, 2)
    $versionLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'Version' $state.Language)
    [void]$aboutTable.Controls.Add($versionLabel, 0, 1)
    [void]$aboutTable.Controls.Add((New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsVersion)), 1, 1)
    $installPathLabel = New-CodexQuotaAutoLabel (Get-CodexQuotaSettingsText 'InstallPath' $state.Language)
    [void]$aboutTable.Controls.Add($installPathLabel, 0, 2)
    $installText = New-CodexQuotaDockedTextBox $installPath
    [void]$aboutTable.Controls.Add($installText, 1, 2)

    $buttonBar = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonBar.Dock = [System.Windows.Forms.DockStyle]::Fill
    $buttonBar.AutoSize = $true
    $buttonBar.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonBar.WrapContents = $false
    $buttonBar.Padding = [System.Windows.Forms.Padding]::new(0, 10, 0, 0)
    [void]$root.Controls.Add($buttonBar, 0, 1)

    $restoreButton = New-CodexQuotaAutoButton (Get-CodexQuotaSettingsText 'RestoreDefault' $state.Language)
    $restoreButton.add_Click({
        $languageBox.SelectedIndex = if ((Normalize-Language (Get-DefaultLanguage)) -eq 'en-US') { 1 } else { 0 }
        for ($i = 0; $i -lt $Screens.Count; $i++) {
            if ($Screens[$i].Primary) {
                $monitorBox.SelectedIndex = $i
                return
            }
        }
        if ($monitorBox.Items.Count -gt 0) { $monitorBox.SelectedIndex = 0 }
    }.GetNewClosure())

    $saveButton = New-CodexQuotaAutoButton (Get-CodexQuotaSettingsText 'Save' $state.Language)
    $saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-CodexQuotaAutoButton (Get-CodexQuotaSettingsText 'Cancel' $state.Language)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$buttonBar.Controls.Add($cancelButton)
    [void]$buttonBar.Controls.Add($saveButton)
    [void]$buttonBar.Controls.Add($restoreButton)

    $form.AcceptButton = $saveButton
    $form.CancelButton = $cancelButton

    $applyLanguage = {
        $form.Text = Get-CodexQuotaSettingsText 'SettingsTitle' $state.Language
        $generalTab.Text = Get-CodexQuotaSettingsText 'General' $state.Language
        $displayTab.Text = Get-CodexQuotaSettingsText 'Display' $state.Language
        $aboutTab.Text = Get-CodexQuotaSettingsText 'About' $state.Language
        $languageLabel.Text = Get-CodexQuotaSettingsText 'DisplayLanguage' $state.Language
        $settingsGroup.Text = Get-CodexQuotaSettingsText 'SettingsFile' $state.Language
        $settingsPathLabel.Text = Get-CodexQuotaSettingsText 'Path' $state.Language
        $openSettingsButton.Text = Get-CodexQuotaSettingsText 'OpenFolder' $state.Language
        $openLogsButton.Text = Get-CodexQuotaSettingsText 'OpenLogs' $state.Language
        $monitorLabel.Text = Get-CodexQuotaSettingsText 'Monitor' $state.Language
        $monitorGroup.Text = Get-CodexQuotaSettingsText 'SelectedMonitor' $state.Language
        $deviceLabel.Text = Get-CodexQuotaSettingsText 'Device' $state.Language
        $boundsLabel.Text = Get-CodexQuotaSettingsText 'Bounds' $state.Language
        $workLabel.Text = Get-CodexQuotaSettingsText 'WorkingArea' $state.Language
        $aboutGroup.Text = Get-CodexQuotaSettingsText 'RuntimeInfo' $state.Language
        $versionLabel.Text = Get-CodexQuotaSettingsText 'Version' $state.Language
        $installPathLabel.Text = Get-CodexQuotaSettingsText 'InstallPath' $state.Language
        $restoreButton.Text = Get-CodexQuotaSettingsText 'RestoreDefault' $state.Language
        $saveButton.Text = Get-CodexQuotaSettingsText 'Save' $state.Language
        $cancelButton.Text = Get-CodexQuotaSettingsText 'Cancel' $state.Language
        & $rebuildMonitorItems ''
        $form.PerformLayout()
    }.GetNewClosure()

    $languageBox.add_SelectedIndexChanged({
        $state.Language = if ($languageBox.SelectedIndex -eq 1) { 'en-US' } else { 'zh-CN' }
        & $applyLanguage
    }.GetNewClosure())

    if ($OnShown) {
        $shownRefreshTimer = $null
        $form.add_Shown({
            $shownRefreshTimer = [System.Windows.Forms.Timer]::new()
            $shownRefreshTimer.Interval = 150
            $shownRefreshTimer.add_Tick({
                $shownRefreshTimer.Stop()
                $shownRefreshTimer.Dispose()
                try {
                    & $OnShown
                }
                catch {
                }
            }.GetNewClosure())
            $shownRefreshTimer.Start()
        }.GetNewClosure())
    }

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $selectedIndex = $monitorBox.SelectedIndex
    if ($selectedIndex -lt 0 -and $monitorBox.Items.Count -gt 0) {
        $selectedIndex = 0
    }
    if ($selectedIndex -lt 0) {
        return $null
    }

    return [pscustomobject]@{
        TargetMonitorDevice = [string]$screenDevices[$selectedIndex]
        XOffset = [int]$XOffset
        VerticalOffset = [int]$VerticalOffset
        Language = Normalize-Language $state.Language
    }
}
