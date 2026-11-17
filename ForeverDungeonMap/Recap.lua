-- ForeverDungeonMap - dungeon recap: what happened in a dungeon run (time, experience, money,
-- loot, bosses, quests, deaths), recorded while the player is inside and shown when they leave.
-- Runs are kept per character (ns.Character().runs, newest first).
-- Loot is every item count that grows in the bags or on the character: this client gives addons
-- no combat log, and loot lines in chat are worded differently in every language.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L
local W, C, TEX = ns.W, ns.C, ns.TEX

local Recap = {}
ns.Recap = Recap

local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots
local GetContainerItemInfo = C_Container and C_Container.GetContainerItemInfo

local WINDOW_NAME = "ForeverDungeonMapRecap"
local WINDOW_WIDTH, WINDOW_HEIGHT = 440, 560
-- where the window opens until the player drags it: right of the screen centre, out of the way
local DEFAULT_POINT, DEFAULT_X, DEFAULT_Y = "RIGHT", -80, 40
-- layout: side margin, header band under the title ribbon, gap to the page, footer with the run buttons
local MARGIN, HEADER_TOP, HEADER_HEIGHT, PANEL_GAP, FOOTER_HEIGHT = 16, 44, 64, 8, 34
local HEADER_ICON_SIZE, HEADER_ICON_LEFT = 44, 10
local PAGE_INSET, PAGE_SCROLL_BAR = 12, 28
local PAGE_WIDTH = WINDOW_WIDTH - 2 * MARGIN - PAGE_INSET - PAGE_SCROLL_BAR
local NAVIGATION_WIDTH, NAVIGATION_HEIGHT = 96, 24
-- runs kept per character
local MAX_RUNS = 20
-- a run left as a ghost or by a /reload goes on when the player is back inside within this time
local RESUME_SECONDS = 600
local SECONDS_PER_MINUTE, SECONDS_PER_HOUR = 60, 3600
local REFRESH_DELAY = 0.5
-- backpack and equipped bags; the worn gear slots end at the tabard
local FIRST_BAG, LAST_BAG, LAST_EQUIPMENT_SLOT = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4, 19
local NAME_SEPARATOR = "  ·  "

-- the run being recorded (the newest of the character's runs); nil outside dungeons
local current
-- GetTime() when the current stretch inside the dungeon began
local segmentStart = 0
-- what the player had at the last look: gains are counted from these
local lastExperience, lastExperienceMax, lastMoney
local carriedItems = {}

local window, header, page, positionLabel, newerButton, olderButton
-- which run the window shows (1 = newest), and the run painted last
local shownIndex, paintedRun = 1, nil
local refreshQueued = false

local function Runs()
    return ns.Character().runs
end

local function ContainerItem(bag, slot)
    local ok, info = pcall(GetContainerItemInfo, bag, slot)
    return ok and type(info) == "table" and info or nil
end

-- itemID -> how many the player carries or wears. Worn gear counts too, so putting on a new
-- piece (the old one drops into the bags) is not loot.
local function CarriedItems()
    local counts = {}
    if not (GetContainerNumSlots and GetContainerItemInfo) then return counts end
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, ns.SafeNumber(GetContainerNumSlots, bag) or 0 do
            local info = ContainerItem(bag, slot)
            if info and info.itemID then counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1) end
        end
    end
    for slot = 1, LAST_EQUIPMENT_SLOT do
        local itemID = ns.SafeNumber(GetInventoryItemID, "player", slot)
        if itemID then counts[itemID] = (counts[itemID] or 0) + 1 end
    end
    return counts
end

-- Remember what the player has now and start the clock.
local function TakeBaseline()
    lastExperience, lastExperienceMax = ns.SafeNumber(UnitXP, "player"), ns.SafeNumber(UnitXPMax, "player")
    lastMoney = ns.SafeNumber(GetMoney)
    carriedItems = CarriedItems()
    segmentStart = GetTime()
end

local function RecordExperience()
    local experience, maximum = ns.SafeNumber(UnitXP, "player"), ns.SafeNumber(UnitXPMax, "player")
    if not (current and experience and maximum and lastExperience) then return end
    local gained = experience - lastExperience
    -- the bar started again: a new level, and the rest of the old bar was earned too
    if gained < 0 then gained = (lastExperienceMax - lastExperience) + experience end
    current.xp = current.xp + gained
    current.endLevel = math.max(current.endLevel, UnitLevel("player") or 0)
    lastExperience, lastExperienceMax = experience, maximum
end

local function RecordMoney()
    local money = ns.SafeNumber(GetMoney)
    if not (current and money and lastMoney) then return end
    -- spending (repairs, a vendor) is not part of the run
    if money > lastMoney then current.money = current.money + money - lastMoney end
    lastMoney = money
end

-- Every item count that grew since the last look is loot.
local function RecordLoot()
    if not current then return end
    local counts = CarriedItems()
    for itemID, count in pairs(counts) do
        local gained = count - (carriedItems[itemID] or 0)
        if gained > 0 then current.items[itemID] = (current.items[itemID] or 0) + gained end
    end
    carriedItems = counts
end

-- xp, money (copper), seconds: gained inside; items = { [itemID] = count }; bosses = names;
-- quests = quest IDs; open: the player may still walk back into it; pausedAt: time() they left.
local function NewRun(instanceID, name)
    local level = UnitLevel("player") or 1
    return { instanceID = instanceID, name = ns.GetDungeon(instanceID, name).name, startedAt = time(), seconds = 0,
        xp = 0, money = 0, deaths = 0, startLevel = level, endLevel = level, bosses = {}, quests = {}, items = {}, open = true }
end

local function NothingHappened(run)
    return run.xp == 0 and run.money == 0 and run.deaths == 0 and #run.bosses == 0 and #run.quests == 0
        and next(run.items) == nil
end

-- The newest run is over; one in which nothing happened (a look through the portal) is dropped.
local function CloseNewestRun()
    local runs = Runs()
    local run = runs[1]
    if not (run and run.open) then return end
    run.open, run.pausedAt = nil, nil
    if NothingHappened(run) then table.remove(runs, 1) end
end

-- The run the player comes back into: this dungeon, left as a ghost or by a /reload, not long ago.
local function ResumableRun(instanceID)
    local run = Runs()[1]
    if not (run and run.open and run.instanceID == instanceID) then return nil end
    if run.pausedAt and time() - run.pausedAt > RESUME_SECONDS then return nil end
    return run
end

local function StartRun(instanceID, name)
    local runs = Runs()
    local run = ResumableRun(instanceID)
    if run then
        run.pausedAt = nil
    else
        CloseNewestRun()
        run = NewRun(instanceID, name)
        table.insert(runs, 1, run)
        for index = #runs, MAX_RUNS + 1, -1 do runs[index] = nil end
    end
    current = run
    TakeBaseline()
end

-- Stop the clock. resumable: the player may come back (ghost run, /reload); otherwise the run
-- is over. Returns the run that was being recorded.
local function StopRun(resumable)
    local run = current
    if not run then return nil end
    run.seconds = run.seconds + math.max(0, GetTime() - segmentStart)
    current = nil
    if resumable then run.pausedAt = time() else CloseNewestRun() end
    return run
end

-- Seconds spent inside (the clock of the run being recorded is still running).
local function RunSeconds(run)
    if run == current then return run.seconds + GetTime() - segmentStart end
    return run.seconds
end

-- "23:45", or "1:05:23" from an hour on.
local function DurationText(seconds)
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / SECONDS_PER_HOUR)
    local minutes = math.floor(seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE)
    if hours > 0 then return ("%d:%02d:%02d"):format(hours, minutes, seconds % SECONDS_PER_MINUTE) end
    return ("%d:%02d"):format(minutes, seconds % SECONDS_PER_MINUTE)
end

-- First row of pills: time inside and experience (per hour in its tooltip).
local function ProgressPills(run)
    local seconds = RunSeconds(run)
    local perHour = seconds > 0 and math.floor(run.xp / seconds * SECONDS_PER_HOUR) or 0
    return {
        { icon = TEX.CLOCK, text = DurationText(seconds), tooltipTitle = L["Time in the dungeon"] },
        { icon = TEX.EXPERIENCE, iconCoords = TEX.EXPERIENCE_COORDS, text = ns.Rewards.FormatExperience(run.xp),
            tooltipTitle = L["Experience gained"], tooltipText = L["%s per hour"]:format(ns.Rewards.FormatExperience(perHour)) },
    }
end

-- Second row of pills: money, a new level, deaths.
local function ResultPills(run)
    local pills = { { text = ns.Rewards.FormatMoney(run.money), tooltipTitle = L["Money looted and earned"] } }
    if run.endLevel > run.startLevel then
        pills[#pills + 1] = { text = L["Level %d"]:format(run.endLevel), tooltipTitle = L["You reached a new level"] }
    end
    if run.deaths > 0 then pills[#pills + 1] = { icon = TEX.DEATH, text = tostring(run.deaths), tooltipTitle = L["Deaths"] } end
    return pills
end

local function RenderBosses(run)
    local total = #(ns.BOSSES[run.instanceID] or {})
    page:Heading(L["Bosses"], ("%d/%d"):format(#run.bosses, total))
    if #run.bosses == 0 then
        page:Text(L["No boss defeated."], ns.Font("disable"), C.MUTED)
        return
    end
    page:Text(table.concat(run.bosses, NAME_SEPARATOR))
end

local function RenderQuests(run)
    if #run.quests == 0 then return end
    page:Heading(L["Quests completed"], #run.quests)
    local names = {}
    for index, questID in ipairs(run.quests) do names[index] = W.QuestName(questID) end
    page:Text(table.concat(names, NAME_SEPARATOR))
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

-- "2026-11-15 18:30", and "In progress" for the run being recorded.
local function HeaderSubText(run)
    local started = date("%Y-%m-%d %H:%M", run.startedAt)
    if run ~= current then return started end
    return started .. NAME_SEPARATOR .. ns.Hex(C.DONE) .. L["In progress"] .. "|r"
end

local function RenderRun(run)
    W.SetDungeonHeader(header, run.instanceID, run.name, HeaderSubText(run))
    -- the same run painted again (it is still being recorded) keeps its scroll position
    page:Reset(run == paintedRun)
    page:Pills(ProgressPills(run))
    page:Pills(ResultPills(run))
    RenderBosses(run)
    RenderQuests(run)
    RenderLoot(run)
    page:Finish()
end

local function RenderEmpty()
    page:Reset()
    page:Empty(L["No dungeon run recorded yet. The recap opens when you leave a dungeon."])
    page:Finish()
end

local function Render()
    local runs = Runs()
    shownIndex = math.max(1, math.min(shownIndex, #runs))
    local run = runs[shownIndex]
    header:SetShown(run ~= nil)
    if run then RenderRun(run) else RenderEmpty() end
    paintedRun = run
    positionLabel:SetText(run and L["Run %d of %d"]:format(shownIndex, #runs) or "")
    W.SetDisabled(newerButton, shownIndex <= 1)
    W.SetDisabled(olderButton, shownIndex >= #runs)
end

-- One repaint for a burst of events, only while the window is open.
local function QueueRefresh()
    if refreshQueued or not (window and window:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshQueued = false
        if window:IsShown() then Render() end
    end)
end

local function ShowIndex(index)
    shownIndex = index
    Render()
end

-- Footer: "Newer" and "Older" step through the runs, "Run 2 of 7" between them.
local function CreateNavigation()
    newerButton = W.Tab(window, L["Newer"], nil, NAVIGATION_WIDTH, NAVIGATION_HEIGHT)
    newerButton:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
    newerButton:SetScript("OnClick", function() ShowIndex(shownIndex - 1) end)
    olderButton = W.Tab(window, L["Older"], nil, NAVIGATION_WIDTH, NAVIGATION_HEIGHT)
    olderButton:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
    olderButton:SetScript("OnClick", function() ShowIndex(shownIndex + 1) end)
    positionLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    positionLabel:SetPoint("CENTER", window, "BOTTOM", 0, MARGIN + NAVIGATION_HEIGHT / 2)
end

local function CreatePage()
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
    header = W.DungeonHeader(window, HEADER_ICON_SIZE, HEADER_ICON_LEFT)
    header:SetPoint("TOPLEFT", MARGIN, -HEADER_TOP)
    header:SetPoint("TOPRIGHT", -MARGIN, -HEADER_TOP)
    header:SetHeight(HEADER_HEIGHT)
    CreatePage()
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

-- The run being recorded, or nil outside dungeons (tests and the bug report read it).
function Recap.Current() return current end

-- Entering a dungeon starts (or goes on with) a run; leaving it alive ends the run and shows
-- the recap; leaving as a ghost only stops the clock until the player is back.
local function OnInstanceChanged(instanceID, name)
    local ghost = UnitIsDeadOrGhost("player") and true or false
    local stopped = StopRun(ghost)
    if instanceID then
        StartRun(instanceID, name)
    elseif stopped and not ghost and Runs()[1] == stopped and ns.Setting("recapPopup") ~= false then
        Recap.Open()
    end
    QueueRefresh()
end

local EVENT_HANDLERS = {
    PLAYER_XP_UPDATE = RecordExperience,
    PLAYER_MONEY = RecordMoney,
    BAG_UPDATE_DELAYED = RecordLoot,
    PLAYER_DEAD = function()
        if current then current.deaths = current.deaths + 1 end
    end,
    QUEST_TURNED_IN = function(questID)
        if current and type(questID) == "number" then table.insert(current.quests, questID) end
    end,
    -- logging out or /reload inside: the run goes on when the player is back in time
    PLAYER_LOGOUT = function() StopRun(true) end,
}

local function ListenToEvents()
    local events = CreateFrame("Frame")
    -- an event this client does not know must never break loading
    for event in pairs(EVENT_HANDLERS) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnEvent", function(_, event, ...)
        EVENT_HANDLERS[event](...)
        QueueRefresh()
    end)
end

ns.OnLoad(ListenToEvents)
ns.OnInstanceChanged(OnInstanceChanged)
ns.OnBossKilled(function(_, boss)
    if current then table.insert(current.bosses, boss.name) end
    QueueRefresh()
end)
