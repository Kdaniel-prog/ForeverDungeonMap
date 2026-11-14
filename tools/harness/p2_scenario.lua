-- p2_scenario.lua - loot filter (usable / slot), live objective progress, class icons, search results.
local addonName, ns = ...
local Mock = MOCK
local Check, Step = Mock.Check, Mock.Step

if not ns.db then
    Step("ADDON_LOADED", function() Mock.FireEvent("ADDON_LOADED", addonName) end)
    Step("PLAYER_ENTERING_WORLD", function() Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
end
local selection = ns.Journal:State()
local bossContent = function() return _G.ForeverDungeonMapJournalBoss:GetScrollChild() end
local function LootIDs()
    local ids = {}
    for _, row in ipairs(Mock.Rows(bossContent())) do
        if rawget(row.w, "itemID") and rawget(row.w, "Sub") then ids[#ids + 1] = row.w.itemID end
    end
    return ids
end

-- loot filter: Verdan drops an axe (6630), a staff (6631) and a cloth cloak (6629)
local verdanIndex, verdan
for index, boss in ipairs(ns.BOSSES[43]) do if boss.name == "Verdan the Everliving" then verdanIndex, verdan = index, boss end end
Mock.player.class = "MAGE"
Step("ShowBoss Verdan", function() ns.Journal:ShowBoss(43, verdan, verdanIndex) end)
local bar = Mock.FindChild(bossContent(), function(child) return child.Usable and child.Slot and child:IsShown() end)
Check("loot filter bar on the boss page", bar ~= nil)
local allCount = #LootIDs()
Step("usable only", function() Mock.Click(bar.Usable) end)
local usable = LootIDs()
local hasAxe = false
for _, itemID in ipairs(usable) do if itemID == 6630 then hasAxe = true end end
Check("usable filter hides the axe for a mage", not hasAxe and #usable < allCount and #usable > 0, table.concat(usable, ","))
Check("usable toggle looks selected", bar.Usable.selected == true)
Mock.CheckRows("filtered loot", bossContent(), { width = _G.ForeverDungeonMapJournalBoss:GetWidth() })
Step("usable off", function() Mock.Click(bar.Usable) end)
Check("usable off shows all loot again", #LootIDs() == allCount)
Step("open slot menu", function() Mock.Click(bar.Slot) end)
local menuRows = {}
for _, row in ipairs(Mock.Descendants(_G.ForeverDungeonMapJournal, function(child) return child:IsVisible() and child.Label and child:GetParent() and child:GetParent():GetFrameStrata() == "FULLSCREEN_DIALOG" end)) do
    menuRows[#menuRows + 1] = row
end
Check("slot menu lists All slots + the loot's slots", #menuRows >= 3, #menuRows)
local backRow
for _, row in ipairs(menuRows) do if row.Label:GetText() == "Back" then backRow = row end end
if Check("slot menu has 'Back'", backRow ~= nil) then
    Step("pick Back", function() Mock.Click(backRow) end)
    local ids = LootIDs()
    Check("slot filter keeps only cloaks", #ids == 1 and ids[1] == 6629, table.concat(ids, ","))
    Check("slot button shows the slot", bar.Slot.Label:GetText() == "Back")
end
Step("other boss resets the slot", function() ns.Journal:ShowBoss(43, ns.BOSSES[43][1], 1) end)
Check("slot filter resets on another boss", selection.slot == nil)
Mock.player.class = "WARRIOR"

-- live objective progress
local quest
for _, candidate in ipairs(ns.QUESTS[43]) do
    if ns.W.QuestState(candidate) ~= "other" and not quest then quest = candidate end
end
Mock.questsInLog[quest.id] = 1
Mock.objectives[quest.id] = {
    { text = "Deviate Hide: 7/20", numFulfilled = 7, numRequired = 20, finished = false },
    { text = "Serpentbloom: 10/10", numFulfilled = 10, numRequired = 10, finished = true },
}
Step("ShowQuest in log", function() ns.Journal:ShowQuest(43, quest) end)
Mock.Advance(1)
local row
for _, candidate in ipairs(Mock.Rows(_G.ForeverDungeonMapJournalList:GetScrollChild())) do
    if rawget(candidate.w, "quest") == quest then row = candidate.w end
end
Check("quest row shows progress icon + count", row and row.Progress:IsShown() and row.Progress.Count:GetText() == "17/30",
    row and row.Progress.Count:GetText())
local page = _G.ForeverDungeonMapJournalQuest:GetScrollChild()
local marks = {}
for _, line in ipairs(Mock.Descendants(page, function(child) return child:IsShown() and child.Mark and child.Mark:IsShown() end)) do
    marks[#marks + 1] = line.Mark.texture:GetTexture()
end
Check("quest page lists objectives with cross / tick", #marks >= 2 and marks[1] == ns.TEX.CROSS and marks[2] == ns.TEX.TICK)
Mock.questsInLog[quest.id], Mock.objectives[quest.id] = nil, nil

-- class icon on class quests
local classDungeon, classQuest
for instanceID, quests in pairs(ns.QUESTS) do
    for _, candidate in ipairs(quests) do
        if candidate.classes and not classQuest and ns.DUNGEONS[instanceID] then classDungeon, classQuest = instanceID, candidate end
    end
end
if Check("data: a class quest exists", classQuest ~= nil) then
    Mock.player.class = classQuest.classes[1]
    Step("ShowQuest class quest", function() ns.Journal:ShowQuest(classDungeon, classQuest) end)
    selection.showAlliance, selection.showHorde = true, true
    Step("refresh", function() ns.Journal:Refresh(true) end)
    local classRow
    for _, candidate in ipairs(Mock.Rows(_G.ForeverDungeonMapJournalList:GetScrollChild())) do
        if rawget(candidate.w, "quest") == classQuest then classRow = candidate.w end
    end
    Check("class icon on the class quest row", classRow and classRow.ClassIcon:IsShown()
        and classRow.ClassIcon.texture:GetTexture() == ns.TEX.CLASS_ICONS)
    Step("hover class icon", function() Mock.Enter(classRow.ClassIcon) end)
    Check("class icon tooltip names the class", GameTooltip._lines[1] == "Class quest")
    Step("leave", function() Mock.Leave(classRow.ClassIcon) end)
    Mock.CheckRows("quest list with class icons", _G.ForeverDungeonMapJournalList:GetScrollChild(), { width = _G.ForeverDungeonMapJournalList:GetWidth() })
    Mock.player.class = "WARRIOR"
end

-- search results dropdown
local search = _G.ForeverDungeonMapJournalSearch
Step("type 'verdan'", function() Mock.TypeText(search, "verdan") end)
local results = Mock.Descendants(_G.ForeverDungeonMapJournal, function(child) return child:IsVisible() and child.result end)
Check("search shows a results dropdown", #results >= 1 and results[1].result.kind == "boss", #results)
if results[1] then
    Step("click result", function() Mock.Click(results[1]) end)
    Check("result opens the boss", selection.boss == verdan and selection.tab == "bosses")
    Check("dropdown closes after a pick", #Mock.Descendants(_G.ForeverDungeonMapJournal, function(child) return child:IsVisible() and child.result end) == 0)
end
Step("type 'wail'", function() Mock.TypeText(search, "wail") end)
results = Mock.Descendants(_G.ForeverDungeonMapJournal, function(child) return child:IsVisible() and child.result end)
Check("dungeon results come first and the list is capped", #results >= 1 and #results <= 6 and results[1].result.kind == "dungeon")
Step("Enter opens the first result", function() Mock.FireScript(search, "OnEnterPressed") end)
Check("Enter opened the dungeon", selection.instanceID == 43)
Step("clear search", function() Mock.TypeText(search, "") end)
