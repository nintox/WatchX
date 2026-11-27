@echo off
rem WatchX - Made by Rikerud
rem Double-click to set up the WatchX bridge: phone alerts, cloud sync of your settings, or both - or to remove it.
rem It's copied to %LOCALAPPDATA%\WatchX, runs hidden in the background and starts by itself when you log in to
rem Windows. Run it again any time to change your choice or the cloud folder.
title WatchX bridge
echo ======================================
echo   WatchX bridge - Made by Rikerud
echo ======================================
echo.

rem Opened straight from the zip, Windows copies only this file somewhere else: the bridge isn't next to it.
if exist "%~dp0watchx_bridge.ps1" goto setup
echo Extract the zip first: right-click WatchX-Bridge.zip, choose "Extract All...",
echo then double-click "Install (Windows).bat" in the folder that comes out.
goto done

:setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watchx_bridge.ps1" -Install
if errorlevel 1 (echo. & echo Something went wrong. See the error above.)

:done
echo.
pause
