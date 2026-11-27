-- ForeverDungeonMap - the recap window: every recorded dungeon run in a list on the left (dungeon,
-- date, time inside, bosses), the picked run in full on the right (times, experience, money, bosses
-- with when they fell, quests, group, loot). Runs are recorded by Recap.lua.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L
local W, C, TEX = ns.W, ns.C, ns.TEX

local Recap = ns.Recap

local WINDOW_NAME = "ForeverDungeonMapRecap"
local WINDOW_WIDTH, WINDOW_HEIGHT = 760, 580
-- where the window opens until the player drags it: right of the screen centre, out of the way
local DEFAULT_POINT, DEFAULT_X, DEFAULT_Y = "RIGHT", -80, 40
-- layout: side margin, top under the title ribbon, gap between panels, footer with the run buttons
local MARGIN, TOP, PANEL_GAP, FOOTER_HEIGHT = 16, 44, 8, 34
local LIST_WIDTH, LIST_INSET, LIST_SCROLL_BAR = 250, 6, 24
local RUN_ROW_HEIGHT, RUN_ROW_GAP, RUN_ICON_SIZE = 50, 4, 34
local HEADER_HEIGHT, HEADER_ICON_SIZE, HEADER_ICON_LEFT = 64, 44, 10
local PAGE_INSET, PAGE_SCROLL_BAR = 12, 28
local DETAIL_WIDTH = WINDOW_WIDTH - 2 * MARGIN - LIST_WIDTH - PANEL_GAP
local PAGE_WIDTH = DETAIL_WIDTH - PAGE_INSET - PAGE_SCROLL_BAR
local LIST_ROW_WIDTH = LIST_WIDTH - 2 * LIST_INSET - LIST_SCROLL_BAR
local NAVIGATION_WIDTH, NAVIGATION_HEIGHT = 96, 24
local CLASS_ICON_SIZE = 14
local SECONDS_PER_MINUTE, SECONDS_PER_HOUR = 60, 3600
local REFRESH_DELAY = 0.5
local NAME_SEPARATOR = "  ·  "
local DATE_FORMAT, TIME_FORMAT = "%Y-%m-%d %H:%M", "%H:%M"

local window, list, header, page, positionLabel, newerButton, olderButton
-- which run the window shows (1 = newest), and the run painted last
local shownIndex, paintedRun = 1, nil
local refreshQueued = false

-- "23:45", or "1:05:23" from an hour on.
local function DurationText(seconds)
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / SECONDS_PER_HOUR)
    local minutes = math.floor(seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE)
    if hours > 0 then return ("%d:%02d:%02d"):format(hours, minutes, seconds % SECONDS_PER_MINUTE) end
    return ("%d:%02d"):format(minutes, seconds % SECONDS_PER_MINUTE)
end

local function IsCurrent(run) return run == Recap.Current() end

local function BossCount(run) return #(ns.BOSSES[run.instanceID] or {}) end

-- "2026-11-15 18:30 - 19:05", and "In progress" for the run being recorded.
local function WhenText(run)
    local started = date(DATE_FORMAT, run.startedAt)
    if IsCurrent(run) then return started .. NAME_SEPARATOR .. ns.Hex(C.DONE) .. L["In progress"] .. "|r" end
    if run.endedAt then return started .. " - " .. date(TIME_FORMAT, run.endedAt) end
    return started
end

local function MakeRunRow(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row.Icon = W.CreateRoundIcon(row, RUN_ICON_SIZE)
    row.Icon:SetPoint("LEFT", 8, 0)
    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, 0)
    row.Name:SetPoint("RIGHT", -6, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Sub:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -3)
    row.Sub:SetPoint("RIGHT", -6, 0)
    row.Sub:SetJustifyH("LEFT")
    row.Sub:SetWordWrap(false)
    row:SetScript("OnClick", function(self) Recap.Show(self.index) end)
    W.Hoverable(row, "row", { selectedBar = true })
    return row
end

-- "2026-11-15 18:30 · 23:45 · 4/6": when, how long, bosses defeated.
local function RunRowSubText(run)
    return table.concat({ date(DATE_FORMAT, run.startedAt), DurationText(Recap.RunSeconds(run)),
        ("%d/%d"):format(#run.bosses, BossCount(run)) }, NAME_SEPARATOR)
end

local function AddRunRow(run, index)
    local row = list:Acquire("run", MakeRunRow)
    row.index = index
    W.SetDungeonIcon(row.Icon, run.instanceID)
    row.Name:SetText(run.name or "?")
    local muted = C.MUTED
    row.Sub:SetText(RunRowSubText(run))
    row.Sub:SetTextColor(muted[1], muted[2], muted[3])
    row:SetSelected(index == shownIndex)
    list:Place(row, RUN_ROW_HEIGHT)
    list:Space(RUN_ROW_GAP)
end

local function RenderList(runs)
    list:Reset(true)
    for index, run in ipairs(runs) do AddRunRow(run, index) end
    list:Finish()
end

-- Pills of the run: time inside, experience (per hour in its tooltip), money, a new level, deaths.
local function RunPills(run)
    local seconds = Recap.RunSeconds(run)
    local perHour = seconds > 0 and math.floor(run.xp / seconds * SECONDS_PER_HOUR) or 0
    local pills = {
        { icon = TEX.CLOCK, text = DurationText(seconds), tooltipTitle = L["Time in the dungeon"] },
        { icon = TEX.EXPERIENCE, iconCoords = TEX.EXPERIENCE_COORDS, text = ns.Rewards.FormatExperience(run.xp),
            tooltipTitle = L["Experience gained"], tooltipText = L["%s per hour"]:format(ns.Rewards.FormatExperience(perHour)) },
        { text = ns.Rewards.FormatMoney(run.money), tooltipTitle = L["Money looted and earned"] },
    }
    if run.endLevel > run.startLevel then
        pills[#pills + 1] = { text = L["Level %d"]:format(run.endLevel), tooltipTitle = L["You reached a new level"] }
    end
    if run.deaths > 0 then pills[#pills + 1] = { icon = TEX.DEATH, text = tostring(run.deaths), tooltipTitle = L["Deaths"] } end
    return pills
end

-- "Zul'Alai  ·  12:34" for a defeated boss, the name alone when the time was not recorded.
local function KilledBossText(run, name)
    local seconds = run.killTimes and run.killTimes[name]
    if not seconds then return name end
    return name .. NAME_SEPARATOR .. ns.Hex(C.MUTED) .. L["after %s"]:format(DurationText(seconds)) .. "|r"
end

local function RenderKilledBosses(run)
    for _, name in ipairs(run.bosses) do
        page:Link(KilledBossText(run, name), nil, C.TEXT, { TEX.TICK, L["Defeated"] })
    end
end

-- Bosses of the dungeon the run did not defeat, muted.
local function RenderMissedBosses(run)
    local killed = {}
    for _, name in ipairs(run.bosses) do killed[name] = true end
    for _, boss in ipairs(ns.BOSSES[run.instanceID] or {}) do
        if not killed[boss.name] then page:Link(boss.name, nil, C.MUTED) end
    end
end

local function RenderBosses(run)
    page:Heading(L["Bosses"], ("%d/%d"):format(#run.bosses, BossCount(run)))
    if #run.bosses == 0 then page:Text(L["No boss defeated."], ns.Font("disable"), C.MUTED) end
    RenderKilledBosses(run)
    RenderMissedBosses(run)
end

-- Turned-in quests; one of the dungeon's own opens on its journal page.
local function RenderQuests(run)
    if #run.quests == 0 then return end
    page:Heading(L["Quests completed"], #run.quests)
    for _, questID in ipairs(run.quests) do
        local quest = W.QuestByID(questID)
        local open = not quest.stub and function() ns.Journal:ShowQuest(run.instanceID, quest) end or nil
        page:Link(quest.name, open, open and C.GOLD or C.TEXT)
    end
end

-- Names of the group sorted, each with its class icon.
local function GroupText(group)
    local names = {}
    for name in pairs(group) do names[#names + 1] = name end
    table.sort(names)
    for index, name in ipairs(names) do
        local class = group[name]
        if type(class) == "string" then names[index] = W.ClassIconString(class, CLASS_ICON_SIZE) .. " " .. name end
    end
    return table.concat(names, NAME_SEPARATOR), #names
end

local function RenderGroup(run)
    if type(run.group) ~= "table" or next(run.group) == nil then return end
    local text, count = GroupText(run.group)
    page:Heading(L["Group"], count)
    page:Text(text)
end

-- Item IDs of a run, the best quality first.
local function SortedLoot(run)
    local itemIDs, quality = {}, {}
    for itemID in pairs(run.items) do
        itemIDs[#itemIDs + 1] = itemID
        quality[itemID] = select(3, W.ItemData(itemID)) or 0
    end
    table.sort(itemIDs, function(first, second)
        if quality[first] ~= quality[second] then return quality[first] > quality[second] end
        return first < second
    end)
    return itemIDs
end

local function RenderLoot(run)
    local itemIDs = SortedLoot(run)
    page:Heading(L["Loot"], #itemIDs)
    if #itemIDs == 0 then
        page:Text(L["Nothing looted."], ns.Font("disable"), C.MUTED)
        return
    end
    for _, itemID in ipairs(itemIDs) do page:Item(itemID, run.items[itemID]) end
end

local function RenderRun(run)
    W.SetDungeonHeader(header, run.instanceID, run.name, WhenText(run))
    -- the same run painted again (it is still being recorded) keeps its scroll position
    page:Reset(run == paintedRun)
    page:Pills(RunPills(run))
    RenderBosses(run)
    RenderQuests(run)
    RenderGroup(run)
    RenderLoot(run)
    page:Finish()
end

local function RenderEmpty()
    page:Reset()
    page:Empty(L["No dungeon run recorded yet. The recap opens when you leave a dungeon."])
    page:Finish()
end

local function UpdateNavigation(run, count)
    positionLabel:SetText(run and L["Run %d of %d"]:format(shownIndex, count) or "")
    W.SetDisabled(newerButton, shownIndex <= 1)
    W.SetDisabled(olderButton, shownIndex >= count)
end

local function Render()
    local runs = Recap.Runs()
    shownIndex = math.max(1, math.min(shownIndex, #runs))
    local run = runs[shownIndex]
    header:SetShown(run ~= nil)
    RenderList(runs)
    if run then RenderRun(run) else RenderEmpty() end
    paintedRun = run
    UpdateNavigation(run, #runs)
end

-- One repaint for a burst of events, only while the window is open.
function Recap.Refresh()
    if refreshQueued or not (window and window:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshQueued = false
        if window:IsShown() then Render() end
    end)
end

-- Show run `index` (1 = newest) of the list.
function Recap.Show(index)
    shownIndex = index
    Render()
end

-- Footer: "Newer" and "Older" step through the runs, "Run 2 of 7" between them.
local function CreateNavigation()
    newerButton = W.Tab(window, L["Newer"], nil, NAVIGATION_WIDTH, NAVIGATION_HEIGHT)
    newerButton:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
    newerButton:SetScript("OnClick", function() Recap.Show(shownIndex - 1) end)
    olderButton = W.Tab(window, L["Older"], nil, NAVIGATION_WIDTH, NAVIGATION_HEIGHT)
    olderButton:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
    olderButton:SetScript("OnClick", function() Recap.Show(shownIndex + 1) end)
    positionLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    positionLabel:SetPoint("CENTER", window, "BOTTOM", 0, MARGIN + NAVIGATION_HEIGHT / 2)
end

-- Left: the scrolling list of runs.
local function CreateList()
    local body = W.Panel(window)
    body:SetPoint("TOPLEFT", MARGIN, -TOP)
    body:SetPoint("BOTTOMLEFT", MARGIN, MARGIN + FOOTER_HEIGHT)
    body:SetWidth(LIST_WIDTH)
    list = ns.Canvas.New("ForeverDungeonMapRecapList", body, { width = LIST_ROW_WIDTH, wheelStep = RUN_ROW_HEIGHT })
    list.scroll:SetPoint("TOPLEFT", LIST_INSET, -LIST_INSET)
    list.scroll:SetPoint("BOTTOMRIGHT", -LIST_SCROLL_BAR, LIST_INSET)
    return body
end

-- Right: the dungeon header over the scrolling page of the picked run.
local function CreateDetail(listBody)
    header = W.DungeonHeader(window, HEADER_ICON_SIZE, HEADER_ICON_LEFT)
    header:SetPoint("TOPLEFT", listBody, "TOPRIGHT", PANEL_GAP, 0)
    header:SetPoint("TOPRIGHT", -MARGIN, -TOP)
    header:SetHeight(HEADER_HEIGHT)
    local body = W.Panel(window)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -PANEL_GAP)
    body:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN + FOOTER_HEIGHT)
    page = ns.Canvas.New("ForeverDungeonMapRecapPage", body, { width = PAGE_WIDTH })
    page.scroll:SetPoint("TOPLEFT", PAGE_INSET, -PAGE_INSET)
    page.scroll:SetPoint("BOTTOMRIGHT", -PAGE_SCROLL_BAR, PAGE_INSET)
end

local function CreateWindow()
    window = W.Window(WINDOW_NAME, WINDOW_WIDTH, WINDOW_HEIGHT, L["Dungeon Recap"])
    W.PlaceWindow(window, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y)
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:Hide()
    tinsert(UISpecialFrames, WINDOW_NAME)
    W.MarkOwned(window)
    W.SetupTooltipBacking()
    CreateDetail(CreateList())
    CreateNavigation()
end

-- The recap window on the newest run (the one being recorded while inside a dungeon).
function Recap.Open()
    if not window then CreateWindow() end
    shownIndex = 1
    Render()
    window:Show()
    window:Raise()
end

function Recap.IsShown() return window ~= nil and window:IsShown() end
