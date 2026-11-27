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
- **Tell your party / guild / friends** – a line in party or guild chat, or a whisper to the friends you list, when
  you spot a stealther, a KOS or WANTED player (or every enemy): who, level, class, guild, reward and where (zone and
  coordinates). Each of the three has its own ticks. Once a minute per player; not twice when a friend's WatchX said
  it first. The Enemies window remembers where you last saw each player, and a new bounty says it in guild chat.
- **Sounds** – pick your own for Stealth, Kill on sight, WANTED, a new enemy nearby and bounty news (or off).
- **Nameplate icons** – class, proven healers and KOS over enemy players; the potions they drink (Free Action,
  Invulnerability, Swiftness …, add your own, choose which come first) while they last, and a warrior's stance
  (Battle, Defensive, Berserker) – in the Enemies list too. `/wx plates test` shows where they go.
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
- Mages: right-click a "Scroll: …" in your bags to cast Comprehend Scroll on it (one click, not the spell and then the
  scroll). Not in a fight, and not while you write a letter.
- Buff warnings before and when a buff runs out. Profiles for different setups – each character remembers its own.
- Export / import (`/wx export`): settings, profiles, the Enemies history, KOS and bounties of all your characters
  as one text to keep or move to another PC (your phone links only if you tick it).
- Rebuff icons: a pulsing icon for each of your own buffs you're missing (Ice Armor, Battle Shout …) – click it to cast
  it. Per class, with quick-add suggestions and a catalogue of every class's buffs (or type a spell ID / Wowhead link); in a row or a column. Unlocked, drag an icon to place it on its own – drop it next to another and they link; size and gap for all. Where they sit, row or column and size are each character's own (an export takes them all to another PC). "Either one" lines (Dampen Magic or Amplify Magic); quiet in cities, hidden in combat if you like. Rogues: every poison in your bags, each rank shown
  with the level it needs – right-click picks one, left-click puts it on.
- Sizes: drag a bar's bottom edge while unlocked, or click + / – in the settings (SIZE), or `/wx size 150` for all.
- +Combat / -Combat on screen (red / green) as a fight starts and ends, if you like (PvP > Enemies list).
- Settings in WatchX's own window (`/wx settings`, or Options > AddOns > WatchX): General, PvP (Enemies list,
  Nameplates, KOS & bounties, Avoid list) and Leveling pages. Alert profiles (Camping, Leveling, PvP …) for what you
  watch and how you're alerted; Export / import of everything at the top.

## Install

- **CurseForge app:** search for *WatchX*.
- **By hand:** download the addon zip from [Releases](https://github.com/nintox/WatchX/releases) and put the
  `WatchX` folder in `World of Warcraft/_forever_/Interface/AddOns/`.

## Phone alerts (optional)

WoW addons can't use the internet, so a small helper (the *bridge*) sends the alerts.
Download **WatchX-Bridge.zip** from [Releases](https://github.com/nintox/WatchX/releases), unzip it and
double-click `Install (Mac).command` or `Install (Windows).bat`. It finds the game by itself, copies itself out
of the game folder (so addon updates don't touch it) and starts with your computer. Nothing else to install.

Then in game: `/wx` → paste your ntfy link and/or Discord webhook → *Save & reload* → *Send test*.

## Credits

The rare catalogue (`Data/Rares.lua`) is generated from the [Questie](https://github.com/Questie/Questie) database for WoW Forever – thanks to everyone who builds it.
