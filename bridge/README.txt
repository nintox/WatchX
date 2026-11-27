WatchX bridge – Made by Rikerud
===============================

WoW addons can't use the internet, so this small helper does it for them:
  1) Phone alerts – WatchX's alerts on your phone (ntfy and/or Discord) within a second
  2) Cloud sync   – the same WatchX settings on all your computers (iCloud Drive, Dropbox, OneDrive, Google Drive)
  3) Both

SET UP (one script – it asks which: 1, 2, 3, or 4 to remove it)
  Mac:      double-click  Install (Mac).command
            (if your Mac says it can't be opened: System Settings > Privacy & Security,
             scroll down, "Open Anyway" – on macOS 14 and older: right-click > Open)
  Windows:  extract the zip first (right-click > Extract All), then double-click  Install (Windows).bat
            (SmartScreen: "More info" > "Run anyway")

It finds World of Warcraft by itself (or asks you for the _forever_ folder), copies itself to
  Mac      ~/Library/Application Support/WatchX
  Windows  %LOCALAPPDATA%\WatchX
and runs invisibly in the background. It starts by itself when you log in to your computer.
After setting it up you can delete the zip and this folder. To change your choice or remove it, run
"Install" again (it's in the folder above too).

PHONE ALERTS: in game /wx > Settings, paste your ntfy link and/or Discord webhook, "Save & reload",
and press "Send test".

CLOUD SYNC: pick a folder your cloud keeps in step – a WatchX folder is made in it. Do the same on the
other computer, with the same folder. Your settings (all of them: profiles, layouts, enemies, KOS) are sent up
when you log out and fetched before you play. Play on one computer at a time. Before a fetch yours is kept as
WatchX.lua.before-sync. Mac: if it says macOS won't let the bridge use the folder, pick one in your home folder
(e.g. ~/Dropbox).

LOG
  Mac ~/Library/Logs/WatchX-bridge.log  ·  Windows %LOCALAPPDATA%\WatchX-bridge.log
