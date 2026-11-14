-- questpins_scenario.lua - world map quest pins (QuestPins.lua) and their location sources (shipped
-- data only, never another addon). Run with and without --combat; all checks must pass.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step
local COMBAT = M.combat
local TEMPLATE = "ForeverDungeonMapQuestPinTemplate"
local WAILING_CAVERNS = 43
local MULGORE, BARRENS, KALIMDOR, THUNDER_BLUFF = 1412, 1413, 1414, 1456

---------------------------------------------------------------------------
-- login, test quests
---------------------------------------------------------------------------
M.player.inInstance = false
Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(6)

Check("quest pin module loaded", type(ns.QuestPins) == "table" and type(ns.QuestPins.Location) == "function")
Check("quest pin template registered", ForeverDungeonMapQuestPinMixin ~= nil)

local function TestQuest(fields)
    fields.level = fields.level or 18
    table.insert(ns.QUESTS[WAILING_CAVERNS], fields)
    return fields
end
TestQuest({ id = 990001, name = "Info Start Quest" })
TestQuest({ id = 990002, name = "Info Named Quest" })
TestQuest({ id = 990003, name = "Info Inside Quest", npc = "Wrong Giver", map = MULGORE, x = 10, y = 10 })
TestQuest({ id = 990010, name = "Grouped Quest A", npc = "Test Giver", map = MULGORE, x = 70, y = 70 })
TestQuest({ id = 990011, name = "Grouped Quest B", npc = "Test Giver", map = MULGORE, x = 70.05, y = 70 })
TestQuest({ id = 990012, name = "Alliance Quest", faction = "Alliance", npc = "Alliance Giver", map = MULGORE, x = 20, y = 20 })
TestQuest({ id = 990013, name = "Locked Quest", npc = "Locked Giver", map = MULGORE, x = 25, y = 25, pre = { 990001 } })
TestQuest({ id = 990014, name = "High Level Quest" })
ns.QUEST_INFO[990014] = { req = 30, lvl = 32, start = { kind = "npc", name = "High Giver", map = MULGORE, x = 15, y = 15 } }
-- shipped quest info (the Questie table): a giver outside, one inside the dungeon, one turn-in NPC
local ENDER = { kind = "npc", name = "Info Ender", map = MULGORE, x = 50, y = 60 }
ns.QUEST_INFO[990001] = { start = { kind = "npc", name = "Info Giver", map = MULGORE, x = 30, y = 40 }, finish = ENDER }
ns.QUEST_INFO[990002] = { start = { kind = "npc", name = "Inside Giver", inside = "Wailing Caverns" }, finish = ENDER }
ns.QUEST_INFO[990003] = { start = { kind = "npc", name = "Inside NPC", inside = "Wailing Caverns" } }
M.questsInLog[990002] = 1

local function Near(a, b) return a and b and math.abs(a - b) < 0.001 end
local function At(location, map, x, y)
    return location ~= nil and location.map == map and Near(location.x, x) and Near(location.y, y)
end

Check("no ForeverDungeonJournal reader", ns.FDJ == nil)
-- right-click on a dungeon map goes one level out: to the entrance's zone, never the continent
local onContinent = {}
for instanceID, dungeon in pairs(ns.DUNGEONS) do
    local entrance = dungeon.cont and ns.GetEntrance(dungeon)
    if entrance and entrance.map == dungeon.cont then onContinent[#onContinent + 1] = dungeon.name end
end
Check("every classic dungeon's entrance is on its zone map", #onContinent == 0, table.concat(onContinent, ", "))
local wcEntrance = ns.GetEntrance(ns.DUNGEONS[WAILING_CAVERNS])
Check("Wailing Caverns entrance on the Barrens map from shipped data", wcEntrance and wcEntrance.map == BARRENS
    and math.abs(wcEntrance.x - 46.0) < 1 and math.abs(wcEntrance.y - 36.5) < 1,
    wcEntrance and ("%s %s %s"):format(wcEntrance.map, wcEntrance.x, wcEntrance.y))
Check("no entrance on the art without shipped data", ns.ENTRANCE_ON_ART ~= nil or ns.GetEntranceOnArt(WAILING_CAVERNS) == nil)

local function Location(questID, which)
    for _, quest in ipairs(ns.QUESTS[WAILING_CAVERNS]) do
        if quest.id == questID then return ns.QuestPins.Location(quest, which) end
    end
end
Check("location: Questie data first", At(Location(1486, "start"), BARRENS, 46.0, 35.7))
Check("location: shipped quest info", At(Location(990001, "start"), MULGORE, 30, 40))
Check("location: inside the dungeon wins over the quest's map fields", Location(990003, "start") == nil)
Check("location: quest fields last", At(Location(990010, "start"), MULGORE, 70, 70))

---------------------------------------------------------------------------
-- pins on the world map
---------------------------------------------------------------------------
local function ActivePins()
    local pins = {}
    for pin in WorldMapFrame:EnumeratePinsByTemplate(TEMPLATE) do pins[#pins + 1] = pin end
    return pins
end
local function PinWithQuest(questID)
    for _, pin in ipairs(ActivePins()) do
        for _, entry in ipairs(pin.spot.entries) do
            if entry.quest.id == questID then return pin, entry end
        end
    end
end
local function ShowMap(mapID)
    Step("user navigates map to " .. mapID, function() M.Dispatch(function() WorldMapFrame:SetMapID(mapID) end) end)
end
local function TooltipText() return table.concat(GameTooltip._lines or {}, "\n") end

WorldMapFrame.mapID = MULGORE
Step("user opens world map (M)", function() M.UserToggleWorldMap() end)
Check("world map open on Mulgore", WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == MULGORE)
local function NavChip(text)
    return M.FindChild(WorldMapFrame, function(c) return c:IsVisible() and c.Label and c.Label:GetText() == text end)
end
Check("outside a dungeon the nav bar still offers Dungeons", NavChip("Dungeons") ~= nil)
ShowMap(BARRENS)
Check("on the Barrens: a dungeon whose entrance is there is offered with its quests",
    NavChip("Wailing Caverns") ~= nil or NavChip("Razorfen Kraul") ~= nil or NavChip("Razorfen Downs") ~= nil)
Step("Dungeons opens the journal home", function() M.Click(NavChip("Dungeons")) end)
Check("journal home shown", _G.ForeverDungeonMapJournal and _G.ForeverDungeonMapJournal:IsShown())
Step("close journal", function() _G.ForeverDungeonMapJournal:Hide() end)
ShowMap(MULGORE)

local infoPin = PinWithQuest(990001)
Check("pick-up pin from shipped data", infoPin ~= nil)
if infoPin then
    local x, y = infoPin:GetPosition()
    Check("pick-up pin position", Near(x, 0.30) and Near(y, 0.40), ("%s,%s"):format(tostring(x), tostring(y)))
    Check("pick-up pin shows '!'", infoPin.Icon:GetTexture() == ns.TEX.QUEST_AVAILABLE)
    Check("pin has a dungeon badge", infoPin.Badge and infoPin.Badge.Icon:GetTexture() ~= nil)
end
local turnInPin, turnInEntry = PinWithQuest(990002)
Check("turn-in pin for a quest in the log", turnInPin ~= nil and turnInEntry.state == "log")
if turnInPin then
    Check("in-progress turn-in shows the grey '?'", turnInPin.Icon:GetTexture() == ns.TEX.QUEST_INCOMPLETE)
end
Check("no pin for a quest started inside the dungeon", PinWithQuest(990003) == nil)
Check("no pin for the other faction's quest", PinWithQuest(990012) == nil)
Check("no pin before the previous quest is done", PinWithQuest(990013) == nil)
Check("no pin below the quest's required level", PinWithQuest(990014) == nil)

local groupPin = PinWithQuest(990010)
Check("quests at one NPC share one pin", groupPin ~= nil and #groupPin.spot.entries == 2 and PinWithQuest(990011) == groupPin)

if groupPin then
    Step("hover grouped pin", function() M.Enter(groupPin) end)
    local text = TooltipText()
    Check("tooltip: NPC name, quests, dungeon, click hint", GameTooltip:IsShown() and text:find("Test Giver", 1, true)
        and text:find("Grouped Quest A", 1, true) and text:find("Grouped Quest B", 1, true)
        and text:find("Wailing Caverns", 1, true) and text:find("Dungeon Journal", 1, true), text)
    Step("leave grouped pin", function() M.Leave(groupPin) end)
    Check("tooltip hidden on leave", not GameTooltip:IsShown())
    Step("left-click grouped pin", function() M.FireScript(groupPin, "OnMouseUp", "LeftButton") end)
    local waypoint = M.waypoint
    Check("click sets a tracked waypoint on the NPC", waypoint ~= nil and waypoint.tracked
        and waypoint.map == groupPin.spot.map and Near(waypoint.x, groupPin.spot.x / 100) and Near(waypoint.y, groupPin.spot.y / 100))
    Check("plain click leaves the journal closed", not (_G.ForeverDungeonMapJournal and _G.ForeverDungeonMapJournal:IsShown()))
    Step("shift-click grouped pin", function()
        M.mod.shift = true
        M.FireScript(groupPin, "OnMouseUp", "LeftButton")
        M.mod.shift = false
    end)
    local state = ns.Journal.State and ns.Journal:State()
    Check("shift-click opens the quest in the journal", _G.ForeverDungeonMapJournal and _G.ForeverDungeonMapJournal:IsShown()
        and state and (state.instanceID or state.id) == WAILING_CAVERNS and state.quest == groupPin.spot.entries[1].quest)
    Step("close journal", function() if _G.ForeverDungeonMapJournal then _G.ForeverDungeonMapJournal:Hide() end end)
end

-- continent map: zone spots converted with C_Map.GetMapRectOnMap
ShowMap(BARRENS)
Check("Barrens: Deviate Hides pick-up", PinWithQuest(1486) ~= nil)
ShowMap(KALIMDOR)
local continentPin = PinWithQuest(1486)
Check("Kalimdor: Deviate Hides pick-up", continentPin ~= nil)
if continentPin then
    local x, y = continentPin:GetPosition()
    Check("continent position from the zone rect", Near(x, 0.42 + 0.20 * 0.46) and Near(y, 0.38 + 0.42 * 0.357), ("%s,%s"):format(tostring(x), tostring(y)))
end
Check("Kalimdor: Mulgore spots too", PinWithQuest(990001) ~= nil)
Check("no pins of another continent", PinWithQuest(1486) ~= nil and (function()
    for _, pin in ipairs(ActivePins()) do
        if C_Map.GetMapInfo(pin.spot.map).parentMapID ~= KALIMDOR then return false end
    end
    return true
end)())

Step("right-click pin", function() if continentPin then M.FireScript(continentPin, "OnMouseUp", "RightButton") end end)
if not COMBAT then Check("right-click goes one map up", WorldMapFrame:GetMapID() == 947) end
ShowMap(MULGORE)

---------------------------------------------------------------------------
-- quest log events: coalesced, after combat
---------------------------------------------------------------------------
local stateCalls = 0
local questState = ns.W.QuestState
ns.W.QuestState = function(...) stateCalls = stateCalls + 1 return questState(...) end
local questCount = 0
for _, quests in pairs(ns.QUESTS) do questCount = questCount + #quests end

M.questsInLog[990001] = 2
M.questsReady[990002] = true
for _ = 1, 6 do Step("QUEST_LOG_UPDATE", function() M.FireEvent("QUEST_LOG_UPDATE") end) end
Check("no rebuild per event", stateCalls == 0, stateCalls .. " QuestState calls")
M.Advance(1)
if COMBAT then
    Check("in combat: pins wait for the end of combat", stateCalls == 0, stateCalls .. " QuestState calls")
    -- the rest runs out of combat; the right-click's queued "one map up" also runs now
    M.combat = false
    Step("PLAYER_REGEN_ENABLED", function() M.FireEvent("PLAYER_REGEN_ENABLED") end)
    Check("after combat: queued right-click went one map up", WorldMapFrame:GetMapID() == 947)
end
Check("one rebuild for a burst of events", stateCalls > 0 and stateCalls <= questCount, ("%d calls, %d quests"):format(stateCalls, questCount))
ShowMap(MULGORE)
local readyPin = PinWithQuest(990002)
Check("ready quest shows the gold '?'", readyPin and readyPin.Icon:GetTexture() == ns.TEX.QUEST_ACTIVE)
local takenPin, takenEntry = PinWithQuest(990001)
Check("picked-up quest: turn-in pin instead of the giver", takenEntry and takenEntry.state == "log" and takenPin.spot.name == "Info Ender")
Check("chain step stays hidden until the previous quest is done", PinWithQuest(990013) == nil)

M.questsInLog[990002], M.questsReady[990002] = nil, nil
M.questsDone[990002] = true
Step("QUEST_TURNED_IN", function() M.FireEvent("QUEST_TURNED_IN", 990002, 0, 0) end)
M.Advance(1)
Check("turned-in quest has no pin", PinWithQuest(990002) == nil)

-- far above the dungeon's level: its pick-ups go, turn-ins stay
M.player.level = 40
Step("PLAYER_LEVEL_UP", function() M.FireEvent("PLAYER_LEVEL_UP", 40) end)
M.Advance(1)
Check("grey dungeon: no pick-up pins", PinWithQuest(990010) == nil)
Check("grey dungeon: turn-in pins stay", PinWithQuest(990001) ~= nil)
M.player.level = 20
Step("PLAYER_LEVEL_UP", function() M.FireEvent("PLAYER_LEVEL_UP", 20) end)
M.Advance(1)

-- setting off / on
ns.db.questPins = false
Step("questPins off", function() ns.QuestPins.Refresh() end)
Check("setting off: no quest pins", WorldMapFrame:GetNumActivePinsByTemplate(TEMPLATE) == 0)
ns.db.questPins = nil
Step("questPins default", function() ns.QuestPins.Refresh() end)
Check("setting default: pins back", WorldMapFrame:GetNumActivePinsByTemplate(TEMPLATE) > 0)
ns.W.QuestState = questState

-- faction change shows the other faction's quests
M.player.faction = "Alliance"
Step("faction refresh", function() ns.QuestPins.Refresh() end)
Check("Alliance player sees the Alliance quest", PinWithQuest(990012) ~= nil)
M.player.faction = "Horde"

-- Questie marks the same NPCs: our zone-map quest pins step aside while its dungeon quests show
if not COMBAT then
local isLoaded = C_AddOns.IsAddOnLoaded
local function PinCount() return #ActivePins() end
ShowMap(MULGORE)
Step("fresh pins", function() ns.QuestPins.Refresh(); M.Advance(1) end)
local before = PinCount()
Step("Questie loaded, dungeon quests on", function()
    C_AddOns.IsAddOnLoaded = function(name) return name == "Questie" or isLoaded(name) end
    Questie = { db = { profile = { enabled = true, showDungeonQuests = true } } }
    ns.QuestPins.Refresh()
    M.Advance(1)
end)
Check("Questie showing dungeon quests: our quest pins step aside", before > 0 and PinCount() == 0, before .. " -> " .. PinCount())
Step("Questie dungeon quests off", function()
    Questie.db.profile.showDungeonQuests = false
    ns.QuestPins.Refresh()
    M.Advance(1)
end)
Check("Questie not showing them: our quest pins are back", PinCount() == before, before .. " vs " .. PinCount())
Step("Questie gone", function()
    C_AddOns.IsAddOnLoaded, Questie = isLoaded, nil
    ns.QuestPins.Refresh()
    M.Advance(1)
end)
end

Step("close world map", function() if WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
if COMBAT then M.combat = true end
Check("no WorldMapFrame:SetMapID from addon code", (M.mapStateTainted or 0) == 0)

