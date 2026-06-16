# Audit Notes

Date: 2026-06-16

## Scope

Audited the current `outputs/` Windows companion app and the current Codex plugin guidance from the official Codex manual. The resulting shape is a repo marketplace plus a plugin that manages the companion app.

## OpenAI/Codex Constraints Applied

- A Codex plugin is the installable distribution unit for reusable skills, scripts, app integrations, and MCP configuration.
- Public or team distribution should use a marketplace source. GitHub marketplace sources can be added with `codex plugin marketplace add owner/repo`.
- The plugin can make Codex aware of workflows and scripts. It is not a mechanism for injecting UI into Codex Desktop.
- Existing threads may not pick up newly installed or updated plugin skills. Start a new thread after install or reinstall.

## Code Findings

- Baseline smoke test passed with `outputs/scripts/Test-CodexQuotaTaskbar.ps1 -SkipVisual`.
- The companion app already separates user settings, logs, and runtime state into `%APPDATA%` and `%LOCALAPPDATA%`.
- Stop scripts use marker-based matching and runtime state for owned app-server cleanup. That is the right safety boundary.
- Existing companion documentation was not suitable for public GitHub publication because it displayed as mojibake in this environment.
- The companion app depends on Codex local `app-server` quota behavior. Treat that as a volatile internal interface and keep tests around it.

## Changes Made For Plugin Packaging

- Added `.agents/plugins/marketplace.json` for GitHub marketplace distribution.
- Added `plugins/codex-quota-taskbar/.codex-plugin/plugin.json`.
- Added a bundled skill under `skills/codex-quota-taskbar/SKILL.md`.
- Added ASCII wrapper scripts for install, start, stop, update, uninstall, logs, status, and tests.
- Copied the existing companion app under `plugins/codex-quota-taskbar/companion`.
- Added a screenshot asset for plugin presentation.

## Residual Risks

- The app is Windows-specific and requires Windows PowerShell 5.1, WPF, WinForms, and a desktop session.
- Full visual QA opens GUI surfaces and should be run only in an interactive Windows session.
- Registry autostart writes under HKCU. That is appropriate for per-user install, but users should understand it before installing.
- The marketplace uses a local-source entry because Codex resolves plugin folders from the marketplace snapshot. This is expected for repo marketplace distribution.

