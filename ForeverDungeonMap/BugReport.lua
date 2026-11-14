-- ForeverDungeonMap - "Report a bug": a window with room for the player's own words and the
-- facts a fix needs (versions, character, where, what the journal shows, settings, blocked calls),
-- to copy with Ctrl+C and paste on the addon's page. Addons cannot send anything themselves.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L

local BugReport = {}
ns.BugReport = BugReport

local WINDOW_NAME = "ForeverDungeonMapBugReport"
local WINDOW_WIDTH, WINDOW_HEIGHT = 600, 460
-- other addons whose presence changes what players see
local RELATED_ADDONS = { "Questie", "QuestieDB", "DungeonMaster", "ForeverDungeonJournal", "TomTom", "ElvUI", "Leatrix_Plus" }
-- newest blocked calls listed
local MAX_LISTED_BLOCKED = 5
-- blank lines left for the player's description
local DESCRIPTION_LINES = 4

local window

local function Metadata(name, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(name, field) end
end

local function IsLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
end

local function VersionLine()
    local version, build = "?", "?"
    if type(GetBuildInfo) == "function" then version, build = GetBuildInfo() end
    return ("Addon %s · client %s (%s) · %s"):format(tostring(Metadata(addonName, "Version") or "?"),
        tostring(version), tostring(build), tostring(GetLocale and GetLocale() or "?"))
end

local function CharacterLine()
    local _, class = UnitClass("player")
    return ("Character: level %s %s %s"):format(tostring(UnitLevel("player")), tostring(class),
        tostring(UnitFactionGroup("player")))
end

-- Zone map and position, or the instance (positions are hidden there).
local function WhereLine()
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType and instanceType ~= "none" then
        return ("Where: instance %s (%s)"):format(tostring(name), tostring(instanceID))
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return "Where: unknown" end
    local info = C_Map.GetMapInfo(mapID)
    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    local x, y = 0, 0
    if ok and position then x, y = position:GetXY() end
    return ("Where: %s (map %d) %.1f, %.1f"):format(info and info.name or "?", mapID, x * ns.PERCENT, y * ns.PERCENT)
end

-- What the journal is showing: dungeon, tab, quest (and step) or boss.
local function JournalLine()
    local state = ns.Journal and ns.Journal.State and ns.Journal:State()
    if not (state and state.instanceID) then return "Journal: not opened" end
    local dungeon = ns.GetDungeon(state.instanceID)
    local parts = { ("Journal: %s (%d), tab %s"):format(dungeon and dungeon.name or "?", state.instanceID, tostring(state.tab)) }
    if state.quest then parts[#parts + 1] = ("quest %d %s"):format(state.quest.id, state.quest.name or "") end
    if state.step then parts[#parts + 1] = ("step %d"):format(state.step) end
    if state.boss then parts[#parts + 1] = "boss " .. tostring(state.boss.name) end
    return table.concat(parts, ", ")
end

local function SettingsLine()
    local parts = {}
    for key in pairs(ns.DEFAULTS or {}) do
        local value = ns.Setting(key)
        if type(value) ~= "table" then parts[#parts + 1] = key .. "=" .. tostring(value) end
    end
    table.sort(parts)
    return "Settings: " .. table.concat(parts, ", ")
end

local function AddonsLine()
    local loaded = {}
    for _, name in ipairs(RELATED_ADDONS) do
        if IsLoaded(name) then loaded[#loaded + 1] = name .. " " .. tostring(Metadata(name, "Version") or "") end
    end
    return "Other addons: " .. (#loaded > 0 and table.concat(loaded, ", ") or "none")
end

-- The newest calls Blizzard blocked (Core.lua keeps them).
local function BlockedLines()
    local blocked = ns.db and ns.db.blocked or {}
    local lines = { ("Blocked calls: %d"):format(#blocked) }
    for i = 1, math.min(MAX_LISTED_BLOCKED, #blocked) do
        local entry = blocked[i]
        lines[#lines + 1] = "  " .. (type(entry) == "table" and table.concat({ tostring(entry.event), tostring(entry.call),
            tostring(entry.time) }, " ") or tostring(entry))
    end
    return lines
end

-- The whole report; every part is guarded so a broken API never stops the rest.
function BugReport.Text()
    local lines = { L["Describe the problem here: what you did, what you expected, what happened."] }
    for _ = 1, DESCRIPTION_LINES do lines[#lines + 1] = "" end
    lines[#lines + 1] = "---- ForeverDungeonMap bug report ----"
    for _, part in ipairs({ VersionLine, CharacterLine, WhereLine, JournalLine, SettingsLine, AddonsLine, BlockedLines }) do
        local ok, result = pcall(part)
        if type(result) == "table" then
            for _, line in ipairs(result) do lines[#lines + 1] = line end
        else
            lines[#lines + 1] = ok and result or ("(failed: " .. tostring(result) .. ")")
        end
    end
    local website = Metadata(addonName, "X-Website")
    if website then lines[#lines + 1] = L["Send it to: %s"]:format(website) end
    return table.concat(lines, "\n")
end

-- /fdmap bug and the journal's bug button.
function BugReport.Open()
    window = window or ns.W.TextWindow(WINDOW_NAME, WINDOW_WIDTH, WINDOW_HEIGHT, L["Report a bug: write, then Ctrl+A, Ctrl+C"])
    ns.W.ShowText(window, BugReport.Text(), true)
end
