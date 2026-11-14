-- ForeverDungeonMap - learns where dungeon quests start and end from play: when a quest giver
-- shows a quest (pick-up) or takes it back (turn-in), the NPC's name and the player's spot
-- are saved in ForeverDungeonMapDB.learnedLocations. Fills the gaps of the shipped data
-- (mostly new WoW Forever quests); /fdmap export hands them to the developers.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

local Learn = {}
ns.Learn = Learn

-- quest frame event -> which end of the quest the NPC stands at
local WHICH_OF_EVENT = { QUEST_DETAIL = "start", QUEST_PROGRESS = "finish", QUEST_COMPLETE = "finish" }
-- saved spots are percent rounded to 0.1
local STEPS_PER_PERCENT = 10

local shownQuestIDs

-- Every quest ID the addon shows: dungeon quests and the quests before them.
local function ShownQuestIDs()
    if shownQuestIDs then return shownQuestIDs end
    shownQuestIDs = {}
    for _, quests in pairs(ns.QUESTS) do
        for _, quest in ipairs(quests) do
            shownQuestIDs[quest.id] = true
            for _, previousID in ipairs(quest.pre or {}) do shownQuestIDs[previousID] = true end
        end
    end
    return shownQuestIDs
end

local function LearnedLocations()
    local savedSettings = ns.db or ForeverDungeonMapDB
    if type(savedSettings) ~= "table" then return {} end
    savedSettings.learnedLocations = savedSettings.learnedLocations or {}
    return savedSettings.learnedLocations
end

-- Result of a game API call, or nil when it is missing or fails.
local function SafeCall(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, first, second = pcall(api, ...)
    if ok then return first, second end
end

local function RoundPercent(fraction)
    return math.floor(fraction * ns.PERCENT * STEPS_PER_PERCENT + 0.5) / STEPS_PER_PERCENT
end

-- uiMapID, x, y (percent) of the player, or nil (inside instances there is no map position).
local function PlayerSpot()
    local mapID = C_Map and SafeCall(C_Map.GetBestMapForUnit, "player")
    if type(mapID) ~= "number" then return nil end
    local position = SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
    if type(position) ~= "table" then return nil end
    local x, y
    if position.GetXY then x, y = SafeCall(position.GetXY, position) else x, y = position.x, position.y end
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return mapID, RoundPercent(x), RoundPercent(y)
end

local function DungeonName()
    local instanceID, instanceName = ns.GetPlayerInstance()
    if not instanceID then return nil end
    local dungeon = ns.DUNGEONS[instanceID]
    return dungeon and dungeon.name or instanceName
end

-- { kind, name, map, x, y } outside, { kind, name, inside } in a dungeon, or nil.
local function CurrentLocation(npcName)
    local dungeonName = DungeonName()
    if dungeonName then return { kind = "npc", name = npcName, inside = dungeonName } end
    if SafeCall(IsInInstance) then return nil end
    local mapID, x, y = PlayerSpot()
    if not mapID then return nil end
    return { kind = "npc", name = npcName, map = mapID, x = x, y = y }
end

-- A quest frame opened: save where the NPC showing it stands, for quests we show.
local function OnQuestFrame(event)
    local questID = SafeCall(GetQuestID)
    if type(questID) ~= "number" or questID <= 0 or not ShownQuestIDs()[questID] then return end
    local npcName = SafeCall(UnitName, "npc")
    if type(npcName) ~= "string" or npcName == "" then return end
    local location = CurrentLocation(npcName)
    if not location then return end
    local learned = LearnedLocations()
    learned[questID] = learned[questID] or {}
    learned[questID][WHICH_OF_EVENT[event]] = location
end

-- Where a quest was seen to start ("start") or end ("finish"), or nil. Read-only.
function Learn.Location(questID, which)
    local learned = LearnedLocations()[questID]
    return learned and learned[which] or nil
end

-- Quest frame events, once the saved settings are loaded.
local function ListenToQuestFrames()
    local events = CreateFrame("Frame")
    for event in pairs(WHICH_OF_EVENT) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnEvent", function(_, event) OnQuestFrame(event) end)
end

ns.OnLoad(function()
    LearnedLocations()
    ListenToQuestFrames()
end)
