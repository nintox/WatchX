WatchX bridge – Made by Rikerud
===============================

Sends WatchX's alerts from the game to your phone (ntfy and/or Discord) within a second.
WoW addons can't use the internet, so this small helper does it for them.

INSTALL (once)
  Mac:      double-click  Install (Mac).command
            (if your Mac says it can't be opened: System Settings > Privacy & Security,
             scroll down, "Open Anyway" – on macOS 14 and older: right-click > Open)
  Windows:  extract the zip first (right-click > Extract All), then double-click  Install (Windows).bat
            (SmartScreen: "More info" > "Run anyway")

It finds World of Warcraft by itself (or asks you for the _forever_ folder), copies itself to
  Mac      ~/Library/Application Support/WatchX
  Windows  %LOCALAPPDATA%\WatchX
and runs invisibly in the background. It starts by itself when you log in to your computer.
After installing you can delete the zip and this folder.

Then in game: /wx > Settings, paste your ntfy link and/or Discord webhook, "Save & reload",
and press "Send test".

CLOUD SYNC (optional – several computers)
  Double-click  Cloud sync (Mac).command  /  Cloud sync (Windows).bat  and pick a folder your cloud keeps in step
  (iCloud Drive, Dropbox, OneDrive, Google Drive). Do the same on the other computer, with the same folder.
  WatchX's settings (all of them: profiles, layouts, enemies, KOS) then follow you: sent up when you log out,
  fetched before you play. Play on one computer at a time. Before a fetch yours is kept as WatchX.lua.before-sync.
  Mac: if the log says macOS won't let the bridge use the folder, pick one in your home folder (e.g. ~/Dropbox).

REMOVE
  Double-click "Uninstall" (here, or in the folder above).

LOG
  Mac ~/Library/Logs/WatchX-bridge.log  ·  Windows %LOCALAPPDATA%\WatchX-bridge.log
