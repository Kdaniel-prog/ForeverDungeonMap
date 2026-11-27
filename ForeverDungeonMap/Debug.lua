-- ForeverDungeonMap - developer tools for the data gaps:
--  /fdmap debug [instanceID | name]  data coverage of a dungeon (current one by default)
--  /fdmap export                     everything learned in play as a Lua snippet to copy
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L

local Debug = {}
ns.Debug = Debug

local EXPORT_WINDOW_NAME = "ForeverDungeonMapExport"
local EXPORT_WIDTH, EXPORT_HEIGHT = 560, 420
local INDENT = "    "
-- at most this many names after "missing:" in a report line
local MAX_LISTED = 6
local LOCATION_SOURCES = { "QUEST_INFO", "FOREVER", "learned", "quest", "none" }

local exportWindow

-- Dungeon of "/fdmap debug <argument>": an instanceID, part of a name, or the current dungeon.
local function ResolveDungeon(argument)
    argument = argument or ""
    local instanceID = tonumber(argument)
    if instanceID then return ns.DUNGEONS[instanceID] and instanceID or nil end
    if argument == "" then return ns.instanceID or ns.GetPlayerInstance() end
    local wanted = ns.Norm(argument)
    for instanceID, dungeon in pairs(ns.DUNGEONS) do
        if ns.Norm(dungeon.name):find(wanted, 1, true) then return instanceID end
    end
end

-- "label have/total" plus up to MAX_LISTED names that lack it
local function CoverageText(label, missing, total)
    local text = ("%s %d/%d"):format(label, total - #missing, total)
    if #missing == 0 then return text end
    local listed = {}
    for i = 1, math.min(#missing, MAX_LISTED) do listed[i] = missing[i] end
    return text .. " (" .. L["missing"] .. ": " .. table.concat(listed, ", ") .. (#missing > MAX_LISTED and ", ..." or "") .. ")"
end

local BOSS_CHECKS = {
    { label = L["position"], test = function(instanceID, boss) return ns.GetBossPos(instanceID, boss.name) ~= nil end },
    { label = L["portrait"], test = function(_, boss) return ns.W.BossDisplay(boss) ~= nil end },
    { label = L["level"], test = function(instanceID, boss) return ns.BossLevel(instanceID, boss.name) ~= nil end },
    { label = L["loot"], test = function(_, boss) return boss.loot ~= nil and #boss.loot > 0 end },
}

local function ReportBosses(instanceID)
    local bosses = ns.BOSSES[instanceID] or {}
    ns.Print(L["Bosses: %d"], #bosses)
    for _, check in ipairs(BOSS_CHECKS) do
        local missing = {}
        for _, boss in ipairs(bosses) do
            if not check.test(instanceID, boss) then missing[#missing + 1] = boss.name end
        end
        if #bosses > 0 then ns.Print("  " .. CoverageText(check.label, missing, #bosses)) end
    end
end

local function ForeverLocation(questID, which)
    local quests = type(ns.FOREVER) == "table" and ns.FOREVER.quests
    local info = type(quests) == "table" and quests[questID]
    return type(info) == "table" and info[which] or nil
end

-- Which data source knows where a quest starts / ends (first one wins, like the quest pins).
function Debug.LocationSource(quest, which)
    local info = ns.QUEST_INFO and ns.QUEST_INFO[quest.id]
    local shipped = info and info[which]
    local forever = ForeverLocation(quest.id, which)
    if shipped then return shipped == forever and "FOREVER" or "QUEST_INFO" end
    if forever then return "FOREVER" end
    if ns.Learn and ns.Learn.Location(quest.id, which) then return "learned" end
    if which == "start" and (quest.npc or quest.drop or quest.inside) then return "quest" end
    return "none"
end

-- "start: QUEST_INFO 7, learned 1, none 1 (none: Name, ...)"
local function SourceSummary(quests, which, label)
    local counts, unknown = {}, {}
    for _, quest in ipairs(quests) do
        local source = Debug.LocationSource(quest, which)
        counts[source] = (counts[source] or 0) + 1
        if source == "none" then unknown[#unknown + 1] = quest.name end
    end
    local parts = {}
    for _, source in ipairs(LOCATION_SOURCES) do
        if counts[source] then parts[#parts + 1] = source .. " " .. counts[source] end
    end
    local text = label .. ": " .. table.concat(parts, ", ")
    if #unknown > 0 then text = text .. " — " .. CoverageText(L["known"], unknown, #quests) end
    return text
end

local function ReportQuests(instanceID)
    local quests = ns.QUESTS[instanceID] or {}
    ns.Print(L["Quests: %d"], #quests)
    if #quests == 0 then return end
    ns.Print("  " .. SourceSummary(quests, "start", L["start"]))
    ns.Print("  " .. SourceSummary(quests, "finish", L["turn-in"]))
    local missing = {}
    for _, quest in ipairs(quests) do
        if not ns.Rewards.Get(quest.id).xp then missing[#missing + 1] = quest.name end
    end
    ns.Print("  " .. CoverageText(L["XP"], missing, #quests))
end

-- /fdmap debug [instanceID | name]
function Debug.Report(argument)
    local instanceID = ResolveDungeon(argument)
    if not instanceID then
        ns.Print(L["debug: not in a dungeon and no dungeon matches '%s' (use an instanceID or a name)"], tostring(argument or ""))
        return
    end
    local dungeon = ns.GetDungeon(instanceID)
    ns.Print(L["Coverage of %s (%s)"], dungeon.name, tostring(instanceID))
    ReportBosses(instanceID)
    ReportQuests(instanceID)
end

local function SortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys, function(first, second)
        if type(first) ~= type(second) then return type(first) == "number" end
        return first < second
    end)
    return keys
end

local function KeyText(key)
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then return key end
    if type(key) == "string" then return ("[%q]"):format(key) end
    return "[" .. tostring(key) .. "]"
end

-- Plain data (tables, strings, numbers, booleans) as a Lua literal.
function Debug.Serialize(value, indent)
    indent = indent or ""
    if type(value) == "string" then return ("%q"):format(value) end
    if type(value) ~= "table" then return tostring(value) end
    local keys = SortedKeys(value)
    if #keys == 0 then return "{}" end
    local inner, lines = indent .. INDENT, { "{" }
    for _, key in ipairs(keys) do
        lines[#lines + 1] = inner .. KeyText(key) .. " = " .. Debug.Serialize(value[key], inner) .. ","
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines, "\n")
end

-- Everything learned in play, as a snippet the developers can paste into the data files.
function Debug.ExportText()
    local savedSettings = ns.db or {}
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
    return table.concat({
        ("-- ForeverDungeonMap %s learned data, client %s"):format(tostring(version or "?"), tostring((GetBuildInfo()))),
        "learnedLocations = " .. Debug.Serialize(savedSettings.learnedLocations or {}),
        "learnedRewards = " .. Debug.Serialize(savedSettings.learnedRewards or {}),
        "learnedDisplays = " .. Debug.Serialize(savedSettings.learnedDisplays or {}),
        "blocked = " .. Debug.Serialize(savedSettings.blocked or {}),
    }, "\n")
end

-- /fdmap export
function Debug.Export()
    exportWindow = exportWindow or ns.W.TextWindow(EXPORT_WINDOW_NAME, EXPORT_WIDTH, EXPORT_HEIGHT, L["Learned data: Ctrl+C to copy"])
    ns.W.ShowText(exportWindow, Debug.ExportText())
end
