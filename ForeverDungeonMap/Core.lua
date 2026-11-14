-- ForeverDungeonMap - Core
-- Namespace, saved settings, instance tracking, boss kill tracking, the combat queue
-- and taint-safe access to the world map.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

-- Blizzard blocked or forbade one of our calls: kept (newest first) in the saved settings with
-- when and where, and said once in chat. Registered first thing, so blocks while the addon's
-- files load are caught too; they wait in `pendingBlocked` until the saved settings exist.
local MAX_BLOCKED = 10
local pendingBlocked = {}

local function SaveBlocked(entry)
    ns.db.blocked = ns.db.blocked or {}
    table.insert(ns.db.blocked, 1, entry)
    for i = #ns.db.blocked, MAX_BLOCKED + 1, -1 do ns.db.blocked[i] = nil end
end

local function RecordBlocked(_, event, blockedAddon, functionName)
    if blockedAddon ~= addonName then return end
    local entry = {
        event = event, call = tostring(functionName), time = date("%Y-%m-%d %H:%M:%S"),
        combat = InCombatLockdown() and true or false, zone = GetRealZoneText and GetRealZoneText() or nil,
        worldMapShown = WorldMapFrame and WorldMapFrame:IsShown() or false, loading = ns.db == nil,
    }
    if ns.db then SaveBlocked(entry) else pendingBlocked[#pendingBlocked + 1] = entry end
    print(("|cffffd100ForeverDungeonMap:|r Blizzard blocked %s"):format(tostring(functionName)))
end

local blockedWatcher = CreateFrame("Frame")
blockedWatcher:RegisterEvent("ADDON_ACTION_BLOCKED")
blockedWatcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockedWatcher:SetScript("OnEvent", RecordBlocked)

ns.MEDIA = "Interface\\AddOns\\ForeverDungeonMap\\Media\\"
ns.SLASH_COMMAND = "/fdmap"
-- Spots in the data are in percent of the map (0..100); map canvases want 0..1.
ns.PERCENT = 100
local WORLD_MAP_COMBAT_KEY = "worldmap"
local ADDON_PREFIX = "ForeverDungeonMap"

-- Saved settings and their defaults.
-- liveZoom: minimap zoom of the live view (0 = farthest out); livePos: { point, relativePoint, x, y };
-- killed: { instanceID, names = { [bossName] = true } } survives /reload;
-- questPins: show where dungeon quests start and end on the world map;
-- autoDungeonMap: the world map opens on our dungeon view inside a dungeon;
-- favourites: { [instanceID] = true }.
ns.DEFAULTS = {
    liveZoom = 0,
    livePos = nil,
    questPins = true,
    autoDungeonMap = true,
    favourites = {},
    killed = {},
}
local SETTINGS_VERSION = 3

-- A setting: through the Settings module when it is loaded, else straight from the saved table.
function ns.Setting(key)
    if ns.Settings and ns.Settings.Get then
        local ok, value = pcall(ns.Settings.Get, key)
        if ok and value ~= nil then return value end
    end
    local value = ns.db and ns.db[key]
    if value == nil then value = ns.DEFAULTS[key] end
    return value
end

local settingWatchers = {}

-- Run watcher(value) whenever a setting changes (here or in the Settings panel).
function ns.WatchSetting(key, watcher)
    settingWatchers[key] = settingWatchers[key] or {}
    table.insert(settingWatchers[key], watcher)
    if ns.Settings and ns.Settings.OnChanged and ns.db then pcall(ns.Settings.OnChanged, key, watcher) end
end

local function NotifySetting(key, value)
    for _, watcher in ipairs(settingWatchers[key] or {}) do
        local ok, problem = pcall(watcher, value)
        if not ok then geterrorhandler()(problem) end
    end
end

-- Change a setting; the Settings module (when loaded) stores it and tells its own listeners.
function ns.SetSetting(key, value)
    if ns.Settings and ns.Settings.Set and pcall(ns.Settings.Set, key, value) then
        if not ns.Settings.OnChanged then NotifySetting(key, value) end
        return
    end
    ns.db[key] = value
    NotifySetting(key, value)
end

-- Watchers registered before the Settings module loaded subscribe to it now.
local function SubscribeWatchers()
    if not (ns.Settings and ns.Settings.OnChanged) then return end
    for key, watchers in pairs(settingWatchers) do
        for _, watcher in ipairs(watchers) do pcall(ns.Settings.OnChanged, key, watcher) end
    end
end

-- Chat message with the addon prefix (in the palette's gold once Theme.lua is loaded).
function ns.Print(format, ...)
    local message = select("#", ...) > 0 and format:format(...) or format
    local prefix = ns.C and (ns.Hex(ns.C.GOLD) .. ADDON_PREFIX .. "|r") or ADDON_PREFIX
    print(prefix .. " " .. message)
end

-- x, y of a { x, y } spot in percent, as 0..1 map coordinates.
-- Name key for matching: lower case, no leading "the ", only letters and digits ("The Deadmines" -> "deadmines").
function ns.Norm(text)
    if type(text) ~= "string" then return "" end
    return (text:lower():gsub("^the ", ""):gsub("[^%w\128-\255]", ""))
end

function ns.Normalized(spot)
    return spot.x / ns.PERCENT, spot.y / ns.PERCENT
end

-- "Key: action · Key: action" hint line with the keys in gold; keyActions = { { key, action }, ... }.
function ns.KeyHint(keyActions)
    local parts = {}
    for _, keyAction in ipairs(keyActions) do
        parts[#parts + 1] = ns.Hex(ns.C.GOLD) .. keyAction[1] .. "|r: " .. keyAction[2]
    end
    return table.concat(parts, " · ")
end

-- instanceID, name when the player is inside a dungeon or raid, else nil.
function ns.GetPlayerInstance()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then return nil end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID, name
end

-- Callbacks other files register for: addon loaded, instance changed, boss killed.
local callbacks = { load = {}, instance = {}, kill = {} }
function ns.OnLoad(callback) table.insert(callbacks.load, callback) end
function ns.OnInstanceChanged(callback) table.insert(callbacks.instance, callback) end
function ns.OnBossKilled(callback) table.insert(callbacks.kill, callback) end

-- Call every callback of a list; one failing callback does not stop the others.
local function Fire(list, ...)
    for _, callback in ipairs(list) do
        local ok, problem = pcall(callback, ...)
        if not ok then geterrorhandler()(problem) end
    end
end

-- Bosses killed in ns.killedInstance ([bossName] = true); kept while you stay in that dungeon.
ns.killed = {}
ns.killedInstance = nil

function ns.IsKilled(instanceID, bossName)
    return instanceID == ns.killedInstance and ns.killed[bossName] == true
end

local function MarkKilled(boss)
    if not ns.instanceID or ns.killed[boss.name] then return end
    ns.killed[boss.name] = true
    ns.db.killed = { instanceID = ns.instanceID, names = ns.killed }
    Fire(callbacks.kill, ns.instanceID, boss)
end

local function BossByEncounter(encounterID, encounterName)
    for _, boss in ipairs(ns.BOSSES[ns.instanceID] or {}) do
        if (boss.encounter and boss.encounter == encounterID) or boss.name == encounterName then return boss end
    end
end

local function BossByCreature(creatureID)
    for _, boss in ipairs(ns.BOSSES[ns.instanceID] or {}) do
        if boss.npcID == creatureID then return boss end
    end
end

local function CreatureIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, creatureID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then return tonumber(creatureID) end
end

-- Saved settings: defaults, cleanup of old keys, kills of the current dungeon.
local function LoadSettings()
    ForeverDungeonMapDB = ForeverDungeonMapDB or {}
    for key, value in pairs(ns.DEFAULTS) do
        if ForeverDungeonMapDB[key] == nil then
            ForeverDungeonMapDB[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    ns.db = ForeverDungeonMapDB
    ns.db.bossPos, ns.db.liveSize, ns.db.liveBig, ns.db.ground, ns.db.sideTab = nil, nil, nil, nil, nil
    if (ns.db.version or 0) < SETTINGS_VERSION then
        ns.db.livePos = nil
        ns.db.version = SETTINGS_VERSION
    end
    for _, entry in ipairs(pendingBlocked) do SaveBlocked(entry) end
    pendingBlocked = {}
    local killed = ns.db.killed
    if killed and killed.instanceID and type(killed.names) == "table" then
        ns.killedInstance, ns.killed = killed.instanceID, killed.names
    end
end

-- Entering or leaving an instance: kills reset in a new dungeon, listeners hear the change.
local function OnZoneChanged()
    local instanceID, name = ns.GetPlayerInstance()
    if instanceID and instanceID ~= ns.killedInstance then
        ns.killedInstance = instanceID
        ns.killed = {}
        ns.db.killed = { instanceID = instanceID, names = ns.killed }
    end
    if instanceID ~= ns.instanceID then
        ns.instanceID, ns.instanceName = instanceID, name
        Fire(callbacks.instance, instanceID, name)
    end
end

-- A dead boss of this dungeon behind a GUID (a dead target, a looted corpse) counts as killed.
-- The combat log is forbidden to addons on this client: registering it raises Blizzard's
-- "blocked from an action" popup, so kills come from encounters, dead targets and loot.
-- GUIDs may be "secret" values: every use is guarded.
local function MarkKilledByGUID(guid)
    if not ns.instanceID then return end
    pcall(function()
        if issecretvalue and issecretvalue(guid) then return end
        local boss = BossByCreature(CreatureIDFromGUID(guid))
        if boss then MarkKilled(boss) end
    end)
end

-- Targeting a corpse: rares and bosses without an encounter.
local function OnTargetChanged()
    if not (UnitExists("target") and UnitIsDead("target")) then return end
    MarkKilledByGUID(UnitGUID("target"))
end

-- Looting a corpse: every loot slot names the GUID it came from.
local function OnLootReady()
    if not (GetNumLootItems and GetLootSourceInfo) then return end
    for slot = 1, GetNumLootItems() do MarkKilledByGUID((GetLootSourceInfo(slot))) end
end

local EVENT_HANDLERS = {
    ADDON_LOADED = function(loadedName)
        if loadedName ~= addonName then return end
        LoadSettings()
        SubscribeWatchers()
        Fire(callbacks.load)
    end,
    ENCOUNTER_END = function(encounterID, encounterName, _, _, success)
        if success == 1 or success == true then
            local boss = BossByEncounter(encounterID, encounterName)
            if boss then MarkKilled(boss) end
        end
    end,
    BOSS_KILL = function(encounterID, encounterName)
        local boss = BossByEncounter(encounterID, encounterName)
        if boss then MarkKilled(boss) end
    end,
    PLAYER_TARGET_CHANGED = OnTargetChanged,
    LOOT_READY = OnLootReady,
    PLAYER_ENTERING_WORLD = OnZoneChanged,
    ZONE_CHANGED_NEW_AREA = OnZoneChanged,
}

local eventFrame = CreateFrame("Frame")
for event in pairs(EVENT_HANDLERS) do
    -- an event this client does not know must never break loading
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end
eventFrame:SetScript("OnEvent", function(_, event, ...) EVENT_HANDLERS[event](...) end)

local afterCombat, afterCombatOrder = {}, {}

-- Run work now, or after combat when called in combat. Only the last work queued under a key
-- runs (a later show replaces an earlier hide); keys run in the order they were first queued.
function ns.AfterCombat(key, work)
    if not InCombatLockdown() then
        work()
        return true
    end
    if not afterCombat[key] then afterCombatOrder[#afterCombatOrder + 1] = key end
    afterCombat[key] = work
    return false
end

local combatEndFrame = CreateFrame("Frame")
combatEndFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEndFrame:SetScript("OnEvent", function()
    local order = afterCombatOrder
    afterCombatOrder = {}
    for _, key in ipairs(order) do
        local work = afterCombat[key]
        afterCombat[key] = nil
        if work then Fire({ work }) end
    end
end)

-- Open the world map (optionally on uiMapID) the way Blizzard does it: C_Map.OpenWorldMap lets
-- Blizzard's own handler set the map, so the map state stays untainted. In combat it waits.
function ns.ShowWorldMap(mapID)
    if not WorldMapFrame then return false end
    if InCombatLockdown() then
        ns.AfterCombat(WORLD_MAP_COMBAT_KEY, function() ns.ShowWorldMap(mapID) end)
        return false
    end
    -- ToggleWorldMap / SetMapID from addon code would taint the map for the whole session
    if not (C_Map and C_Map.OpenWorldMap) then return false end
    return (pcall(C_Map.OpenWorldMap, mapID))
end

-- Move the open world map to another map. In combat it waits, and then only happens if the
-- map is still open. onChange runs right before the change (e.g. to expect it).
function ns.ChangeOpenWorldMap(mapID, onChange)
    if InCombatLockdown() then
        ns.AfterCombat(WORLD_MAP_COMBAT_KEY, function()
            if WorldMapFrame and WorldMapFrame:IsShown() then ns.ChangeOpenWorldMap(mapID, onChange) end
        end)
        return
    end
    if onChange then onChange(mapID) end
    ns.ShowWorldMap(mapID)
end

-- The game's own map pin plus the on-screen navigation arrow on a spot { map, x, y } (0-100),
-- and a TomTom arrow when TomTom is installed. True when any waypoint was set.
function ns.SetWaypoint(spot, title)
    if not (spot and spot.map and spot.x and spot.y) then return false end
    local x, y = ns.Normalized(spot)
    local placed = false
    local tomTom = _G.TomTom
    if tomTom and tomTom.AddWaypoint then
        placed = pcall(tomTom.AddWaypoint, tomTom, spot.map, x, y, { title = title, from = addonName })
    end
    -- the same calls DungeonMaster makes on this client; a map without coordinates refuses them
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap) then return placed end
    if not C_Map.CanSetUserWaypointOnMap(spot.map) then return placed end
    if not pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(spot.map, x, y)) then return placed end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

-- One map up from a map canvas (right-click on our pins, which keep the click).
function ns.ShowParentMap(map)
    local info = map and map.GetMapID and map:GetMapID() and C_Map.GetMapInfo(map:GetMapID())
    local parentMapID = info and info.parentMapID
    if parentMapID and parentMapID ~= 0 then ns.ChangeOpenWorldMap(parentMapID) end
end

-- A dungeon's map: on the world map (out of combat) or in the journal's Map tab (in combat).
function ns.OpenMap(instanceID)
    instanceID = instanceID or ns.instanceID
    if InCombatLockdown() or not WorldMapFrame then
        if instanceID and ns.DUNGEONS[instanceID] then ns.Journal:OpenDungeon(instanceID, "map") end
        return
    end
    if WorldMapFrame:IsShown() then
        if instanceID then ns.View:Open(instanceID) end
        return
    end
    ns.View.pendingOpen = instanceID
    ns.ShowWorldMap()
    -- some clients open the map through an event: open the view now if the map is already up
    if WorldMapFrame:IsShown() and instanceID and not ns.View:IsShown() then ns.View:Open(instanceID) end
end

local SLASH_ACTIONS = {
    journal = function() ns.Journal:Toggle() end,
    resetlive = function()
        ns.db.livePos = nil
        ns.Print("live view position reset")
    end,
    resetkills = function()
        ns.killed = {}
        ns.db.killed = { instanceID = ns.instanceID, names = ns.killed }
        if ns.View then ns.View:Refresh() end
        ns.Print("defeated bosses cleared")
    end,
}
SLASH_ACTIONS.config = function()
    if ns.Settings and ns.Settings.Open then ns.Settings.Open() end
end
SLASH_ACTIONS.help = function()
    ns.Print("%s: dungeon map  ·  journal  ·  config (options)  ·  debug [dungeon]  ·  export  ·  bug (report a bug)  ·  resetlive  ·  resetkills", ns.SLASH_COMMAND)
end
SLASH_ACTIONS.j = SLASH_ACTIONS.journal
SLASH_ACTIONS.debug = function(argument)
    if ns.Debug then ns.Debug.Report(argument) end
end
SLASH_ACTIONS.export = function()
    if ns.Debug then ns.Debug.Export() end
end
SLASH_ACTIONS.bug = function()
    if ns.BugReport then ns.BugReport.Open() end
end

SLASH_FOREVERDUNGEONMAP1 = ns.SLASH_COMMAND
SlashCmdList.FOREVERDUNGEONMAP = function(message)
    -- first word is the command, the rest its argument ("/fdmap debug 43")
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local action = SLASH_ACTIONS[command:lower()]
    if action then action(argument) else ns.OpenMap() end
end

function ForeverDungeonMap_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then ns.OpenMap() else ns.Journal:Toggle() end
end

function ForeverDungeonMap_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:SetText("ForeverDungeonMap", ns.C.GOLD[1], ns.C.GOLD[2], ns.C.GOLD[3])
    GameTooltip:AddLine("Left-click: Dungeon Journal", 1, 1, 1)
    GameTooltip:AddLine("Right-click: dungeon map", 1, 1, 1)
    GameTooltip:Show()
end

function ForeverDungeonMap_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
