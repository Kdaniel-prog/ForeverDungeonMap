-- ForeverDungeonMap - dungeon data
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).
--
-- [instanceID] = {
--   name, min, max   display name and level range
--   art              folder under Interface\WorldMap\ (client map art)
--   floors           number of art floors (art<N>_1..12); detected in game when possible
--   cont, cx, cy     entrance on the continent map (percent); the zone is resolved in game
--   entrance         { map, x, y } entrance directly on a zone map (percent), overrides cont
--   forever          new WoW Forever dungeon
-- }
-- Dungeon list, level ranges and entrance coordinates: DungeonMaster by MalkDev (GPLv3),
-- see THIRD_PARTY.md. Art folder names are the client's own file paths.
-- Bosses, loot and quests are in Generated.lua, boss spots in BossPositions.lua.

local addonName, ns = ...

ns.DUNGEONS = {
    [389] = { name = "Ragefire Chasm", min = 13, max = 18, art = "Ragefire", floors = 1, cont = 1414, cx = 58.41, cy = 44.76 },
    [43] = { name = "Wailing Caverns", min = 15, max = 24, art = "WailingCaverns", floors = 1, cont = 1414, cx = 52.39, cy = 55.25 },
    [36] = { name = "The Deadmines", min = 17, max = 26, art = "TheDeadmines", floors = 2, cont = 1415, cx = 40.67, cy = 79.58 },
    [33] = { name = "Shadowfang Keep", min = 20, max = 30, art = "ShadowfangKeep", floors = 7, cont = 1415, cx = 40.98, cy = 32.8 },
    [48] = { name = "Blackfathom Deeps", min = 24, max = 32, art = "BlackFathomDeeps", floors = 3, cont = 1414, cx = 44.32, cy = 34.84 },
    [34] = { name = "The Stockade", min = 24, max = 32, art = "TheStockade", floors = 1, cont = 1415, cx = 43.04, cy = 69.16 },
    [90] = { name = "Gnomeregan", min = 29, max = 38, art = "Gnomeregan", floors = 4, cont = 1415, cx = 42.79, cy = 53.81 },
    [47] = { name = "Razorfen Kraul", min = 29, max = 38, art = "RazorfenKraul", floors = 1, cont = 1414, cx = 50.88, cy = 70.34 },
    [189] = { name = "Scarlet Monastery", min = 30, max = 46, art = "ScarletMonastery", floors = 4, cont = 1415, cx = 47.72, cy = 19.36 },
    [129] = { name = "Razorfen Downs", min = 37, max = 46, art = "RazorfenDowns", floors = 1, cont = 1414, cx = 53.27, cy = 71.2 },
    [70] = { name = "Uldaman", min = 41, max = 51, art = "Uldaman", floors = 2, cont = 1415, cx = 53.85, cy = 57.62 },
    [209] = { name = "Zul'Farrak", min = 44, max = 54, art = "ZulFarrak", floors = 1, cont = 1414, cx = 54.23, cy = 79.78 },
    [349] = { name = "Maraudon", min = 46, max = 55, art = "Maraudon", floors = 2, cont = 1414, cx = 39.26, cy = 58.22 },
    [109] = { name = "Sunken Temple", min = 50, max = 60, art = "TheTempleOfAtalHakkar", floors = 1, cont = 1415, cx = 56.81, cy = 75.13 },
    [230] = { name = "Blackrock Depths", min = 52, max = 60, art = "BlackrockDepths", floors = 2, cont = 1415, cx = 48.12, cy = 62.4 },
    [229] = { name = "Blackrock Spire", min = 55, max = 60, art = "BlackrockSpire", floors = 7, cont = 1415, cx = 48.97, cy = 63.86 },
    [429] = { name = "Dire Maul", min = 54, max = 60, art = "DireMaul", floors = 6, cont = 1414, cx = 43.84, cy = 67.38 },
    [289] = { name = "Scholomance", min = 58, max = 60, art = "Scholomance", floors = 4, cont = 1415, cx = 52.7, cy = 26.35 },
    [329] = { name = "Stratholme", min = 58, max = 60, art = "Stratholme", floors = 2, cont = 1415, cx = 56.99, cy = 18.02 },

    -- WoW Forever dungeons: no client map art of their own (tile maps they reuse are in Data/Forever.lua)
    [2959] = { name = "City of Dalaran", min = 28, max = 35, forever = true },
    [2998] = { name = "Excavation Site: Wetlands", min = 26, max = 33, forever = true },
    [2999] = { name = "Ruins of Lordaeron", min = 15, max = 22, forever = true, entrance = { map = 1420, x = 61.0, y = 46.0 } },
    [3065] = { name = "Hall of Thanes", min = 13, max = 20, forever = true, entrance = { map = 1455, x = 44.0, y = 56.0 } },
}

local genericRecords = {}

-- Record for an instance; unknown instances get a generic record.
function ns.GetDungeon(instanceID, fallbackName)
    local dungeon = ns.DUNGEONS[instanceID]
    if dungeon then return dungeon end
    if not genericRecords[instanceID] then
        genericRecords[instanceID] = { name = fallbackName or ("Instance " .. tostring(instanceID)), unknown = true }
    end
    return genericRecords[instanceID]
end

-- true / false when the client can tell whether a file exists, nil when it cannot.
local function FileExists(path)
    if type(GetFileIDFromPath) == "function" then return GetFileIDFromPath(path) ~= nil end
    return nil
end

-- Client tile floors of a classic dungeon ("Interface\WorldMap\<Art>\<Art><n>_1..12").
local function ClassicFloors(instanceID, dungeon)
    local floors = {}
    local wings = ns.WINGS and ns.WINGS[instanceID]
    for i = 1, 9 do
        local base = ("Interface\\WorldMap\\%s\\%s%d_"):format(dungeon.art, dungeon.art, i)
        local exists = FileExists(base .. "1")
        if exists == nil then exists = i <= (dungeon.floors or 1) end
        if exists then
            local wing = wings and wings[i]
            floors[#floors + 1] = { base = base, index = i, name = wing and wing.name, min = wing and wing.min, max = wing and wing.max }
        end
    end
    -- one-floor maps whose tiles carry no floor number (ZulFarrak/ZulFarrak1..12)
    local plainBase = ("Interface\\WorldMap\\%s\\%s"):format(dungeon.art, dungeon.art)
    if #floors == 0 and FileExists(plainBase .. "1") then floors[1] = { base = plainBase, index = 1 } end
    return floors
end

-- The art of a WoW Forever dungeon (Data/Forever.lua): client world-map tiles it reuses, or its own
-- minimap textures laid out as square pieces.
local function ForeverFloors(instanceID, dungeon)
    local floors = {}
    for i, floor in ipairs(dungeon.tileFloors or {}) do
        if type(floor) == "table" and type(floor.tiles) == "string" and FileExists(floor.tiles .. "1") ~= false then
            floors[#floors + 1] = { base = floor.tiles, index = i, name = floor.name, overview = floor.kind == "overview" }
        elseif type(floor) == "table" and type(floor.pieces) == "table" then
            floors[#floors + 1] = { pieces = floor.pieces, pieceSize = floor.pieceSize, index = i, name = floor.name,
                overview = floor.kind == "overview" }
        end
    end
    return floors
end

-- Floors of the map, each either client tiles { base, index, name, min, max } (4x3 grid of 256px)
-- or one custom texture { texture, texRight, texBottom }. `overview` floors get no boss pins.
function ns.GetFloors(instanceID, dungeon)
    if not dungeon.floorList then
        dungeon.floorList = dungeon.art and ClassicFloors(instanceID, dungeon) or ForeverFloors(instanceID, dungeon)
    end
    return dungeon.floorList
end

-- Position in the floor list of art floor number `index`.
function ns.FloorSlot(floors, index)
    for i, floor in ipairs(floors) do
        if floor.index == index then return i end
    end
end

-- The zone under a continent spot, with the spot converted to that zone's percent coordinates.
local function ZoneEntrance(dungeon)
    local info = C_Map.GetMapInfoAtPosition(dungeon.cont, dungeon.cx / 100, dungeon.cy / 100)
    if not (info and info.mapID ~= dungeon.cont and info.mapType == Enum.UIMapType.Zone) then return nil end
    local left, right, top, bottom = C_Map.GetMapRectOnMap(info.mapID, dungeon.cont)
    if not left or right == left or bottom == top then return nil end
    local x = (dungeon.cx / 100 - left) / (right - left)
    local y = (dungeon.cy / 100 - top) / (bottom - top)
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return { map = info.mapID, x = x * 100, y = y * 100 }
end

-- Entrance as { map = uiMapID, x = percent, y = percent }, or nil.
-- The shipped zone-map entrance of a dungeon record (Data/DungeonSpots.lua), or nil.
local function ShippedZoneEntrance(dungeon)
    for instanceID, record in pairs(ns.DUNGEONS) do
        if record == dungeon then return ns.ENTRANCE_ON_ZONE and ns.ENTRANCE_ON_ZONE[instanceID] end
    end
end

-- Sources in order: the record's own entrance, the shipped zone entrance, the zone under the
-- continent spot (worked out in game), the continent spot itself.
function ns.GetEntrance(dungeon)
    if dungeon.entranceResolved then return dungeon.entranceResolved end
    local entrance = dungeon.entrance or ShippedZoneEntrance(dungeon)
    if not entrance and dungeon.cont and dungeon.cx and C_Map.GetMapInfoAtPosition and C_Map.GetMapRectOnMap then
        -- not cached when only the continent spot is known: the zone may resolve later
        local zoneEntrance = ZoneEntrance(dungeon)
        if not zoneEntrance then return { map = dungeon.cont, x = dungeon.cx, y = dungeon.cy } end
        entrance = zoneEntrance
    end
    dungeon.entranceResolved = entrance
    return entrance
end

-- Boss spot on the map art { floor = art floor number, x, y }, from the shipped
-- Data/BossPositions.lua only.
function ns.GetBossPos(instanceID, bossName)
    local shipped = ns.BOSS_POS[instanceID]
    return shipped and shipped[bossName]
end

-- Entrance spot on the map art { floor, x, y } (Data/DungeonSpots.lua).
function ns.GetEntranceOnArt(instanceID)
    return ns.ENTRANCE_ON_ART and ns.ENTRANCE_ON_ART[instanceID]
end
