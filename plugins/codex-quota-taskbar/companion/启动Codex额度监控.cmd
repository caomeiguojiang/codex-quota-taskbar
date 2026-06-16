@echo off
set "SCRIPT_DIR=%~dp0"
set "MONITOR_SCRIPT="
for /f "usebackq delims=" %%F in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%SCRIPT_DIR%src' -Filter '*.ps1' -File | Where-Object { ((Get-Content -LiteralPath $_.FullName -TotalCount 1 -Encoding UTF8) -as [string]).Trim() -eq '# CODEX_QUOTA_MONITOR_ENTRY' } | Select-Object -First 1 -ExpandProperty FullName"`) do (
    set "MONITOR_SCRIPT=%%F"
)
if not defined MONITOR_SCRIPT (
    echo Monitor script not found.
    exit /b 1
)
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%MONITOR_SCRIPT%"
