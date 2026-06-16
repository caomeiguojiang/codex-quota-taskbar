# Codex Quota Taskbar Companion

This folder contains the Windows native companion app used by the Codex Quota Taskbar plugin.

## What It Does

- Shows 5-hour and weekly Codex quota windows near the Windows taskbar.
- Runs a tray monitor that starts the overlay when Codex Desktop is open and hides it when Codex closes.
- Provides a right-click overlay menu for refresh, opening Codex, settings, monitor selection, and exit.
- Stores settings in `%APPDATA%\CodexQuotaTaskbar\settings.json`.
- Stores logs in `%LOCALAPPDATA%\CodexQuotaTaskbar\logs`.
- Stores runtime state in `%LOCALAPPDATA%\CodexQuotaTaskbar\runtime`.

## Entry Points

- `启动Codex额度监控.cmd`: portable start entrypoint.
- `停止Codex额度监控.cmd`: portable stop entrypoint.
- `安装Codex额度监控.ps1`: per-user install entrypoint.
- `卸载Codex额度监控.ps1`: per-user uninstall entrypoint.
- `scripts/Test-CodexQuotaTaskbar.ps1`: parse, smoke, and visual QA test entrypoint.

The `.cmd` files discover PowerShell scripts by marker comments. Do not hardcode localized script filenames in `.cmd` wrappers.

## Install

```powershell
.\安装Codex额度监控.ps1 -StartNow
```

Default install path:

```text
%LOCALAPPDATA%\CodexQuotaTaskbar\app
```

Autostart location:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CodexQuotaTaskbar
```

## Uninstall

```powershell
.\卸载Codex额度监控.ps1
```

Keep settings:

```powershell
.\卸载Codex额度监控.ps1 -KeepSettings
```

## Test

Fast smoke test:

```powershell
.\scripts\Test-CodexQuotaTaskbar.ps1 -SkipVisual
```

Full visual QA:

```powershell
.\scripts\Test-CodexQuotaTaskbar.ps1
```

## Compatibility

The companion app uses Windows PowerShell 5.1, WPF, WinForms, and Win32 `user32.dll`. It is intended for Windows 10 and Windows 11 desktop sessions.

Codex itself is best supported on Windows 11. Recent fully updated Windows 10 is best effort.

## Limits

- This is not an internal Codex Desktop UI plugin.
- It cannot appear over UAC secure desktop, lock screens, exclusive fullscreen apps, or stronger topmost windows.
- Quota fetching depends on local Codex app-server behavior and may need updates if Codex changes that interface.

