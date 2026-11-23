WatchX – Made by Rikerud
========================

Rare mob spawn alerts – in game and on your phone within a second (ntfy and/or Discord),
with a screenshot. Prince Nazjak (Tidal Charm) is built in, and you can add your own mobs.
Also warns you 5 minutes before an AFK logout, and when you get logged out.

INSTALL
1. CurseForge app: search for WatchX. Or by hand: put the "WatchX" folder in
   World of Warcraft/_forever_/Interface/AddOns/
2. Start the game. The "How it works" guide opens by itself the first time.
   /wx opens the panel.

PHONE ALERTS (one-time setup)
1. Get the free "ntfy" app, tap + and pick a secret topic name (or use a Discord webhook).
2. In game: /wx > Settings. Paste ntfy.sh/<your-topic> and/or the Discord webhook
   and press "Save & reload".
3. Download WatchX-Bridge.zip from  https://github.com/nintox/WatchX/releases
   Unzip it anywhere and double-click:
     Mac:      Install (Mac).command
               (if your Mac says it can't be opened: System Settings > Privacy & Security,
                scroll down, "Open Anyway" – on macOS 14 and older: right-click > Open)
     Windows:  Install (Windows).bat
               (SmartScreen: "More info" > "Run anyway")
   It finds the game by itself (or asks you for the _forever_ folder), copies itself to
   Mac ~/Library/Application Support/WatchX or Windows %LOCALAPPDATA%\WatchX, runs invisibly
   in the background and starts by itself on startup. Addon updates don't touch it.
   It only uses what ships with Mac/Windows, so there is nothing else to install.
4. Press "Send test" in the panel.

HOW IT WORKS
WoW addons can't use the internet. When something happens, WatchX takes a screenshot with a
small black-and-white code block in the top-left corner; the bridge sees the new picture,
reads the code and sends the alert. Your own screenshots are never sent. WatchX's pictures
are kept in Screenshots/WatchX (the newest 30).

Remove the bridge: double-click "Uninstall" (in the zip, or in the folder it copied itself to).
Log: Mac ~/Library/Logs/WatchX-bridge.log, Windows %LOCALAPPDATA%\WatchX-bridge.log
In game: /wx log
