-- ForeverDungeonMap - buttons after the world map's nav bar crumbs ("World > Kalimdor > ..."):
-- "Dungeons" (the Dungeon Journal's home page) always, and when there is a dungeon to offer, its
-- map and its quests. That dungeon is the one we are in, else the one shown last while the map is
-- open, else the one whose entrance is on the map shown (nearest the player's level).
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local _, ns = ...
local W, TEX, L = ns.W, ns.TEX, ns.L

local NavButtons = {}
ns.NavButtons = NavButtons

local GAP, HEIGHT, LEVELS_ABOVE_NAV = 4, 28, 5

local dungeonsButton, mapButton, questsButton

-- The dungeon whose entrance is on map `mapID`, nearest the player's level; nil when none.
local function DungeonOnMap(mapID)
    local level = UnitLevel("player") or 1
    local best, bestGap
    for instanceID, dungeon in pairs(ns.DUNGEONS) do
        local entrance = dungeon.min and ns.GetEntrance(dungeon)
        if entrance and entrance.map == mapID then
            local gap = math.abs((dungeon.min + dungeon.max) / 2 - level)
            if not bestGap or gap < bestGap then best, bestGap = instanceID, gap end
        end
    end
    return best
end

function NavButtons.Target()
    return ns.instanceID or ns.View.lastShownInstanceID or DungeonOnMap(WorldMapFrame:GetMapID())
end

local function DungeonName(instanceID)
    return ns.GetDungeon(instanceID, instanceID == ns.instanceID and ns.instanceName or nil).name
end

local function CreateButtons()
    dungeonsButton = W.Tab(WorldMapFrame, L["Dungeons"], TEX.LFG_DUNGEON, nil, HEIGHT)
    W.Mask(dungeonsButton, dungeonsButton.Icon)
    W.Tooltip(dungeonsButton, L["Dungeons"], L["Open the Dungeon Journal with every dungeon"])
    dungeonsButton:SetScript("OnClick", function() ns.Journal:ShowHome() end)
    mapButton = W.Tab(WorldMapFrame, "", TEX.LFG_DUNGEON, nil, HEIGHT)
    W.Mask(mapButton, mapButton.Icon)
    W.Tooltip(mapButton, L["Open the dungeon map"])
    mapButton:SetScript("OnClick", function(clicked) ns.View:Open(clicked.instanceID, DungeonName(clicked.instanceID)) end)
    questsButton = W.Tab(WorldMapFrame, "", TEX.QUEST_AVAILABLE, nil, HEIGHT)
    W.Tooltip(questsButton, L["Quests of this dungeon"])
    questsButton:SetScript("OnClick", function(clicked) ns.Journal:OpenDungeon(clicked.instanceID, "quests") end)
end

-- The dungeon's map and quests chips, or hidden when there is no dungeon to offer.
local function FillDungeonButtons(instanceID)
    mapButton:SetShown(instanceID ~= nil)
    questsButton:SetShown(instanceID ~= nil)
    if not instanceID then return end
    mapButton.instanceID, questsButton.instanceID = instanceID, instanceID
    mapButton.Label:SetText(DungeonName(instanceID))
    W.SetDungeonIcon(mapButton, instanceID)
    local questCount = #(ns.QUESTS[instanceID] or {})
    questsButton.Label:SetText(questCount > 0 and L["Quests (%d)"]:format(questCount) or L["Quests"])
    W.FitTab(mapButton)
    W.FitTab(questsButton)
end

-- In a row right after the last crumb (Blizzard rebuilds the crumbs on every map change).
local function PlaceButtons(navBar)
    local crumbs = navBar.navList
    local lastCrumb = crumbs and crumbs[#crumbs]
    dungeonsButton:ClearAllPoints()
    if lastCrumb then
        dungeonsButton:SetPoint("LEFT", lastCrumb, "RIGHT", GAP, 0)
    else
        dungeonsButton:SetPoint("LEFT", navBar, "LEFT", GAP, 0)
    end
    mapButton:ClearAllPoints()
    mapButton:SetPoint("LEFT", dungeonsButton, "RIGHT", GAP, 0)
    questsButton:ClearAllPoints()
    questsButton:SetPoint("LEFT", mapButton, "RIGHT", GAP, 0)
    for _, button in ipairs({ dungeonsButton, mapButton, questsButton }) do
        button:SetFrameLevel(navBar:GetFrameLevel() + LEVELS_ABOVE_NAV)
    end
end

-- Shown while the world map is open on a Blizzard map (our dungeon view has its own header).
function NavButtons.Update()
    local navBar = WorldMapFrame and WorldMapFrame.NavBar
    local shown = navBar ~= nil and WorldMapFrame:IsShown() and not ns.View:IsShown()
    if not shown then
        if dungeonsButton then
            for _, button in ipairs({ dungeonsButton, mapButton, questsButton }) do button:Hide() end
        end
        return
    end
    if not dungeonsButton then CreateButtons() end
    W.FitTab(dungeonsButton)
    dungeonsButton:Show()
    FillDungeonButtons(NavButtons.Target())
    PlaceButtons(navBar)
end
