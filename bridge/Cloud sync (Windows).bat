@echo off
rem WatchX - Made by Rikerud
rem Double-click to sync WatchX's settings through a cloud folder (OneDrive, Dropbox, Google Drive, iCloud):
rem pick the folder here, and the same folder on your other computer. The bridge (installed with
rem "Install (Windows).bat") then keeps the settings in step: copied up when you log out, down before you play.
title WatchX - cloud sync
echo ======================================
echo   WatchX - cloud sync
echo   Made by Rikerud
echo ======================================
echo.
if not exist "%LOCALAPPDATA%\WatchX\watchx_bridge.ps1" (
    echo The bridge isn't installed yet - double-click "Install (Windows).bat" first.
    goto done
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\WatchX\watchx_bridge.ps1" -Cloud
echo.
echo Checking that the bridge can use it...
timeout /t 8 /nobreak >nul
powershell -NoProfile -Command "Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'WatchX-bridge.log') -ErrorAction SilentlyContinue | Select-String 'Cloud sync:' | Select-Object -Last 1 | ForEach-Object { $_.Line }"

:done
echo.
pause
