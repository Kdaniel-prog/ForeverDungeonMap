# Third-party data

ForeverDungeonMap is licensed under the GNU General Public License v3 (see `LICENSE`).
It uses data from the following sources:

| Data | Source | Author | License |
|---|---|---|---|
| Dungeon list, level ranges, entrance coordinates (`Data/Dungeons.lua`) | DungeonMaster 1.6.3 | MalkDev | GPLv3 |
| Bosses, boss loot, dungeon quests, quest chains and factions (`Data/Generated.lua`, made by `tools/import_dungeonmaster.py`) | DungeonMaster 1.6.3 (`Data.lua`, `Curated.lua`) | MalkDev | GPLv3 |
| Quest start / turn-in NPCs and locations, required levels (`Data/QuestInfo.lua`, made by `tools/import_questie.py`) | [QuestieDB](https://github.com/Questie/QuestieDB) (Forever data) | Questie contributors | GPLv3 |
| Boss levels (`Data/BossLevels.lua`, made by `tools/import_boss_levels.py`) | [QuestieDB](https://github.com/Questie/QuestieDB) `foreverNpcDB.lua` | Questie contributors | GPLv3 |
| WoW Forever dungeon quests (`Data/ForeverQuests.lua`, made by `tools/import_forever_quests.py` from `tools/forever_quests.json`): NPC spots | [QuestieDB](https://github.com/Questie/QuestieDB) `foreverNpcDB.lua` | Questie contributors | GPLv3 |
| WoW Forever dungeon quests (same file): who gives / takes each quest, chains, where the quest items lie (plain game facts only, re-written) | [Wowhead WoW Forever](https://www.wowhead.com/forever) quest pages and public fan guides listed in `tools/forever_quests.json` | - | facts |
| WoW Forever dungeons (`Data/Forever.lua`, made by `tools/import_forever.py`): level ranges of the released dungeons, entrances, boss NPC and display IDs, Forever quest givers | DungeonMaster (`Data.lua`, `Curated.lua`) | MalkDev | GPLv3 |
| `Data/Forever.lua`: entrances of City of Dalaran and Excavation Site: Wetlands | [Questie / QuestieDB](https://github.com/Questie/Questie) (`Database/Zones/data/dungeons.lua`) | Questie contributors | GPLv3 |
| `Data/Forever.lua`: dungeon IDs, names, players, boss encounters, map art paths, loading screens, map bounds | Blizzard client tables of WoW Forever 1.60.1.70938 (Map, MapDifficulty, ContentTuning, DungeonEncounter, AreaTable, UiMapAssignment, UiMapXMapArt, WorldMapOverlay, LoadingScreens) via [wago.tools](https://wago.tools/db2) | Blizzard Entertainment | game data (facts only) |
| `Data/Forever.lua`: boss display IDs, boss levels and level ranges of dungeons that are not out yet (plain game facts, listed one by one in the file header) | [foreverchanges.pro](https://foreverchanges.pro/dungeons), [wowf.io](https://wowf.io/en/dungeons) | site authors | game facts |
| `Data/Forever.lua` map floors of City of Dalaran, Excavation Site: Wetlands, Ruins of Lordaeron and The Hall of Thanes (made by `tools/make_forever_maps.py`): FileDataIDs of each dungeon map's own minimap tiles (from its WDT file) and the retail world map tiles the client ships for Dalaran (retail UiMap 125 "Dalaran" and 126 "The Underbelly") | WoW Forever 1.60.1.70938 client files (Map table, WDT files, file listing) via [wago.tools](https://wago.tools) | Blizzard Entertainment | nothing shipped: only FileDataIDs / paths |
| `Data/Forever.lua` boss and entrance spots of those four dungeons (`bossPositions`, `entranceOnArt`; approximate) | Pin positions of [foreverchanges.pro](https://foreverchanges.pro/dungeons) dungeon pages (whose maps are drawn by Santiago Reyes), carried onto the client art through hand-measured landmarks. Only the positions (facts) are used; the fan maps are not shipped or read | site authors | game facts |
| Quest experience (`Data/QuestXP.lua`, made by `tools/import_quest_xp.py`) | [QuestieDB](https://github.com/Questie/QuestieDB) `support/Forever/QuestXP/xpDB-classic.lua` | Questie contributors | GPLv3 |
| Texture references (`Data/Art.lua`, made by `tools/make_art.py`): Encounter Journal art, loading screens, LFG icons by FileDataID | file listing of the WoW Forever client via [wago.tools](https://wago.tools/files) | Blizzard Entertainment | nothing shipped: only FileDataIDs |
| Spawn points inside dungeons: bosses the Encounter Journal lacks (`Data/BossPositions.lua`), portal arrival points and quest givers/enders (`Data/DungeonSpots.lua`); made by `tools/import_map_spots.py` | [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (`creature`, `gameobject`, `areatrigger_teleport`, quest relation tables; `creature_template` display IDs for `CREATURE_DISPLAY`) | CMaNGOS / classic-db contributors | GPLv3 |
| `Data/DungeonSpots.lua` (`ENTRANCE_ON_ZONE`): dungeon entrances (cave mouths) on the zone maps | [Questie](https://github.com/Questie/Questie) (`Database/Zones/data/dungeons.lua`) | Questie contributors | GPLv3 |
| Boss spots, dungeon floors and how world positions land on the floor art, subzone names per floor (`Data/BossPositions.lua`, `Data/DungeonSpots.lua`, `Data/FloorAreas.lua`; made by `tools/import_map_spots.py`) | Blizzard client tables and files (JournalEncounter, UiMapAssignment, UiMap, WMOAreaTable, AreaTable, AreaTrigger, WDT/WMO files, dungeon map art tiles to check spots lie on the drawn floor) of retail and WoW Forever 1.60.1 via [wago.tools](https://wago.tools/db2) | Blizzard Entertainment | game data (facts only) |

Boss positions on the dungeon maps come first from Blizzard's own Encounter Journal data of the retail
client (`JournalEncounter`); bosses it does not cover are placed at their CMaNGOS classic-db spawn point.

**ForeverDungeonJournal** (by Exehn) is not used: nothing of it is shipped, and since 0.7.1 nothing
of it is read at runtime either; all data comes from the sources above. The journal's layout
follows FDJ's; the code and the visual skin are our own.

Dungeon map artwork, boss portraits, item and dungeon icons, Encounter Journal pictures and loading
screens are not shipped with this addon: `Data/Art.lua` only stores FileDataIDs and the textures are
loaded from the game client's own files. The small icons in `Media/` are drawn by `tools/make_icons.py`.
