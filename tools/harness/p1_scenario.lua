-- p1_scenario.lua - Track / Share, reward pills, boss icon size, favourites, tooltip backing,
-- settings (autoDungeonMap, showOtherFaction). Runs after scenario.lua or on its own.
local addonName, ns = ...
local Mock = MOCK
local Check, Step = Mock.Check, Mock.Step
local COMBAT = Mock.combat

if not ns.db then
    Step("ADDON_LOADED", function() Mock.FireEvent("ADDON_LOADED", addonName) end)
    Step("PLAYER_ENTERING_WORLD", function() Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
end
Mock.player.inInstance = true
Step("back in WC", function() Mock.FireEvent("ZONE_CHANGED_NEW_AREA") end)

local journalState = function() return ns.Journal:State() end
local function questOfWailingCaverns()
    for _, quest in ipairs(ns.QUESTS[43]) do
        if ns.W.QuestState(quest) ~= "other" and (quest.rewards or quest.choices) then return quest end
    end
end
local quest = questOfWailingCaverns()

-- Track / Share
Step("ShowQuest WC", function() ns.Journal:ShowQuest(43, quest) end)
local header = _G.ForeverDungeonMapJournalQuest:GetParent()
local track = Mock.FindChild(header, function(child) return child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() == ns.TEX.TRACK end)
local share = Mock.FindChild(header, function(child) return child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() == ns.TEX.SHARE end)
Check("Track and Share icon buttons on the quest page", track ~= nil and share ~= nil and track:IsVisible())
if track and share then
    Check("Track disabled while the quest is not in the log", track.disabled == true)
    Mock.questsInLog[quest.id] = 1
    Step("QUEST_LOG_UPDATE (accepted)", function() Mock.FireEvent("QUEST_LOG_UPDATE") end)
    Mock.Advance(1)
    Check("Track enabled for a quest in the log", track.disabled == false)
    Check("Share disabled when not in a group", share.disabled == true and share.tooltipLines[1]:find("group", 1, true) ~= nil)
    Step("click Track", function() Mock.Click(track) end)
    Check("Track adds the quest watch", Mock.questsWatched[quest.id] == true and track.selected == true)
    Step("click Track again", function() Mock.Click(track) end)
    Check("Track again removes the quest watch", Mock.questsWatched[quest.id] == nil)
    Mock.party = { { name = "Friend", class = "MAGE" } }
    Step("GROUP_ROSTER_UPDATE", function() Mock.FireEvent("GROUP_ROSTER_UPDATE") end)
    Mock.Advance(1)
    if COMBAT then
        Check("Share disabled in combat", share.disabled == true)
    else
        Check("Share enabled in a group", share.disabled == false)
        Step("click Share", function() Mock.Click(share) end)
        Check("Share selects and pushes the quest", Mock.pushedQuests[#Mock.pushedQuests] == quest.id)
    end
    Mock.party = {}
    Mock.questsInLog[quest.id] = nil
end

-- reward pills (Rewards module may not have data in the mock: feed it)
if ns.Rewards then
    local originalGet = ns.Rewards.Get
    ns.Rewards.Get = function(questID) return { xp = 1600, money = 12345, approximate = false } end
    Step("refresh with rewards", function() ns.Journal:Refresh(true) end)
    local content = _G.ForeverDungeonMapJournalQuest:GetScrollChild()
    local pills = Mock.Descendants(content, function(child) return child:IsShown() and child.Label and child.Icon and child.SetBackdrop and not child.itemID end)
    local texts = {}
    for _, pill in ipairs(pills) do texts[#texts + 1] = pill.Label:GetText() or "" end
    local joined = table.concat(texts, " | ")
    Check("XP pill", joined:find("1,600 XP", 1, true) ~= nil, joined)
    Check("money pill", joined:find("1g 23s 45c", 1, true) ~= nil, joined)
    Mock.CheckRows("quest page with pills", content, { width = _G.ForeverDungeonMapJournalQuest:GetWidth() })
    ns.Rewards.Get = originalGet
    Step("refresh without rewards", function() ns.Journal:Refresh(true) end)
else
    Check("Rewards module absent: page still renders", _G.ForeverDungeonMapJournalQuest:IsVisible())
end

-- boss icon size control (journal Map tab and overlay share the setting)
Step("OpenDungeon(43 map)", function() ns.Journal:OpenDungeon(43, "map") end)
local map = ns.Journal.map
local startScale = ns.Setting("bossIconScale")
Check("boss icon size control", map.scaleText and map.scaleText:GetText() == ("%d%%"):format(startScale * 100 + 0.5), map.scaleText and map.scaleText:GetText())
Step("plus", function() Mock.Click(map.scalePlus) end)
local raised = startScale + 0.1
Check("plus raises the boss icon size by 10%", math.abs(ns.Setting("bossIconScale") - raised) < 0.001, ns.Setting("bossIconScale"))
Check("pins follow the size", math.abs(map.pins[1]:GetScale() - raised) < 0.001)
for _ = 1, 10 do Step("plus", function() Mock.Click(map.scalePlus) end) end
Check("size stops at 160%", map.scaleText:GetText() == "160%" and map.scalePlus.disabled)
for _ = 1, 12 do Step("minus", function() Mock.Click(map.scaleMinus) end) end
Check("size stops at 60%", map.scaleText:GetText() == "60%" and map.scaleMinus.disabled)
if ns.View.map then Check("overlay map shows the same size", ns.View.map.scaleText:GetText() == "60%") end
ns.SetSetting("bossIconScale", startScale)

-- favourites
Step("ShowHome", function() ns.Journal:ShowHome() end)
local grid = _G.ForeverDungeonMapJournalGrid:GetScrollChild()
local firstCard = Mock.Shown(grid._children)[1]
Step("star the first card", function() Mock.Click(firstCard.Star) end)
local favourites = ns.Setting("favourites")
Check("star saves the favourite", type(favourites) == "table" and favourites[firstCard.instanceID] == true)
Check("star turns gold", not firstCard.Star.Icon:IsDesaturated())
local chip = Mock.FindChild(_G.ForeverDungeonMapJournal, function(child) return child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() == ns.TEX.FAVOURITE and child.Underline end)
Step("favourites chip", function() Mock.Click(chip) end)
Check("favourites filter shows only favourites", #Mock.Shown(grid._children) == 1)
Step("open favourite", function() ns.Journal:OpenDungeon(firstCard.instanceID) end)
Step("unstar in the header", function()
    Mock.Click(Mock.FindChild(_G.ForeverDungeonMapJournal, function(child) return child.Star == nil and child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() == ns.TEX.FAVOURITE and child:IsVisible() and not child.Underline end))
end)
Check("header star removes the favourite", not (ns.Setting("favourites") or {})[firstCard.instanceID])

-- tooltip backing
Step("ShowHome", function() ns.Journal:ShowHome() end)
local allChip = Mock.FindChild(_G.ForeverDungeonMapJournal, function(child) return child.Label and child.Label:GetText() == "All" end)
Step("All chip", function() Mock.Click(allChip) end)
local card = Mock.Shown(grid._children)[1]
Step("hover our card star", function() Mock.Enter(card.Star) end)
Check("solid backing behind our tooltips", ns.W.tooltipBacking and ns.W.tooltipBacking:IsShown())
Step("leave", function() Mock.Leave(card.Star) end)
Step("foreign tooltip", function()
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetText("other addon")
    GameTooltip:Show()
end)
Check("no backing behind other tooltips", not ns.W.tooltipBacking:IsShown())
Step("hide foreign tooltip", function() GameTooltip:Hide() end)

-- a newly opened dungeon lists only the player's faction, even with an old "both factions" setting saved
ns.db.showOtherFaction = true
Step("OpenDungeon(36)", function() ns.Journal:OpenDungeon(36, "quests") end)
Check("quests of the player's faction only", journalState().showHorde and not journalState().showAlliance)
ns.db.showOtherFaction = nil
-- settings: autoDungeonMap
ns.SetSetting("autoDungeonMap", false)
if WorldMapFrame:IsShown() then Mock.UserToggleWorldMap() end
Step("user opens map, auto off", function() Mock.UserToggleWorldMap() end)
Check("autoDungeonMap off: Blizzard map only", not ns.View:IsShown())
Step("close map", function() Mock.UserToggleWorldMap() end)
ns.SetSetting("autoDungeonMap", true)
Step("user opens map, auto on", function() Mock.UserToggleWorldMap() end)
Check("autoDungeonMap on: dungeon view", ns.View:IsShown())
Step("close map", function() Mock.UserToggleWorldMap() end)
if COMBAT then
    Mock.combat = false
    Step("PLAYER_REGEN_ENABLED", function() Mock.FireEvent("PLAYER_REGEN_ENABLED") end)
    Mock.combat = true
end
