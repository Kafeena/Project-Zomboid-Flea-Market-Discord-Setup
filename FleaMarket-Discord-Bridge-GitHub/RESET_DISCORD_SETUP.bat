@echo off
setlocal
set "PRIVATE_DIR=%USERPROFILE%\Zomboid\Lua\KafeenaFleaMarketBridge"
echo This removes the saved private webhook setup and bridge progress.
echo It does not delete Project Zomboid listings or market data.
echo.
choice /C YN /M "Reset Discord bridge setup"
if errorlevel 2 exit /b 0
if exist "%PRIVATE_DIR%\discord_private.json" del /q "%PRIVATE_DIR%\discord_private.json"
if exist "%PRIVATE_DIR%\discord_bridge_state.json" del /q "%PRIVATE_DIR%\discord_bridge_state.json"
echo.
echo Discord bridge setup reset.
pause
endlocal
