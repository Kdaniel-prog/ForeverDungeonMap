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
local lastCard = Mock.Shown(grid._children)[#Mock.Shown(grid._children)]
Check("cards stay clean: no star on a card that is not a favourite", not lastCard.Star:IsShown())
Step("hover the last card", function() Mock.Enter(lastCard) end)
Check("the star shows on the hovered card", lastCard.Star:IsShown())
-- the client: the card's OnLeave comes first, the mouse is already on the star (inside the card)
Step("move onto its star", function()
    Mock.mouseFocus = lastCard.Star
    Mock.Leave(lastCard)
    Mock.Enter(lastCard.Star)
end)
Check("the star stays while the mouse is on it", lastCard.Star:IsShown())
-- cards are pooled: after the click this card may show another dungeon
local starredID = lastCard.instanceID
Step("star the last card", function() Mock.Click(lastCard.Star) end)
Step("leave the star", function() Mock.Leave(lastCard.Star) end)
local favourites = ns.Setting("favourites")
Check("star saves the favourite", type(favourites) == "table" and favourites[starredID] == true)
firstCard = Mock.Shown(grid._children)[1]
local hereFirst = ns.instanceID and ns.DUNGEONS[ns.instanceID] and 2 or 1
local starredCard = Mock.Shown(grid._children)[hereFirst]
Check("a favourite moves to the front (after the dungeon you are in)", starredCard.instanceID == starredID,
    tostring(starredCard.instanceID) .. " / " .. tostring(starredID))
Check("star turns gold and stays without the mouse", starredCard.Star:IsShown() and not starredCard.Star.Icon:IsDesaturated())
Check("a favourite card has the gold border", starredCard.selected == true)
firstCard = starredCard
local chip = Mock.FindChild(_G.ForeverDungeonMapJournal, function(child) return child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() == ns.TEX.FAVOURITE and child.Underline end)
Step("favourites chip", function() Mock.Click(chip) end)
Check("favourites filter shows only favourites", #Mock.Shown(grid._children) == 1)
Step("open favourite", function() ns.Journal:OpenDungeon(firstCard.instanceID) end)
Step("unstar in the header", function()
    Mock.Click(Mock.FindChild(_G.ForeverDungeonMapJournal, function(child) return child.Star == nil and child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() == ns.TEX.FAVOURITE and child:IsVisible() and not child.Underline end))
end)
Check("header star removes the favourite", not (ns.Setting("favourites") or {})[firstCard.instanceID])

-- hide mode: a round tick / cross on every card, a veil and "Hidden" over a hidden one
Step("ShowHome for hide mode", function() ns.Journal:ShowHome() end)
local allChipForHide = Mock.FindChild(_G.ForeverDungeonMapJournal, function(child) return child.Label and child.Label:GetText() == "All" end)
Step("All chip", function() Mock.Click(allChipForHide) end)
local hideButton = Mock.FindChild(_G.ForeverDungeonMapJournal, function(child)
    return child.Label and child.Label.GetText and child.Label:GetText() == "Hide dungeons"
end)
Check("Hide dungeons button", hideButton ~= nil)
if hideButton then
    local countBefore = #Mock.Shown(grid._children)
    Step("enter hide mode", function() Mock.Click(hideButton) end)
    local target = Mock.Shown(grid._children)[countBefore]
    Check("hide mode: every card has the round toggle with a tick, no star", target.HideToggle:IsShown()
        and target.HideToggle.Icon:GetTexture() == ns.TEX.TICK and not target.Star:IsShown())
    local hintShown = false
    for _, child in ipairs(Mock.Descendants(_G.ForeverDungeonMapJournal)) do
        for _, region in ipairs({ child:GetRegions() }) do
            if region.GetText and region:IsVisible() and (region:GetText() or ""):find("hide or show them", 1, true) then hintShown = true end
        end
    end
    Check("hide mode: the hint says what to do", hintShown)
    local targetID = target.instanceID
    Step("click the card", function() Mock.Click(target) end)
    local hiddenCard
    for _, card in ipairs(Mock.Shown(grid._children)) do if card.instanceID == targetID then hiddenCard = card end end
    Check("the hidden card stays in place with a cross, the veil and \"Hidden\"", hiddenCard ~= nil
        and hiddenCard.HideToggle.Icon:GetTexture() == ns.TEX.CROSS and hiddenCard.HiddenVeil:IsShown()
        and hiddenCard.HiddenLabel:IsShown() and hiddenCard.Art:IsDesaturated())
    Step("Done", function() Mock.Click(hideButton) end)
    Check("Done: the hidden dungeon is out of the list, the button counts it",
        #Mock.Shown(grid._children) == countBefore - 1 and hideButton.Label:GetText() == "Hidden (1)", hideButton.Label:GetText())
    Step("hide mode again", function() Mock.Click(hideButton) end)
    for _, card in ipairs(Mock.Shown(grid._children)) do
        if card.instanceID == targetID then Step("show it again with its toggle", function() Mock.Click(card.HideToggle) end) end
    end
    Step("Done again", function() Mock.Click(hideButton) end)
    Check("shown again: the list is whole, no veil left", #Mock.Shown(grid._children) == countBefore
        and not Mock.Shown(grid._children)[1].HiddenVeil:IsShown())
end

-- the elite frame around every boss pin of the dungeon map: silver for rare elites, gold for the
-- others; nothing is drawn over the portrait
Step("journal map tab of Wailing Caverns", function() ns.Journal:OpenDungeon(43, "map") end)
local journalMap = ns.Journal.map
if journalMap and journalMap.numPins then
    local gold, silver, without = 0, 0, {}
    for i = 1, journalMap.numPins do
        local pin = journalMap.pins[i]
        local frame = pin.EliteFrame
        if not frame:IsShown() then without[#without + 1] = pin.boss.name
        elseif frame:IsDesaturated() then silver = silver + 1
        else gold = gold + 1 end
        if pin.boss.rare then Check("rare " .. pin.boss.name .. ": silver frame", frame:IsShown() and frame:IsDesaturated()) end
    end
    Check("every boss pin has the elite frame", #without == 0 and gold > 0, table.concat(without, ", "))
    Check("the rare elite has the silver one", silver >= 1, silver)
    Check("no elite icon over the portrait", journalMap.pins[1].Elite == nil)
end

-- event bosses have their spots (Sunken Temple's dragons, Scholomance's summons...)
for _, wanted in ipairs({ { 109, "Weaver" }, { 109, "Dreamscythe" }, { 109, "Atal'alarion" }, { 289, "Kormok" },
        { 289, "Darkmaster Gandling" }, { 129, "Tuten'kash" }, { 229, "Warchief Rend Blackhand" }, { 329, "Ezra Grimm" } }) do
    Check(("%d %s has a map spot"):format(wanted[1], wanted[2]), ns.GetBossPos(wanted[1], wanted[2]) ~= nil)
end

-- bosses no source has a spot for stand in a row at the map's bottom (two of Blackmaw Hold's
-- are taken off the map for this)
local BLACKMAW_HOLD = 2974
local UNPLACED = { "Unbound Spirit", "Varrox Bleakhoof" }
local keptSpots = {}
for _, name in ipairs(UNPLACED) do keptSpots[name], ns.BOSS_POS[BLACKMAW_HOLD][name] = ns.BOSS_POS[BLACKMAW_HOLD][name], nil end
Step("journal map tab of Blackmaw Hold", function() ns.Journal:OpenDungeon(BLACKMAW_HOLD, "map") end)
local blackmawMap = ns.Journal.map
Check("Blackmaw Hold: every boss has a pin", blackmawMap.numPins == #ns.BOSSES[BLACKMAW_HOLD], blackmawMap.numPins)
local unplacedPins = {}
for i = 1, blackmawMap.numPins do
    local pin = blackmawMap.pins[i]
    if not ns.GetBossPos(BLACKMAW_HOLD, pin.boss.name) then unplacedPins[#unplacedPins + 1] = pin end
end
local firstPin, secondPin = unplacedPins[1], unplacedPins[2]
local _, _, _, firstX, firstY = firstPin:GetPoint(1)
local _, _, _, secondX, secondY = secondPin:GetPoint(1)
Check("Blackmaw Hold: the bosses without a spot stand in one row, in boss order", firstY == secondY and secondX > firstX
    and firstPin.index < secondPin.index)
Step("hover a Blackmaw Hold pin without a spot", function() Mock.Enter(firstPin) end)
Check("its tooltip says the spot is not known yet", table.concat(GameTooltip._lines, " "):find("not known yet", 1, true) ~= nil,
    table.concat(GameTooltip._lines, " | "))
Step("leave the pin", function() Mock.Leave(firstPin) end)
for name, spot in pairs(keptSpots) do ns.BOSS_POS[BLACKMAW_HOLD][name] = spot end

-- Alcaz Prison: every boss on its spot (forg.gg's map fitted onto ours)
Step("journal map tab of Alcaz Prison", function() ns.Journal:OpenDungeon(2994, "map") end)
local alcazMap = ns.Journal.map
local alcazBosses = ns.BOSSES[2994] or {}
Check("Alcaz Prison: every boss has a pin", alcazMap.numPins == #alcazBosses and #alcazBosses == 5, alcazMap.numPins)
local placed = 0
for _, boss in ipairs(alcazBosses) do if ns.GetBossPos(2994, boss.name) then placed = placed + 1 end end
Check("Alcaz Prison: every boss has a map spot", placed == #alcazBosses, placed)
Check("Alcaz Prison bosses carry their creature IDs", alcazBosses[1] and alcazBosses[1].npcID == 255391)
local withLoot = 0
for _, boss in ipairs(alcazBosses) do if boss.loot and #boss.loot > 0 then withLoot = withLoot + 1 end end
Check("Alcaz Prison: every boss has its loot", withLoot == #alcazBosses, withLoot)
Check("Alcaz Prison is out: no longer coming soon", ns.DUNGEONS[2994] and not ns.DUNGEONS[2994].comingSoon)
local kingOp
for _, boss in ipairs(ns.BOSSES[3001] or {}) do if boss.name == "King Op" then kingOp = boss end end
Check("King Op (rare elite) is marked rare: silver frame", kingOp and kingOp.rare == true)

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
