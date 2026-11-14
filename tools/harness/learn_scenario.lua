-- learn_scenario.lua - quest locations learned in play (Learn.lua), /fdmap debug and
-- /fdmap export (Debug.lua). The shared mock has no quest frame events, no "npc" unit and
-- no player map position: stand-ins are defined here. Run with and without --combat.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step
local MULGORE = 1412
local LEARNED_QUEST = 990050

for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do M.KNOWN_EVENTS[event] = true end
-- the quest frame being shown, the NPC behind it, the player's spot
local questFrame = { questID = 0, npc = nil }
local playerSpot = { map = MULGORE, x = 0.12345, y = 0.6789 }
function GetQuestID() return questFrame.questID end
local unitName = UnitName
function UnitName(unit)
    if unit == "npc" then return questFrame.npc end
    return unitName(unit)
end
C_Map.GetBestMapForUnit = function(unit) return not M.player.inInstance and playerSpot.map or nil end
C_Map.GetPlayerMapPosition = function(mapID, unit)
    if M.player.inInstance or mapID ~= playerSpot.map then return nil end
    return { GetXY = function() return playerSpot.x, playerSpot.y end }
end

M.player.inInstance = false
table.insert(ns.QUESTS[43], { id = LEARNED_QUEST, name = "Learned Quest", level = 18 })
Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(6)

local function QuestFrame(event, questID, npc)
    questFrame.questID, questFrame.npc = questID, npc
    Step(event .. " " .. questID, function() M.FireEvent(event) end)
end
local function Near(a, b) return a and b and math.abs(a - b) < 0.001 end

Check("learnedLocations created in the saved settings", type(ForeverDungeonMapDB.learnedLocations) == "table")
QuestFrame("QUEST_DETAIL", LEARNED_QUEST, "Learned Giver")
local start = ns.Learn.Location(LEARNED_QUEST, "start")
Check("pick-up learned with NPC, map and spot rounded to 0.1 %", start and start.name == "Learned Giver" and start.map == MULGORE
    and Near(start.x, 12.3) and Near(start.y, 67.9) and start.inside == nil,
    start and ("%s %s %s %s"):format(tostring(start.name), tostring(start.map), tostring(start.x), tostring(start.y)))
local quest = ns.QUESTS[43][#ns.QUESTS[43]]
Check("quest pins use the learned spot", ns.QuestPins.Location(quest, "start") == start)
Check("learned spots come after the shipped data", ns.QuestPins.Location(ns.W.QuestByID(1486), "start").map == 1413)

QuestFrame("QUEST_DETAIL", 424242, "Random Giver")
Check("quests we do not show are not recorded", ForeverDungeonMapDB.learnedLocations[424242] == nil)
QuestFrame("QUEST_PROGRESS", LEARNED_QUEST, nil)
Check("no NPC (item / unknown giver): nothing recorded", ns.Learn.Location(LEARNED_QUEST, "finish") == nil)

M.player.inInstance = true
QuestFrame("QUEST_COMPLETE", LEARNED_QUEST, "Inside Ender")
local finish = ns.Learn.Location(LEARNED_QUEST, "finish")
Check("turn-in inside a dungeon: dungeon name instead of a spot", finish and finish.inside == "Wailing Caverns"
    and finish.name == "Inside Ender" and finish.map == nil)
M.player.inInstance = false

-- the learned pick-up shows as a world map pin
WorldMapFrame.mapID = MULGORE
Step("user opens world map (M)", function() M.UserToggleWorldMap() end)
local pinFound = false
for pin in WorldMapFrame:EnumeratePinsByTemplate("ForeverDungeonMapQuestPinTemplate") do
    for _, entry in ipairs(pin.spot.entries) do
        if entry.quest.id == LEARNED_QUEST then pinFound = true end
    end
end
Check("world map pin at the learned spot", pinFound)
Step("close world map", function() M.UserToggleWorldMap() end)

-- /fdmap debug
local function PrintsSince(first)
    local lines = {}
    for i = first + 1, #M.report.prints do lines[#lines + 1] = M.report.prints[i] end
    return table.concat(lines, "\n")
end
local printed = #M.report.prints
Step("/fdmap debug 43", function() ns.Debug.Report("43") end)
local report = PrintsSince(printed)
Check("debug report: dungeon, bosses, quest sources, XP", report:find("Coverage of Wailing Caverns", 1, true)
    and report:find("Bosses: ", 1, true) and report:find("position ", 1, true) and report:find("QUEST_INFO ", 1, true)
    and report:find("learned 1", 1, true) and report:find("XP ", 1, true), report)
Check("source of a Questie quest", ns.Debug.LocationSource(ns.W.QuestByID(1486), "start") == "QUEST_INFO")
Check("source of a learned quest", ns.Debug.LocationSource(quest, "start") == "learned")
printed = #M.report.prints
Step("/fdmap debug wailing", function() ns.Debug.Report("wailing") end)
Check("debug by name", PrintsSince(printed):find("Coverage of Wailing Caverns", 1, true) ~= nil)
printed = #M.report.prints
Step("/fdmap debug nowhere", function() ns.Debug.Report("no such dungeon") end)
Check("debug with no match explains usage", PrintsSince(printed):find("instanceID", 1, true) ~= nil)

-- /fdmap export
ForeverDungeonMapDB.learnedRewards = ForeverDungeonMapDB.learnedRewards or {}
ForeverDungeonMapDB.learnedRewards[959] = { xp = 1300, level = 20, money = 2500 }
Step("/fdmap export", function() ns.Debug.Export() end)
local window = _G.ForeverDungeonMapExport
local text = window and window.EditBox:GetText() or ""
Check("export window shown", window and window:IsShown())
Check("export has locations and rewards", text:find("learnedLocations", 1, true) and text:find("[990050]", 1, true)
    and text:find("Learned Giver", 1, true) and text:find("learnedRewards", 1, true) and text:find("[959]", 1, true), text:sub(1, 300))
local chunk = loadstring(text)
local sandbox = {}
if chunk then setfenv(chunk, sandbox) pcall(chunk) end
Check("export is valid Lua that rebuilds the data", chunk ~= nil and sandbox.learnedLocations
    and sandbox.learnedLocations[LEARNED_QUEST].start.name == "Learned Giver" and sandbox.learnedRewards[959].money == 2500)
Step("export again reuses the window", function() ns.Debug.Export() end)
Check("one export window", _G.ForeverDungeonMapExport == window)
Step("close export", function() window:Hide() end)

-- blocked calls are recorded for the developers (no taint log on the client)
Step("another addon is blocked", function() M.FireEvent("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Foo()") end)
Check("other addons' blocks are ignored", ns.db.blocked == nil or #ns.db.blocked == 0)
Step("we are blocked", function() M.FireEvent("ADDON_ACTION_BLOCKED", addonName, "WorldMapFrame:SetMapID()") end)
Check("our blocked call is saved", ns.db.blocked and ns.db.blocked[1] and ns.db.blocked[1].call == "WorldMapFrame:SetMapID()"
    and ns.db.blocked[1].event == "ADDON_ACTION_BLOCKED")
Check("export lists blocked calls", ns.Debug.ExportText():find("SetMapID", 1, true) ~= nil)
