WatchX bridge – Made by Rikerud
===============================

Sends WatchX's alerts from the game to your phone (ntfy and/or Discord) within a second.
WoW addons can't use the internet, so this small helper does it for them.

INSTALL (once)
  Mac:      double-click  Install (Mac).command
            (if your Mac says it can't be opened: right-click > Open)
  Windows:  double-click  Install (Windows).bat
            (SmartScreen: "More info" > "Run anyway")

It finds World of Warcraft by itself (or asks you for the _forever_ folder), copies itself to
  Mac      ~/Library/Application Support/WatchX
  Windows  %LOCALAPPDATA%\WatchX
and runs invisibly in the background. It starts by itself when you log in to your computer.
After installing you can delete the zip and this folder.

Then in game: /wx > Settings, paste your ntfy link and/or Discord webhook, "Save & reload",
and press "Send test".

REMOVE
  Double-click "Uninstall" (here, or in the folder above).

LOG
  Mac ~/Library/Logs/WatchX-bridge.log  ·  Windows %LOCALAPPDATA%\WatchX-bridge.log
