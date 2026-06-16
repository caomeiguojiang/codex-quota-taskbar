---
name: codex-quota-taskbar
description: Install, start, stop, update, test, and inspect logs for the Windows Codex quota taskbar companion app. Use when the user asks for a Codex quota overlay, taskbar quota monitor, Windows companion app management, or plugin-managed quota UI.
---

# Codex Quota Taskbar

This plugin manages a Windows native companion app. The companion app is a PowerShell/WPF tray and taskbar overlay that shows Codex quota status.

## Boundary

- The plugin does not inject UI into Codex Desktop.
- The plugin does not hook Codex Desktop's internal Electron lifecycle.
- The plugin runs scripts that install, start, stop, test, update, and inspect the native Windows companion app.
- The overlay itself remains a local Windows process under the user's account.

## Script Locations

Resolve the plugin root from this skill file by going two directories up from `skills/codex-quota-taskbar/`. Management scripts live under `scripts/`:

- `scripts/install.ps1`: install the companion app to `%LOCALAPPDATA%\CodexQuotaTaskbar\app`.
- `scripts/start.ps1`: start the portable companion app from the plugin, or use `-Installed` for the installed copy.
- `scripts/stop.ps1`: stop monitor, overlay, and owned local Codex app-server processes.
- `scripts/update.ps1`: stop the current app and reinstall from the plugin copy.
- `scripts/uninstall.ps1`: remove the installed copy and optional settings.
- `scripts/test.ps1`: run parse, smoke, and optional visual QA tests.
- `scripts/logs.ps1`: print or open the companion log directory.
- `scripts/status.ps1`: report install, autostart, settings, logs, and candidate process status.

## Common Tasks

Use Windows PowerShell. From the plugin root:

```powershell
.\scripts\install.ps1 -StartNow
.\scripts\start.ps1
.\scripts\start.ps1 -Installed
.\scripts\stop.ps1
.\scripts\update.ps1 -StartNow
.\scripts\uninstall.ps1 -KeepSettings
.\scripts\logs.ps1
.\scripts\status.ps1
```

Run a fast verification after edits:

```powershell
.\scripts\test.ps1 -SkipVisual
```

Run full visual QA only when a desktop session is available and screenshots are needed:

```powershell
.\scripts\test.ps1
```

## Development Rules

- Keep companion runtime settings out of source. Settings belong in `%APPDATA%\CodexQuotaTaskbar\settings.json`.
- Logs and runtime state belong under `%LOCALAPPDATA%\CodexQuotaTaskbar`.
- Preserve marker comments in companion scripts because wrappers discover scripts by marker, not by localized filenames.
- Avoid broad process kills. Stop only marker-matched PowerShell scripts and app-server processes owned by this companion app.
- Treat Codex app-server quota details as an internal interface that may change. When it changes, update the companion app and rerun `scripts/test.ps1 -SkipVisual`.

