@echo off
rem WatchX - Made by Rikerud. Double-click to remove the alert bridge.
title WatchX - uninstall
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WatchX bridge.lnk" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*watchx_bridge.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
del /q "%LOCALAPPDATA%\WatchX\watchx_bridge.ps1" "%LOCALAPPDATA%\WatchX\watchx_decode.js" "%LOCALAPPDATA%\WatchX\wow_folder.txt" 2>nul
rem cloud sync: the chosen folder and what was last in step (the files in your cloud folder are left as they are)
del /q "%LOCALAPPDATA%\WatchX\cloud_folder.txt" "%LOCALAPPDATA%\WatchX\Cloud sync (Windows).bat" 2>nul
rmdir /s /q "%LOCALAPPDATA%\WatchX\sync" 2>nul
rem its work folder and log too (this file may be running from %LOCALAPPDATA%\WatchX: that folder goes only when empty)
rmdir /s /q "%TEMP%\watchx-bridge" 2>nul
del /q "%LOCALAPPDATA%\WatchX-bridge.log" "%LOCALAPPDATA%\WatchX-bridge.log.old" 2>nul
rmdir "%LOCALAPPDATA%\WatchX" 2>nul
echo The WatchX bridge has been stopped and removed. (The in-game addon is untouched.)
pause
