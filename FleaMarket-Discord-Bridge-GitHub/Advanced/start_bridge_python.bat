@echo off
cd /d "%~dp0"
where py >nul 2>&1
if not errorlevel 1 (
    py -3 discord_bridge.py
) else (
    python discord_bridge.py
)
if errorlevel 1 pause
