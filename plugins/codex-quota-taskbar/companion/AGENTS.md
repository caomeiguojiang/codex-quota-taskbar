# AGENTS.md

## Scope

This folder contains the Windows companion app for Codex quota taskbar status.

## File Roles

- `src/Codex额度浮层.ps1`: WPF overlay UI, context menu, settings dialog, monitor switching, quota fetching, display positioning, drag handling, and mock visual QA.
- `src/启动Codex额度监控.ps1`: monitor process, tray menu, startup settings GUI, Codex process detection, and overlay lifecycle.
- `src/停止Codex额度监控.ps1`: stops monitor and delegates owned overlay/app-server cleanup.
- `src/停止Codex额度浮层.ps1`: stops overlay and owned local Codex app-server processes.
- `启动Codex额度监控.cmd` and `停止Codex额度监控.cmd`: portable user entrypoints.
- `安装Codex额度监控.ps1` and `卸载Codex额度监控.ps1`: per-user install/uninstall entrypoints.
- `scripts/Test-CodexQuotaTaskbar.ps1`: parse, smoke, and visual QA test entrypoint.

## Hard Requirements

- Keep marker comments:
  - `CODEX_QUOTA_OVERLAY_ENTRY`
  - `CODEX_QUOTA_MONITOR_ENTRY`
  - `CODEX_QUOTA_STOP_OVERLAY_ENTRY`
  - `CODEX_QUOTA_STOP_MONITOR_ENTRY`
  - `CODEX_QUOTA_INSTALL_ENTRY`
  - `CODEX_QUOTA_UNINSTALL_ENTRY`
- The `.cmd` files must stay ASCII-only and find `.ps1` files in `src/` through marker comments.
- Do not put machine-local settings in `src/`.
- Settings live at `%APPDATA%\CodexQuotaTaskbar\settings.json`.
- Logs and runtime state live under `%LOCALAPPDATA%\CodexQuotaTaskbar`.
- Preserve `zh-CN` and `en-US` support in monitor and overlay UI.
- Avoid broad process kills. Stop only marker-matched PowerShell scripts and local `codex.exe app-server --listen ws://127.0.0.1:*` processes whose parent PID or runtime state belongs to this tool.
- Preserve `-NoConfig` on `src/启动Codex额度监控.ps1` for automated startup.
- Preserve `-MockQuota` and `-VisualQa` on `src/Codex额度浮层.ps1` for automation.
- Keep overlay sizing per-monitor.

## Testing

```powershell
.\scripts\Test-CodexQuotaTaskbar.ps1 -SkipVisual
.\scripts\Test-CodexQuotaTaskbar.ps1
```

