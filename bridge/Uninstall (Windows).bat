@echo off
rem WatchX - Made by Rikerud. Double-click to remove the alert bridge.
title WatchX - uninstall
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WatchX bridge.lnk" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*watchx_bridge.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
del /q "%LOCALAPPDATA%\WatchX\watchx_bridge.ps1" "%LOCALAPPDATA%\WatchX\watchx_decode.js" "%LOCALAPPDATA%\WatchX\wow_folder.txt" 2>nul
echo The WatchX bridge has been stopped and removed. (The in-game addon is untouched.)
pause
