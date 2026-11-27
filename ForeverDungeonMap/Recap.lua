-- ForeverDungeonMap - dungeon recap: records what happens in a dungeon run (time, experience, money,
-- loot, bosses and when they fell, quests, deaths, the group) while the player is inside; the window
-- (RecapWindow.lua) shows it when they leave. Runs are kept per character (ns.Character().runs, newest first).
-- Loot is every item count that grows in the bags or on the character: this client gives addons
-- no combat log, and loot lines in chat are worded differently in every language.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

local Recap = {}
ns.Recap = Recap

local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots
local GetContainerItemInfo = C_Container and C_Container.GetContainerItemInfo

-- runs kept per character
local MAX_RUNS = 20
-- a run left as a ghost or by a /reload goes on when the player is back inside within this time
local RESUME_SECONDS = 600
-- backpack and equipped bags; the worn gear slots end at the tabard
local FIRST_BAG, LAST_BAG, LAST_EQUIPMENT_SLOT = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4, 19
local PARTY_SIZE = 4

-- the run being recorded (the newest of the character's runs); nil outside dungeons
local current
-- GetTime() when the current stretch inside the dungeon began
local segmentStart = 0
-- what the player had at the last look: gains are counted from these
local lastExperience, lastExperienceMax, lastMoney
local carriedItems = {}

function Recap.Runs()
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

-- Everyone who was in the group during the run: name -> class file ("MAGE").
local function RecordGroup()
    if not current then return end
    current.group = current.group or {}
    for index = 1, PARTY_SIZE do
        local unit = "party" .. index
        local name = UnitExists(unit) and UnitName(unit)
        if type(name) == "string" and name ~= "" then current.group[name] = select(2, UnitClass(unit)) or true end
    end
end

-- xp, money (copper), seconds: gained inside; items = { [itemID] = count }; bosses = names;
-- killTimes = { [boss name] = seconds into the run }; quests = quest IDs; group = { [name] = class };
-- open: the player may still walk back into it; pausedAt: time() they left; endedAt: time() it ended.
local function NewRun(instanceID, name)
    local level = UnitLevel("player") or 1
    return { instanceID = instanceID, name = ns.GetDungeon(instanceID, name).name, startedAt = time(), seconds = 0,
        xp = 0, money = 0, deaths = 0, startLevel = level, endLevel = level, bosses = {}, killTimes = {}, quests = {},
        items = {}, group = {}, open = true }
end

local function NothingHappened(run)
    return run.xp == 0 and run.money == 0 and run.deaths == 0 and #run.bosses == 0 and #run.quests == 0
        and next(run.items) == nil
end

-- The newest run is over; one in which nothing happened (a look through the portal) is dropped.
local function CloseNewestRun()
    local runs = Recap.Runs()
    local run = runs[1]
    if not (run and run.open) then return end
    run.endedAt = run.pausedAt or time()
    run.open, run.pausedAt = nil, nil
    if NothingHappened(run) then table.remove(runs, 1) end
end

-- The run the player comes back into: this dungeon, left as a ghost or by a /reload, not long ago.
local function ResumableRun(instanceID)
    local run = Recap.Runs()[1]
    if not (run and run.open and run.instanceID == instanceID) then return nil end
    if run.pausedAt and time() - run.pausedAt > RESUME_SECONDS then return nil end
    return run
end

local function StartRun(instanceID, name)
    local runs = Recap.Runs()
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
    RecordGroup()
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
function Recap.RunSeconds(run)
    if run == current then return run.seconds + GetTime() - segmentStart end
    return run.seconds
end

-- The run being recorded, or nil outside dungeons (tests and the bug report read it).
function Recap.Current() return current end

-- Repaint the window if it is open (RecapWindow.lua).
local function Refresh()
    if Recap.Refresh then Recap.Refresh() end
end

-- Entering a dungeon starts (or goes on with) a run; leaving it alive ends the run and shows
-- the recap; leaving as a ghost only stops the clock until the player is back.
local function OnInstanceChanged(instanceID, name)
    local ghost = UnitIsDeadOrGhost("player") and true or false
    local stopped = StopRun(ghost)
    if instanceID then
        StartRun(instanceID, name)
    elseif stopped and not ghost and Recap.Runs()[1] == stopped and ns.Setting("recapPopup") ~= false and Recap.Open then
        Recap.Open()
    end
    Refresh()
end

local EVENT_HANDLERS = {
    PLAYER_XP_UPDATE = RecordExperience,
    PLAYER_MONEY = RecordMoney,
    BAG_UPDATE_DELAYED = RecordLoot,
    GROUP_ROSTER_UPDATE = RecordGroup,
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
        Refresh()
    end)
end

-- A boss fell: its name and how far into the run (runs from before 0.8 have no killTimes).
local function OnBossKilled(_, boss)
    if not current then return end
    table.insert(current.bosses, boss.name)
    current.killTimes = current.killTimes or {}
    current.killTimes[boss.name] = math.floor(Recap.RunSeconds(current))
    Refresh()
end

ns.OnLoad(ListenToEvents)
ns.OnInstanceChanged(OnInstanceChanged)
ns.OnBossKilled(OnBossKilled)
