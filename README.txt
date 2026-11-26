WatchX – Made by Rikerud
========================

A PvP addon for World of Warcraft: Forever, with a rare scan like unitscan. /wx

NOTE: WatchX is in active development. Not everything has been fully tested in game yet
(the rare scan least of all), so bugs can happen. Report them at
https://github.com/nintox/WatchX/issues

PVP
- Enemies: the enemy players around you – who has you targeted, who went into Stealth
  (with a warning card). Click a row to target.
- Kill on sight (players and guilds), class / healer / KOS icons on nameplates.
- WANTED bounties shared with your guild and friends: a reward for one kill or per kill,
  claimed by themselves, paid by mail with one click, announced in guild chat if you like.
- Tell your party / guild: a chat line when you spot a stealther, KOS or WANTED player (or every enemy).
- Sounds of your choice for Stealth, Kill on sight, WANTED, a new enemy nearby and bounty news.
- History of everyone you've met, and an avoid list.

ALERTS
- Phone alerts within a second (ntfy and/or Discord, with a screenshot): an enemy player,
  a rare up, attacked while idle. A warning 5 minutes before an AFK logout.

RARE SCAN (like unitscan)
- 428 rares to pick from (from Questie's data), your own names, respawn timers, map spots.

LEVELING
- XP bar, XP boosts (rested, XP food, sleeping bag, campfire, Camp Benefits), eating & drinking timer,
  buff warnings, rebuff icons (click to cast the buff you're missing). Profiles (one per character),
  export / import of everything (/wx export).
- Sizes: + / - in the settings (SIZE), or /wx size 150 for every bar at once.
- Settings: WatchX's own window (/wx settings), with pages for General, PvP and Leveling.

INSTALL
1. CurseForge app: search for WatchX. Or by hand: put the "WatchX" folder in
   World of Warcraft/_forever_/Interface/AddOns/
2. Start the game. The "How it works" guide opens by itself the first time.
   /wx opens the panel.

PHONE ALERTS (one-time setup)
1. Get the free "ntfy" app, tap + and pick a secret topic name (or use a Discord webhook).
2. In game: /wx (the settings). Paste ntfy.sh/<your-topic> and/or the Discord webhook
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
