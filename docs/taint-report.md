# Taint report: "ForeverDungeonMap has been blocked from an action only available to the Blizzard UI"

That popup is `ADDON_ACTION_FORBIDDEN`: secure Blizzard code called a protected function while its
execution was tainted, and the first addon found on that taint path was ours. The addon does not
call protected functions itself. Our code runs, writes something or runs Blizzard code inside our call,
and a later Blizzard call reads that state.

## Evidence from the client

- `Logs\General.log` (2026-11-13, 13:09:33): with the build that was installed then,
  `DungeonView.lua:38` called `WorldMapFrame:SetMapID` through `pcall` from inside the
  `WorldMapFrame` OnShow hook (stack: `ToggleWorldMap` → `ShowUIPanel` → `SetAttribute` → our
  hook → `OnMapChanged` → `secureexecuterange`). It also hit `Blizzard_MapCanvas.lua:309 assertion
  failed!` (a pin template with OnEnter). The `[E][Lua]` lines from the other `Canvas.lua`/`Widgets.lua` errors
  are `GetItemInfo` nil calls and do not involve taint.
- None of `ADDON_ACTION`, `taint` or `forbidden` appears in any `Logs\*.log`. `taintLog` is not
  set in `WTF\Config.wtf`, so the client never wrote a taint log. GamePad is not enabled either.
- Questie on this client (`Questie\Modules\QuestieCompat.lua:300-319`) says that calling
  `WorldMapFrame:SetMapID` from addon code "would leave the map's state tainted for the session, so
  Blizzard's map navigation later gets its pins blocked in combat". Questie uses `C_Map.OpenWorldMap` instead.
  Questie also hides its pins from the gamepad map cursor (`HBDHooks.lua:28`) on WoW Forever only.
  Leatrix_Plus (`Leatrix_Plus.lua:16946`) says the world map reads the frame under the pointer
  every frame, so taint written on that frame spreads into the map's own code.
- Headless check: when `tools/harness/taint_scenario.lua` runs against the installed `LiveView.lua`,
  it reports 14 `ADDON_ACTION_FORBIDDEN` events on the first map open. The current file reports 0.

## Findings, most likely first

1. **World map state tainted by `WorldMapFrame:SetMapID` from addon code (installed build).**
   We changed the map inside our tainted OnShow hook. Blizzard's data providers then refreshed in
   that taint, and their pins call `CheckMouseButtonPassthrough` → `SetPassThroughButtons`, which is
   restricted. That call is blocked in combat, and on this engine it can also show the popup. The
   map stays tainted until `/reload`, so the popup can appear long after the map was opened.
   *Status:* fixed in source. `ns.ShowWorldMap` (Core.lua) uses `C_Map.OpenWorldMap` and waits for
   the end of combat. One leftover: if `C_Map.OpenWorldMap` raises an error, `ns.ShowWorldMap`
   still falls back to `ToggleWorldMap` plus `SetMapID` (patch A below).
2. **Our own map pins calling `SetPassThroughButtons`.** `AcquirePin` runs inside our provider's
   tainted `RefreshAllData` and calls the restricted API on every new pin.
   *Status:* fixed. `EntrancePins.lua:21-23` and `QuestPins.lua:198-200` make
   `SetPassThroughButtons`, `SetPropagateMouseClicks` and `CheckMouseButtonPassthrough` no-ops, and
   the pin XML has no OnEnter/OnLeave/OnMouseUp.
3. **Live view: Blizzard frames hidden or shown from addon code (fixed in this change).** The old
   `LiveView.lua` called `MinimapCluster:Hide()` and `Show()` (an Edit Mode system frame), hid the
   Minimap's Blizzard children (`MinimapBackdrop`, `ZoomHitArea`), and showed or hid its window
   while the Minimap was inside. `Hide()` and `Show()` run every affected OnHide/OnShow handler
   synchronously, inside our tainted execution:
   - the cluster's Edit Mode system mixin;
   - its dropdown buttons (`AddonCompartmentFrame`, Tracking), which use the shared
     `Blizzard_Menu` manager;
   - the managed-frame layout.

   Anything those handlers write becomes tainted. Later, secure code reads it and calls a protected
   function, and the popup names us. Typical cases are a unit-frame menu doing "Set Focus"
   (`FocusUnit`) or Edit Mode re-applying the layout to the protected action bars.

   Two smaller problems in the same file:
   - `Minimap:SetScript("OnMouseWheel", ...)` handed the Minimap's script slot to the addon. The
     "restored" Blizzard handler then ran tainted on every wheel event.
   - `GiveBack` was an `OnHide` hook, so hiding UIParent (Alt+Z) moved the Minimap.
4. **Gamepad map cursor reading our pins** (only with the GamePad UI enabled). Blizzard's cursor
   reads pin centers outside secure code, which taints the gamepad UI. Questie fixes this on this
   client by returning no center. *Status:* open, see patch B.
5. **Shared `GameTooltip` filled from map pins and the overlay** (`EntrancePins.lua`,
   `QuestPins.lua`, `MapCanvas.lua`, `Widgets.lua`). This is low risk: every map addon does it, and
   it only matters together with the gamepad tooltip path (Questie uses its own tooltip there).
   *Status:* left as is.
6. **The `ForeverDungeonMapView` overlay** is a mouse-enabled child of `WorldMapFrame.ScrollContainer`,
   and the map reads the frame under the pointer every frame. This is low risk while the overlay
   holds no field Blizzard reads. *Rule:* never put `owningMap`, `pinTemplate`, `dataProvider` or
   similar Blizzard keys on it.
7. **`UIPanelCloseButton` on our windows** (`Widgets.lua:186`, `:209`). Its default OnClick sends
   our frame through the secure panel manager (`HideUIPanel` → `SetAttribute`). This is low risk.
   *Status:* optional patch C.
8. **Safe as written:** `hooksecurefunc(WorldMapFrame, "OnMapChanged")`,
   `WorldMapFrame:HookScript("OnShow"/"OnHide"/"OnSizeChanged")`, the pin providers
   (`AddDataProvider`, isolated by `secureexecuterange`), and `tinsert(UISpecialFrames, ...)` for
   the journal. All of these are post-hooks or isolated calls. The work inside them is tainted, but
   it no longer touches Blizzard frames in combat.

## What changed in `ForeverDungeonMap/LiveView.lua`

- **Nothing of Blizzard's is hidden or shown.** `MinimapCluster` stays shown and in place. It gets
  `SetAlpha(0)`, and its clickable descendants (3 levels deep, the Minimap excluded) get
  `SetMouseClickEnabled(false)` and `SetMouseMotionEnabled(false)`. The Minimap's decorations and
  regions are faded the same way. Each change is recorded and undone in reverse order, which
  restores the exact alpha and the exact click/motion state.
- **Order of steps:** the window is shown before the Minimap moves in and hidden after the Minimap
  moved out. The Minimap's own children therefore never get OnShow/OnHide from our code.
- **Combat:** nothing is reparented, moved, resized or faded in combat. `Live:Show()`,
  `Live:Hide()` and resizes are queued with `ns.AfterCombat`. The visibility key keeps only the
  last request, and a separate key handles resizes. If the map is closed in combat, the Minimap
  stays in the window titled "(closes after combat)" and goes home on `PLAYER_REGEN_ENABLED`.
- **Exact restore:** parent, every anchor point, size, scale, strata, level, shown state, mask
  (the last mask another addon set, e.g. Leatrix's square one), zoom, mouse-wheel flag,
  `C_Minimap` ground textures, and the alpha and mouse state of every faded object. A single
  redraw timer restores the latest zoom, so an old timer can no longer bring back the live zoom.
- **Wheel zoom:** `Minimap:HookScript("OnMouseWheel")` replaces `SetScript`. It is active only
  while the Minimap is borrowed, and it zooms itself only when Blizzard has no wheel handler.
- **Edit Mode:** `hooksecurefunc(EditModeManagerFrame, "EnterEditMode")` gives the Minimap back.
  Logging out also gives it back. The window's `OnHide` hook is gone.
- **Unchanged for the player:** the enlarged square live minimap next to the world map (right side,
  or left without room), the window height following the map, dragging with a saved position, the
  party/raid names in class colours, the close button that keeps the window closed until the map
  is reopened, and `Live:IsBorrowing()` for tests.

## Patches proposed for files I do not own

**A. `Core.lua:191-194` (`ns.ShowWorldMap`)**: never fall back to `ToggleWorldMap`/`SetMapID`.
Replace

```lua
    if C_Map and C_Map.OpenWorldMap and pcall(C_Map.OpenWorldMap, mapID) then return true end
    -- older clients without C_Map.OpenWorldMap (never reached in combat)
    if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
    if mapID and WorldMapFrame:GetMapID() ~= mapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID) end
    return true
```

with

```lua
    -- ToggleWorldMap / SetMapID from addon code would taint the map for the whole session
    if not (C_Map and C_Map.OpenWorldMap) then return false end
    return (pcall(C_Map.OpenWorldMap, mapID))
```

**B. `EntrancePins.lua` after line 23 (builder) and `QuestPins.lua` after line 200 (QuestPins owner)**:

```lua
-- Blizzard's gamepad map cursor reads pin centers outside secure code and skips pins
-- without one, so our pins never taint it (Questie does the same on this client).
function Pin:GetCenter() return nil end
```

Nothing in the addon calls `GetCenter` on a pin; `MapCanvas.lua:163` uses its own `area`.

**C. (optional) `Widgets.lua:186` and `:209`**: after each `CreateFrame(..., "UIPanelCloseButton")`:

```lua
    -- our windows are not UI panels: a plain Hide keeps the secure panel manager out of it
    window.CloseButton:SetScript("OnClick", function(button) button:GetParent():Hide() end)
```

**D. `tools/harness/wowmock.lua:995` and `:997`**: `x ~= nil and x or y` returns `y` when `x` is
`false`, so `SetMouseClickEnabled(false)` still reads as enabled. Replace with

```lua
function Frame:IsMouseClickEnabled()
    if self._mouseClick ~= nil then return self._mouseClick end
    return self._mouse or false
end
```

Do the same for `IsMouseMotionEnabled` with `_mouseMotion`. `taint_scenario.lua` works around the
bug on the frames it checks.

## Harness: `tools/harness/taint_scenario.lua`

```
python -I tools/harness/run.py tools/harness/taint_scenario.lua
python -I tools/harness/run.py --combat tools/harness/taint_scenario.lua   (login / reload in combat)
```

The scenario adds these taint features on top of the mock:
- Blizzard OnShow/OnHide sentinels on `MinimapCluster`, its tracking, compartment and zone buttons,
  `MinimapBackdrop` and the zoom buttons. A sentinel that runs in tainted execution reports
  `ADDON_ACTION_FORBIDDEN`.
- `Hide()` or `Show()` on those frames from addon code is reported even out of combat.
- `Minimap:SetScript` from addon code is reported.
- A Blizzard wheel handler on the Minimap.
- A small `EditModeManagerFrame` that checks the Minimap is at home.

It covers five cases:
1. Map opened in a dungeon out of combat, then combat: wheel zoom, map resize, navigation to a zone,
   map closed. The Minimap stays put until combat ends, then goes home.
2. Map opened in combat: the live view waits and opens after combat. Opened and closed in combat:
   it never opens.
3. Live view shown and hidden in and out of combat, the last request wins, and the close button.
4. Edit Mode entered and exited after the live view was used, and entered while it is open.
5. Another addon's square mask survives.

Every case ends with a full snapshot comparison: parent, points, size, scale, strata, level, mask,
zoom, wheel, script, ground, cluster, children and regions. Results: 34/34 checks and 0 protected
calls in both modes. The default `scenario.lua` is also green in both modes.

## In-game test checklist

1. Before testing, run `/console taintLog 1` (use `2` for full detail; it stays in `WTF\Config.wtf`), then `/reload`.
   The log is written to `B:\World of Warcraft\_forever_\Logs\taint.log`. Lua errors still go to
   `Logs\General.log`. It is flushed on `/reload` or logout.
2. In a dungeon, out of combat, press M. The live view should open next to the map at the same
   height. The normal minimap corner should be empty and its buttons not clickable.
3. Pull a mob with the map open. Then:
   - wheel-zoom the live view;
   - maximize or minimize the map;
   - navigate to the zone with the nav bar;
   - close the map.

   The live view should stay up with "(closes after combat)". After combat the minimap should be
   back: round (or your Leatrix square), same place, zoom and zone text, buttons clickable.
4. In combat, press M. The dungeon map should show without a live view. After combat the live view should appear.
5. Close the live view with X. It should stay closed until the map is reopened.
6. After using the live view, open Edit Mode, select and move the minimap, save and exit. Then open
   Edit Mode with the map open: the minimap should go home first.
7. Enter combat. Right-click your own and the target's unit frame, use "Set Focus", and press ESC
   with the map open. No popup should appear.
8. In a normal zone in combat, open the map, navigate between continents and zones, and hover
   Blizzard quest pins, our entrance pins and our quest pins. No popup should appear.
9. Search `taint.log` for `ForeverDungeonMap`. Lines with `blocked` or `forbidden`, or
   `Execution tainted by ForeverDungeonMap` right before an `ADDON_ACTION_` line, are failures;
   send them together with the steps that caused them. Lines like
   `Global variable X tainted by ForeverDungeonMap` are only informational.
10. Afterwards run `/console taintLog 0`.
