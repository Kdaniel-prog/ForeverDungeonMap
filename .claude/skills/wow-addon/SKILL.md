---
name: wow-addon
description: Facts and traps for building the ForeverDungeonMap addon on the WoW Forever client (interface 16001, modern Midnight-era engine with classic content) - missing APIs, taint rules, map pins, data pipeline, the headless harness and how to install/test. Load before touching any addon code, data generator or test in this repo, together with the clean-code skill.
---
# WoW Forever addon engineering (ForeverDungeonMap)

## The client
- Product `wowf`, install `B:\World of Warcraft\_forever_`, addons in `Interface\AddOns`.
- `## Interface: 16001`. Engine is the modern retail one (Midnight/12.x): retail map canvas,
  `C_*` namespaces, Settings API, Addon Compartment, secret values in combat log.
- Classic dungeon map art exists (`Interface\WorldMap\<Name>\<Name><floor>_1..12`, 4x3 tiles of
  256px, visible 1002x668) but there are NO uiMap records for dungeons: positions inside
  instances are nil for everyone, `GetPlayerFacing()` is nil, compass rotation is forbidden.
  The only live position view is the real Minimap (drawn by the client).
- New WoW Forever dungeons have no UiMap, but the client ships their own minimap textures (WDT tiles,
  drawn as `pieces` floors) and City of Dalaran reuses retail Dalaran tiles (tools/make_forever_maps.py).

## APIs: use guarded aliases
- `GetItemInfo` does NOT exist (proved by `Logs\General.log`). Same for `GetItemInfoInstant`,
  `GetItemQualityColor`: always `C_Item.*` through a local alias at the top of the file.
- Fonts like `GameFontNormalHuge`, `QuestTitleFont` exist; resolve through `ns.Font(role)`.
- Never register `COMBAT_LOG_EVENT_UNFILTERED`: this client forbids the combat log to addons and
  raises the "blocked from an action" popup even inside `pcall` (found 2026-11-13; it was the
  long-standing popup). Kills come from ENCOUNTER_END / BOSS_KILL, dead targets and loot sources.
  Register other unsure events with `pcall`. The blocked recorder sits at the top of Core.lua so
  blocks while files load are caught (`ForeverDungeonMapDB.blocked`).

## Taint (the "blocked from an action only available to the Blizzard UI" popup)
- Never call protected functions; never move/hide protected or Edit Mode frames in combat
  (`InCombatLockdown()` -> defer to `PLAYER_REGEN_ENABLED`).
- Do not call `WorldMapFrame:SetMapID` ourselves when avoidable: use `C_Map.OpenWorldMap(id)`
  (Questie does the same), never in combat. Same for `ToggleWorldMap`/`NavigateToParentMap`.
- Map pins: mixin no-ops `SetPassThroughButtons`, `SetPropagateMouseClicks`,
  `CheckMouseButtonPassthrough`; the XML template must NOT have OnEnter/OnLeave/OnMouseUp
  scripts (`Blizzard_MapCanvas.lua:309 assertion failed`) - the canvas calls the mixin's
  `OnMouseEnter/OnMouseLeave/OnMouseUp` itself.
- Lua errors are in `Logs\General.log` (and on screen with `/console scriptErrors 1`).

## Data pipeline (tools/, all `python -I`, sources are GPLv3 or Blizzard data)
| file | generator | source |
|---|---|---|
| Data/Generated.lua | import_dungeonmaster.py | DungeonMaster addon (GPLv3) |
| Data/QuestInfo.lua | import_questie.py | QuestieDB (GPLv3) |
| Data/BossLevels.lua | import_boss_levels.py | QuestieDB foreverNpcDB |
| Data/BossPositions.lua, DungeonSpots.lua, FloorAreas.lua | import_map_spots.py | Blizzard JournalEncounter/UiMapAssignment/WMO files (wago.tools) + CMaNGOS classic-db spawns (GPLv3) |
| Data/Art.lua | make_art.py | wago.tools file list for build 1.60.1.70938 (FileDataIDs) |
| Data/Forever.lua | import_forever.py | DungeonMaster, Questie, wago.tools tables, fan sites |
- ForeverDungeonJournal (FDJ) has NO licence: never copy its code, data or Media, and (user decision,
  0.7.1) never read it at runtime either: every spot, map and reward comes from our own shipped data,
  so every character sees the same thing. APR is "All Rights
  Reserved": not used.
- Every source is listed in `ForeverDungeonMap/THIRD_PARTY.md`.

## Test before handing back
- Syntax: luaparser check script (scratchpad `check.py`) on every changed .lua.
- Headless: `python -I tools/harness/run.py` (default profile = this client) and `--combat`;
  exit code 0 = no Lua errors, no failed checks, no protected-call violations. Add scenario
  checks for every new feature.
- Install = copy `ForeverDungeonMap/` into the AddOns folder (the lead does it). New files in
  the .toc need a full client restart, not just `/reload`.

## UI rules
- Layout/UX mirrors FDJ (docs/ui-spec.md); the skin is our own "Gilded Codex" (Theme.lua).
- Less text, more icons: done = tick icon, missing = cross icon, never the words "done"/"not done".
- Hover always shows the gold border (`W.Hoverable`), selected keeps it, repaints keep scroll.
