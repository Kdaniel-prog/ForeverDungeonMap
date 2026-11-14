-- ForeverDungeonMap - merges the generated WoW Forever data (Data/Forever.lua, ns.FOREVER)
-- into the dungeon, boss, level, quest and art tables. Works without ns.FOREVER as well.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

local forever = type(ns.FOREVER) == "table" and ns.FOREVER or {}
local bossDisplay = type(forever.bossDisplay) == "table" and forever.bossDisplay or {}

-- Crop of a loading screen used as art when the art generator has no entry for a dungeon.
local LOADING_SCREEN_ART = {
    cardCoords = { 0.05, 0.95, 0.30, 0.58 }, bgCoords = { 0, 1, 0.42, 0.56 }, iconCoords = { 0.35, 0.65, 0.20, 0.80 },
}

ns.DUNGEONS = ns.DUNGEONS or {}
ns.BOSSES = ns.BOSSES or {}
ns.QUESTS = ns.QUESTS or {}
ns.BOSS_LEVELS = ns.BOSS_LEVELS or {}
ns.QUEST_INFO = ns.QUEST_INFO or {}
ns.ART = ns.ART or {}

-- Copy the listed keys from source to target where target has none.
local function FillMissing(target, source, keys)
    for _, key in ipairs(keys) do
        if target[key] == nil and source[key] ~= nil then target[key] = source[key] end
    end
end

local function TableOrEmpty(value) return type(value) == "table" and value or {} end

-- Our boss list for a Forever dungeon that Generated.lua does not know.
local function BossesFromForever(foreverDungeon)
    local bosses = {}
    for _, boss in ipairs(TableOrEmpty(foreverDungeon.bosses)) do
        if type(boss) == "table" and boss.name then
            bosses[#bosses + 1] = { name = boss.name, npcID = boss.npcID, encounter = boss.encounter,
                display = bossDisplay[boss.name] or (boss.npcName and bossDisplay[boss.npcName]) }
        end
    end
    return bosses
end

-- Display and encounter IDs for bosses Generated.lua lists without them.
local function CompleteBosses(bosses, foreverDungeon)
    for _, boss in ipairs(bosses) do
        boss.display = boss.display or bossDisplay[boss.name]
        for _, foreverBoss in ipairs(TableOrEmpty(foreverDungeon.bosses)) do
            if not boss.encounter and (foreverBoss.name == boss.name or foreverBoss.npcName == boss.name) then
                boss.encounter = foreverBoss.encounter
            end
        end
    end
end

local function HasLoot(bosses)
    for _, boss in ipairs(bosses) do
        if boss.loot and #boss.loot > 0 then return true end
    end
    return false
end

local function MergeDungeon(instanceID, foreverDungeon)
    local dungeon = ns.DUNGEONS[instanceID]
    if not dungeon then
        dungeon = { name = foreverDungeon.name, comingSoon = true }
        ns.DUNGEONS[instanceID] = dungeon
    end
    dungeon.forever = true
    FillMissing(dungeon, foreverDungeon, { "min", "max", "zone", "loading", "players" })
    local entrance = foreverDungeon.entrance
    if not dungeon.entrance and type(entrance) == "table" and entrance.map and entrance.x then
        dungeon.entrance = { map = entrance.map, x = entrance.x, y = entrance.y, approx = entrance.approx }
    end
    if type(foreverDungeon.floors) == "table" and #foreverDungeon.floors > 0 then dungeon.tileFloors = foreverDungeon.floors end
    if #(ns.BOSSES[instanceID] or {}) == 0 then ns.BOSSES[instanceID] = BossesFromForever(foreverDungeon) end
    CompleteBosses(ns.BOSSES[instanceID], foreverDungeon)
    if not ns.ART[instanceID] and foreverDungeon.loading then
        local screen = foreverDungeon.loading
        ns.ART[instanceID] = { card = screen, bg = screen, icon = screen, cardCoords = LOADING_SCREEN_ART.cardCoords,
            bgCoords = LOADING_SCREEN_ART.bgCoords, iconCoords = LOADING_SCREEN_ART.iconCoords }
    end
    -- "coming soon": neither quests nor loot are known yet
    if dungeon.comingSoon then
        dungeon.comingSoon = not HasLoot(ns.BOSSES[instanceID]) and #(ns.QUESTS[instanceID] or {}) == 0
    end
end

for instanceID, foreverDungeon in pairs(TableOrEmpty(forever.dungeons)) do
    if type(instanceID) == "number" and type(foreverDungeon) == "table" and foreverDungeon.name then
        MergeDungeon(instanceID, foreverDungeon)
    end
end

-- Boss levels: the shipped table first, Forever fills the gaps.
for instanceID, levels in pairs(TableOrEmpty(forever.bossLevels)) do
    ns.BOSS_LEVELS[instanceID] = ns.BOSS_LEVELS[instanceID] or {}
    for bossName, level in pairs(TableOrEmpty(levels)) do
        if ns.BOSS_LEVELS[instanceID][bossName] == nil and type(level) == "table" then
            ns.BOSS_LEVELS[instanceID][bossName] = level
        end
    end
end

-- Boss and entrance spots on the Forever art (percent there, 0..1 in BOSS_POS / ENTRANCE_ON_ART):
-- the shipped tables first, Forever fills the gaps.
local function ArtSpot(spot)
    return { floor = spot.floor, x = spot.x / ns.PERCENT, y = spot.y / ns.PERCENT, roams = spot.roams }
end

ns.BOSS_POS = ns.BOSS_POS or {}
for instanceID, positions in pairs(TableOrEmpty(forever.bossPositions)) do
    ns.BOSS_POS[instanceID] = ns.BOSS_POS[instanceID] or {}
    for bossName, spot in pairs(TableOrEmpty(positions)) do
        if ns.BOSS_POS[instanceID][bossName] == nil and type(spot) == "table" and spot.x then
            ns.BOSS_POS[instanceID][bossName] = ArtSpot(spot)
        end
    end
end

ns.ENTRANCE_ON_ART = ns.ENTRANCE_ON_ART or {}
for instanceID, foreverDungeon in pairs(TableOrEmpty(forever.dungeons)) do
    local spot = type(foreverDungeon) == "table" and foreverDungeon.entranceOnArt
    if type(spot) == "table" and spot.x and not ns.ENTRANCE_ON_ART[instanceID] then
        ns.ENTRANCE_ON_ART[instanceID] = ArtSpot(spot)
    end
end

-- Quest locations: QUEST_INFO first, then Forever.
for questID, info in pairs(TableOrEmpty(forever.quests)) do
    if type(info) == "table" then
        if ns.QUEST_INFO[questID] then
            FillMissing(ns.QUEST_INFO[questID], info, { "req", "lvl", "start", "finish" })
        else
            ns.QUEST_INFO[questID] = info
        end
    end
end

-- Checked Forever quest data (Data/ForeverQuests.lua) beats both: spots, chains, levels.
local CHECKED_INFO_KEYS = { "lvl", "req", "start", "finish" }
local CHECKED_QUEST_KEYS = { "name", "faction", "pre", "next", "inside", "drop" }

local function FindQuest(instanceID, questID)
    for _, quest in ipairs(ns.QUESTS[instanceID] or {}) do
        if quest.id == questID then return quest end
    end
end

-- The quest's row in its dungeon list, added when the list does not have it yet.
local function DungeonQuest(instanceID, questID, checked)
    local quest = FindQuest(instanceID, questID)
    if not quest then
        quest = { id = questID, forever = true }
        ns.QUESTS[instanceID] = ns.QUESTS[instanceID] or {}
        table.insert(ns.QUESTS[instanceID], quest)
    end
    if checked.lvl then quest.level = checked.lvl end
    return quest
end

ns.QUEST_NAMES = ns.QUEST_NAMES or {}
for questID, name in pairs(TableOrEmpty(ns.FOREVER_QUEST_NAMES)) do
    ns.QUEST_NAMES[questID] = ns.QUEST_NAMES[questID] or name
end
for questID, checked in pairs(TableOrEmpty(ns.FOREVER_QUESTS)) do
    if type(checked) == "table" then
        local info = ns.QUEST_INFO[questID] or {}
        ns.QUEST_INFO[questID] = info
        for _, key in ipairs(CHECKED_INFO_KEYS) do info[key] = checked[key] or info[key] end
        if checked.name then ns.QUEST_NAMES[questID] = checked.name end
        if checked.dungeon then
            local quest = DungeonQuest(checked.dungeon, questID, checked)
            for _, key in ipairs(CHECKED_QUEST_KEYS) do
                if checked[key] ~= nil then quest[key] = checked[key] end
            end
        end
    end
end

-- An item a boss drops that starts a quest goes into the boss's loot (like Mutanus' Glowing Shard).
local function AddStarterToLoot(instanceID, start)
    if not (start.kind == "item" and start.itemID and start.dropBy) then return end
    for _, boss in ipairs(ns.BOSSES[instanceID] or {}) do
        if boss.name == start.dropBy then
            boss.loot = boss.loot or {}
            for _, itemID in ipairs(boss.loot) do
                if itemID == start.itemID then return end
            end
            table.insert(boss.loot, start.itemID)
        end
    end
end

-- Spot (0..1 of the floor art) of "entrance" or a boss of the dungeon.
local function NearSpot(instanceID, near)
    if near == "entrance" then return ns.ENTRANCE_ON_ART[instanceID] end
    return ns.BOSS_POS[instanceID] and ns.BOSS_POS[instanceID][near]
end

-- In-dungeon quest givers / enders / starters of the checked data as "!" / "?" spots on the
-- dungeon map (one spot per name; Data/DungeonSpots.lua has none for the Forever dungeons).
ns.QUEST_NPC_ON_ART = ns.QUEST_NPC_ON_ART or {}
local function AddQuestSpot(instanceID, questID, location, listName)
    local spot = location and location.near and NearSpot(instanceID, location.near)
    if not spot then return end
    ns.QUEST_NPC_ON_ART[instanceID] = ns.QUEST_NPC_ON_ART[instanceID] or {}
    local spots = ns.QUEST_NPC_ON_ART[instanceID]
    local found
    for _, existing in ipairs(spots) do
        if existing.name == location.name then found = existing end
    end
    if not found then
        found = { kind = location.kind, name = location.name, floor = spot.floor, x = spot.x, y = spot.y, starts = {}, ends = {} }
        table.insert(spots, found)
    end
    table.insert(found[listName], questID)
end

for questID, checked in pairs(TableOrEmpty(ns.FOREVER_QUESTS)) do
    if type(checked) == "table" and checked.dungeon then
        if type(checked.start) == "table" then AddStarterToLoot(checked.dungeon, checked.start) end
        AddQuestSpot(checked.dungeon, questID, checked.start, "starts")
        AddQuestSpot(checked.dungeon, questID, checked.finish, "ends")
    end
end

-- Boss level { minimum, maximum, rank } or nil.
function ns.BossLevel(instanceID, bossName)
    local levels = ns.BOSS_LEVELS[instanceID]
    return levels and levels[bossName]
end
