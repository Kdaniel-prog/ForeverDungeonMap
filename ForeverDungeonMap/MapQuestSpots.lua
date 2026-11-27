-- ForeverDungeonMap - quest givers and turn-ins inside a dungeon, drawn on the dungeon map
-- (MapCanvas). Spots come from Data/DungeonSpots.lua and ForeverData.lua: "!" where a quest can be
-- picked up, "?" where a quest in the log is turned in, the log icon where an objective of a quest
-- in the log lies. Click: the quest in the journal.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local _, ns = ...
local W, C, L = ns.W, ns.C, ns.L
local MapCanvas = ns.MapCanvas

local SPOT_SIZE = 20
local TOOLTIP_ICON_SIZE = 14
-- above the entrance markers, below the boss portraits
local LEVEL_ABOVE_AREA = 3
-- states that earn a giver its "!" and an ender its "?"
local START_STATES = { avail = true, locked = true }
local END_STATES = { log = true, ready = true }
-- an objective spot (a tablet to rub) matters while the quest is in the log and not done
local OBJECTIVE_STATES = { log = true }
local CLICK_HINT = L["Click: open in Dungeon Journal"]

-- { quest, state } of the spot's quests worth a marker now, most urgent first.
local function SpotEntries(spot)
    local entries = {}
    local function Add(questIDs, wantedStates)
        for _, questID in ipairs(questIDs or {}) do
            local quest = W.QuestByID(questID)
            local state = W.QuestState(quest)
            if not quest.stub and wantedStates[state] then entries[#entries + 1] = { quest = quest, state = state } end
        end
    end
    Add(spot.ends, END_STATES)
    Add(spot.starts, START_STATES)
    Add(spot.objectives, OBJECTIVE_STATES)
    table.sort(entries, function(a, b) return W.STATE_ORDER[a.state] < W.STATE_ORDER[b.state] end)
    return entries
end

-- NPC name, one line per quest with its state icon, click hint.
local function ShowSpotTooltip(marker)
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:SetText(marker.spot.name or L["Quest giver"], C.GOLD[1], C.GOLD[2], C.GOLD[3])
    for _, entry in ipairs(marker.entries) do
        local title, red, green, blue = W.QuestTitleLine(entry.quest)
        GameTooltip:AddLine(ns.IconString(W.StateTexture(entry.state), TOOLTIP_ICON_SIZE) .. " " .. title, red, green, blue)
    end
    GameTooltip:AddLine(CLICK_HINT, C.HINT[1], C.HINT[2], C.HINT[3])
    GameTooltip:Show()
end

-- Quest marker number i (made on first use); right-click is the map's "back" like everywhere.
function MapCanvas:QuestSpot(i)
    self.questSpots = self.questSpots or {}
    if self.questSpots[i] then return self.questSpots[i] end
    local marker = CreateFrame("Button", nil, self.area)
    marker:SetSize(SPOT_SIZE, SPOT_SIZE)
    marker.Icon = marker:CreateTexture(nil, "ARTWORK")
    marker.Icon:SetAllPoints()
    marker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    marker:SetScript("OnClick", function(clicked, button)
        if button == "RightButton" then
            if self.options.onRightClick then self.options.onRightClick() end
            return
        end
        ns.Journal:ShowQuest(self.state.instanceID, clicked.entries[1].quest)
    end)
    marker:SetScript("OnEnter", ShowSpotTooltip)
    marker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.questSpots[i] = marker
    return marker
end

-- { spot, entries, x, y } of the markers on this floor, pushed clear of the boss portraits
-- (which stay put) and of each other.
function MapCanvas:QuestPlacesOnFloor(spots, floor)
    local points, places = {}, {}
    for _, occupied in ipairs(self.occupiedSpots or {}) do points[#points + 1] = { x = occupied.x, y = occupied.y } end
    local fixedCount = #points
    for _, spot in ipairs(spots) do
        local entries = (spot.floor or 1) == floor.index and SpotEntries(spot) or {}
        if #entries > 0 then
            local x, y = self:ArtToOffset(spot.x, spot.y)
            local place = { spot = spot, entries = entries, x = x, y = y }
            places[#places + 1] = place
            points[#points + 1] = place
        end
    end
    local distance = math.max(SPOT_SIZE, ((self.occupiedDistance or 0) + SPOT_SIZE) / 2)
    MapCanvas.SpreadApart(points, distance, fixedCount)
    return places
end

local function QuestSpotsShown()
    return ns.Setting("questPins") ~= false
end

-- Quest markers of the floor on screen (none on overview maps or with quest pins switched off).
function MapCanvas:LayoutQuestSpots(floor)
    local shown = 0
    local spots = ns.QUEST_NPC_ON_ART and ns.QUEST_NPC_ON_ART[self.state.instanceID]
    if spots and floor and self.state.fit and not floor.overview and QuestSpotsShown() then
        for _, placed in ipairs(self:QuestPlacesOnFloor(spots, floor)) do
            shown = shown + 1
            local marker = self:QuestSpot(shown)
            marker.spot, marker.entries = placed.spot, placed.entries
            W.SetStateIcon(marker.Icon, placed.entries[1].state)
            marker:ClearAllPoints()
            marker:SetPoint("CENTER", self.area, "CENTER", placed.x, placed.y)
            marker:SetFrameLevel(self.area:GetFrameLevel() + LEVEL_ABOVE_AREA)
            marker:Show()
        end
    end
    for i = shown + 1, #(self.questSpots or {}) do self.questSpots[i]:Hide() end
    self.numQuestSpots = shown
end

-- A quest was taken, finished or handed in: the dungeon map on screen redraws its markers.
local questWatcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do questWatcher:RegisterEvent(event) end
questWatcher:SetScript("OnEvent", function()
    if ns.View and ns.View:IsShown() then ns.View:Refresh() end
end)
