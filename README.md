# Codex Quota Taskbar

Codex Quota Taskbar is a Codex plugin plus a Windows native companion app.

The plugin lets Codex install, start, stop, update, test, and inspect logs for the companion app. The companion app is a PowerShell/WPF tray and taskbar overlay that shows Codex quota status near the Windows taskbar.

## Boundary

This is not a Codex Desktop internal UI plugin. It does not inject UI into Codex Desktop, patch Electron, or hook Codex Desktop process lifecycle internals. Codex manages the tool through plugin skills and scripts; Windows displays the overlay through the native companion app.

## Repository Layout

```text
codex-quota-taskbar/
  .agents/plugins/marketplace.json
  plugins/codex-quota-taskbar/
    .codex-plugin/plugin.json
    skills/codex-quota-taskbar/SKILL.md
    scripts/
    assets/screenshot.png
    companion/
```

## Install From GitHub

After this repository is pushed to GitHub, users can add it as a marketplace:

```powershell
codex plugin marketplace add caomeiguojiang/codex-quota-taskbar
```

Then open Codex Plugins and install **Codex Quota Taskbar** from the `codex-quota-taskbar` marketplace.

CLI install is also possible after the marketplace is added:

```powershell
codex plugin add codex-quota-taskbar@codex-quota-taskbar
```

## Local Test Install

From the parent directory that contains this repository:

```powershell
codex plugin marketplace add .\codex-quota-taskbar
codex plugin add codex-quota-taskbar@codex-quota-taskbar
```

Restart Codex or start a new thread after installing so the bundled skill is available.

## Plugin Tasks

From `plugins/codex-quota-taskbar`:

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

Fast verification:

```powershell
.\scripts\test.ps1 -SkipVisual
```

Full visual QA:

```powershell
.\scripts\test.ps1
```

## Windows App Behavior

- Installed app path: `%LOCALAPPDATA%\CodexQuotaTaskbar\app`
- User settings: `%APPDATA%\CodexQuotaTaskbar\settings.json`
- Logs: `%LOCALAPPDATA%\CodexQuotaTaskbar\logs`
- Runtime state: `%LOCALAPPDATA%\CodexQuotaTaskbar\runtime`
- Autostart: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CodexQuotaTaskbar`

The stop scripts are intentionally scoped. They stop marker-matched monitor and overlay scripts plus local Codex app-server processes owned by this tool.
