<img src="Media/logo.png" width="128" alt="WatchX logo">

# WatchX

**Made by Rikerud** – a PvP addon for World of Warcraft: Forever, with a rare scan like unitscan. `/wx`

> **Note:** WatchX is in active development. Not everything has been fully tested in game yet – the rare scan
> (unitscan-style) least of all – so bugs can happen. Please report them on
> [GitHub Issues](https://github.com/nintox/WatchX/issues).

## PvP

- **Enemies** – the enemy players around you, newest first: who has you targeted, who went into Stealth or
  Vanish (with a warning card), level, class, guild. Click a row to target.
- **Kill on sight** – players and whole guilds; they get a red card and a skull on their nameplate.
- **WANTED bounties** – put gold on a player's head, shared with your guild and friends who run WatchX. A
  reward for one kill or per kill (e.g. 1g a kill, up to 10). Kills are claimed by themselves, you pay by mail
  with one click, and it can be announced in guild chat.
- **Tell your party / guild** – a line in party or guild chat when you spot a stealther, a KOS or WANTED player
  (or every enemy): who, level, class, guild, reward and where. Once a minute per player; not twice when a friend's
  WatchX said it first.
- **Sounds** – pick your own for Stealth, Kill on sight, WANTED, a new enemy nearby and bounty news (or off).
- **Nameplate icons** – class, proven healers and KOS over enemy players.
- **History** – everyone you've met: kills, deaths, last seen, notes, guilds.
- **Avoid list** – people you don't want to play with: tooltip, group warning, a mark in chat.

## Alerts

- **Phone alerts** within a second, with a screenshot, through [ntfy](https://ntfy.sh) and/or Discord: an
  enemy player, a rare up, attacked while idle or AFK.
- **AFK logout warning** 5 minutes before, and a note when you've been logged out.

## Rare scan (like unitscan)

- A catalogue of 428 rares (from Questie's data), your own names, spawn alerts with a big target button,
  respawn timers and spots on the map. Prince Nazjak (Tidal Charm) is built in.

## Leveling and more

- An XP bar with rested and quest XP, XP boosts (rested, XP food, sleeping bag, campfire and tent), and what a camp gave you (Camp Benefits).
- An eating & drinking timer: time left, where your health / mana ends, a tick for each gain.
- Buff warnings before and when a buff runs out. Profiles for different setups – each character remembers its own.
- Export / import (`/wx export`): settings, profiles, the Enemies history, KOS and bounties of all your characters
  as one text to keep or move to another PC (your phone links only if you tick it).
- Rebuff icons: a pulsing icon for each of your own buffs you're missing (Ice Armor, Battle Shout …) – click it to cast
  it. Per class, with quick-add suggestions; in a row or a column.

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

## Credits

The rare catalogue (`Data/Rares.lua`) is generated from the [Questie](https://github.com/Questie/Questie) database for WoW Forever – thanks to everyone who builds it.
