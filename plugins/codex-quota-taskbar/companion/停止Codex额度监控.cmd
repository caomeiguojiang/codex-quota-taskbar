@echo off
set "SCRIPT_DIR=%~dp0"
set "STOP_SCRIPT="
for /f "usebackq delims=" %%F in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%SCRIPT_DIR%src' -Filter '*.ps1' -File | Where-Object { ((Get-Content -LiteralPath $_.FullName -TotalCount 1 -Encoding UTF8) -as [string]).Trim() -eq '# CODEX_QUOTA_STOP_MONITOR_ENTRY' } | Select-Object -First 1 -ExpandProperty FullName"`) do (
    set "STOP_SCRIPT=%%F"
)
if not defined STOP_SCRIPT (
    echo Stop script not found.
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%STOP_SCRIPT%"
