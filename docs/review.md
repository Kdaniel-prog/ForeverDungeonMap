# Clean-code review of `ForeverDungeonMap/*.lua`

Read-only review against `.claude/skills/clean-code` and `.claude/skills/wow-addon`. Line numbers
are from 2026-11-13; other agents are still editing these files, so lines may have moved. Each
finding is fixed by the file's owner. Most important first.

The code is in good shape:
- there are no banner headers, no trailing comments, and no 5-line block copied between files;
- no function is longer than 40 lines;
- the item APIs go through aliases (`Widgets.lua:9-11`);
- `OnUpdate` is only used while dragging (`MapCanvas.lua:59`, `:191`, `:436`).

The findings are mostly rule 4 (shared code pulled up) and rule 5 (nothing hard-wired).

## 1. Duplicated code that belongs in one place (rule 4)

1. **The map pin base is defined twice.**
   - Repeated: the four taint guards (`SetPassThroughButtons`, `SetPropagateMouseClicks`,
     `CheckMouseButtonPassthrough`, `GetCenter`), the mixin creation, and the provider skeleton
     (`RemoveAllData`, `OnMapChanged`, `AddDataProvider` once).
   - Where: `EntrancePins.lua:15-27`, `:97-121` and `QuestPins.lua:190-202`, `:274-292`.
   - Why it matters: a third pin kind would copy it again, and a missing guard brings the
     taint popup back.
   - Fix: one `ns.CreatePinMixin()` and `ns.CreatePinProvider(template, refresh)` in a shared file
     (e.g. `PinBase.lua`, loaded before both). Each pin kind keeps only its icon, tooltip and click.
2. **The header band is built twice.**
   - Art texture, inset 3 and shade: `DungeonView.lua:70-77` and `Journal.lua:479-486`.
   - Filling the art (`SetShown`, `SetTexture(art.bg)`, `SetTexCoord`): `DungeonView.lua:142-145`
     and `Journal.lua:374-376`.
   - Fix: `W.HeaderArt(parent)` and `W.SetHeaderArt(texture, instanceID)` in `Widgets.lua`.
3. **The empty-state message is written out four times** in the journal: `Space(20)` followed by
   `Text(..., ns.Font("disable"...), C.MUTED, 8)` at `Journal.lua:133-134`, `:152-153`,
   `:185-186` and `:343-344`. Fix: a `Canvas:Empty(text, font)` method, plus constants for the 20
   and the 8.
4. **Percent coordinates are converted by hand.**
   - `x / 100, y / 100` appears in `EntrancePins.lua:109`, `:111`, `:115`, `QuestPins.lua:184`,
     `:188` and `Journal.lua:984` (TomTom).
   - `PERCENT = 100` is defined separately in `Settings.lua:14` and `Learn.lua:15`.
   - Fix: one `ns.Normalized(spot)` returning `x / 100, y / 100`, and one shared `ns.PERCENT`.
5. **The quest tooltip in `Widgets.lua:841-848` and the quest pin tooltip
   (`QuestPins.lua` `AddQuestLine`)** each build "level + name + colour" lines their own way.
   They should share `W.QuestTitleLine(quest)`.

## 2. Hard-wired colours, textures and numbers (rule 5)

6. **Colour codes typed into strings instead of `ns.Hex(C.*)`:**
   - `Core.lua:76` (`|cff33ff99`, the chat prefix);
   - `DungeonView.lua:22` and `MapCanvas.lua:17` (`|cffffd100` hint keys; both hints are also
     near copies of each other, see item 2);
   - `Widgets.lua:844`, `:845`, `:848` (`|cffffd100` tooltip labels).

   Fix: `ns.Hex(C.GOLD)` plus one `W.KeyHint(key, action)` helper.
7. **Colours given as numbers:** `0.8, 0.8, 0.8` in `EntrancePins.lua:60` and `Widgets.lua:841`
   (add `C.SUBTLE` to Theme); `0, 0, 0` in `Widgets.lua:188`, `:190` (`C.SHADE_*` tokens exist).
8. **Pin scale limits:** `EntrancePins.lua:31` has `SetScalingLimits(1, 1.0, 1.25)` written out,
   while `QuestPins.lua:220` uses named constants. Both should use shared constants, which follows
   from item 1.
9. **Layout offsets typed again and again** (a number typed twice gets a named constant):
   - `Journal.lua`: the 4/8/12/20 paddings appear 15-37 times each, e.g. `:518-540`, `:589-595`,
     `:703-709`. Header geometry (icon 44, name at 62/-12) is unnamed while
     `DungeonView.lua` uses `ICON_SIZE`.
   - `Canvas.lua:597-625` (quest row cluster): `-8`, `-32`, `-52`, `-76` are icon size + gap
     sums. Compute them from `ICON_SIZE` and `GAP` so the row survives a size change.
   - `DungeonView.lua:117`: `8 + ICON_SIZE + 10 + ... + 16` and the `1000` width fallback.
   - `MapCanvas.lua:448-456`: frame level offsets `+1`, `+2` and `+20` (three times). Name the
     layers.
10. **Game data in code:** `Compat_FDJ.lua:20-24` `WING_OF` lists dungeon IDs (189, 329, 429).
    Rule 5 puts game data in `Data/*.lua`; move it next to the dungeon records (`Data/Dungeons.lua`).
11. **Textures outside Theme:** `LiveView.lua` (mine) still holds Blizzard's minimap mask
    `Interface\\Masks\\CircleMaskScalable`. Proposal: add `TEX.MINIMAP_ROUND_MASK` to `Theme.lua`;
    I will switch to it once it exists. The other LiveView colours and textures now use
    `ns.Hex(C.MUTED)`, `C.WHITE` and `TEX.WHITE`.

## 3. Names (rule 1)

12. **`fn` as a parameter or loop name:** `Settings.lua:53` (`OnChanged(key, fn)`), `:60`,
    `Rewards.lua:105`, `:110`. Use `listener`.
13. **`id` as a loop name:** `Compat_FDJ.lua:102`, `Debug.lua:27`. Use `instanceID`.
14. **Short field and parameter names:** `MapCanvas.lua:100` (`up`, which reads as a direction);
    `Journal.lua:40` (`ui`, allowed only as the abbreviation UI; consider `widgets`).

## 4. Comments and function length (rules 2 and 3)

15. **About 60 functions longer than 8 lines have no comment above them.** Most have
    self-explanatory names, but these are worth a line:
    - `Core.lua:154` `OnZoneChanged` and `:210` `ns.AfterCombat` (the one-per-key rule matters
      to callers);
    - `Compat_FDJ.lua:73` `Import`, `:153` `IndexQuestRecords`, `:184` `IndexInsideSpot`,
      `:266` `FindQuestLocation`;
    - `Journal.lua:180` `RenderBoss`, `:322` `RenderRewards`, `:671` `Matches` (what search
      matches), `:774` `FillCard`;
    - `ForeverData.lua:62` `MergeDungeon` (which source wins);
    - `Learn.lua:79` `OnQuestFrame`.
16. **Functions between 26 and 35 lines** (allowed; split them when touched):
    - `Journal.lua:551` `CreateQuestHeader` (35);
    - `MapCanvas.lua:315` `MapCanvas:Layout` (29);
    - `Widgets.lua:208` and `:268` (28 and 29);
    - `DungeonView.lua:65` `CreateHeader` (28; item 2 shortens it);
    - `Canvas.lua:614` `MakeQuestRow` (26).

## 5. WoW-specific notes

17. `Widgets.lua:574` `IsDone` falls back to the global `IsQuestFlaggedCompleted`. That is
    fine (it is guarded), but move it to a top-of-file alias like the item APIs at `Widgets.lua:9-11`.
18. Taint: the patches proposed in `docs/taint-report.md` are applied: `ns.ShowWorldMap` no longer
    calls `SetMapID`, and both pin kinds have `GetCenter`. Item 1 would keep the guards from drifting
    apart. Optional patch C (plain Hide on our close buttons, `Widgets.lua` `W.Window` /
    `W.CreateWindow`) is still open.

## Owner TODOs for the release (not code style)

- Add `## X-Curse-Project-ID: <id>` to `ForeverDungeonMap.toc` once the CurseForge project
  exists. Until then, `release.yml` passes `-p ${{ vars.CURSEFORGE_PROJECT_ID }}`.
- Change `## Version: 0.6.0` to `## Version: @project-version@` so the packager writes the tag
  into the .toc.
- Repository settings: secret `CF_API_KEY` and variable `CURSEFORGE_PROJECT_ID`. Optionally set
  the variable `CURSEFORGE_GAME_VERSION`, used if CurseForge has no game version for
  interface 16001, and the secret `WAGO_API_TOKEN`.
- Take the screenshots named in `ForeverDungeonMap/README.md` (`docs/screenshots/*.png`) and upload
  them to the CurseForge project.

## Review pass applied (Core, DungeonView, MapCanvas, EntrancePins, LiveView, PinBase)

- **#1** New `PinBase.lua` with:
  - `ns.PinBase.CreatePinMixin()`, which has the taint guards (`SetPassThroughButtons`,
    `SetPropagateMouseClicks`, `CheckMouseButtonPassthrough`, `GetCenter`), the tooltip wiring
    (`OnMouseEnter` → kind's `FillTooltip(tooltip)`), right-click one map up, and other clicks
    → `OnPinClick(button)`, plus `ApplyScalingLimits(min, max)`;
  - `ns.PinBase.CreateProvider(template, buildPins)`, which provides `RemoveAllData`,
    `RefreshAllData`, `OnMapChanged`, `Attach()` and `Refresh()`.

  EntrancePins.lua uses it, and QuestPins.lua has adopted it already (nothing left to route).
- **#2** The header art builder `W.CreateHeaderArt(panel)` / `W.SetHeaderArt(art, instanceID)`
  lives in DungeonView.lua for now, and DungeonView uses it. See patch E.
- **#4** `ns.PERCENT` and `ns.Normalized(spot)` are in Core.lua. EntrancePins and MapCanvas use
  them; QuestPins uses `ns.Normalized` already. See patch F.
- **#6** `ns.KeyHint({ { key, action }, ... })` is in Core.lua and builds the DungeonView and
  MapCanvas hints. `ns.Print` uses `ns.Hex(C.GOLD)`, and the MapCanvas floor range uses
  `ns.Hex(C.MUTED)`. See patch G.
- **#7** `WING_OF` is done: it moved to `Data/CompatData.lua` as `ns.JOURNAL_WING_OF`.
- **#8** The entrance pin scale limits are named constants.
- **#9** Named constants for the DungeonView header geometry, frame levels, scan depth and
  fallback width. MapCanvas has them too: frame-level layers, sizes, zoom snap, scale steps and
  epsilon.
- **Core:** `ns.ChangeOpenWorldMap(mapID, onChange)` is the one place for the "in combat wait,
  then only if the map is still open" rule. `ns.ShowParentMap` and DungeonView's `SetWorldMap`
  use it.
- **#11** LiveView uses `TEX.MINIMAP_ROUND_MASK`, falling back to the path.
- **#15** Comments were added above the functions that needed them, in all five files.

### Patch E (builder): move the header art builder to Widgets.lua and use it in Journal.lua
1. Move `W.CreateHeaderArt` and `W.SetHeaderArt` from DungeonView.lua (they sit above
   `CreateHeaderTexts`, together with the `HEADER_ART_INSET = 3` constant) into Widgets.lua. Do
   not copy them. DungeonView then keeps working unchanged.
2. In `Journal.lua` `CreatePage` (currently lines 576-581), replace
   ```lua
   ui.headerArt = head:CreateTexture(nil, "BACKGROUND", nil, 1)
   W.Inset(ui.headerArt, BAND_INSET)
   ui.headerArt:SetAlpha(ns.ALPHA.headerArt)
   local shade = head:CreateTexture(nil, "BACKGROUND", nil, 2)
   W.Inset(shade, BAND_INSET)
   W.ShadeHorizontal(shade)
   ```
   with `ui.headerArt = W.CreateHeaderArt(head)`.
3. In `Journal.lua` `RenderHeader` (currently lines 468-473), replace the `local art = ...` line
   and the `SetShown`/`if art and art.bg ... end` block with
   `W.SetHeaderArt(ui.headerArt, selection.instanceID)`.

### Patch F (builder): percent spots
Done by the builder: no `/ 100` and no local `PERCENT` are left outside `Core.lua`.

### Patch G (builder): gold key labels
Done by the builder: no `|cffffd100` is left in `Widgets.lua`.
