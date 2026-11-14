-- ForeverDungeonMap - "Report a bug": a window with room for the player's own words and the
-- facts a fix needs (versions, character, where, what the journal shows, settings, blocked calls),
-- to copy with Ctrl+C and paste on the addon's page. Addons cannot send anything themselves.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L

local BugReport = {}
ns.BugReport = BugReport

local WINDOW_NAME = "ForeverDungeonMapBugReport"
local WINDOW_WIDTH, WINDOW_HEIGHT = 620, 520
-- layout: side inset, top under the title ribbon, box heights, gap after a step title
local INSET, TOP, DESCRIPTION_HEIGHT, DETAILS_HEIGHT, STEP_GAP = 18, -46, 120, 200, 6
local COPY_BUTTON_WIDTH, COPY_BUTTON_HEIGHT, LINK_HEIGHT = 170, 26, 24
-- other addons whose presence changes what players see
local RELATED_ADDONS = { "Questie", "QuestieDB", "DungeonMaster", "ForeverDungeonJournal", "TomTom", "ElvUI", "Leatrix_Plus" }
-- newest blocked calls listed
local MAX_LISTED_BLOCKED = 5

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

-- The details a fix needs; every part is guarded so a broken API never stops the rest.
function BugReport.Text()
    local lines = { "---- ForeverDungeonMap bug report ----" }
    for _, part in ipairs({ VersionLine, CharacterLine, WhereLine, JournalLine, SettingsLine, AddonsLine, BlockedLines }) do
        local ok, result = pcall(part)
        if type(result) == "table" then
            for _, line in ipairs(result) do lines[#lines + 1] = line end
        else
            lines[#lines + 1] = ok and result or ("(failed: " .. tostring(result) .. ")")
        end
    end
    return table.concat(lines, "\n")
end

-- The player's words and the details, as one text to paste.
function BugReport.Combined(description)
    return (description ~= "" and description or "-") .. "\n\n" .. BugReport.Text()
end

-- Gold step title ("1. ...") under `above` (or at the top).
local function StepTitle(parent, text, above)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if above then
        title:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2 * STEP_GAP)
    else
        title:SetPoint("TOPLEFT", INSET, TOP)
    end
    title:SetText(text)
    return title
end

-- Framed text box under a step title, full window width.
local function PlaceBox(box, title, height)
    box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -STEP_GAP)
    box:SetPoint("RIGHT", -INSET, 0)
    box:SetHeight(height)
end

-- One-line, read-only box with the address to paste the report at.
local function CreateLinkBox(parent)
    local box = ns.W.Panel(parent)
    box:SetHeight(LINK_HEIGHT)
    local editBox = CreateFrame("EditBox", nil, box)
    editBox:SetPoint("TOPLEFT", 6, 0)
    editBox:SetPoint("BOTTOMRIGHT", -6, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ns.Font("GameFontHighlightSmall"))
    local link = Metadata(addonName, "X-Issues") or ""
    editBox:SetText(link)
    editBox:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(link) end end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box.EditBox = editBox
    return box
end

-- "Copy everything" puts description + details in the details box, selected for Ctrl+C.
local function CreateCopyRow(frame)
    local copy = ns.W.Tab(frame, L["Copy everything"], nil, COPY_BUTTON_WIDTH, COPY_BUTTON_HEIGHT)
    copy:SetPoint("TOPLEFT", frame.Details, "BOTTOMLEFT", 0, -2 * STEP_GAP)
    frame.CopyHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.CopyHint:SetPoint("LEFT", copy, "RIGHT", 10, 0)
    copy:SetScript("OnClick", function()
        ns.W.SetBoxText(frame.Details, BugReport.Combined(frame.Description.EditBox:GetText()))
        frame.Details.EditBox:SetFocus()
        frame.Details.EditBox:HighlightText()
        frame.CopyHint:SetText(L["Selected: press Ctrl+C"])
    end)
    frame.CopyButton = copy
    local pasteTitle = StepTitle(frame, L["3. Paste it here (a new issue on GitHub):"], copy)
    frame.Link = CreateLinkBox(frame)
    frame.Link:SetPoint("TOPLEFT", pasteTitle, "BOTTOMLEFT", 0, -STEP_GAP)
    frame.Link:SetPoint("RIGHT", -INSET, 0)
end

local function CreateWindow()
    local frame = ns.W.Window(WINDOW_NAME, WINDOW_WIDTH, WINDOW_HEIGHT, L["Report a bug"])
    frame:SetPoint("CENTER")
    -- one layer above the journal (DIALOG, raised on every click), or it opens hidden behind it
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    tinsert(UISpecialFrames, WINDOW_NAME)
    local describeTitle = StepTitle(frame, L["1. What went wrong? What did you do, what did you expect?"])
    frame.Description = ns.W.TextBox(frame, { placeholder = L["Write here..."] })
    PlaceBox(frame.Description, describeTitle, DESCRIPTION_HEIGHT)
    local detailsTitle = StepTitle(frame, L["2. Details the addon filled in (read-only):"], frame.Description)
    frame.Details = ns.W.TextBox(frame, { readOnly = true })
    PlaceBox(frame.Details, detailsTitle, DETAILS_HEIGHT)
    CreateCopyRow(frame)
    return frame
end

-- /fdmap bug and the journal's "Report a bug" button: fresh details, cursor in the description.
function BugReport.Open()
    window = window or CreateWindow()
    ns.W.SetBoxText(window.Details, BugReport.Text())
    window.CopyHint:SetText("")
    window:Show()
    window:Raise()
    window.Description.EditBox:SetFocus()
end
