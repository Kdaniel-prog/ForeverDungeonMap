# ForeverDungeonMap

Dungeon maps and a Dungeon Journal for **WoW Forever** (`## Interface: 16001`).

![Dungeon map with the live view](../docs/screenshots/dungeon-map.png)
![Dungeon Journal: boss and loot](../docs/screenshots/journal-boss.png)
![Quest page](../docs/screenshots/journal-quest.png)
![Quest pins on a zone map](../docs/screenshots/quest-pins.png)

*(Screenshots are placeholders until the first release.)*

## Features

- **Dungeon map on M.** Inside a dungeon, the world map shows the dungeon's own map, with floors,
  zoom and drag, and round boss portraits. Hover a portrait for its loot; click it to open the
  boss in the journal.
- **Live view.** Whenever the world map is open, the real minimap is enlarged next to it, to the
  map window's height. It shows you, your group and other addons' minimap pins. You can drag it
  and zoom it with the mouse wheel. Inside instances the game hides all positions from addons,
  but the minimap is drawn by the client, so it still shows them. An option limits the live view
  to dungeons and raids. In combat the game does not let the minimap move: the window opens
  with a note and the minimap moves in when the fight ends. Works with EllesmereUI's minimap.
- **Right-click goes one map out:** dungeon > zone with the entrance > continent.
- **Dungeon entrance pins** on zone and continent maps. Click one to open that dungeon's map;
  Shift-click to open its journal page.
- **Quest pins:** where dungeon quests start (!) and are turned in (?). Click one for a waypoint
  with the on-screen arrow; Shift-click opens the quest in the journal.
- **Dungeon Journal:**
  - bosses with loot and levels, defeated bosses crossed out;
  - dungeon quests with their chains, start and turn-in NPCs, and rewards;
  - search, faction filter and a map tab;
  - Track and Share buttons; "Show on Map" sets a waypoint with the on-screen arrow (and a TomTom one, if installed).
- **The WoW Forever dungeons** have their level ranges, bosses, maps and loading-screen art, where
  the game has them.
- **Options:** Game Menu > Options > AddOns > ForeverDungeonMap.

## Slash commands

| Command | What it does |
|---|---|
| `/fdmap` | Opens the dungeon map (in combat: the journal's Map tab) |
| `/fdmap journal` (or `/fdmap j`) | Opens or closes the Dungeon Journal |
| `/fdmap config` | Opens the options panel |
| `/fdmap resetlive` | Puts the live view back next to the world map |
| `/fdmap resetkills` | Clears the defeated bosses of the current dungeon |
| `/fdmap help` | Lists the commands |
| `/fdmap debug [dungeon]` | Shows how complete the data is for a dungeon (the current one by default) |
| `/fdmap export` | Shows the quest-giver spots learned while playing as text you can copy, to send to the developers |

The Addon Compartment button opens the journal (left-click) or the dungeon map (right-click).

## Works with

- **Questie, TomTom, HereBeDragons, GatherMate:** their minimap pins stay visible in the live view.
- **Leatrix Plus:** your square minimap mask comes back after the live view closes.

## Data sources

Dungeons, bosses, loot and quests come from DungeonMaster and QuestieDB (both GPLv3). Boss
positions come from Blizzard's Encounter Journal data, and game facts from wago.tools. Every
source, with its author and licence, is listed in [THIRD_PARTY.md](THIRD_PARTY.md). Map art,
portraits and icons are not shipped: they are loaded from the game client's own files.

## Licence

GNU General Public License v3; see [LICENSE](LICENSE).
Copyright (C) 2026 kiszeldaniel.
