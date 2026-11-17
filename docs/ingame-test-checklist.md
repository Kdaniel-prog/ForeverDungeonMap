# In-game test checklist (ForeverDungeonMap 0.6.0)

Work through it in order, after a **full client restart** (new files in the .toc are not picked
up by `/reload`). Tick each line; for each failure note the step number and send any
`Logs\General.log` / `Logs\taint.log` lines with "ForeverDungeonMap".

Logs: `B:\World of Warcraft\_forever_\Logs\General.log` (Lua errors) and `...\Logs\taint.log`.

## 0. Setup
1. [ ] Start the game, log in, then run `/console taintLog 1` and `/reload`.
2. [ ] No Lua error on login. The AddOns list shows ForeverDungeonMap 0.6.0.
3. [ ] Game Menu > Options > AddOns > ForeverDungeonMap opens. All five options are there, and
   their tooltips read well.
4. [ ] `/fdmap config` opens the same panel. `/fdmap help` lists the commands.
   `/fdmap debug` and `/fdmap export` open without errors.

## 1. Journal (out of a dungeon)
5. [ ] `/fdmap journal` opens the journal. Check the home page:
   - dungeon cards show their loading-screen art, cropped cleanly;
   - the WoW Forever emblem is drawn with the right aspect;
   - fonts look right (title font, Morpheus-style headings on the quest page).
6. [ ] Search works; the faction filter works.
7. [ ] Open a boss page:
   - the round portrait ring fits the picture;
   - loot rows show icons, names in quality colours and item tooltips;
   - Shift-click puts a link in chat; Ctrl-click opens the dressing room.
8. [ ] WoW Forever dungeons (Hall of Thanes, Ruins of Lordaeron, ...):
   - loot item IDs show real items, not "Loading..." forever;
   - level ranges and bosses look correct.
9. [ ] Open a quest page:
   - the parchment crop has no ragged edges;
   - "Starts at" and "Turn in" are right;
   - the chain panel is right;
   - the XP and money pills show sensible values, with "≈" when approximate.
10. [ ] Track adds the quest to the objective tracker (only for quests in your log). Share is
    enabled only in a group with a shareable quest, and it really shares.
11. [ ] Hover each texture-based button (gold action buttons, tabs, item slots): no green or
    missing textures; the hover gold border shows.
12. [ ] The journal's Map tab shows the map art, boss pins and the "Entrance" label. The boss
    icon size control works.

## 2. World map (out of a dungeon)
13. [ ] On a zone map, dungeon entrance pins sit on the real entrances. Their tooltip is right.
    Click opens the dungeon map, Shift-click opens the journal, right-click goes one map up.
14. [ ] Quest pins (!/?) sit on the real NPCs, checked against Questie's pins if it is installed.
    The continent map shows them in the right place too.
15. [ ] A quest's "Show on Map" opens the zone (through `C_Map.OpenWorldMap`) with the
    highlighted spot, puts the game's waypoint there and the on-screen arrow points to it
    (also a TomTom waypoint if TomTom is installed). A click on a quest pin does the same;
    Shift-click opens the quest in the journal.
16. [ ] Hall of Thanes shows the Old Ironforge tiles in the right order, with no seams or gaps.

## 2b. Journal cards and the map's elite dragons
16a. [ ] Home page: only favourite cards show a star; hovering a card shows its faint star; a
    click makes it gold, the card gets a gold border and moves to the front.
16b. [ ] "Hide dungeons": every card gets a round tick, the hint line shows at the bottom left. A
    click on a card (or its tick) veils it with "Hidden" and a cross; "Done" removes it from the
    list and the button reads "Hidden (1)". Bringing it back works the same way.
16c. [ ] Dungeon map (M in a dungeon, or the journal's Map tab): every boss portrait has a small
    gold dragon on its top edge, rares a silver one; a defeated boss's dragon is grey.

## 3. Inside a dungeon, out of combat
17. [ ] Press M. The dungeon map opens, boss portraits sit where the bosses stand, floors switch,
    and wheel zoom and drag work.
18. [ ] The live view opens next to the map at the same height:
    - the player arrow and the group are visible;
    - wheel zoom works;
    - you can drag the window, and it keeps its place after `/reload`;
    - party names are listed in class colours;
    - the normal minimap corner is empty and its buttons are not clickable.
19. [ ] Close the live view with X. It stays closed until the map is reopened.
20. [ ] Close the map. The minimap is back exactly as before: shape (round, or your square one),
    position, zoom, zone text, and buttons clickable.
21. [ ] Untick "Live view next to the map" with the map open: the minimap goes home at once. Tick
    it again: the live view is back.
21-1. [ ] Navigate the map away from the dungeon (nav bar, or right-click the dungeon map): the
    dungeon view steps aside, the live view stays.
21-2. [ ] Untick "Dungeon map on M inside dungeons" and press M: no dungeon map, but the live view
    opens. Tick it again.

## 3a. Outside a dungeon
21-3. [ ] Press M in a zone or a city. The live view opens next to the map and shows the zone
    around you; closing the map puts the minimap back exactly.
21-4. [ ] Tick "Live view only inside dungeons". Press M outside: no live view. Walk into a
    dungeon and press M: the live view opens. Untick the option again.

## 3b. Inside a dungeon, with EllesmereUI's minimap enabled
The headless `ellesmere_scenario.lua` rebuilds EllesmereUI's side from its source; these steps
are the proof on the real client.
21a. [ ] Press M. The enlarged minimap is inside the live view window, not on EllesmereUI's spot,
    and stays there when the map is maximized, minimized or the quest log opens. It is as bright
    as the normal minimap: no dark grey patch over it. (If there is one: `/fdmap bug`, "Copy
    everything" - the "Live view" lines say which layer the window and the minimap are on.)
21b. [ ] The player arrow and the group are visible up to the edges of the live view (with
    EllesmereUI's Rectangular shape and with its Forever Square frame and zone title), and
    EllesmereUI's border runs around the whole live view, not as a small box in the middle.
21c. [ ] Drag the live view window by its title bar or its footer: the minimap stays visible on
    top of it. Hovering the dots on the minimap shows their tooltips; the wheel zooms.
21d. [ ] Close the map. The minimap is back on EllesmereUI's spot with its size, shape and border,
    and EllesmereUI's unlock mode still moves it.
21e. [ ] Wheel-zoom the live view, close the map and open it again: the live view opens on the
    zoom you left it on, and EllesmereUI's minimap keeps its own zoom.
21f. [ ] With EllesmereUI's minimap visibility on "mouse-over" (or "in combat"), press M: the
    minimap is visible inside the live view. Close the map: it is hidden again as before.

## 4. Inside a dungeon, in combat (taint)
22. [ ] Open the map, then pull. While in combat:
    - wheel zoom works;
    - maximizing or minimizing the map works;
    - navigating to the zone with the nav bar works;
    - closing the map leaves the live view up with "(closes after combat)".

    After combat the minimap goes home.
23. [ ] Press M in combat. The dungeon map shows, and the live view window opens with the note
    that the minimap cannot move in combat; the normal minimap stays in its corner. After combat
    the minimap moves into the window. Closing the map in combat closes the empty window at once.
23a. [ ] With the minimap inside the live view, pull and try to drag the window: it stays put, no
    "blocked" message. After combat it drags again.
24. [ ] `/fdmap` in combat opens the journal's Map tab instead of the world map.
25. [ ] Defeat a boss: it is crossed out on the map and in the journal, and stays crossed out
    after `/reload`.
26. [ ] In combat, try each of these. No "blocked from an action only available to the Blizzard
    UI" popup may appear:
    - right-click your own unit frame and use "Set Focus";
    - press ESC with the map open;
    - hover Blizzard's quest pins.

## 5. Edit Mode and leaving
27. [ ] After using the live view, open Edit Mode, then move and save the minimap. Then open Edit
    Mode with the map open: the minimap goes home first and stays there until Edit Mode closes.
28. [ ] Leave the dungeon. The world map opens normally and shows no dungeon view.
29. [ ] `/fdmap resetlive` and `/fdmap resetkills` print their messages.

## 6. Wrap up
30. [ ] Search `Logs\taint.log` for `ForeverDungeonMap`. Any `blocked` or `forbidden` line, or
    `Execution tainted by ForeverDungeonMap` right before an `ADDON_ACTION_` line, is a failure.
31. [ ] `Logs\General.log` has no new `ForeverDungeonMap` Lua errors.
32. [ ] Run `/console taintLog 0`.
