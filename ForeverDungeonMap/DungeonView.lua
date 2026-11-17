-- ForeverDungeonMap - dungeon view on the world map.
-- Inside a dungeon, opening the world map (M) shows the dungeon's own map (MapCanvas: art,
-- floors, zoom/drag, boss portraits; a boss opens its loot and quests in the Dungeon Journal).
-- Right-click goes one level out to the entrance's zone.
-- Taint: we never call WorldMapFrame:SetMapID; map changes go through ns.ShowWorldMap
-- (C_Map.OpenWorldMap, out of combat only).
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local W, C, TEX = ns.W, ns.C, ns.TEX

local HEADER_HEIGHT = 46
local ICON_SIZE = 34
-- Blizzard's round map buttons sit on the left edge of the canvas, over our header
local ICON_LEFT = 40
-- gap between the round icon and the name / sub-line, and after the longer of the two
local TEXT_GAP, TEXT_TO_TABS_GAP = 10, 16
local TITLE_RAISE = 2
-- header width to plan with before the header has been laid out
local FALLBACK_HEADER_WIDTH = 1000
-- inset of the header art inside the panel's border
-- how deep below the map canvas TopLevel looks for frame levels
local LEVEL_SCAN_DEPTH = 3
-- our view sits this many levels above the highest Blizzard layer; the header above the map
local LEVELS_ABOVE_BLIZZARD, HEADER_LEVEL_ABOVE_VIEW = 10, 20
local JOURNAL_TAB_WIDTH, QUEST_TAB_WIDTH, COMPACT_TAB_WIDTH, TAB_HEIGHT, TAB_GAP = 146, 112, 34, 30, 6
-- the "Dungeons" button on the right of the header
local DUNGEONS_BUTTON_WIDTH, HEADER_RIGHT_INSET = 120, 8
local RESERVED_RIGHT = DUNGEONS_BUTTON_WIDTH + 2 * HEADER_RIGHT_INSET
-- Blizzard changes the map right after opening it; that change must not close our view.
local OPEN_GRACE_SECONDS = 0.5
local EXPECTED_MAP_SECONDS = 2
local MAX_FRAME_LEVEL = 8800
local HINT = ns.KeyHint({ { "Right-click", "one map up" }, { "Wheel", "zoom" }, { "Drag", "move" } })

local View = {}
ns.View = View

local frame, map, header, headerArt, dungeonIcon, title, subtitle, journalTab, questTab, dungeonsButton

local state = { instanceID = nil, dungeon = nil, openedAt = 0, expectedMap = nil, expectedUntil = 0 }

local function Host() return WorldMapFrame and WorldMapFrame.ScrollContainer end
local function Bosses() return ns.BOSSES[state.instanceID] or {} end

-- The coming map change is ours: OnWorldMapChanged must not close the view for it.
local function ExpectMap(mapID)
    state.expectedMap, state.expectedUntil = mapID, GetTime() + EXPECTED_MAP_SECONDS
end

-- Move the world map underneath (user action only; in combat it waits until combat ends).
local function SetWorldMap(mapID)
    if not mapID or not WorldMapFrame then return end
    if WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == mapID then return end
    ns.ChangeOpenWorldMap(mapID, ExpectMap)
end

-- Highest frame level used inside a frame tree (pins, player layer...).
local function TopLevel(root, skip)
    local top = root:GetFrameLevel()
    local function Scan(parent, depth)
        if depth > LEVEL_SCAN_DEPTH then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= skip then
                top = math.max(top, child:GetFrameLevel())
                Scan(child, depth + 1)
            end
        end
    end
    Scan(root, 0)
    return top
end

local function CreateHeaderTexts()
    dungeonIcon = W.CreateRoundIcon(header, ICON_SIZE)
    dungeonIcon:SetPoint("LEFT", ICON_LEFT, 0)
    title = header:CreateFontString(nil, "OVERLAY", ns.Font("title"))
    title:SetPoint("TOPLEFT", dungeonIcon, "TOPRIGHT", TEXT_GAP, TITLE_RAISE)
    title:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
    title:SetWordWrap(false)
    subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("BOTTOMLEFT", dungeonIcon, "BOTTOMRIGHT", TEXT_GAP, 0)
    subtitle:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
end

local function CreateHeaderTabs()
    journalTab = W.Tab(header, "Bosses & Loot", TEX.SKULL, JOURNAL_TAB_WIDTH, TAB_HEIGHT)
    journalTab:SetScript("OnClick", function() ns.Journal:OpenDungeon(state.instanceID, "bosses") end)
    questTab = W.Tab(header, "Quests", TEX.QUEST_AVAILABLE, QUEST_TAB_WIDTH, TAB_HEIGHT)
    questTab:SetPoint("LEFT", journalTab, "RIGHT", TAB_GAP, 0)
    questTab:SetScript("OnClick", function() ns.Journal:OpenDungeon(state.instanceID, "quests") end)
end

-- "Dungeons" on the right: the Dungeon Journal's home page with every dungeon's card.
local function CreateDungeonsButton()
    dungeonsButton = W.Tab(header, ns.L["Dungeons"], TEX.LFG_DUNGEON, DUNGEONS_BUTTON_WIDTH, TAB_HEIGHT)
    dungeonsButton:SetPoint("RIGHT", -HEADER_RIGHT_INSET, 0)
    W.Mask(dungeonsButton, dungeonsButton.Icon)
    W.Tooltip(dungeonsButton, ns.L["Dungeons"], ns.L["Open the Dungeon Journal with every dungeon"])
    dungeonsButton:SetScript("OnClick", function() ns.Journal:ShowHome() end)
end

-- Header band: art strip, round icon, name, sub-line, the two gilded tabs and the Dungeons button.
local function CreateHeader()
    header = W.Panel(map.area)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    headerArt = W.CreateHeaderArt(header)
    CreateHeaderTexts()
    CreateHeaderTabs()
    CreateDungeonsButton()
end

-- The view frame on the map canvas and the map inside it (once).
local function CreateUI()
    if frame then return end
    local host = Host()
    frame = CreateFrame("Frame", "ForeverDungeonMapView", host)
    frame:SetAllPoints(host)
    frame:EnableMouse(true)
    frame:Hide()
    W.MarkOwned(frame)
    map = ns.MapCanvas.Create(frame, {
        top = HEADER_HEIGHT,
        onBoss = function(boss, index) ns.Journal:ShowBoss(state.instanceID, boss, index) end,
        onRightClick = function() View:GoUp() end,
        hint = HINT,
    })
    View.map = map
    CreateHeader()
end

-- Tabs right after the name/sub-line, never under the map's own top-right controls;
-- icon-only (with tooltips) when the space is short.
local function PlaceTabs()
    local width = header:GetWidth()
    local textWidth = math.max(title:GetStringWidth(), subtitle:GetStringWidth())
    local x = ICON_LEFT + ICON_SIZE + TEXT_GAP + textWidth + TEXT_TO_TABS_GAP
    local maximumX = (width > 0 and width or FALLBACK_HEADER_WIDTH) - RESERVED_RIGHT
    local compact = x + JOURNAL_TAB_WIDTH + TAB_GAP + QUEST_TAB_WIDTH > maximumX
    journalTab:SetSize(compact and COMPACT_TAB_WIDTH or JOURNAL_TAB_WIDTH, TAB_HEIGHT)
    questTab:SetSize(compact and COMPACT_TAB_WIDTH or QUEST_TAB_WIDTH, TAB_HEIGHT)
    W.SetTabCompact(journalTab, compact)
    W.SetTabCompact(questTab, compact)
    W.Tooltip(journalTab, compact and "Bosses & Loot" or nil, "Open the Dungeon Journal")
    W.Tooltip(questTab, compact and questTab.Label:GetText() or nil, "Quests of this dungeon")
    local tabsWidth = compact and (2 * COMPACT_TAB_WIDTH + TAB_GAP) or (JOURNAL_TAB_WIDTH + TAB_GAP + QUEST_TAB_WIDTH)
    journalTab:ClearAllPoints()
    journalTab:SetPoint("LEFT", header, "LEFT", math.min(x, maximumX - tabsWidth), 0)
end

-- Our layers above everything on the map canvas, in a fixed order.
local function RaiseLayers()
    local base = math.min(TopLevel(Host(), frame) + LEVELS_ABOVE_BLIZZARD, MAX_FRAME_LEVEL)
    frame:SetFrameLevel(base)
    map:SetBaseLevel(base + 1)
    header:SetFrameLevel(base + HEADER_LEVEL_ABOVE_VIEW)
end

-- Icon, art, name, "Level · bosses · quests · WoW Forever" and the quest count on the tab.
local function FillHeader(instanceID, dungeon)
    W.SetDungeonIcon(dungeonIcon, instanceID)
    W.SetHeaderArt(headerArt, instanceID)
    title:SetText(dungeon.name)
    local parts = { ns.RangeText(dungeon), ("%d bosses"):format(#Bosses()) }
    local questCount = #(ns.QUESTS[instanceID] or {})
    if questCount > 0 then parts[#parts + 1] = ("%d quests"):format(questCount) end
    if dungeon.forever then parts[#parts + 1] = ns.Hex(C.FOREVER) .. "WoW Forever|r" end
    subtitle:SetText(table.concat(parts, " · "))
    questTab.Label:SetText(questCount > 0 and ns.L["Quests (%d)"]:format(questCount) or ns.L["Quests"])
end

-- The buttons after the world map's nav bar follow our view (they hide while it is shown).
local function UpdateNavButtons()
    if ns.NavButtons then ns.NavButtons.Update() end
end

-- Show the map of an instance.
function View:Open(instanceID, name)
    if not Host() or not instanceID then return end
    CreateUI()
    local dungeon = ns.GetDungeon(instanceID, name)
    state.instanceID, state.dungeon = instanceID, dungeon
    state.openedAt = GetTime()
    View.lastShownInstanceID = instanceID
    FillHeader(instanceID, dungeon)
    RaiseLayers()
    frame:Show()
    PlaceTabs()
    map:SetDungeon(instanceID, name)
    UpdateNavButtons()
end

function View:Close()
    if frame and frame:IsShown() then frame:Hide() end
    UpdateNavButtons()
end

function View:IsShown() return frame ~= nil and frame:IsShown() end
function View:Layout() if map and self:IsShown() then map:Layout() end end
function View:FocusBoss(boss) if map then map:FocusBoss(boss) end end

-- One level out: to the zone with the dungeon entrance.
function View:GoUp()
    local entrance = state.dungeon and ns.GetEntrance(state.dungeon)
    self:Close()
    if entrance then SetWorldMap(entrance.map) end
end

-- Leave the dungeon view and mark a spot { map, x, y, title, text } on its zone map.
function View:ShowSpot(spot)
    if not (spot and spot.map and spot.x and spot.y) then return end
    self:Close()
    ns.SetHighlight(spot)
    -- the map opens on the spot's zone: do not cover it with the dungeon view. Only that
    -- opening: in combat the map stays closed, and a later M must show the dungeon again.
    if not WorldMapFrame:IsShown() then View.suppressOpenUntil = GetTime() + EXPECTED_MAP_SECONDS end
    if WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == spot.map then
        if ns.RefreshPins then ns.RefreshPins() end
    else
        SetWorldMap(spot.map)
    end
end

-- A boss died: redraw if visible.
function View:Refresh()
    if self:IsShown() then map:Layout() end
end

-- The world map opened: show the pending dungeon, or the one we are in.
local function OnWorldMapShown()
    local suppressed = View.suppressOpenUntil and GetTime() <= View.suppressOpenUntil
    View.suppressOpenUntil = nil
    if suppressed then return end
    -- inside a dungeon the map opens on our view unless the player turned that off
    local instanceID = View.pendingOpen or (ns.Setting("autoDungeonMap") and ns.instanceID or nil)
    View.pendingOpen = nil
    if instanceID then View:Open(instanceID, instanceID == ns.instanceID and ns.instanceName or nil) end
end

-- The player navigated the world map (nav bar, dropdown...): step aside. Changes Blizzard
-- makes right after opening and the ones we asked for are ignored.
local function OnWorldMapChanged()
    if not View:IsShown() then return end
    local now = GetTime()
    if now - state.openedAt < OPEN_GRACE_SECONDS then return end
    if state.expectedMap and now <= state.expectedUntil and WorldMapFrame:GetMapID() == state.expectedMap then
        state.expectedMap = nil
        return
    end
    View:Close()
end

-- Hooks on the world map (secure post-hooks: they never change Blizzard's map state).
local function Setup()
    if not WorldMapFrame or View.hooked then return end
    View.hooked = true
    WorldMapFrame:HookScript("OnShow", function()
        OnWorldMapShown()
        UpdateNavButtons()
    end)
    WorldMapFrame:HookScript("OnHide", function()
        View.lastShownInstanceID = nil
        View:Close()
    end)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        OnWorldMapChanged()
        UpdateNavButtons()
    end)
end

ns.OnLoad(function()
    local loadedLater = not WorldMapFrame
    ns.WhenWorldMapLoaded(function()
        Setup()
        -- the pins could not get on a map that did not exist yet
        if loadedLater and ns.SetupPins then ns.SetupPins() end
    end)
end)

ns.OnInstanceChanged(function(instanceID, name)
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    if not instanceID then View:Close() elseif ns.Setting("autoDungeonMap") then View:Open(instanceID, name) end
    UpdateNavButtons()
end)

ns.OnBossKilled(function() View:Refresh() end)
