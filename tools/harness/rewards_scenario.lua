-- rewards_scenario.lua - quest XP / money rewards (Rewards.lua, Data/QuestXP.lua).
-- The shared mock has no quest frame reward APIs or events: stand-ins are defined here.
-- Run with and without --combat.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step

for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do M.KNOWN_EVENTS[event] = true end
-- the quest frame currently shown, and quest log reward values the client has cached
local questFrame = { questID = 0, xp = 0, money = 0 }
local questLogXP, questLogMoney = {}, {}
function GetQuestID() return questFrame.questID end
function GetRewardXP() return questFrame.xp end
function GetRewardMoney() return questFrame.money end
function GetQuestLogRewardXP(questID) return questLogXP[questID] or 0 end
function GetQuestLogRewardMoney(questID) return questLogMoney[questID] or 0 end
function GetMaxPlayerLevel() return 60 end
-- a "secret" value as the modern client hands out in combat
local SECRET = 777
function issecretvalue(value) return value == SECRET end
-- another addon's XP table must be ignored (only shipped data counts)
ForeverDungeonJournal_NS = { FOREVER_QUEST_BASE_XP = { [96394] = 1050 } }

Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
M.Advance(6)

Check("generated XP table loaded", type(ns.QUEST_XP) == "table" and ns.QUEST_XP[1486] == 1600)
Check("learnedRewards created in the saved settings", type(ForeverDungeonMapDB.learnedRewards) == "table")

-- offline values, scaled to the player's level (cMaNGOS rounding)
M.player.level = 20
local reward = ns.Rewards.Get(1486)
Check("offline XP at a lower player level: full value, approximate", reward.xp == 1600 and reward.approximate == true and reward.money == nil,
    tostring(reward.xp))
M.player.level = 25
Check("offline XP scaled down 8 levels above the quest", ns.Rewards.Get(1486).xp == 650, tostring(ns.Rewards.Get(1486).xp))
M.player.level = 60
Check("no XP at max level", ns.Rewards.Get(1486).xp == nil)
M.player.level = 20
Check("unknown quest: nothing", ns.Rewards.Get(424242).xp == nil and ns.Rewards.Get(424242).money == nil)
Check("other addons' XP tables are not read", ns.Rewards.Get(96394).xp == (ns.QUEST_XP[96394] and ns.Rewards.Get(96394).xp or nil))

-- what the client says wins
questLogXP[1486], questLogMoney[1486] = 1234, 560
reward = ns.Rewards.Get(1486)
Check("quest log API values are exact", reward.xp == 1234 and reward.money == 560 and reward.approximate == false)
questLogXP[1486], questLogMoney[1486] = SECRET, nil
Check("secret values are ignored", ns.Rewards.Get(1486).xp == 1600)
questLogXP[1486] = nil

-- learning from the quest frames
local learnedIDs = {}
ns.Rewards.OnLearned(function(questID) learnedIDs[#learnedIDs + 1] = questID end)
questFrame.questID, questFrame.xp, questFrame.money = 959, 1300, 2500
Step("QUEST_DETAIL", function() M.FireEvent("QUEST_DETAIL") end)
reward = ns.Rewards.Get(959)
Check("learned on QUEST_DETAIL", reward.xp == 1300 and reward.money == 2500 and reward.approximate == false and learnedIDs[1] == 959)
Check("learned values saved", ForeverDungeonMapDB.learnedRewards[959].xp == 1300 and ForeverDungeonMapDB.learnedRewards[959].level == 20)
questFrame.xp, questFrame.money = 0, 0
Step("QUEST_PROGRESS without rewards", function() M.FireEvent("QUEST_PROGRESS") end)
Check("QUEST_PROGRESS zeros do not overwrite", ns.Rewards.Get(959).xp == 1300 and ns.Rewards.Get(959).money == 2500)
questFrame.xp, questFrame.money = 1300, 0
Step("QUEST_COMPLETE without money", function() M.FireEvent("QUEST_COMPLETE") end)
Check("QUEST_COMPLETE: no money reward", ns.Rewards.Get(959).money == nil)
M.player.level = 22
reward = ns.Rewards.Get(959)
Check("learned at another level: offline estimate instead", reward.approximate == true and reward.xp ~= 1300, tostring(reward.xp))
M.player.level = 20
questFrame.questID = 0
Step("QUEST_DETAIL without a quest", function() M.FireEvent("QUEST_DETAIL") end)
Check("no quest ID: nothing learned", ForeverDungeonMapDB.learnedRewards[0] == nil)

-- formatting
local experienceText = ns.Rewards.FormatExperience(1600, true)
Check("XP text with the approximate sign", experienceText == "\226\137\1361,600 XP" or experienceText == "\226\137\1361600 XP", experienceText)
Check("exact XP text", ns.Rewards.FormatExperience(90, false) == "90 XP")
local moneyText = ns.Rewards.FormatMoney(12345)
Check("money without GetCoinTextureString: gold, silver, copper", moneyText:find("1", 1, true) == 1 and moneyText:find("23", 1, true)
    and moneyText:find("45", 1, true), moneyText)
Check("zero money still reads as copper", ns.Rewards.FormatMoney(0):find("0", 1, true) == 1, ns.Rewards.FormatMoney(0))
function GetCoinTextureString(copper) return "coins:" .. copper end
Check("money uses Blizzard's coin string when present", ns.Rewards.FormatMoney(12345) == "coins:12345")
GetCoinTextureString = nil
