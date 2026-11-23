# WatchX

**Made by Rikerud** – a World of Warcraft: Forever addon.

Rare mob spawn alerts (Prince Nazjak / Tidal Charm built in) with respawn timers, instant phone alerts via
[ntfy](https://ntfy.sh) and Discord, an AFK logout warning, attack alerts, a Nearby enemies list with stealth
warnings, class/healer/KOS nameplate icons, XP boosts until level 60, buff warnings, and profiles. `/wx`

## Install

- **CurseForge app:** search for *WatchX*.
- **By hand:** download the addon zip from [Releases](https://github.com/nintox/WatchX/releases) and put the
  `WatchX` folder in `World of Warcraft/_forever_/Interface/AddOns/`.

## Phone alerts (optional)

WoW addons can't use the internet, so a small helper (the *bridge*) sends the alerts.
Download **WatchX-Bridge.zip** from [Releases](https://github.com/nintox/WatchX/releases), unzip it and
double-click `Install (Mac).command` or `Install (Windows).bat`. It finds the game by itself, copies itself out
of the game folder (so addon updates don't touch it) and starts with your computer. Nothing else to install.

Then in game: `/wx` → Settings → paste your ntfy link and/or Discord webhook → *Save & reload* → *Send test*.
