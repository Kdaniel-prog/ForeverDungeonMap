# Changelog

All notable changes to ForeverDungeonMap. Versions follow the `## Version` of the .toc;
releases are tagged `vX.Y.Z`.

## 0.8.0 (2026-11-27)

### Changed
- Live view: inside a dungeon it stays open on its own, no world map (M) needed: bigger, at the
  top right of the screen until you drag it elsewhere (the spot is kept), with zoom in / zoom out
  buttons in its bottom-left corner. Closed, it comes back in the next dungeon. Option: "Live view
  on its own in dungeons" (off: the old way, next to the world map).
- The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and The Shaper's Terrace no
  longer say "Coming soon": they are out (their bosses are seen dropping loot).

### Fixed
- Dungeon entrance and quest pins on the zone maps were drawn under Blizzard's own quest hub ("...")
  and point-of-interest pins and could not be seen (The Drowned City under the Vile Reef): they are on top now.
- Boss portraits learned in play: every creature is loaded on a fresh model frame, and the client's
  stand-in model (the same ID for several bosses) is never kept; wrong ones learned before are dropped.

### Added
- Quests of the new WoW Forever dungeons: The Drowned City (11), Krol'dok Stronghold, Alcaz Prison,
  Blackmaw Hold and The Shaper's Terrace, with their chains (e.g. The Vile Reef before The Drowned
  City) and the quest givers on the world map where their spot is known.
- New bosses: Gill, "Pyromancer" Braxton and Umbra (rare elites, The Drowned City), Bossman Toof
  (Krol'dok Stronghold), Moontouched Wanderer (rare elite, Blackmaw Hold), with their drops.
  The Drowned City has its entrance in Stranglethorn Vale.
- The Drowned City map: every boss and rare in its place (from the Icy Veins map), the entrance,
  and the four Tablets of I'lalai while "The Drowned City" / "Take Two With Water" is in the log.
- Alcaz Prison, Krol'dok Stronghold and The Shaper's Terrace: every boss and rare on its spot of the
  dungeon map, and the entrance (forg.gg's floor maps fitted onto ours). Blackmaw Hold: Impaan,
  Bonesnout and the entrance exact; Withermaw and the bosses of its deep caves (Unbound Spirit,
  Bloodmane, Blackmaw Behemoth, Varrox) roughly, their tooltip says so.
- Quest givers no source places get a rough spot at the place they stand at (Farholde Keep, Rog'mar,
  Ursolan, Brackenwall Village, Legashi Stronghold), shown with "~"; Alcaz Prison's givers stand inside.
- New quests: Shaw Needs To Know, State Secrets (Alliance and Horde); The Secret Prison, The Man in the
  Iron Chains, Krol'dok Moulding, Lingering Essence and Beneath Nordrassil now count as dungeon quests;
  quest rewards, more quest giver spots (Lorekeeper Nok, Commander Truesong, Curator Thorius...).
- Quest pages of the new dungeons show the objective and where the quest items drop.
- Boss pages of the new bosses show the creature in 3D where the client has no Encounter Journal
  picture of it.
- Dungeon entrances: Alcaz Prison (Alcaz Island) and Krol'dok Stronghold exact now, The Shaper's
  Terrace approximate (Un'Goro Crater); quest givers of Krol'dok placed (Icy Veins).
- Portraits for bosses no data source has a picture for: the addon loads the creature in game and
  keeps its display ID (also in /fdmap export).
- Recap: every recorded run in a list on the left; a click shows the run in full on the right:
  start and end time, time inside, experience (per hour), money, deaths, the bosses with how far
  into the run each fell (the ones not defeated greyed), quests (click: their journal page), the
  group with class icons, and the loot.

## 0.7.3 (2026-11-17)

### Changed
- Elite bosses on the dungeon maps have a frame around their portrait instead of the dragon icon
  on top of it: gold for elites and bosses, silver for rare elites, grey once the boss is dead.
  Nothing covers the portrait any more.
- Bosses whose place on the map no source knows yet (the WoW Forever dungeons that are not out:
  Alcaz Prison, The Drowned City, Blackmaw Hold, The Shaper's Terrace, Krol'dok Stronghold) are
  no longer missing from the map: they stand in a row at the bottom of it, in boss order, and
  their tooltip says the spot is not known yet.
- The bosses of those dungeons have their loot (from wowf.io; King Op's is not known yet) and
  their creature IDs, and King Op is marked as a rare elite. They stay "Coming soon" until they
  are out.

### Fixed
- Event bosses that are summoned or fly in had no pin on the dungeon map. They now stand where
  they appear: Sunken Temple's Atal'alarion, Weaver and Dreamscythe; Razorfen Downs' Tuten'kash
  and Plaguemaw the Rotting; Blackfathom Deeps' Baron Aquanis; Lower Blackrock Spire's Warchief
  Rend Blackhand and Lord Valthalak; Blackrock Depths' Vault; Scholomance's Kirtonos, Kormok,
  Ras Frostwhisper and Darkmaster Gandling; Stratholme's Ezra Grimm; Dire Maul's Lord Hel'nurath.

## 0.7.2 (2026-11-17)

### Changed
- The live view opens with the world map (M) everywhere, not only inside dungeons. The new option
  "Live view only inside dungeons" limits it to dungeons and raids again; "Live view next to the
  map" still switches it off completely.
- Pressing M in combat opens the live view window at once, with a note in it: the game does not
  let addons move the minimap in combat, so the minimap moves in when the fight ends.
- With the minimap inside, the live view window is dragged by its title bar or its footer.
- Dungeon Journal cards: the favourite star is a round gold-ringed button (like the entrance
  button). It stays on favourites and shows on the other cards only under the mouse. Favourites
  get a gold border and come first in the list, right after the dungeon you are in.
- Hiding dungeons: in hide mode every card has a round tick (shown) or cross (hidden) in its
  corner, a hidden card is veiled with "Hidden" across it, the whole card toggles, and a line at
  the bottom says what to do. The big check boxes are gone.
- Every boss on the dungeon maps carries the elite dragon: gold for elites and bosses, silver
  for rare elites. It turns grey with the boss.

### Fixed
- Inside a dungeon the live view sometimes did not come up. It was tied to the dungeon's map
  view, so it was missing whenever that view was closed, switched off, or the game had not told
  the addon about the dungeon yet. It now follows the world map itself, and the addon checks
  where you are every time the map opens.
- After "show on the map" was used in combat, the next M opened the plain world map instead of
  the dungeon's map.
- With EllesmereUI's minimap the live view stayed on the minimap's own spot and only grew there.
  It now moves into the live view window, keeps its place and size while the map is open, and
  goes back to EllesmereUI's spot, size and shape afterwards.
- With EllesmereUI's minimap the live view was a dark grey patch: EllesmereUI locks the layer the
  minimap is drawn on, so the minimap stayed under the live view window's dark background. The
  live view now takes that lock off while it moves the minimap and puts it back. The window's
  background is also built around the minimap's place, and nothing of the window is drawn in
  that place while the minimap is there, so no addon's minimap can end up under it again.
- With EllesmereUI's minimap the live view forgot its zoom (EllesmereUI's own wheel zoom is the
  one that runs there), and a minimap hidden by EllesmereUI's visibility rules stayed hidden
  inside the live view.
- The live view window no longer tries to move when it is dragged in combat with the minimap
  inside: the game blocks that move.

## 0.7.1 (2026-11-14)

### Changed
- The journal's quest list starts with only your faction's quests; the crest toggles above the
  list add the other faction. The "Other faction's quests in the journal" option is gone.
- WoW Forever dungeon quests look like the classic ones: a quest item a boss drops is in that
  boss's loot (The Baron: Abominable Head, Relic Guardian: Titan Relic), and quest givers inside
  the dungeon (Captain Truman, Rexxie Copperclutch, ...) are "!" / "?" spots on the dungeon map.
- Quest experience comes from the game (WoW Forever's values): the addon asks the game to load a
  quest's data when it is not cached yet. Reward items the game shows on the quest frame are
  remembered and shown instead of the shipped list.
- "Report a bug" (blue bug button at the journal's bottom right, or `/fdmap bug`): write what went
  wrong, the addon adds the details a fix needs (read-only), "Copy everything" selects both for
  Ctrl+C, and the GitHub issues link is right there to paste it.
- Releases are automatic: GitHub tags the version from this changelog and uploads it to CurseForge.
- A quest chain is one row in the journal's quest list: its first step in that dungeon, with the
  chain icon; the other steps (also the ones after the dungeon quest) open under it. The row shows
  the most urgent state of its steps. The quest page lists the whole chain ("Quest chain").
- Bigger faction crests: the list's Alliance / Horde toggles, the quest header, and the quest rows
  (centred on the row).
- WoW Forever dungeon quests checked one by one (new `tools/forever_quests.json` ->
  `Data/ForeverQuests.lua`): where each is picked up and turned in, whole chains (e.g. the five
  steps of Unending Torment), NPC spots from QuestieDB's Forever NPC table. Fixes, among others:
  The Wrath of Rath'mael (Deathguard Kristof), The New Plague (Theodore Griffs), Highland Hides
  (James Halloran), Horrors in the Highland (Rethiel the Greenwarden), Old Ironforge Incursion
  (Earthseer Farsen -> Magni).
- Quests whose starter lies at random spots (Crest of Lordaeron) list every place on the quest
  page; in-dungeon quest givers get a short "where" note.
- "Show on Map" and a click on a quest pin set the game's own waypoint, with the on-screen
  arrow to the quest giver (and a TomTom waypoint, if TomTom is installed). Shift-click on a
  quest pin opens the quest in the journal.
- Boss portraits (map pins, boss list, boss page) and dungeon icons have no ring any more: the
  ring art had a dark fill that hid the portrait. Only the portrait, and a cross when the boss is
  dead. Bosses without a portrait (rares, books) get a gold-framed "?" with an elite dragon
  (silver for rare elites).
- If Blizzard blocks one of the addon's calls, the call is saved (and shown by `/fdmap export`),
  so the cause can be found without a taint log.

- After the world map's nav bar crumbs, on every map: "Dungeons" (the journal with every dungeon),
  and the map and quests of a dungeon: the one you are in, the one shown last, or the one whose
  entrance is on the map shown.
- The live view's footer shows the area you are in, and the floor ("Floor 2/3") when the data
  ties that area to a floor.

- Everything comes from the addon's own data: ForeverDungeonJournal is no longer read at runtime,
  so every character sees the same pins whether or not that addon is enabled.
- Smaller quest pins on the world map.
- Boss portraits and quest markers on the dungeon map are pushed apart so none hides another.
- Dungeon map header: room for Blizzard's map buttons on the left, full-size Bosses and Quests
  tabs, and a "Dungeons" button that opens the Dungeon Journal with every dungeon's card.
- Right-click on a dungeon map goes to the entrance's zone, never straight to the continent.
- With Questie showing dungeon quests, our world-map quest pins step aside (same NPCs, one icon).
- Maps for the WoW Forever dungeons from the game's own files: their minimap textures (Ruins of
  Lordaeron, Excavation Site, Hall of Thanes, the coming-soon ones) and retail Dalaran's tiles
  (City of Dalaran), with boss and entrance spots.
- Quest givers and turn-ins inside a dungeon ("!" / "?") on the dungeon map, and every portal
  of a dungeon (wings, back doors) marked as an entrance.
- Bosses and rares the Encounter Journal has no spot for (Razorfen Kraul, Scarlet Monastery,
  Scholomance, Shadowfang Keep, the Stockade and more) are on the dungeon map now, at their
  spawn point from the CMaNGOS classic database (GPLv3). New generated data for entrance spots,
  dungeon entrances on zone maps, quest givers inside dungeons and the floor of each subzone (`tools/import_map_spots.py`).
- Rares without a portrait (Deviate Faerie Dragon, Razorfen Spearhide, ...) get their creature
  display from the CMaNGOS database; a spawn the dungeon art does not draw is moved onto the
  nearest drawn floor.
- The dungeon map's level picker is a dropdown ("Level 1", "Level 2", or the wing's name); the
  map follows you to the floor of the area you walk into when the data knows it.

### Fixed
- The Dungeon Journal's search box can be clicked into again (the window's drag strip covered it).
- Zul'Farrak's map shows: its tiles have no floor number in their file names.
- The "ForeverDungeonMap has been blocked from an action" popup: the addon no longer registers the
  combat log, which this client forbids to addons. Boss kills come from encounter ends, a boss's
  corpse as target, or its loot.
- The parchment of the quest page now fills the whole page.

## 0.6.0 (2026-11-13)

### New
- "Gilded Codex" look for the Dungeon Journal and the dungeon map: one palette, gold borders on
  hover and selection, parchment quest pages, round boss portraits (docs/ui-spec.md).
- The Dungeon Journal has a home page, a search box, a faction filter, a Map tab, inline quest
  chains, and Track and Share buttons on quests.
- Quest pins on zone and continent maps show where dungeon quests start (!) and are turned in (?).
  The tooltip lists every quest of that NPC; a click opens the quest in the journal.
- Experience and money reward pills on quest pages. The game's own values are used when it has
  them, otherwise QuestieDB's quest XP table scaled to your level (marked approximate).
- Options panel (Game Menu > Options > AddOns > ForeverDungeonMap) with these switches: quest pins,
  live view, dungeon map on M, boss icon size, and the other faction's quests.
- When a quest giver offers or takes back a quest, the addon remembers where that NPC stands.
  This fills gaps in the shipped data for new WoW Forever quests. `/fdmap export` shows the
  learned spots so you can send them in; `/fdmap debug` shows how complete each dungeon's data is.
- `/fdmap config` and `/fdmap help`.
- Maps and data for the WoW Forever dungeons that have them (e.g. Hall of Thanes on the Old
  Ironforge tiles), and their loading screens as journal art.

### Changed
- The live view no longer hides or moves any Blizzard frame. The minimap cluster is only made
  invisible, and nothing is moved in combat: the change waits until the fight ends. The minimap
  comes back exactly as it was, including another addon's square mask. Entering Edit Mode gives
  it back too.
- World map changes go through `C_Map.OpenWorldMap` and wait for the end of combat.

### Fixed
- The "ForeverDungeonMap has been blocked from an action only available to the Blizzard UI"
  popup (docs/taint-report.md).
- `GetItemInfo` errors: the client only has `C_Item`.
- `Blizzard_MapCanvas.lua:309 assertion failed!`: the pin templates no longer have OnEnter or OnLeave.

## 0.5.0 (2026-11-13)

### New
- The Dungeon Journal was rewritten:
  - colour themes and rows of fixed height;
  - a parchment quest page with "Starts at", "Turn in", the quest chain and a reward grid;
  - a faction filter, a search box, and TomTom waypoints.
- Quest givers and turn-in NPCs from QuestieDB (432 quests), and boss levels from QuestieDB.
- Encounter Journal cards, lore, loading screens and 148 boss pictures, all taken from the game
  client's own files by FileDataID.

### Fixed
- The map pins no longer call `SetPassThroughButtons` (a taint source).
- The live view stays above the world map (DIALOG strata) and is safe in combat.

## 0.4.0

Internal build; its changes shipped with 0.5.0.

## 0.3.0 (2026-11-13)

### New
- Boss positions on the dungeon maps from Blizzard's Encounter Journal data (112 bosses in 15
  dungeons).
- When ForeverDungeonJournal is installed, its boss and entrance spots and its maps of the new
  WoW Forever dungeons are read at runtime. Nothing of it is shipped.
- Side panel: a boss shows its loot and related quests; a quest shows its objective, starting
  NPC, chain and rewards.
- Defeated bosses are crossed out and stay crossed out after `/reload`.

### Changed
- The live view has no +/- buttons; its height follows the world map window.

## 0.2.0

### New
- Pressing M inside a dungeon opens the dungeon's own map in the world map window, with floors,
  zoom, drag, and boss portraits whose tooltip shows the loot.
- Right-click goes one map out (dungeon > zone > continent); dungeon entrance pins on zone and
  continent maps.
- The live view: the real minimap, enlarged next to the dungeon map. It shows you, your group,
  and other addons' minimap pins.
- Dungeons, bosses, loot and quests imported from DungeonMaster (GPLv3).

## 0.1.0

### New
- `ForeverDungeonMapProbe`, a developer probe that showed what the client allows inside instances:
  - no positions for addons (`UnitPosition` and `C_Map.GetBestMapForUnit` return nil);
  - classic dungeon map art is present;
  - the client-drawn minimap still shows the dungeon layout and the group.

  This set the design: a dungeon map plus a live minimap view.
