# ForeverDungeonMap – UI specification (Dungeon Journal + dungeon map)

Status: design spec for v0.6 · Target client: WoW Forever 1.60.1.70938 (`## Interface: 16001`, Lua 5.1, modern UI engine)
Scope: `Journal.lua`, `Canvas.lua`, `Theme.lua`, `Widgets.lua`, `DungeonView.lua`, `LiveView.lua`, `Data/*.lua`.

**Rules for this spec**

* **Layout and UX: copy FDJ's.** ForeverDungeonJournal (FDJ, by Exehn, *no licence*) is the reference for the window layout, its regions and the way it works. We **re-implement** that layout in our own code. We **do not copy** FDJ code, data tables or `Media/*.tga` art.
* **Visual skin: our own.** It is built from Blizzard UI textures that exist in the client: gold-trimmed dialog frames, dark stone, parchment, item-quality frames and Friz Quadrata/Morpheus fonts. Every dungeon uses the **same palette**. FDJ tints its panels green or brown per dungeon; we do not. Each dungeon's character comes from its **art**: EJ background, EJ lore picture, EJ button art and loading screens.
* Every texture is given as `path` + **FDID**. "✔" means the FDID is in the wago.tools listing for build 1.60.1.70938 (scratchpad `art_research/*.json`, `ui_research/*.json`). "⚠ verify" means it was not confirmed: an atlas name, a texcoord, or something to check in game.

---

## 0. Visual identity – "Gilded Codex"

The journal looks like a **dark leather-and-stone book with gold fittings**. UI chrome is dark and gold. Text you read (quests) sits on parchment. Each dungeon's own picture is the only per-dungeon colour.

### 0.1 Texture kit (all ✔ unless marked)

| Role | Texture (path) | FDID | Use |
|---|---|---|---|
| Window background | `Interface\FrameGeneral\UI-Background-Rock` | 374155 ✔ | tiled (`SetHorizTile/SetVertTile`), vertex colour `0.32,0.30,0.28` → dark stone |
| Window background (alt) | `Interface\DialogFrame\UI-DialogBox-Background-Dark` | 312922 ✔ | backdrop `bgFile`, tile 32; use it if the rock texture looks too busy |
| Window border | `Interface\DialogFrame\UI-DialogBox-Gold-Border` | 131076 ✔ | backdrop `edgeFile`, edgeSize 32, insets 11 |
| Window border (fallback) | `Interface\DialogFrame\UI-DialogBox-Border` | 131072 ✔ | the same, silver-gold |
| Title ribbon | `Interface\DialogFrame\UI-DialogBox-Header` | 131080 ✔ | 300×64 at `TOP 0,+13`; title text at ribbon `TOP 0,-14` (classic GameMenu style) |
| Title ribbon (alt) | `Interface\DialogFrame\UI-DialogBox-Gold-Header` | 131079 ✔ | if it reads better on the gold border (⚠ verify visually) |
| Corner flourish (P2) | `Interface\DialogFrame\UI-DialogBox-Gold-Dragon` | 131078 ✔ | top-left corner ornament, 64×64 at `TOPLEFT -14,+14` (⚠ verify the look) |
| Inset panel edge | `Interface\Tooltips\UI-Tooltip-Border` | 137057 ✔ | backdrop edge, edgeSize 12, insets 3 (panels, rows, pills) |
| Inset inner shadow | `Interface\Common\ShadowOverlay-Top/-Bottom/-Left/-Right/-Corner` | 423813 / 423809 / 423811 / 423812 / 423810 ✔ | 16 px vignette inside panels and the map frame |
| Gold hairline divider (dark bg) | `Interface\Common\UI-TooltipDivider` | 609615 ✔ | 2 px tall, full width, under panel titles |
| Dialog divider (alt) | `Interface\DialogFrame\UI-DialogBox-Divider` | 131074 ✔ | under the window top bar |
| Parchment page | `Interface\QuestFrame\QuestBG` | 530420 ✔ | quest page background (texcoords ⚠ verify: start with full `0,1,0,1`; crop so the edge stays clean) |
| Parchment page (alt) | `Interface\QuestFrame\QuestBackgroundParchment` | 3813080 ✔ | the modern quest parchment. Try atlas `QuestBG-Parchment` first (⚠ verify `C_Texture.GetAtlasInfo`) |
| Parchment section break | `Interface\QuestFrame\UI-HorizontalBreak` | 136783 ✔ | 256×32 under the quest title, alpha 0.8 |
| Parchment bullet | `Interface\QuestFrame\UI-Quest-BulletPoint` | 136788 ✔ | 12×12 before each objective and chain line |
| Reward name plate | `Interface\QuestFrame\UI-QuestItemNameFrame` | 136796 ✔ | classic quest-reward look: icon + plate (see 3.9) |
| Row hover glow | `Interface\QuestFrame\UI-QuestTitleHighlight` | 136810 ✔ | `ADD`, alpha 0.30 (dark rows) / 0.18 (parchment) |
| Item quality frame | `Interface\Common\WhiteIconFrame` | 651080 ✔ | over every item icon, `SetVertexColor(ITEM_QUALITY_COLORS[q])` |
| Item slot backing | `Interface\Buttons\UI-Quickslot2` | 130841 ✔ | 64×64 behind 36 px icons (texcoord ⚠ ~`0.18,0.82,0.18,0.82`) |
| Square hover | `Interface\Buttons\ButtonHilight-Square` | 130718 ✔ | `ADD` on icon buttons |
| Round portrait ring | `Interface\Common\portrait-ring-withbg` | 652158 ✔ | boss portraits, round dungeon icon (⚠ verify the inner radius; fallback is our `Media\Ring.tga`) |
| Round ring hover | `Interface\Common\portrait-ring-withbg-highlight` | 652157 ✔ | hover state of round portraits and map pins |
| Small gold ring | `Interface\Common\GoldRing` | 519888 ✔ | level badges (22–28 px) |
| Circle mask | `Interface\CharacterFrame\TempPortraitAlphaMask` | 130924 ✔ | `CreateMaskTexture` for portraits and round art crops |
| Circle mask (alt) | `Interface\Common\CommonMaskCircle` | 5757702 ✔ | the same; or keep our own `Media\CircleMask.tga` |
| Quest icons | `Interface\GossipFrame\AvailableQuestIcon` / `ActiveQuestIcon` / `IncompleteQuestIcon` | 132049 / 132048 / 365195 ✔ | `!` / gold `?` / grey `?` |
| Done tick | `Interface\RaidFrame\ReadyCheck-Ready` | 136814 ✔ | completed |
| Defeated X | `Interface\RaidFrame\ReadyCheck-NotReady` | 136813 ✔ | killed boss overlay |
| Faction crests | `Interface\Common\icon-alliance` / `icon-horde` | 652155 / 652156 ✔ | faction icons and toggles (round crests; our own choice, not FDJ's shields) |
| Faction (fallback) | `Interface\TargetingFrame\UI-PVP-Alliance` / `-Horde` | 136998 / 137000 ✔ | texcoord `0.05,0.62,0.02,0.60` (current code) |
| Boss skull | `Interface\TargetingFrame\UI-TargetingFrame-Skull` | 137025 ✔ | "Bosses" tab icon |
| Map icon | `Interface\Icons\INV_Misc_Map_01` | 134269 ✔ | "Map" tab icon |
| XP icon | `Interface\Icons\XP_Icon` | 894556 ✔ | XP pill glyph |
| Notes icon | `Interface\Icons\INV_Misc_Note_01` | 134327 ✔ | "Notes" heading glyph (P1) |
| Action button (gold) | `Interface\Buttons\UI-DialogBox-Button-Gold-Up` / `-Gold-Down` + `UI-DialogBox-Button-Highlight` | 949700 / 949699 / 130762 ✔ | **our action buttons** (Show on Map, Show Turn In, Track, Share, Show Quest Chain); texcoord ⚠ `0,0.625,0,0.6875` like UIPanelButton; fallback `UIPanelButtonTemplate` |
| Action button disabled | `Interface\Buttons\UI-DialogBox-Button-Disabled` | 130760 ✔ | disabled action button |
| Round hover | `Interface\Buttons\UI-Common-MouseHilight` | 130757 ✔ | ADD on round icons (header icons, chain toggle) |
| List highlight | `Interface\Buttons\UI-Listbox-Highlight2` | 130783 ✔ | search-result rows, chain lines |
| Coins | `Interface\MoneyFrame\UI-GoldIcon` / `UI-SilverIcon` / `UI-CopperIcon` | 237618 / 237620 / 237617 ✔ | money pill. Simplest: `GetCoinTextureString(copper)` |
| Favourite star | `Interface\Common\FavoritesIcon` | 922035 ✔ | loot favourites (P1) |
| Search icon | `Interface\Common\UI-Searchbox-Icon` | 374210 ✔ | comes with `SearchBoxTemplate` |
| Page arrows | `Interface\Buttons\UI-SpellbookIcon-PrevPage-Up/Down/Disabled`, `NextPage-Up/Down/Disabled` | 130869/130868/130867, 130866/130865/130864 ✔ | back button, floor selector |
| Plus/minus | `Interface\Buttons\UI-PlusButton-Up/Down/Hilight`, `UI-MinusButton-Up/Down` | 130838/130836/130837, 130821/130820 ✔ | boss-icon size control |
| EJ boss placeholder | `Interface\EncounterJournal\UI-EJ-BOSS-Default` | 521744 ✔ | boss with no display ID |
| EJ paper frame | `Interface\EncounterJournal\UI-EJ-BossModelPaperFrame` | 527690 ✔ | frame around the EJ creature picture on the boss header (P2, ⚠ coords) |

**Per-dungeon art** (from `Data/Art.lua`, generated by `tools/make_art.py`):

| Field | Source | Example (Wailing Caverns) | Use |
|---|---|---|---|
| `card` | `Interface\EncounterJournal\UI-EJ-DungeonButton-<Name>` | 608229 ✔ | home card art (coords `0,0.684,0,0.742`) |
| `lore` | `Interface\EncounterJournal\UI-EJ-LoreBG-<Name>` | 608313 ✔ | **watermark** behind the boss-detail panel (alpha 0.18) + map-tab backdrop |
| `bg` | classic loading screen | 131882 ✔ | header band strip (coords `0,1,0.42,0.56`) |
| `BOSS_ART[name]` | `Interface\EncounterJournal\UI-EJ-BOSS-<Name>` | 607805 ✔ | 128×64 creature picture on the boss header |
| `ICONS[id]` | `Interface\LFGFrame\LFGIcon-<Name>` | 136364 ✔ | round dungeon icon (masked) |
| (alt bg) | `Interface\EncounterJournal\UI-EJ-Background-<Name>` | 608190 ✔ | larger EJ backdrop; could replace `bg` in the header band (⚠ verify crop) |

### 0.2 Palette (one palette for every dungeon; replaces `Theme.lua` moods)

| Token | RGBA | Used for |
|---|---|---|
| `INK` | 0.06, 0.05, 0.04, 0.94 | panel fill (list panel, detail panel, map frame) |
| `ROW` | 0.11, 0.09, 0.07, 0.96 | list rows, loot rows, pills |
| `ROW_HOVER` | 0.16, 0.13, 0.09, 0.98 | row fill on hover |
| `ROW_SEL` | 0.24, 0.18, 0.08, 0.98 | selected row fill |
| `ROW_PRESS` | 0.08, 0.06, 0.05, 1 | pressed (mouse down) |
| `EDGE` | 0.36, 0.29, 0.17, 1 | default row / panel border |
| `EDGE_PANEL` | 0.55, 0.43, 0.22, 1 | panel border (bronze) |
| `GOLD` | 1.00, 0.82, 0.00 | `NORMAL_FONT_COLOR`: titles, hover border |
| `GOLD_SOFT` | 1.00, 0.78, 0.30, 1 | selected border, selected left bar |
| `TEXT` | 0.93, 0.91, 0.86 | body text on dark |
| `MUTED` | 0.64, 0.60, 0.52 | secondary text on dark |
| `PARCH_TEXT` | 0.20, 0.12, 0.04 | body text on parchment |
| `PARCH_HEAD` | 0.42, 0.11, 0.02 | "rubric" section headings on parchment |
| `PARCH_MUTED` | 0.38, 0.29, 0.18 | secondary text on parchment |
| `PARCH_ROW` | 0.16, 0.12, 0.07, 0.92 | item buttons / pills **on** parchment (dark inlays) |
| `DONE` | 0.25, 1.00, 0.25 (dark bg) / 0.10, 0.45, 0.08 (parchment) | completed |
| `DEFEATED` | 1.00, 0.32, 0.25 | killed boss text |
| `FOREVER` | 0.40, 0.80, 1.00 | "WoW Forever" tag, Forever emblem tint |
| `XP` | 0.62, 0.45, 1.00 | the "XP" glyph in the XP pill |

Level colours use Blizzard's `GetQuestDifficultyColor(level)` (⚠ verify it exists; fallback `GetDifficultyColor`) for quests and bosses. Dungeon ranges compare the player level `p` with `min/max`: `p < min-2` red `1,0.1,0.1`; `p < min` orange `1,0.5,0.25`; `min ≤ p ≤ max` yellow/green `GetQuestDifficultyColor(p)`; `p > max` grey `0.5,0.5,0.5`.

### 0.3 Fonts (Blizzard font objects; check `_G[name]` at load and fall back to the right-hand column)

| Role | Font object | Fallback |
|---|---|---|
| Window title (on ribbon) | `GameFontNormal` | – |
| Dungeon name (header band), boss name (detail) | `QuestTitleFontBlackShadow` (Morpheus) | `GameFontNormalHuge` |
| Panel titles ("Bosses", "Quests  7") | `GameFontNormalLarge` | – |
| Row title | `GameFontNormal` (quest) / `GameFontHighlight` (boss) | – |
| Row sub-line | `GameFontHighlightSmall` (colour `MUTED`) | – |
| Quest page title | `QuestTitleFont` (Morpheus), colour `PARCH_HEAD` | `GameFontNormalLarge` |
| Quest page headings | `QuestTitleFont` at 14 px via `SetFont(path, 14)` ⚠, colour `PARCH_HEAD` | `GameFontNormal` |
| Quest page body | `QuestFont`, colour `PARCH_TEXT` | `GameFontHighlight` |
| Quest page small | `QuestFontNormalSmall` | `GameFontNormalSmall` |
| Item name in row | `GameFontNormal` + quality colour | – |
| Badges / pill numbers | `NumberFontNormal` / `NumberFontNormalSmall` | `GameFontHighlightSmall` |
| Disabled / empty state | `GameFontDisable` / `GameFontDisableLarge` | – |

Body text on dark gets shadow `0,0,0,1 @ (1,-1)`. Text on parchment has **no** shadow.

### 0.4 Interaction states (all buttons, rows, pins, icons)

| State | Fill | Border | Extra |
|---|---|---|---|
| normal | `ROW` | `EDGE` | – |
| **hover** | `ROW_HOVER` | **`GOLD`** (always) | `UI-QuestTitleHighlight` ADD 0.30; title text → `GOLD`/white; tooltip if informational |
| pressed | `ROW_PRESS` | `GOLD` | content offset `+1,-1` while the mouse is down |
| selected | `ROW_SEL` | `GOLD_SOFT` | 3 px gold bar on the left edge (`GOLD_SOFT`), title white |
| selected + hover | `ROW_SEL` | `GOLD` | glow |
| disabled | `ROW` alpha 0.5 | `EDGE` alpha 0.5 | icons desaturated, text `GameFontDisable` |

**Hover must always show the gold border.** Implement it once (`W.Hoverable(frame)`, see §6) so every row and button gets the same behaviour. The visual is recomputed from `frame:IsMouseOver()` on every repaint. Today a repaint (for example `GET_ITEM_INFO_RECEIVED`) resets the colours and the hover look disappears. That causes the user complaint "hover sometimes has no border".

Tooltips opened from our frames get a solid dark backing (an extra `BACKGROUND` texture `0.03,0.03,0.04,1` on `GameTooltip`/`ShoppingTooltip1/2`, shown only while the owner is inside our frame tree). The tooltip border stays as Blizzard draws it.

---

## 1. FDJ layout → our implementation (mapping)

| FDJ element (reference screenshots 15–25) | FDJ size / behaviour | Ours | Notes |
|---|---|---|---|
| Main window | 850×590, dialog border, rock bg, DIALOG strata, movable | **860×600**, rock bg + **gold** dialog border, title **ribbon** | `UISpecialFrames` (Esc closes) |
| Top strip: search · title · Report · Language | 34 px dark strip | 30 px strip: search (left), ribbon title (centre), ★ Favourites + close (right) | no Report/Language (P2) |
| Red "Dungeons" button (back) | 130×24, below the strip | gilded back tab "◄ Dungeons" 120×22 | home page: filter chips on the same row |
| Dungeon header panel | name (large) + "LV 15-24" + 2 round icons (entrance swirl, LFG eye) + Map/Bosses/Quests red buttons 108×30 | header band 64 px with **dungeon art strip**, round dungeon icon, name in Morpheus, level line, entrance + LFG round icons, **gilded tabs** Map/Bosses/Quests 108×30 | same placement |
| Left panel (boss list) | 344 wide, title "Bosses", scroll | 344 wide, title, scroll | identical geometry |
| Boss button | 315×55, 44 px portrait, 28 px level medallion lower-left, name, "RARE" | **308×56**, 46 px round portrait + ring, 24 px gold-ring level badge, order number, rare/defeated tag | |
| Right panel: boss header + loot | 68 px portrait + level, name, loot rows 388×52 | 72 px portrait, Morpheus name, "Boss 7 of 8 · Level 21 Elite", EJ creature picture, **loot rows 434×46** | + lore watermark |
| Loot row | icon, quality name, "Off Hand, Shield" | same + WhiteIconFrame quality frame, ★, "You have it" | compact mode 30 px (P2) |
| Quests title row | "Quests \| 7", red Track, two faction toggles 40×32 | "Quests  7", Track (gold action button 70×22), faction crest toggles 36×30 | |
| Quest button | 296×48, ! icon, title, "Available from Level N", faction icons, chain icon, ✓ / big ? + "Turn in" | **308×48**, same elements | |
| Inline chain under quest | grows the row; lines 18 px "1. Name ✓" in a dark inset | same; plus a per-step "pick-up" pin icon | |
| "In Dungeon" icon + tooltip | small swirl after the level text | atlas `Dungeon` 14 px (⚠ verify), tooltip "Starts in the dungeon" | |
| "Required Quests – click to show the whole chain" | chain icon tooltip; click expands | identical behaviour, our own `Media\Chain.tga` | |
| Quest detail parchment | title (small caps), level, factions, Share + ✓; Objective, Show on Map, Starts at (+ item button), Turn in, Notes, Rewards (XP pill purple, money pill) | parchment (`QuestBG`), Morpheus title, rubric headings, same section order, **reward plates** (classic `UI-QuestItemNameFrame`), our own XP/money pills | |
| Map tab | full body panel, map art, boss portrait pins, "Entrance", "Boss icons 90% − +" bottom-left | same, built on the shared map canvas from `DungeonView.lua` | |
| Home: dungeon cards | 2 columns, 352×126 art cards | 2 columns, **388×120** cards | |
| Favourites popup, Loot filter, RPG mode, options | various | Favourites P1, Loot filter P2, RPG mode – (not planned) | |

---

## 2. Feature inventory

Priorities: **P0** = must ship in the next version · **P1** = soon · **P2** = later.
"Data" = what the feature needs. "Have?" = whether `Data/*.lua` already has it.

### 2.1 Window & navigation

| # | Feature | Pri | Data | Have? |
|---|---|---|---|---|
| 1 | Home page: dungeon cards (art, name, level range coloured, "8 bosses · 9 quests", ✓ when all your quests are done, "You are here", Forever emblem) | P0 | `DUNGEONS`, `ART.card`, `ICONS`, `BOSSES`, `QUESTS` | ✔ (except the missing Forever dungeons, #6) |
| 2 | Open on the current instance; otherwise home | P0 | `ns.instanceID` | ✔ |
| 3 | Back "◄ Dungeons", header tabs Map / Bosses / Quests | P0 | – | ✔ (restyle) |
| 4 | Search box: dungeons, bosses, **items, quests**; result dropdown (max 6 rows of 24 px, then scroll); Enter = first result | P1 | boss/quest names ✔; item names only at runtime (`C_Item.GetItemNameByID`, async) | partly |
| 5 | Filter chips All / Classic / Forever; option "hide outleveled" | P0 / P2 | `d.forever`, `d.max` | ✔ |
| 6 | Missing Forever dungeons: The Drowned City (2970), Blackmaw Hold (2974), Alcaz Prison (2994), The Shaper's Terrace (3001), Krol'dok Stronghold (3039) | P1 | name ✔ (`Map.csv`), loading screen ✔ (§5), levels ✗ (in game: `GetInstanceInfo`/LFG), bosses from `DungeonEncounter.csv` (forever_src) ⚠, loot ✗ | ✗ |
| 7 | Remember the last dungeon/tab/selection per session; scroll positions kept on repaint | P0 | – | partly |
| 8 | Key binding (`Bindings.xml`), `/fdm journal`, Addon Compartment | P1 | – | compartment ✔ |
| 9 | Header icons: "Show entrance" (opens the world map with the entrance pinned) and LFG eye (opens Group Finder) | P1 / P2 | `DUNGEONS.cont/cx/cy/entrance` ✔ | ✔ |
| 10 | Level colouring everywhere (dungeons, quests, bosses) | P0 | `d.min/max`, `QUEST_INFO.lvl/req`, `BOSS_LEVELS` | ✔ |

### 2.2 Bosses & loot

| # | Feature | Pri | Data | Have? |
|---|---|---|---|---|
| 11 | Boss list: round portrait, level badge, order number, rare tag, defeated state (desaturated + red X) | P0 | `BOSSES[i].display` ✔ (a few missing → EJ default), `BOSS_LEVELS` ✔, `rare` ✔, kills (`Core.lua`) ✔ | ✔ |
| 12 | Boss header: portrait 72, name, "Boss i of n · Level 21 Elite/Rare elite/Boss", EJ creature picture, Show on map | P0 | `BOSS_LEVELS[...][3]` rank ✔, `BOSS_ART` ✔, `BossPositions` ✔ | ✔ |
| 13 | **Loot list must render** (currently empty; see §6.1 – probably `GetItemInfo` is nil in 16001) | **P0** | `BOSSES[i].loot` ✔ (206 bosses with loot) | ✔ |
| 14 | Loot row: icon + quality frame, quality-coloured name, "Slot, Type", GameTooltip on hover (with compare), **Shift-click = chat link**, **Ctrl-click = try on** (`DressUpItemLink`), "Loading…" until cached, then refills itself | P0 | `C_Item.GetItemInfo`, `C_Item.GetItemInfoInstant` | runtime |
| 15 | "You have it" tag (bags + bank) | P1 | `C_Item.GetItemCount(id, true)` | runtime |
| 16 | Favourites: right-click a loot row → ★; home ★ popup lists favourites → click opens the source boss | P1 | SavedVariables `favourites[itemID]={instance,boss}` | ✗ (new) |
| 17 | Compact loot view (30 px rows) toggle | P2 | – | – |
| 18 | Loot filter (usable by class, armour type, slot, stats) | P2 | `C_Item.GetItemInfoInstant` classID/subclassID, `C_Item.GetItemStats` | runtime |
| 19 | Shared loot / unique trash drops section | P2 | ✗ not in our data (DungeonMaster has none; would need cMaNGOS `creature_loot_template`) | ✗ |
| 20 | Boss → related quests (quests that need this boss) | P1 | heuristic name match ✔; better: QuestieDB `objectives` creature IDs (field 10) vs `npcID` | partly |

### 2.3 Quest list

| # | Feature | Pri | Data | Have? |
|---|---|---|---|---|
| 21 | Quest row: state icon, title in difficulty colour, "Available from Level N" (red if you are below), faction crests, class icon, ✓ done, big ? + "Turn in" when ready | P0 | `QUESTS` (faction, classes) ✔, `QUEST_INFO.req/lvl` ✔, state at runtime: `C_QuestLog.IsQuestFlaggedCompleted`, `C_QuestLog.GetLogIndexForQuestID`, `C_QuestLog.ReadyForTurnIn` ⚠ / `IsComplete` | ✔ |
| 22 | Sorted single list, **no group sub-headers** (the old headers overlapped rows, 13.png). Order: ready to turn in → in log → available → locked (needs previous) → completed → other faction/class (greyed) | P0 | – | – |
| 23 | Title row "Quests  7" (count after the filter) | P0 | – | ✔ |
| 24 | Faction toggle buttons (default: own faction on, other off); empty state "No Horde quests recorded for this dungeon." | P0 | `q.faction` | ✔ |
| 25 | Chain icon after the level text. Tooltip **"Required Quests" / "Click to show the whole quest chain"**. Click expands the chain **inline** under the row | P0 | `q.pre` (ordered) ✔, names `QUEST_NAMES` ✔ | ✔ |
| 26 | Inline chain lines "1. A Recipe For Death ✓", "In log" tag, a pin icon per step = **where to pick up that step**. Clicking a step opens that step's quest page (Starts at / Turn in / Show on Map) | P0 | `QUEST_INFO[preID].start/finish` ✔ (`import_questie.py` also covers `pre` IDs) | ✔ |
| 27 | "In Dungeon" icon (quest starts inside: NPC/object/item drop in the dungeon). Tooltip "In Dungeon" | P0 | `QUEST_INFO.start.inside` ✔, `q.inside` ✔, `q.drop` ✔ | ✔ |
| 28 | Track button → small movable tracker of this dungeon's quests in your log with objective progress; "Tracking" while on | P1 | runtime `C_QuestLog.GetQuestObjectives(id)` | runtime |
| 29 | Class quests: only your class by default (option: all classes) | P1 | `q.classes` ✔ | ✔ |
| 30 | Repeatable quests collapsed behind "Show repeatable quests (n)" | P2 | QuestieDB `specialFlags` (field 24, bit 1) ✗ not imported | ✗ |

### 2.4 Quest page (parchment)

| # | Feature | Pri | Data | Have? |
|---|---|---|---|---|
| 31 | Header: title, "Available from Level 13", faction crests, class icon, ✓ when done; **Share** (enabled only if in log + in a group + pushable) | P0 / Share P1 | `QUEST_INFO.req` ✔; Share: `C_QuestLog.IsPushableQuest(id)` ⚠, `C_QuestLog.SetSelectedQuest(id)` + `QuestLogPushQuest()` (both non-protected, wrap in `pcall`) | ✔ |
| 32 | Objective text; live progress lines when in log ("0/20 Deviate Hides") | P0 / P1 | `q.objective` ✔; progress at runtime | ✔ |
| 33 | **Starts at**: NPC/object name, zone, (x, y); **Show on Map** button. For item-started quests, an **item button** (icon, name, tooltip) + "In Dungeon" icon, "Drops from <boss>" | P0 | `QUEST_INFO.start` ✔ (kind/name/map/x/y/inside/dropBy). **Missing: `itemID` for item starts** → extend `import_questie.py` (QuestieDB `startedBy[3]` = item IDs) | partly |
| 34 | **Turn in**: NPC, zone (x, y); **Show Turn In** button | P0 | `QUEST_INFO.finish` ✔ | ✔ |
| 35 | Required quests list (numbered, ✓ done, each clickable → that step's page), button "Show quest chain" (expands it in the list and scrolls to it) | P0 | `q.pre` ✔ | ✔ |
| 36 | Leads to (follow-up quest) | P2 | QuestieDB `nextQuestInChain` (22) / `childQuests` (14) ✗ not imported | ✗ |
| 37 | **Notes** (hand-written tips; may contain item buttons, e.g. "Its follow-up offers: [Talbar Mantle] [Quagmire Galoshes]") | P1 | ✗ → new **`Data/Notes.lua`** written by us: `[questID] = { text = "...", items = {...} }` | ✗ |
| 38 | Rewards: "Choose one reward" / "Rewards" / "You will also receive:"; item plates in 2 columns | P0 | `q.choices`, `q.rewards` ✔ | ✔ |
| 39 | **XP pill** | P1 | ✗ **not in our data, and not in QuestieDB** (its `questKeys` 1–36 have no XP/money). Sources: (a) **runtime learn + cache**: `GetQuestLogRewardXP(questID)` while the quest is in the log ⚠ signature, `GetRewardXP()` on `QUEST_DETAIL`/`QUEST_COMPLETE` → `ForeverDungeonMapDB.questReward[id] = {xp=, money=}`; (b) **offline**: cMaNGOS classic-db `quest_template.RewMoneyMaxLevel` (GPL) → `fullXP = RewMoneyMaxLevel / 0.6` for quest level ≤ 60, scaled down by the player/quest level difference like the server; mark it "≈". WoW Forever changed some XP values, so runtime values win; (c) Questie's main repo may have a quest-XP table (⚠ verify licence and format) | ✗ |
| 40 | **Money pill** | P1 | ✗ same sources: `GetQuestLogRewardMoney(questID)` ⚠ / `GetRewardMoney()`; offline cMaNGOS `RewOrReqMoney` | ✗ |
| 41 | Reputation pills ("+250 Orgrimmar") | P2 | QuestieDB `reputationReward` (field 26) ✔ in the source, ✗ not imported | ✗ |
| 42 | Required items / provided item | P2 | QuestieDB `requiredSourceItems` (21), `sourceItemId` (11) ✗ not imported | ✗ |
| 43 | Shift-click the title → quest link in chat (only if in log: `GetQuestLink`), else plain `[name]` | P2 | runtime | – |

### 2.5 Map

| # | Feature | Pri | Data | Have? |
|---|---|---|---|---|
| 44 | **Map tab inside the journal**: map art, floor selector, round boss pins, "Entrance" pin, hover tooltip, click pin → boss page | P0 | client art (`DUNGEONS.art/floors`) ✔, `BossPositions` ✔ (15 dungeons), entrance ✔ | ✔ |
| 45 | "Boss icons 90% − +" control (0–100 %, step 10, default 90, saved account-wide), shared by the journal map and the M-map overlay | P1 | SavedVariables | ✗ |
| 46 | Show quest giver / turn-in on the zone map (+ TomTom waypoint) | P0 | `QUEST_INFO` ✔ | ✔ |
| 47 | Forever dungeons without client map art: show FDJ's map at runtime if FDJ is installed (`Compat_FDJ.lua`); otherwise a "no map yet" card on the dungeon's loading screen with the boss list as numbered chips | P1 | `Compat_FDJ` ✔ | ✔ |
| 48 | Quest objects/NPCs inside the dungeon as map pins | P2 | QuestieDB spawns with dungeon `zoneID` ✗ | ✗ |

### 2.6 Cross-cutting

| # | Feature | Pri | Notes |
|---|---|---|---|
| 49 | Hover = gold border, everywhere (§0.4) | P0 | `W.Hoverable` |
| 50 | Solid tooltip backing for tooltips opened from our frames | P1 | §0.4 |
| 51 | Event-driven refresh (`QUEST_LOG_UPDATE`, `QUEST_TURNED_IN`, `GET_ITEM_INFO_RECEIVED`, `ITEM_DATA_LOAD_RESULT`, `BOSS_KILL`), coalesced to 1 repaint per 0.25 s, keeping scroll and hover | P0 | partly done |
| 52 | Localisation of UI strings (`L` table) | P2 | – |

**Top P0 items for the next version:** #13 loot renders, #49 hover border, the new visual skin (§0), #21–#27 quest list incl. the inline chain with pick-up spots, #31–#35 + #38 the quest page sections, #44 the journal Map tab, #11–#12 boss list/header, #1 home cards, #22 no overlapping group headers.

---

## 3. Journal window – layout

Coordinates are offsets from the window's TOPLEFT (x right, y down). Sizes are in UI units at scale 1.

```
 860 x 600  ─ gold dialog border (edge 32, insets 11) ──────────────────────────────────────
 |  [🔍 Search dungeons, bosses, items…    ]      ╔═ Dungeon Journal ═╗          [★] [X] |  y 18..42
 |  [◄ Dungeons]                                                                          |  y 50..72
 |  ───────────────────────────── gold hairline (UI-TooltipDivider) ──────────────────────|  y 78
 | ┌ header band: dungeon art strip + left→right dark gradient ──────────────────────────┐ |  y 84..148
 | │ (◉) Wailing Caverns   (◎)(👁)                       [🗺 Map] [💀 Bosses] [! Quests] │ |
 | │ 44  Level 15-24 · 8 bosses · 9 quests                                               │ |
 | └─────────────────────────────────────────────────────────────────────────────────────┘ |
 | ┌ list panel 344 ───────────────┐  ┌ detail panel 474 ──────────────────────────────┐ |  y 156..584
 | │ Bosses                         │  │ (portrait) Verdan the Everliving   [EJ art]     │ |
 | │ ═══════════                    │  │  21        Boss 7 of 8 · Level 21 Elite         │ |
 | │ [(o) Lord Cobrahn        1 ]  ▲│  │ ═══════════════════════════════════════════    │ |
 | │ [(o) Lady Anacondra      2 ]  █│  │ Loot  3                                        │ |
 | │ [(o) Kresh               3 ]  ││  │ [▣ Seedcloud Buckler        Off Hand, Shield ★]│ |
 | │ ...                            ││  │ [▣ Living Root              Two-Hand, Staff   ]│ |
 | │                               ▼│  │ Quests for this boss …     [Show on map]       │ |
 | └────────────────────────────────┘  └────────────────────────────────────────────────┘ |
 ────────────────────────────────────────────────────────────────────────────────────────────
```

### 3.1 Window frame

| Property | Value |
|---|---|
| Frame | `CreateFrame("Frame","ForeverDungeonMapJournal",UIParent,"BackdropTemplate")`, **860×600**, `CENTER 0,10`, strata `DIALOG`, `SetToplevel(true)`, movable by dragging the top 44 px only (`RegisterForDrag` on a 44 px drag-handle child), clamped |
| Backdrop | bg: rock 374155 as a separate tiled texture (`BACKGROUND`, inset 11) or `bgFile` 312922 tile 32; edge 131076 edgeSize 32, insets 11/11/11/11 |
| Vignette | `ShadowOverlay-*` around the inside (alpha 0.6) |
| Title ribbon | texture 131080, 300×64, `TOP 0,13`; FontString `GameFontNormal` "Dungeon Journal" at ribbon `TOP 0,-14` |
| Close | `UIPanelCloseButton` at `TOPRIGHT -5,-5` |
| Favourites | 24×24 button at `TOPRIGHT -40,-18`, icon 922035, tooltip "Favourites" (P1) |
| Search | `SearchBoxTemplate` 250×20 at `TOPLEFT 24,-20` |
| Back / filter row | y −50, height 22. Page: "◄ Dungeons" gilded tab 120×22 at `TOPLEFT 20,-50`. Home: chips All/Classic/Forever 80×22 (gap 4), at right "Your level: 25" `GameFontNormal` at `TOPRIGHT -24,-54` |
| Hairline | `UI-TooltipDivider` 609615, `TOPLEFT 18,-76` → `TOPRIGHT -18,-76`, height 4 |
| Body | `TOPLEFT 16,-156`, `BOTTOMRIGHT -16,16` → 828×428 |

### 3.2 Header band (`TOPLEFT 16,-84`, `TOPRIGHT -16,-84`, height 64)

| Layer | Spec |
|---|---|
| Frame | BackdropTemplate, bg `INK`, edge 137057 size 12 colour `EDGE_PANEL` |
| Art | `ART[id].bg` (or the loading screen for Forever dungeons) inset 3, `SetTexCoord(bgCoords)`, alpha 0.75 |
| Gradient | WHITE8X8 `SetGradient("HORIZONTAL", 0,0,0,0.92 → 0,0,0,0.25)` over the left 70 %; solid 0.25 over the rest |
| Round icon | 44×44 at `LEFT 10,0`: icon texture (LFGIcon or loading-screen crop) + mask 130924 + ring 652158 |
| Name | `QuestTitleFontBlackShadow`, `GOLD`, `TOPLEFT 62,-12`, single line, max width 360 |
| Sub-line | `GameFontHighlightSmall` at name `BOTTOMLEFT 0,-4`: "Level 15–24" (level colour) · "8 bosses · 9 quests" (`MUTED`) · "WoW Forever" (`FOREVER`) · "You are here" (`DONE`) |
| Round action icons | 22×22 each, after the name (`LEFT` name `RIGHT +10,0`, gap 6): ◎ "Show entrance on map" (atlas `Dungeon` ⚠ / LFGIcon-Dungeon 136334 masked), 👁 "Find group" (`Interface\LFGFrame\LFG-Eye` 136317, texcoord first frame `0,0.125,0,0.25` ⚠) P2. Ring 519888 around each; hover ring 652157 |
| Tabs | 3 gilded tabs 108×30, right-aligned: Quests `RIGHT -10,0`, Bosses left of it −6, Map left of it −6 |

**Gilded tab** (also used for "◄ Dungeons" and the filter chips):
BackdropTemplate, bg `ROW`, edge 137057 size 12 colour `EDGE`; icon 20×20 at `LEFT 8,0`; label `GameFontNormal` at icon `RIGHT +6,0`.
Hover: §0.4. **Selected**: bg `ROW_SEL`, edge `GOLD_SOFT`, label white, 2 px gold underline at the bottom inside the border (`GOLD_SOFT`, alpha 0.9). Pressed: offset +1,−1.
Icons: Map = `INV_Misc_Map_01`; Bosses = skull 137025; Quests = 132049. The Quests tab shows a count: "Quests 9".

### 3.3 Body: list panel (left)

| Property | Value |
|---|---|
| Panel | `TOPLEFT body 0,0`, width **344**, full height (428). bg `INK`, edge 137057/12 `EDGE_PANEL`, inner vignette |
| Title | `GameFontNormalLarge` `GOLD` at `TOPLEFT 12,-11` ("Bosses" / "Quests") + count `GameFontHighlight` ("7") 8 px right of it |
| Title divider | 609615 at `TOPLEFT 8,-34` → `TOPRIGHT -8,-34`, height 4 |
| Quests title extras | right side, vertically centred on the title: **faction toggles** 36×30 (`TOPRIGHT -10,-6`, Alliance left of Horde, gap 4); **Track** gold action button 70×22 left of them (gap 8) |
| Scroll frame | `UIPanelScrollFrameTemplate`, `TOPLEFT 8,-40`, `BOTTOMRIGHT -28,8` → visible 308×380 |
| Content | width **308** (fixed: set before measuring text) |
| Row spacing | 4 px; first row at y 0 |
| Wheel step | one row (60 px bosses / 52 px quests) |
| Scroll bar | hidden when content ≤ visible height (`ScrollBar:SetShown`), rows keep their width |
| Empty state | `GameFontDisable` centred, 20 px from the top: "No bosses known." / "No Alliance quests recorded for this dungeon." |

### 3.4 Body: detail panel (right)

| Property | Value |
|---|---|
| Panel | `TOPLEFT list TOPRIGHT +10,0`, `BOTTOMRIGHT body` → **474×428** |
| Boss mode | bg `INK`, edge `EDGE_PANEL`; lore watermark `ART.lore` inset 4, alpha 0.18, desaturated 0.3; scroll `TOPLEFT 12,-12`, `BOTTOMRIGHT -28,12` → content width **434** |
| Quest mode | parchment: texture 530420 inset 4 (no tint), edge 137057/12 colour `0.45,0.33,0.18`; **fixed header** (not scrolling) 64 px; scroll `TOPLEFT 18,-70`, `BOTTOMRIGHT -30,14` → content width **426** |
| Map mode | list + detail are hidden; the map panel fills the whole body (§3.10) |

### 3.5 Boss row (list)

```
┌──────────────────────────────────────────────────────────────┐ 308 x 56
│ ╭────╮                                                  ┌─┐ │
│ │ 46 │  Lord Cobrahn                                    │1│ │  order number
│ ╰─(20)  Rare · Defeated                                 └─┘ │
└──────────────────────────────────────────────────────────────┘
```

| Element | Spec |
|---|---|
| Frame | Button + BackdropTemplate, 308×56, `W.Hoverable` |
| Portrait | 46×46 at `LEFT 6,0`: `SetPortraitTextureFromCreatureDisplayID` (pcall) → masked 130924; ring 652158 over it (52×52, centred); fallback EJ default 521744 |
| Level badge | 24×24 centred on the portrait's `BOTTOMLEFT +6,+4`: dark disc (mask 130924 with colour `0.06,0.05,0.04`) + ring 519888, number `NumberFontNormalSmall` in the level colour |
| Name | `GameFontHighlight` (`TEXT`), `LEFT portrait RIGHT +12,+7`, right edge −34, no wrap. Defeated → `MUTED` |
| Sub | `GameFontHighlightSmall` (`MUTED`) under the name −2: "Rare" (`0.75,0.75,1`), "Defeated" (`DEFEATED`), else "3 drops" |
| Order number | 18×18 at `RIGHT -8,0`: `NumberFontNormalSmall` `MUTED` in a 1 px `EDGE` square; selected → `GOLD` |
| Defeated | portrait desaturated + vertex 0.55, X 136813 at 70 % over the portrait |
| Click | select (detail shows the boss); double-click → Map tab focused on the boss (P1) |

### 3.6 Boss detail header (right panel, boss mode)

| Element | Spec |
|---|---|
| Block | 96 px tall |
| Portrait | 72×72 at `TOPLEFT 4,-4` (same parts as the row, ring 80×80); level badge 30×30 |
| Name | `QuestTitleFontBlackShadow` `GOLD` at `TOPLEFT 92,-14`, right edge = the EJ art's left −8 |
| Info | `GameFontHighlight` `MUTED` under the name −6: "Boss 7 of 8 · Level 21 Elite" (rank 1 Elite, 2 Rare Elite, 3 Boss) · "Defeated" |
| EJ creature picture | `BOSS_ART[name]`, 160×80 at `TOPRIGHT -4,-6`, alpha 0.95, a 1 px `EDGE` frame (P2: paper frame 527690); hidden if missing |
| Buttons | under the info line: gold action button "Show on map" 120×22 (only with a known position) |
| Divider | 609615 at y −100 |
| Section heading | "Loot  3": `GameFontNormalLarge` `GOLD` + count `GameFontHighlight`; right side (P2): compact/detailed toggle, loot-filter funnel |
| After the loot | "Quests for this boss" heading + compact quest rows (308-style rows, but 434 wide, 40 px) – P1 |

### 3.7 Loot row

```
┌────────────────────────────────────────────────────────────────────────────┐ 434 x 46
│ ┌──┐ Seedcloud Buckler                                       ★  You have it│
│ │36│ Off Hand, Shield                                                      │
│ └──┘                                                                       │
└────────────────────────────────────────────────────────────────────────────┘
```

| Element | Spec |
|---|---|
| Frame | Button + Backdrop 434×46, gap 4, `W.Hoverable`, `RegisterForClicks("LeftButtonUp","RightButtonUp")` |
| Icon | 36×36 at `LEFT 6,0`; quality frame 651080 at 38×38 tinted by quality (hidden for quality ≤ 1); hover 130718 ADD |
| Name | `GameFontNormal`, quality colour, `TOPLEFT icon TOPRIGHT +10,-3`, right −90, no wrap |
| Sub | `GameFontHighlightSmall` `MUTED`: "<slot>, <subtype>" (`_G[equipLoc]`), or the item class for non-equipment |
| Right | ★ 16×16 (`FavoritesIcon`, shown if favourite), "You have it" `GameFontNormalSmall` `DONE` (P1) |
| Loading | name "Loading…" `MUTED`; refill on `ITEM_DATA_LOAD_RESULT(itemID, success)` / `Item:ContinueOnItemLoad`; on `success == false` show "Unknown item #id" and keep the row |
| Tooltip | `GameTooltip:SetOwner(self,"ANCHOR_RIGHT")`, `SetItemByID(id)`, `Show()`; Shift held → `GameTooltip_ShowCompareItem()` |
| Clicks | Shift-left → `ChatEdit_InsertLink(link)`; Ctrl-left → `DressUpItemLink(link)`; right → toggle favourite (P1) |
| Compact (P2) | 434×30, icon 24, name only, sub moves to the right |

### 3.8 Quest row (list) + inline chain

```
┌─────────────────────────────────────────────────────────────┐ 308 x 48 (collapsed)
│  !   The New Plague                              (A)(H)  ✓  │
│      Available from Level 16  ⛓ ◎                           │
│   ┌──────────────────────────────────────────────────────┐  │ + inline chain
│   │ 1. A Recipe For Death  ✓                          📍 │  │   10 + n*18 + 6
│   │ 2. A Recipe For Death  ✓                          📍 │  │
│   │ 3. A Recipe For Death     In log                  📍 │  │
│   └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

| Element | Spec |
|---|---|
| Frame | Button + Backdrop, width 308, height 48 collapsed / `48 + 10 + n*18 + 10` expanded; `W.Hoverable` |
| State icon | 22×22 at `TOPLEFT 8,-8`: available 132049; locked 132049 desaturated alpha 0.5; in log (incomplete) 365195; in log (complete) 132048; done 132049 at alpha 0.6 |
| Title | `GameFontNormal`, `TOPLEFT 38,-8`, right −76, no wrap. Colour: `GetQuestDifficultyColor(lvl)`; done → `DONE`; other faction/class → `MUTED` |
| Sub | `GameFontHighlightSmall` `MUTED` under the title −3: "Available from Level 13"; red `1,0.3,0.3` if player level < req |
| Chain toggle | 16×16 (`Media\Chain.tga`) right after the sub text (`LEFT sub +GetStringWidth()+6`). Hover: ring glow + tooltip **"Required Quests"** (gold) / **"Click to show the whole quest chain"** (white). Click toggles the expansion (state kept per quest ID for the session) |
| In Dungeon | 14×14 after the chain toggle (gap 4) or after the sub text; tooltip **"In Dungeon"** + "This quest starts inside the dungeon." |
| Right cluster | from `TOPRIGHT -8,-8` leftwards: done ✓ 136814 20×20; faction crests 18×18 (both if neutral), class icon 18×18 (`Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes` + `CLASS_ICON_TCOORDS` ⚠ verify) |
| Ready to turn in | replaces the right cluster: big round ? (132048, 30×30 at `TOPRIGHT -10,-9`) + "Turn in" `GameFontHighlight` `DONE` left of it. Click the ? → Show Turn In |
| Chain panel | inset at `TOPLEFT 38,-46`, right −8, bg `0,0,0,0.35`, edge 137057/10 `EDGE`; lines 18 px from y −5: bullet 136788 10 px + "1. <name>" `GameFontHighlightSmall`; ✓ 12×12 after the name if done (name `DONE`); "In log" `GameFontNormalSmall` gold at right −22; **pick-up pin** 14×14 at `RIGHT -4,0` (`Interface\WorldMap\UI-WorldMap-QuestIcon` 346294 ⚠ texcoord, or a gossip ! icon) → `Journal:ShowLocation(QUEST_INFO[id].start)`; its tooltip shows "Starts at: Mebok Mizzyrix, Ratchet (62.4, 37.6)" |
| Chain line hover | `GOLD` 0.10 fill, text white; click → select that step: the right page shows the **step's** page (title + "Step 2 of 4 – part of The New Plague" + Starts at / Turn in / Show on Map + "Back to The New Plague") |
| Selection | §0.4 selected; the selected step inside an open chain gets a `GOLD` 0.18 fill |

### 3.9 Quest page (parchment, right panel in quest mode)

Fixed header (64 px, not scrolling):

| Element | Spec |
|---|---|
| Title | `QuestTitleFont` `PARCH_HEAD`, `TOPLEFT 18,-14`, right −130, one line (truncate) |
| Meta | `QuestFont` `PARCH_MUTED` under the title −4: "Available from Level 13"; then faction crests 20×20 + class icon 20×20 (gap 4) |
| Share | gold action button 80×22 at `TOPRIGHT -40,-12`; disabled (greyed) unless in log + grouped + pushable; tooltip explains why |
| Done | ✓ 136814 24×24 at `TOPRIGHT -12,-11` |
| Break | `UI-HorizontalBreak` 136783 at `TOPLEFT 12,-56` → `TOPRIGHT -12,-56`, height 12 |

Scrolling body, sections **in this order** (each section is skipped if it is empty). Section spacing 12 px. Heading height 20. Body text measured after `SetWidth(426)`.

| # | Section | Content |
|---|---|---|
| 1 | **Objective** | `QuestFont` text. If in log: progress lines with bullet 136788, "0/20 Deviate Hides" (complete lines `DONE`, alpha 0.7). Optional "Show on Map" (P2) |
| 2 | **Starts at** (+ "In Dungeon" 14 px icon after the heading) | NPC/object: "Nalpak" (bold via `QuestFontHighlight` ⚠) + "\n" + "above the entrance to Wailing Caverns, The Barrens (73.4, 25.9)". Item: **item button** 230×38 (dark inlay `PARCH_ROW`, icon 30, name quality colour, tooltip, shift-link) + "Drops from Mutanus the Devourer". Then gold action button **"Show on Map"** 112×22 |
| 3 | **Turn in** | same text format; button **"Show Turn In"** 112×22 |
| 4 | **Required quests** | numbered lines (bullet + "1. Raptor Horns ✓"), each a link-coloured button (`0.10,0.28,0.55`, hover underline + `GOLD` glow) → opens that step; trailing line "n. <this quest> (this quest)" in `PARCH_HEAD`; button "Show Quest Chain" 132×22 → expands the chain in the list and scrolls it into view |
| 5 | **Notes** (P1) | `QuestFont` text from `Data/Notes.lua`; optional item plates (same as the rewards) |
| 6 | **Rewards** | heading "Choose one reward" (`q.choices`) or "Rewards"; item plates 2 per line; a second block "You will also receive:" for `q.rewards` when choices also exist; then the **pill row**: XP pill, money pill, rep pills (P2) |

**Reward item plate** (classic quest-frame look, our own composition): 206×42, two columns with an 8 px gap.
Icon 36×36 at `LEFT 2,0` with quality frame 651080 and slot backing 130841. Name plate 136796 at `LEFT icon RIGHT -6,0`, size 168×42 (texcoord ⚠ ~`0,0.85,0.12,0.88`). Name `GameFontHighlightSmall` (wraps to 2 lines), quality colour (white → `TEXT`), at `LEFT icon RIGHT +6,0`, right −6.
Hover: gold border overlay (1 px `GOLD` frame) + `UI-QuestItemHighlight` 136795 ADD. Clicks as in the loot row.

**Pills** (height 26, gap 8, left-aligned):

| Pill | Spec |
|---|---|
| XP | Backdrop bg `PARCH_ROW`, edge 137057/10 colour `GOLD_SOFT`; left glyph = XP icon 894556 at 20×20 (`LEFT 4,0`, texcoord `0.08,0.92,0.08,0.92`), fallback the text "XP" `GameFontNormalSmall` in colour `XP`; value `GameFontHighlight` "1,600 XP" (`BreakUpLargeNumbers`); width = text + 44. Tooltip "Experience (at your level)"; "≈" prefix if it comes from offline data |
| Money | the same frame, text `GetCoinTextureString(copper)` (Blizzard coin icons 237618/237620/237617) |
| Reputation (P2) | the same frame, faction name + "+250" in `DONE` |

### 3.10 Map tab (journal)

| Element | Spec |
|---|---|
| Panel | body rect (828×428), bg `0.03,0.025,0.02,1`, edge 137057/12 `EDGE_PANEL`, `SetClipsChildren(true)`; lore art `ART.lore` blurred backdrop at alpha 0.12 behind the map (fills the empty sides) |
| Map canvas | **shared `MapCanvas` widget** (extract it from `DungeonView.lua`): art 1002×668 (tiles 4×3 of 256) fitted to (828−16)×(428−16) → about 618×412, centred; wheel zoom 1–4× at the cursor, drag to pan, right-click = back to Bosses tab |
| Map frame | 1 px `EDGE_PANEL` line + `ShadowOverlay-*` around the art rect |
| Floor selector | top-left inside the panel: prev/next arrows 24×24 + floor name `GameFontNormal` (e.g. "The Graveyard 30-38"); hidden for 1 floor |
| Boss pins | §4.2 component, base size 40 × scale |
| Entrance pin | atlas `Dungeon` 18×18 (⚠ verify; fallback 136334 masked) + label "Entrance" `GameFontNormal` `GOLD` with shadow, left of the icon |
| Boss icon size | bottom-left 92×48 box: bg `INK`, edge `EDGE`; "Boss icons" `GameFontNormalSmall`; minus 18×18, "90%" `GameFontHighlightSmall`, plus 18×18. Range 0–100 % in 10 % steps; 0 % hides the pins; saved in `ForeverDungeonMapDB.bossIconScale` (shared with the M map) |
| No art | the loading-screen art (Forever) cropped to the panel at alpha 0.5 + `GameFontDisableLarge` "No map for this dungeon yet." + numbered boss chips in a row (P1) |
| Hint | bottom-right `GameFontHighlightSmall` `MUTED`: "Wheel: zoom · Drag: move · Right-click: back" |

### 3.11 Home page

| Element | Spec |
|---|---|
| Grid | scroll `TOPLEFT 16,-84`, `BOTTOMRIGHT -32,16`; **2 columns**, card **388×120**, gap 12 h / 10 v |
| Card | Button + Backdrop: bg `INK`, edge 137057/12 `EDGE`. Art `ART.card` (or the loading screen) inset 4. Top shade 0→0.55 black over the top 40 px; bottom gradient 0.9→0 over the bottom 56 px |
| Text | name `GameFontNormalLarge` `GOLD` at `TOPLEFT 14,-12`; counts `GameFontHighlight` at `TOPRIGHT -14,-12` ("✓ 9/9 quests" when all done – P1); level `GameFontHighlight` level-coloured at `BOTTOMLEFT 14,10`; "8 bosses" `MUTED` after it; round icon 40×40 at `BOTTOMRIGHT -12,10` (masked + ring); Forever emblem `FOREVER` "WoW Forever" small at the top-right under the counts; "You are here" in `DONE` |
| Hover | border `GOLD` + art brightened (vertex 1.15 → clamp) + 130718 ADD 0.15 |
| Sort | by `min` level, then name; the current instance first |

---

## 4. Dungeon map (world-map overlay, `DungeonView.lua`) – changes for consistency

### 4.1 Header bar (top of the map overlay, height 42)

* Use the **same header-band component** as the journal (§3.2), scaled to 42 px: round icon 32, name `QuestTitleFontBlackShadow`, sub-line "Level 15–24 · 8 bosses · 9 quests", the art strip behind it. No green or brown tint.
* Buttons: gilded tabs "Bosses & Loot" and "Quests (9)", **left-anchored** after the sub-line, max x = header width − 260. They must never reach the WorldMapFrame's own top-right controls: in 12.png/13.png our "Quests (9)" overlapped Blizzard's "World Map"/quest-log controls. If space is short, hide the labels and keep icon-only tabs (30×30) with tooltips.
* The floor selector moves into the header (right of the tabs): arrows + floor name.

### 4.2 Boss pin component (shared by the M map and the journal Map tab)

| Part | Spec |
|---|---|
| Size | 40 × `bossIconScale` (0–1, default 0.9) |
| Portrait | creature portrait masked 130924 |
| Ring | 652158 at 1.15× the size; hover 652157 + scale 1.1 (animated over 0.08 s, optional) |
| Order badge | 16×16 at `BOTTOMRIGHT +3,-3`: dark square, 1 px `GOLD_SOFT` border, number `NumberFontNormalSmall` (keep: the order is our addition, FDJ has none) |
| Defeated | desaturate + 136813 X |
| Tooltip | name (`GOLD`), "Boss 3 of 8 · Level 20 Elite", top 3 loot names in quality colours + "+2 more", "Click: loot & quests" |
| Click | left → `Journal:ShowBoss` (journal opens on the boss); right → map one level up (M map) / back (journal) |

### 4.3 Other overlay elements

* Entrance pin + label exactly as in §3.10.
* Boss icon size control bottom-left (same widget and setting as §3.10).
* Footer hint: `GameFontHighlightSmall`, keys in `GOLD`.
* Background around the art: same `0.03,0.025,0.02` + lore art at 0.12 (no flat brown).
* World-map entrance pins (`EntrancePins.lua`): round LFG icon 24 (masked + ring 519888), hover ring 652157 + tooltip "Wailing Caverns · Level 15–24 · Click: open journal".
* Live view (`LiveView.lua`): frame skin = the inset panel (`INK` + 137057 `EDGE_PANEL`), title in `GameFontNormal`, so it matches the journal.

---

## 5. WoW Forever dungeons (no Blizzard EJ art)

| Instance ID | Dungeon | Loading screen (`Interface\Glues\LoadingScreens\…`) | FDID | Round icon |
|---|---|---|---|---|
| 2959 | City of Dalaran | `camelot160\main\loadscreen_camelot_dalaran` | 7963775 ✔ | loading-screen crop |
| 2998 | Excavation Site: Wetlands | `camelot160\main\loadscreen_camelot_excavation` | 7963777 ✔ | crop |
| 2999 | Ruins of Lordaeron | `camelot160\main\loadscreen_camelot_ruinsoflordaeron` | 7963782 ✔ | **`Interface\LFGFrame\LFGIcon-RuinsofLordaeron` 460869 ✔** (or the crop) |
| 3065 | The Hall of Thanes | `camelot160\main\loadscreen_camelot_oldironforge` | 7963781 ✔ | crop |
| 2970 | The Drowned City | `expansion0\main\loadscreen_thedrownedcity_7963741` | 7963741 ✔ | crop |
| 2974 | Blackmaw Hold | `expansion0\main\loadscreen_blackmawhold_7963784` | 7963784 ✔ | crop |
| 2994 | Alcaz Prison | `expansion0\main\loadscreen_alcazprison_7963734` | 7963734 ✔ | crop |
| 3001 | The Shaper's Terrace | `expansion0\main\loadscreen_theshapersterrace_7963783` | 7963783 ✔ | crop |
| 3039 | Krol'dok Stronghold | `expansion0\main\loadscreen_kroldokstronghold_7963780` | 7963780 ✔ | crop |

The loading-screen FDIDs are confirmed by `Map.csv` (LoadingScreenID 647/691/650/693/695/692/690/696/694) → `LoadingScreens.csv` (MainImageFileDataID). WoW Forever logo: `camelot160\logo\logo_camelot` 7961223 ✔. Use it for the Forever emblem (filter chip icon, home card corner), scaled to 48×24 (⚠ verify its aspect).

How each surface uses the art (add `iconCoords` and `focus` per dungeon to `Data/Art.lua` from `make_art.py`):

| Surface | Classic dungeon | Forever dungeon |
|---|---|---|
| Home card (388×120 ≈ 3.2:1) | `UI-EJ-DungeonButton-*` | loading screen, texcoords around the focal band, e.g. `0.05,0.95,0.30,0.58` (aspect-correct for 388×120 on a 2:1 image ⚠ check each picture) |
| Header band (≈ 828×64) | classic loading screen strip `0,1,0.42,0.56` | the same loading screen, a thin strip through the focal point `0,1,f-0.05,f+0.05` |
| Round icon (32–44) | `LFGIcon-*` (already round) | **loading-screen square crop under the circle mask**: for a 2:1 image a full-height square is u∈[0.25,0.75]; zoom to the subject with the default `0.35,0.65,0.20,0.80`, then mask 130924 + ring 652158 |
| Lore watermark / map backdrop | `UI-EJ-LoreBG-*` | the loading screen, alpha 0.12–0.18, `SetDesaturation(0.3)` |
| Boss portraits | display IDs | display IDs; unknown → EJ default 521744 with a gold "?" (`GameFontNormalHuge`) |
| Boss header picture | `UI-EJ-BOSS-*` | none → hide; the name area takes the width |
| Map | client tiles | FDJ map at runtime if FDJ is installed (`Compat_FDJ`), else the "No map yet" card (§3.10) |

Mark Forever dungeons with a "WoW Forever" tag (`FOREVER` colour) in the header sub-line and on the cards.

---

## 6. Implementation notes & pitfalls

### 6.1 Bugs to fix first (from the user's complaints)

1. **No loot on the boss page.** `Canvas.lua` calls the global `GetItemInfo`, `GetItemInfoInstant` and `GetItemQualityColor`. On the 16001 client these may be gone (retail moved them to `C_Item.*`). Then `FillItem` raises an error at the first loot row and `RenderBoss` stops after the "Loot" heading. Fix: use local aliases `local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo`, the same for `GetItemInfoInstant`, `GetItemQualityColor` (`C_Item.GetItemQualityColor`), `GetItemCount`, `IsQuestFlaggedCompleted` (`C_QuestLog`). Confirm with `/console scriptErrors 1`. Also wrap each row's fill in `pcall` so one bad item cannot blank the page.
2. **Hover without a border.** Hover is only a `SetHighlightTexture` (faint on dark fills), and a repaint (`ns.Paint`) resets the colours. Fix: `W.Hoverable(f)` stores `f._hover` in `OnEnter`/`OnLeave` (`HookScript`) and every `Paint` goes through `f:ApplyVisual()`, which reads `_hover`, `_selected`, `_pressed` (§0.4).
3. **Quests "not as pretty"**: the group sub-headers overlapped rows (13.png), and the page lacked parchment structure. Fix: §2.3 #22 and §3.9.

### 6.2 Layout & text

* **Fixed widths first.** Set the width of a FontString (`SetWidth`) **before** `SetText` → `GetStringHeight()`; otherwise the height is for one line, or 0 on the first frame. Scroll children need an explicit `SetWidth` too; `GetWidth()` of a not-yet-laid-out frame is 0.
* **Fixed row heights.** Every row type has a constant height (or a height computed from fixed parts, like `48 + 10 + n*18 + 10` for chains). Never measure a frame after layout to place the next one.
* `SetWordWrap(false)` + `SetMaxLines(1)` on titles; long names get "…".
* After `SetFont`/`SetFontObject` changes, re-measure.
* Use `BreakUpLargeNumbers` for XP and `GetCoinTextureString` for money.

### 6.3 Frames, pooling, performance

* **Pool everything** (rows, chain lines, pills, item plates, pins) per kind. `Reset()` hides **and** `ClearAllPoints()` on every pooled frame; acquire re-anchors. Never `CreateFrame` per repaint.
* Coalesce repaints: one `C_Timer.After(0.25)` per burst of events. Keep the scroll offset (`Reset(true)`) and the hover state.
* Item data: `C_Item.RequestLoadItemDataByID(id)` + `ITEM_DATA_LOAD_RESULT` (or `Item:CreateFromItemID(id):ContinueOnItemLoad`). Guard the callback with `row.itemID == id and row:IsShown()`. Custom Forever items (IDs ≥ 250000) may never load: treat `success == false`.
* `BackdropTemplate` is required for `SetBackdrop` on the modern engine (`CreateFrame(..., "BackdropTemplate")`, or `Mixin(f, BackdropTemplateMixin)` + `OnBackdropSizeChanged`).
* Textures by **FDID** (`SetTexture(130924)`) do not depend on the path spelling; paths still work and are easier to read. Pick one per call site and keep it consistent.
* Masks: `local m = f:CreateMaskTexture(); m:SetTexture(130924, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); tex:AddMaskTexture(m)`. One mask per texture; when pooled, do not add it twice.
* Atlases (`SetAtlas`) can differ in this client: check `C_Texture.GetAtlasInfo(name)` and fall back to a file texture.
* `SetPortraitTextureFromCreatureDisplayID` is slow on first use and can return nothing for unknown display IDs: `pcall`, then fallback.

### 6.4 Taint & the world map

* Never call protected functions (`CastSpell`, `TargetUnit`, `UseAction`…). FDJ's "target the NPC when close" needs a secure button: do not copy that idea without a secure template. `QuestLogPushQuest` and `C_QuestLog.SetSelectedQuest` are fine (wrap in `pcall`).
* **Map pins**: the map canvas calls `SetPassThroughButtons` on pins, which is Blizzard-only. Override it, and `SetPropagateMouseClicks` / `CheckMouseButtonPassthrough`, as no-ops on our pin mixin (already done in `EntrancePins.lua`). Never call `SetPassThroughButtons` ourselves.
* Do not replace Blizzard functions (`C_Map.*`, `WorldMapFrame.*`); use `hooksecurefunc` / `HookScript` only. Call `WorldMapFrame:SetMapID` via `pcall` and only from a user action (the current `SetWorldMap`).
* Our overlay's frame levels: stay below 8800 (current `RaiseLayers`). Do not put our frames in `UISpecialFrames` while the world map is open (it would close the map too).
* In combat: opening/closing our own frames is fine (non-secure). Do not `Show()`/`Hide()` any secure frame and do not change bindings in combat (`InCombatLockdown()`).

### 6.5 Scrollbars

* `UIPanelScrollFrameTemplate`: anchor the scroll frame so the bar (≈ 20 px) lies inside the panel (right inset 28). Set `scrollFrame.scrollBarHideable = true`, or hide `ScrollBar` manually when `content:GetHeight() <= scroll:GetHeight()`.
* Wheel step = one row: `scroll:SetScript("OnMouseWheel", ...)` with `SetVerticalScroll(clamp(cur - delta*step))`.
* After a content-height change, call `scroll:UpdateScrollChildRect()`.

### 6.6 Data pipeline additions

| Change | Where |
|---|---|
| `start.itemID` for item-started quests | `tools/import_questie.py` (QuestieDB `startedBy[3]`) |
| `rep = {{factionID, value}}` (P2), `next = questID` (P2), `repeatable` (P2) | `tools/import_questie.py` (fields 26, 22, 24) |
| XP / money | new SavedVariables cache learned from the quest log / quest frames; optional offline table generated from cMaNGOS classic-db (GPL) into `Data/QuestRewards.lua` (our own generator, attribution in `THIRD_PARTY.md`) |
| Notes | new hand-written `Data/Notes.lua` |
| Forever dungeons 2970/2974/2994/3001/3039 | `Data/Dungeons.lua` + `tools/make_art.py` (loading screens above) + bosses from `DungeonEncounter.csv` |
| Single palette | `Theme.lua`: remove `MOODS`/`BY_DUNGEON`; export the §0.2 tokens and `W.Hoverable`, the gilded tab, pills, and plates as widgets in `Widgets.lua` |
