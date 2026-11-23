@echo off
rem WatchX - Made by Rikerud
rem Double-click to install the alert bridge. It's copied to %LOCALAPPDATA%\WatchX, runs hidden in the
rem background and starts automatically every time you log in to Windows.
title WatchX - install
echo ======================================
echo   WatchX - phone alerts
echo   Made by Rikerud
echo ======================================
echo.

rem Opened straight from the zip, Windows copies only this file somewhere else: the bridge isn't next to it.
if exist "%~dp0watchx_bridge.ps1" goto install
echo Extract the zip first: right-click WatchX-Bridge.zip, choose "Extract All...",
echo then double-click "Install (Windows).bat" in the folder that comes out.
goto done

:install
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watchx_bridge.ps1" -Install
if errorlevel 1 goto failed
timeout /t 3 /nobreak >nul

echo.
echo The bridge is installed and running in the background (%LOCALAPPDATA%\WatchX).
echo It starts automatically when you log in to Windows.
echo.
echo --- Status ---
type "%LOCALAPPDATA%\WatchX-bridge.log" 2>nul
echo --------------
echo.
echo Next step in game: type /wx and press Settings, paste your
echo ntfy URL and/or Discord webhook and press "Save & reload".
echo.
choice /c YN /m "Send a test alert now"
if errorlevel 2 goto done
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\WatchX\watchx_bridge.ps1" -Test
goto done

:failed
echo.
echo Something went wrong during installation. See the error above.

:done
echo.
pause
