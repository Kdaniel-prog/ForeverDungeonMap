-- ForeverDungeonMap - quest experience and money rewards for the journal's reward pills.
-- Experience: what the game tells us (quest log API, or learned from the quest frames at the
-- player's current level), else QuestieDB's offline table (Data/QuestXP.lua), scaled to the
-- player's level and marked approximate.
-- Money: only what the game tells us.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L

local Rewards = {}
ns.Rewards = Rewards

-- quest frame events that read the shown quest's rewards; true = the frame lists its rewards
-- (QUEST_PROGRESS does not: only non-zero values are kept from it)
local LEARN_EVENTS = { QUEST_DETAIL = true, QUEST_PROGRESS = false, QUEST_COMPLETE = true }
-- level penalty of quest experience (cMaNGOS formula, as in Questie's QuestXP, GPLv3):
-- tenths of the full value = 2 * (quest level - player level) + 20, kept within 1..10
local TENTHS_AT_SAME_LEVEL, TENTHS_PER_LEVEL, TENTHS_MIN, TENTHS_MAX = 20, 2, 1, 10
-- the server rounds the result to these steps
local EXPERIENCE_ROUNDING = {
    { limit = 100, step = 5 }, { limit = 500, step = 10 }, { limit = 1000, step = 25 }, { limit = math.huge, step = 50 },
}
local COPPER_PER_SILVER, COPPER_PER_GOLD = 100, 10000
-- "≈" in front of estimated experience
local APPROXIMATE_PREFIX = "\226\137\136"

local listeners = {}

local function PlayerLevel()
    return UnitLevel("player") or 1
end

local function IsMaxLevel()
    if type(GetMaxPlayerLevel) ~= "function" then return false end
    local ok, maxLevel = pcall(GetMaxPlayerLevel)
    return ok and type(maxLevel) == "number" and PlayerLevel() >= maxLevel
end

-- A positive number from a game API, or nil (missing API, error, secret value, zero).
local function PositiveNumber(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if not ok or type(value) ~= "number" then return nil end
    local isSecret = _G.issecretvalue
    if isSecret and isSecret(value) then return nil end
    return value > 0 and value or nil
end

local function LearnedRewards()
    local savedSettings = ns.db or ForeverDungeonMapDB
    if type(savedSettings) ~= "table" then return {} end
    savedSettings.learnedRewards = savedSettings.learnedRewards or {}
    return savedSettings.learnedRewards
end

local function RoundExperience(experience)
    for _, rounding in ipairs(EXPERIENCE_ROUNDING) do
        if experience <= rounding.limit then
            local half = math.floor(rounding.step / 2)
            return rounding.step * math.floor((experience + half) / rounding.step)
        end
    end
end

-- Full quest experience -> what a player of the current level gets.
local function ScaleExperience(fullExperience, questLevel)
    if type(questLevel) ~= "number" then return fullExperience end
    local tenths = TENTHS_PER_LEVEL * (questLevel - PlayerLevel()) + TENTHS_AT_SAME_LEVEL
    tenths = math.max(TENTHS_MIN, math.min(TENTHS_MAX, tenths))
    return RoundExperience(fullExperience * tenths / 10)
end
Rewards.ScaleExperience = ScaleExperience

local function QuestLevel(questID)
    local W = ns.W
    return W and W.QuestLevel(W.QuestByID(questID)) or nil
end

local function OfflineExperience(questID)
    return ns.QUEST_XP and ns.QUEST_XP[questID]
end

-- quests whose data was asked from the server once (the answer fires QUEST_DATA_LOAD_RESULT)
local requested = {}

-- Ask the game to load a quest it has not cached yet, so GetQuestLogRewardXP gets its WoW Forever
-- value; one request per quest and session.
local function RequestQuestData(questID)
    if requested[questID] or not (C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function") then return end
    requested[questID] = true
    pcall(C_QuestLog.RequestLoadQuestByID, questID)
end

-- experience, approximate
local function Experience(questID, learned)
    if IsMaxLevel() then return nil, false end
    local live = PositiveNumber(GetQuestLogRewardXP, questID)
    if live then return live, false end
    RequestQuestData(questID)
    if learned and learned.xp and learned.level == PlayerLevel() then return learned.xp, false end
    local full = OfflineExperience(questID)
    if full then return ScaleExperience(full, QuestLevel(questID)), true end
    if learned and learned.xp then return learned.xp, true end
    return nil, false
end

-- { xp = number|nil, money = copper|nil, approximate = true when xp is an estimate }
function Rewards.Get(questID)
    local learned = LearnedRewards()[questID]
    local xp, approximate = Experience(questID, learned)
    local learnedMoney = learned and learned.money
    local money = PositiveNumber(GetQuestLogRewardMoney, questID) or (learnedMoney and learnedMoney > 0 and learnedMoney or nil)
    return { xp = xp, money = money, approximate = approximate }
end

-- Item IDs the game showed on the quest frame: choices, rewards; nil when never seen there.
function Rewards.Items(questID)
    local learned = LearnedRewards()[questID]
    if not (learned and learned.choices) then return nil end
    return learned.choices, learned.rewards or {}
end

-- Run listener(questID) whenever a quest's rewards were learned from a quest frame or loaded.
function Rewards.OnLearned(listener)
    table.insert(listeners, listener)
end

local function NotifyLearned(questID)
    for _, listener in ipairs(listeners) do
        local ok, problem = pcall(listener, questID)
        if not ok then geterrorhandler()(problem) end
    end
end

-- "1,600 XP", with "≈" in front when estimated.
function Rewards.FormatExperience(experience, approximate)
    local number = type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(experience) or tostring(experience)
    return (approximate and APPROXIMATE_PREFIX or "") .. L["%s XP"]:format(number)
end

local function CoinText(amount, texture, letter)
    if texture then return ("%d|T%s:0:0:2:0|t"):format(amount, tostring(texture)) end
    return amount .. letter
end

-- Copper as gold / silver / copper with Blizzard's coin icons.
function Rewards.FormatMoney(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    if type(GetCoinTextureString) == "function" then return GetCoinTextureString(copper) end
    local TEX = ns.TEX or {}
    local gold = math.floor(copper / COPPER_PER_GOLD)
    local silver = math.floor(copper % COPPER_PER_GOLD / COPPER_PER_SILVER)
    local rest = copper % COPPER_PER_SILVER
    local parts = {}
    if gold > 0 then parts[#parts + 1] = CoinText(gold, TEX.COIN_GOLD, "g") end
    if silver > 0 then parts[#parts + 1] = CoinText(silver, TEX.COIN_SILVER, "s") end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = CoinText(rest, TEX.COIN_COPPER, "c") end
    return table.concat(parts, " ")
end

local function CanReadFrameItems()
    return type(GetQuestItemLink) == "function" and type(GetNumQuestChoices) == "function"
        and type(GetNumQuestRewards) == "function"
end

-- Item IDs of the quest frame's "choice" or "reward" list.
local function FrameItems(listType, countApi)
    local items = {}
    for i = 1, PositiveNumber(countApi) or 0 do
        local ok, link = pcall(GetQuestItemLink, listType, i)
        local itemID = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if itemID then items[#items + 1] = itemID end
    end
    return items
end

-- Read the quest frame's rewards (QUEST_DETAIL / QUEST_PROGRESS / QUEST_COMPLETE).
local function Learn(event)
    local questID = PositiveNumber(GetQuestID)
    if not questID then return end
    local listsRewards = LEARN_EVENTS[event]
    local experience, money = PositiveNumber(GetRewardXP), PositiveNumber(GetRewardMoney)
    if not experience and not money and not listsRewards then return end
    local learned = LearnedRewards()
    local entry = learned[questID] or {}
    if experience then entry.xp, entry.level = experience, PlayerLevel() end
    if money or listsRewards then entry.money = money or 0 end
    if listsRewards and CanReadFrameItems() then
        entry.choices, entry.rewards = FrameItems("choice", GetNumQuestChoices), FrameItems("reward", GetNumQuestRewards)
    end
    learned[questID] = entry
    NotifyLearned(questID)
end

-- Quest frame events, once the saved settings are loaded.
local function ListenToQuestFrames()
    local events = CreateFrame("Frame")
    for event in pairs(LEARN_EVENTS) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnEvent", function(_, event) Learn(event) end)
    -- a requested quest arrived: its WoW Forever experience can be read now
    local loads = CreateFrame("Frame")
    pcall(loads.RegisterEvent, loads, "QUEST_DATA_LOAD_RESULT")
    loads:SetScript("OnEvent", function(_, _, questID, success)
        if success and requested[questID] then NotifyLearned(questID) end
    end)
end

ns.OnLoad(function()
    LearnedRewards()
    ListenToQuestFrames()
end)
