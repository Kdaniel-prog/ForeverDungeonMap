-- journey_scenario.lua - the new WoW Forever dungeons get their quests, extra bosses and entrances
-- from Data/JourneyContent.lua, and the journal and map open on them without errors.
-- Run: python -I tools/harness/run.py tools/harness/journey_scenario.lua   (and with --combat)
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step

local DROWNED_CITY, KROLDOK, BLACKMAW_HOLD = 2970, 3039, 2974
local SHADY_SALTSEERS, TAKE_TWO_WITH_WATER, THE_VILE_REEF = 95789, 95787, 629

local function Quests(instanceID) return ns.QUESTS[instanceID] or {} end

local function FindBoss(instanceID, name)
    for _, boss in ipairs(ns.BOSSES[instanceID] or {}) do
        if boss.name == name then return boss end
    end
end

-- quests an Alliance player sees: Alliance ones and the ones for both factions
local function AllianceQuestCount(instanceID)
    local count = 0
    for _, quest in ipairs(Quests(instanceID)) do
        if quest.faction ~= "Horde" then count = count + 1 end
    end
    return count
end

Check("Drowned City has its 11 quests", #Quests(DROWNED_CITY) == 11, #Quests(DROWNED_CITY))
Check("Drowned City: 7 quests for Alliance (5 Alliance, 2 for both factions)", AllianceQuestCount(DROWNED_CITY) == 7, AllianceQuestCount(DROWNED_CITY))
local saltseers = ns.QUEST_INFO[SHADY_SALTSEERS]
Check("Shady Saltseers starts at Krazek in Booty Bay", saltseers and saltseers.start and saltseers.start.name == "Krazek"
    and saltseers.start.map == 1434)
local takeTwo
for _, quest in ipairs(Quests(DROWNED_CITY)) do
    if quest.id == TAKE_TWO_WITH_WATER then takeTwo = quest end
end
Check("Take Two With Water carries its chain", takeTwo and takeTwo.pre and #takeTwo.pre == 5, takeTwo and takeTwo.pre and #takeTwo.pre)
Check("a classic chain step keeps Questie's data first", ns.QUEST_NAMES[THE_VILE_REEF] ~= nil)
Check("Gill is a rare elite of the Drowned City", FindBoss(DROWNED_CITY, "Gill") and FindBoss(DROWNED_CITY, "Gill").rare == true)
Check("Bossman Toof joins Krol'dok", FindBoss(KROLDOK, "Bossman Toof") ~= nil)
Check("Moontouched Wanderer joins Blackmaw Hold", FindBoss(BLACKMAW_HOLD, "Moontouched Wanderer") ~= nil)
Check("no boss twice in the Drowned City", (function()
    local seen = {}
    for _, boss in ipairs(ns.BOSSES[DROWNED_CITY] or {}) do
        if seen[boss.name] then return false end
        seen[boss.name] = true
    end
    return true
end)())
local entrance = ns.GetEntrance(ns.DUNGEONS[DROWNED_CITY])
Check("Drowned City entrance in Stranglethorn Vale", entrance and entrance.map == 1434)

if not ns.db then
    Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
    Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
end
Step("open the Drowned City map", function() ns.Journal:OpenDungeon(DROWNED_CITY, "map") end)
Step("open the Drowned City quests", function() ns.Journal:OpenDungeon(DROWNED_CITY) end)
Step("show Take Two With Water", function() ns.Journal:ShowQuest(DROWNED_CITY, takeTwo) end)
Check("quest page shown", _G.ForeverDungeonMapJournalQuest:IsVisible())

-- spots of the Icy Veins map: every Drowned City boss and rare has one, the entrance too
local spotted = 0
for _, boss in ipairs(ns.BOSSES[DROWNED_CITY]) do
    if ns.GetBossPos(DROWNED_CITY, boss.name) then spotted = spotted + 1 end
end
Check("every Drowned City boss and rare has a map spot", spotted == #ns.BOSSES[DROWNED_CITY], spotted .. "/" .. #ns.BOSSES[DROWNED_CITY])
local zulAlai = ns.GetBossPos(DROWNED_CITY, "Zul'Alai")
Check("Zul'Alai stands east of the centre pool", zulAlai and zulAlai.x > 0.6 and zulAlai.y > 0.4 and zulAlai.y < 0.55)
Check("Umbra and Braxton are rare elites", FindBoss(DROWNED_CITY, "Umbra") and FindBoss(DROWNED_CITY, "Umbra").rare
    and FindBoss(DROWNED_CITY, "\"Pyromancer\" Braxton") and FindBoss(DROWNED_CITY, "\"Pyromancer\" Braxton").rare)
Check("Drowned City entrance on its map", ns.GetEntranceOnArt(DROWNED_CITY) ~= nil)

-- the four I'lalai tablets show on the map while the quest is in the log
local THE_DROWNED_CITY_QUEST = 95775
local function TabletMarkers()
    local count = 0
    for i = 1, ns.Journal.map.numQuestSpots or 0 do
        local marker = ns.Journal.map.questSpots[i]
        if marker.spot.kind == "object" then count = count + 1 end
    end
    return count
end
Step("open the Drowned City map again", function() ns.Journal:OpenDungeon(DROWNED_CITY, "map") end)
Check("no tablet markers without the quest", TabletMarkers() == 0, TabletMarkers())
M.questsInLog[THE_DROWNED_CITY_QUEST] = 1
Step("quest in the log, map again", function() ns.Journal:OpenDungeon(DROWNED_CITY, "quests"); ns.Journal:OpenDungeon(DROWNED_CITY, "map") end)
Check("four tablet markers with the quest in the log", TabletMarkers() == 4, TabletMarkers())
M.questsInLog[THE_DROWNED_CITY_QUEST] = nil

-- portraits: a display ID no table has is learned from the creature ID in play
local GILL_NPC, GILL_DISPLAY = 264177, 145001
M.creatureDisplays[GILL_NPC] = GILL_DISPLAY
-- the map asked for Gill before the client knew it; a minute later it asks again
M.Advance(61)
local gill = FindBoss(DROWNED_CITY, "Gill")
Step("ask for Gill's portrait", function() ns.W.BossDisplay(gill) end)
M.Advance(1)
Check("Gill's display ID is learned and kept", ns.BossModels.Display(GILL_NPC) == GILL_DISPLAY and ns.db.learnedDisplays[GILL_NPC] == GILL_DISPLAY)
Check("Gill's portrait uses it", ns.W.BossDisplay(gill) == GILL_DISPLAY)
local umbra = FindBoss(DROWNED_CITY, "Umbra")
Step("ask for Umbra's portrait (the client never loads it)", function() ns.W.BossDisplay(umbra) end)
M.Advance(10)
Check("an unknown creature gives up without an error", ns.BossModels.Display(umbra.npcID) == nil)
Check("the export lists learned display IDs", ns.Debug.ExportText():find("learnedDisplays", 1, true) ~= nil)

-- none of the five new dungeons says "Coming soon" any more: their bosses are seen dropping loot
for _, instanceID in ipairs({ 2970, 3039, 2994, 2974, 3001 }) do
    Check("not coming soon: " .. ns.DUNGEONS[instanceID].name, not ns.DUNGEONS[instanceID].comingSoon)
end

-- the boss page shows the creature in 3D where the client has no Encounter Journal picture
local gillIndex
for index, boss in ipairs(ns.BOSSES[DROWNED_CITY]) do if boss.name == "Gill" then gillIndex = index end end
Step("open Gill's page", function() ns.Journal:ShowBoss(DROWNED_CITY, gill, gillIndex) end)
local model = M.FindChild(_G.ForeverDungeonMapJournal, function(child)
    return child.GetDisplayInfo and child:IsVisible() and child:GetDisplayInfo() == GILL_DISPLAY
end)
Check("Gill's page shows its 3D model", model ~= nil)

-- entrances: exact for Alcaz Prison and Krol'dok, approximate for The Shaper's Terrace
local alcaz, kroldok, shapers = ns.GetEntrance(ns.DUNGEONS[2994]), ns.GetEntrance(ns.DUNGEONS[3039]), ns.GetEntrance(ns.DUNGEONS[3001])
Check("Alcaz Prison entrance on Alcaz Island", alcaz and alcaz.map == 1445 and not alcaz.approx and alcaz.y < 20)
Check("Krol'dok entrance from the guide", kroldok and kroldok.map == 2548 and not kroldok.approx)
Check("The Shaper's Terrace has an entrance in Un'Goro", shapers and shapers.map == 1449)
Check("no draft twin of Blood Red Bandanas", (function()
    for _, quest in ipairs(Quests(2994)) do if quest.id == 96906 then return false end end
    return true
end)())

-- every new dungeon has its entrance pin on its zone map
local ENTRANCE_TEMPLATE = "ForeverDungeonMapEntrancePinTemplate"
local ZONE_OF = { [2970] = 1434, [2994] = 1445, [3039] = 2548, [3001] = 1449, [2974] = 1447 }
Step("open the world map", function() if not WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
for instanceID, zoneMap in pairs(ZONE_OF) do
    Step("world map on " .. zoneMap, function() M.Dispatch(function() WorldMapFrame:SetMapID(zoneMap) end) end)
    local found = false
    for pin in WorldMapFrame:EnumeratePinsByTemplate(ENTRANCE_TEMPLATE) do
        if pin.instanceID == instanceID then found = true end
    end
    Check(("entrance pin of %s on map %d"):format(ns.DUNGEONS[instanceID].name, zoneMap), found)
    local covered = false
    for pin in WorldMapFrame:EnumeratePinsByTemplate(ENTRANCE_TEMPLATE) do
        if pin:GetFrameLevelType() ~= "PIN_FRAME_LEVEL_TRACKED_CONTENT" then covered = true end
    end
    Check("entrance pins drawn above Blizzard's quest hub pins on map " .. zoneMap, not covered)
end

-- every creature is looked up on a fresh model frame: one boss's model never sticks to the next
local DREADRISE_NPC, DREADRISE_DISPLAY = 260042, 145002
M.creatureDisplays[DREADRISE_NPC] = DREADRISE_DISPLAY
local UMBRA_NPC = 264172
M.creatureDisplays[UMBRA_NPC] = nil
M.Advance(61)
Step("ask for Dreadrise, then Umbra", function()
    ns.BossModels.Request(DREADRISE_NPC)
    ns.BossModels.Request(UMBRA_NPC)
end)
M.Advance(10)
Check("Dreadrise gets its own model", ns.BossModels.Display(DREADRISE_NPC) == DREADRISE_DISPLAY)
Check("Umbra does not inherit Dreadrise's model", ns.BossModels.Display(UMBRA_NPC) == nil, tostring(ns.BossModels.Display(UMBRA_NPC)))
Check("models of older versions are dropped once", ns.db.learnedDisplaysVersion == 2)

-- the client's stand-in model (the same ID for every creature it has not loaded) is never kept
local ZUL_ALAI_NPC, VAR_TAKA_NPC, STAND_IN = 258905, 258924, 150000
M.creatureDisplays[ZUL_ALAI_NPC], M.creatureDisplays[VAR_TAKA_NPC] = STAND_IN, STAND_IN
M.Advance(61)
Step("ask for Zul'Alai and Var'Taka", function()
    ns.BossModels.Request(ZUL_ALAI_NPC)
    ns.BossModels.Request(VAR_TAKA_NPC)
end)
M.Advance(10)
Check("one model ID for two bosses is kept for neither", ns.BossModels.Display(ZUL_ALAI_NPC) == nil
    and ns.BossModels.Display(VAR_TAKA_NPC) == nil)
Check("the known stand-in 142144 is never kept", (function()
    M.creatureDisplays[DREADRISE_NPC] = 142144
    ns.db.learnedDisplays[DREADRISE_NPC] = nil
    M.Advance(61)
    ns.BossModels.Request(DREADRISE_NPC)
    M.Advance(10)
    return ns.BossModels.Display(DREADRISE_NPC) == nil
end)())

-- forg.gg's maps fitted onto ours: the bosses of the four other new dungeons on their spots
local function Spotted(instanceID)
    local count = 0
    for _, boss in ipairs(ns.BOSSES[instanceID] or {}) do
        if ns.GetBossPos(instanceID, boss.name) then count = count + 1 end
    end
    return count
end
Check("Alcaz Prison: all 5 bosses on the map", Spotted(2994) == 5, Spotted(2994))
Check("Krol'dok: all 6 bosses and Bossman Toof on the map", Spotted(3039) == #ns.BOSSES[3039], Spotted(3039) .. "/" .. #ns.BOSSES[3039])
Check("Shaper's Terrace: all 11 bosses on the map", Spotted(3001) == #ns.BOSSES[3001], Spotted(3001) .. "/" .. #ns.BOSSES[3001])
Check("Blackmaw Hold: Impaan, Bonesnout and Withermaw on the map", Spotted(2974) >= 3, Spotted(2974))
Check("Withermaw's spot is marked approximate (a cave, only roughly placed)", ns.GetBossPos(2974, "Withermaw").approx == true)
Check("Blackmaw Hold: all its bosses on the map, the deep caves roughly", Spotted(2974) == #ns.BOSSES[2974] - 1, Spotted(2974))
for _, instanceID in ipairs({ 2994, 3039, 3001, 2974 }) do
    Check("entrance on the dungeon map: " .. ns.DUNGEONS[instanceID].name, ns.GetEntranceOnArt(instanceID) ~= nil)
end
-- quests forg.gg lists that the other sources did not have
local function HasQuest(instanceID, questID)
    for _, quest in ipairs(Quests(instanceID)) do if quest.id == questID then return quest end end
end
Check("Alcaz Prison: Shaw Needs To Know and both State Secrets", HasQuest(2994, 95264) and HasQuest(2994, 96376) and HasQuest(2994, 96377))
Check("Shaw Needs To Know has its reward choices", HasQuest(2994, 95264).choices and #HasQuest(2994, 95264).choices == 3)
Check("Blackmaw Magic (Alliance) starts at Archmage Timear", ns.QUEST_INFO[97173] and ns.QUEST_INFO[97173].start
    and ns.QUEST_INFO[97173].start.name == "Archmage Timear")

-- givers known only by the place they stand at get a rough spot, shown with "~"
local keyIngredients = ns.QUEST_INFO[94974]
Check("Kreza Darkthorn stands roughly at Rog'mar", keyIngredients and keyIngredients.start and keyIngredients.start.map == 2548
    and keyIngredients.start.approx == true)
Check("a rough spot reads with ~", (ns.W.LocationText(keyIngredients.start) or ""):find("~", 1, true) ~= nil,
    ns.W.LocationText(keyIngredients.start))
Check("Commander Folkar stands inside Alcaz Prison", ns.QUEST_INFO[95483] and ns.QUEST_INFO[95483].start
    and ns.QUEST_INFO[95483].start.inside == "Alcaz Prison")
-- the tooltip of a roughly placed boss says so
Step("journal map tab of Blackmaw Hold", function() ns.Journal:OpenDungeon(2974, "map") end)
local varroxPin
for i = 1, ns.Journal.map.numPins do
    if ns.Journal.map.pins[i].boss.name == "Varrox Bleakhoof" then varroxPin = ns.Journal.map.pins[i] end
end
Step("hover Varrox", function() M.Enter(varroxPin) end)
Check("Varrox's tooltip says the spot is rough", table.concat(GameTooltip._lines, " "):find("Only roughly here", 1, true) ~= nil,
    table.concat(GameTooltip._lines, " | "))
Step("leave Varrox", function() M.Leave(varroxPin) end)
