@echo off
setlocal
title Flea Market by Kafeena - Discord Bridge
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo.
    echo Windows PowerShell was not found.
    echo This bridge requires Windows PowerShell 5.1 or newer.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0FleaMarketDiscordBridge.ps1"
if errorlevel 1 (
    echo.
    echo The Discord bridge stopped because of an error.
    pause
)
endlocal
