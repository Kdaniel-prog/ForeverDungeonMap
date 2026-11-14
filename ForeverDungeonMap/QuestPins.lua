-- ForeverDungeonMap - world map pins where dungeon quests are picked up and turned in.
-- Zone maps show the quest givers ("!") and turn-in NPCs ("?") of every dungeon quest the
-- player can take or has in the log; continent maps show the same spots, converted.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local W, C, TEX, L = ns.W, ns.C, ns.TEX, ns.L

local QuestPins = {}
ns.QuestPins = QuestPins

local TEMPLATE = "ForeverDungeonMapQuestPinTemplate"
-- quest log events come in bursts: one rebuild this long after the last one
local REFRESH_DELAY = 0.5
local PIN_SIZE = 16
-- pin scale limits while zooming the map
local PIN_SCALE_MIN, PIN_SCALE_MAX = 0.9, 1.2
local HIGHLIGHT_SIZE = 22
local BADGE_SIZE = 9
local BADGE_RING_SIZE = 12
-- badge centre from the pin's bottom right corner
local BADGE_OFFSET_X, BADGE_OFFSET_Y = -1, 2
local TOOLTIP_ICON_SIZE = 14
local CONTINENT_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
-- how many parent maps up a zone may sit below the continent it is drawn on
local MAX_MAP_DEPTH = 4
local CLICK_HINT = L["Click: waypoint and arrow · Shift-click: Dungeon Journal"]
local UNKNOWN_NPC = L["Quest giver"]

-- quest state -> which end of the quest gets a pin
local WHICH_OF_STATE = { avail = "start", log = "finish", ready = "finish" }

-- built pin spots, nil when they need a rebuild
local spots

local function ForeverQuestInfo(questID)
    local quests = type(ns.FOREVER) == "table" and ns.FOREVER.quests
    local info = type(quests) == "table" and quests[questID]
    return type(info) == "table" and info or nil
end

-- the quest's own giver fields (Generated.lua), for quests started outside the dungeon
local function QuestFieldLocation(quest)
    if quest.inside or quest.drop or not (quest.map and quest.x and quest.y) then return nil end
    return { kind = "npc", name = quest.npc, map = quest.map, x = quest.x, y = quest.y }
end

-- Sources in order (all shipped or learned, never another addon): Questie, WoW Forever data,
-- learned in play, quest fields.
local LOCATION_SOURCES = {
    function(quest, which) local info = ns.QUEST_INFO and ns.QUEST_INFO[quest.id] return info and info[which] end,
    function(quest, which) local info = ForeverQuestInfo(quest.id) return info and info[which] end,
    function(quest, which) return ns.Learn.Location(quest.id, which) end,
    function(quest, which) return which == "start" and QuestFieldLocation(quest) or nil end,
}

-- World map spot { kind, name, map, x, y } (percent) where `quest` starts ("start") or is
-- turned in ("finish"); nil when it is inside the dungeon or unknown.
function QuestPins.Location(quest, which)
    for _, source in ipairs(LOCATION_SOURCES) do
        local location = source(quest, which)
        if type(location) == "table" then
            if location.inside then return nil end
            if location.map and location.x and location.y then return location end
        end
    end
end

-- Questie already puts "!" / "?" on the same NPCs when its "show dungeon quests" option is on;
-- two icons on one spot hide each other, so ours step aside (only its on/off setting is read).
local function QuestieShowsDungeonQuests()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if not (isLoaded and isLoaded("Questie")) then return false end
    local questie = _G.Questie
    local profile = type(questie) == "table" and type(questie.db) == "table" and questie.db.profile
    if type(profile) ~= "table" then return true end
    return profile.enabled ~= false and profile.showDungeonQuests ~= false
end

local function PinsEnabled()
    return ns.Settings.Get("questPins") ~= false and not QuestieShowsDungeonQuests()
end

-- grey dungeon: the player is above its level range (ns.RangeColor paints it grey)
local function IsGreyDungeon(instanceID)
    local dungeon = ns.DUNGEONS[instanceID]
    return dungeon ~= nil and dungeon.max ~= nil and (UnitLevel("player") or 1) > dungeon.max
end

local function CanPickUp(instanceID, quest)
    local requiredLevel = W.QuestRequiredLevel(quest)
    if requiredLevel and requiredLevel > (UnitLevel("player") or 1) then return false end
    return not IsGreyDungeon(instanceID)
end

-- { quest, instanceID, state, location } when the quest needs a pin now, else nil
local function QuestEntry(instanceID, quest)
    local state = W.QuestState(quest)
    local which = WHICH_OF_STATE[state]
    if not which or (which == "start" and not CanPickUp(instanceID, quest)) then return nil end
    local location = QuestPins.Location(quest, which)
    if not location then return nil end
    return { quest = quest, instanceID = instanceID, state = state, location = location }
end

-- one pin per NPC on a map (by name; by coordinates when the name is unknown)
local function SpotKey(location)
    local npcKey = location.name and ns.Norm(location.name)
    if not npcKey or npcKey == "" then npcKey = ("%.1f:%.1f"):format(location.x, location.y) end
    return location.map .. ":" .. npcKey
end

local function AddEntry(spotList, spotByKey, entry)
    local location = entry.location
    local key = SpotKey(location)
    local spot = spotByKey[key]
    if not spot then
        spot = { map = location.map, x = location.x, y = location.y, name = location.name, entries = {} }
        spotByKey[key] = spot
        spotList[#spotList + 1] = spot
    end
    table.insert(spot.entries, entry)
end

-- turn-ins ready first, then in progress, then pick-ups; lower levels first
local function CompareEntries(first, second)
    local firstOrder, secondOrder = W.STATE_ORDER[first.state], W.STATE_ORDER[second.state]
    if firstOrder ~= secondOrder then return firstOrder < secondOrder end
    local firstLevel, secondLevel = W.QuestLevel(first.quest) or 0, W.QuestLevel(second.quest) or 0
    if firstLevel ~= secondLevel then return firstLevel < secondLevel end
    return (first.quest.name or "") < (second.quest.name or "")
end

local function FinishSpots(spotList)
    for _, spot in ipairs(spotList) do
        table.sort(spot.entries, CompareEntries)
        spot.state = spot.entries[1].state
    end
    return spotList
end

local function BuildSpots()
    local spotList, spotByKey, seen = {}, {}, {}
    for instanceID, quests in pairs(ns.QUESTS) do
        for _, quest in ipairs(quests) do
            if not seen[quest.id] then
                seen[quest.id] = true
                local entry = QuestEntry(instanceID, quest)
                if entry then AddEntry(spotList, spotByKey, entry) end
            end
        end
    end
    return FinishSpots(spotList)
end

local function CurrentSpots()
    if not spots then spots = BuildSpots() end
    return spots
end

local rectCache = {}

local function IsAncestorMap(zoneMapID, ancestorMapID)
    local info = C_Map.GetMapInfo(zoneMapID)
    for _ = 1, MAX_MAP_DEPTH do
        if not info or not info.parentMapID or info.parentMapID == 0 then return false end
        if info.parentMapID == ancestorMapID then return true end
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return false
end

-- left, right, top, bottom of a zone on a continent map (0..1), or nil
local function ZoneRect(zoneMapID, continentMapID)
    local key = zoneMapID .. ":" .. continentMapID
    if rectCache[key] == nil then
        rectCache[key] = false
        if C_Map.GetMapRectOnMap and IsAncestorMap(zoneMapID, continentMapID) then
            local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, zoneMapID, continentMapID)
            if ok and left and right and top and bottom and right ~= left and bottom ~= top then
                rectCache[key] = { left, right, top, bottom }
            end
        end
    end
    local rect = rectCache[key]
    if rect then return rect[1], rect[2], rect[3], rect[4] end
end

local function IsContinentMap(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info ~= nil and info.mapType == CONTINENT_MAP_TYPE
end

-- normalized x, y of a spot on map `mapID`, or nil when it is not on that map
local function PositionOnMap(spot, mapID, onContinent)
    local x, y = ns.Normalized(spot)
    if spot.map == mapID then return x, y end
    if not onContinent then return nil end
    local left, right, top, bottom = ZoneRect(spot.map, mapID)
    if not left then return nil end
    return left + (right - left) * x, top + (bottom - top) * y
end

-- Mixin used by QuestPins.xml (must be global and defined before the XML loads); the taint
-- guards, tooltip wiring and right-click come from PinBase.lua.
ForeverDungeonMapQuestPinMixin = ns.PinBase.CreatePinMixin()
local Pin = ForeverDungeonMapQuestPinMixin

-- small round dungeon icon at the pin's bottom right
local function CreateBadge(pin)
    local badge = CreateFrame("Frame", nil, pin)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("CENTER", pin, "BOTTOMRIGHT", BADGE_OFFSET_X, BADGE_OFFSET_Y)
    badge.Icon = badge:CreateTexture(nil, "ARTWORK")
    badge.Icon:SetAllPoints()
    W.Mask(badge, badge.Icon)
    badge.Ring = badge:CreateTexture(nil, "OVERLAY")
    badge.Ring:SetTexture(TEX.GOLD_RING)
    badge.Ring:SetSize(BADGE_RING_SIZE, BADGE_RING_SIZE)
    badge.Ring:SetPoint("CENTER")
    return badge
end

function Pin:OnLoad()
    W.MarkOwned(self)
    self:ApplyScalingLimits(PIN_SCALE_MIN, PIN_SCALE_MAX)
    self:SetSize(PIN_SIZE, PIN_SIZE)
    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetAllPoints()
    self.Highlight = self:CreateTexture(nil, "HIGHLIGHT")
    self.Highlight:SetTexture(TEX.RING_HOVER)
    self.Highlight:SetBlendMode("ADD")
    self.Highlight:SetSize(HIGHLIGHT_SIZE, HIGHLIGHT_SIZE)
    self.Highlight:SetPoint("CENTER")
    self.Badge = CreateBadge(self)
end

function Pin:OnAcquired(spot, x, y)
    self.spot = spot
    self.Icon:SetTexture(W.StateTexture(spot.state))
    W.SetDungeonIcon(self.Badge, spot.entries[1].instanceID)
    self:SetPosition(x, y)
end

-- State icon + the shared quest title line ("[17] Deviate Hides" in its level colour, crests),
-- dungeon name on the right
local function AddQuestLine(tooltip, entry)
    local title, red, green, blue = W.QuestTitleLine(entry.quest)
    local icon = ns.IconString(W.StateTexture(entry.state), TOOLTIP_ICON_SIZE)
    local dungeon = ns.DUNGEONS[entry.instanceID]
    tooltip:AddDoubleLine(icon .. " " .. title, dungeon and dungeon.name or "", red, green, blue,
        C.MUTED[1], C.MUTED[2], C.MUTED[3])
end

-- NPC name, one line per quest, click hint.
function Pin:FillTooltip(tooltip)
    tooltip:SetText(self.spot.name or UNKNOWN_NPC, C.GOLD[1], C.GOLD[2], C.GOLD[3])
    for _, entry in ipairs(self.spot.entries) do AddQuestLine(tooltip, entry) end
    tooltip:AddLine(CLICK_HINT, C.HINT[1], C.HINT[2], C.HINT[3])
end

-- Click: waypoint with the navigation arrow to the NPC; Shift-click: the first quest in the journal.
function Pin:OnPinClick()
    local entry = self.spot.entries[1]
    if IsShiftKeyDown() then
        ns.Journal:ShowQuest(entry.instanceID, entry.quest)
        return
    end
    ns.SetWaypoint(self.spot, (self.spot.name or UNKNOWN_NPC) .. " - " .. (entry.quest.name or ""))
end

local function BuildPins(map, mapID)
    if not PinsEnabled() then return end
    local onContinent = IsContinentMap(mapID)
    for _, spot in ipairs(CurrentSpots()) do
        local x, y = PositionOnMap(spot, mapID, onContinent)
        if x then map:AcquirePin(TEMPLATE, spot, x, y) end
    end
end

local provider = ns.PinBase.CreateProvider(TEMPLATE, BuildPins)

-- Repaint the open world map (after combat: our pins live on Blizzard's map canvas).
local function RepaintShownMap()
    if WorldMapFrame and WorldMapFrame:IsShown() then provider:Refresh() end
end

-- Rebuild the pins now (e.g. after the questPins setting changed).
function QuestPins.Refresh()
    spots = nil
    ns.AfterCombat("questPins", RepaintShownMap)
end

local refreshPending = false
local function ScheduleRefresh()
    spots = nil
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        QuestPins.Refresh()
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", ScheduleRefresh)

-- The world map may load on demand, after us: put the pins on it then.
local worldMapLoaded = CreateFrame("Frame")
worldMapLoaded:RegisterEvent("ADDON_LOADED")
worldMapLoaded:SetScript("OnEvent", function(_, _, loadedName)
    if loadedName == "Blizzard_WorldMap" then provider:Attach() end
end)

ns.OnLoad(function()
    ns.Settings.OnChanged("questPins", QuestPins.Refresh)
    provider:Attach()
end)
