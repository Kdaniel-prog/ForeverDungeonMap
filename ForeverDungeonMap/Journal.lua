-- ForeverDungeonMap - Dungeon Journal window (docs/ui-spec.md section 3).
-- Home: search, filter chips and every dungeon as an art card. Dungeon page: header band
-- (art, round icon, name, levels, Map / Bosses / Quests tabs), the list on the left (bosses, or
-- one sorted quest list with inline chains), details on the right (boss header + loot, or a
-- parchment quest page), or the dungeon map (Map tab).
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L
local W, C, TEX = ns.W, ns.C, ns.TEX
local Canvas = ns.Canvas

local Journal = {}
ns.Journal = Journal

local WINDOW_WIDTH, WINDOW_HEIGHT = 860, 600
local SIDE_MARGIN, BODY_TOP, HEADER_TOP, HEADER_HEIGHT = 16, 156, 84, 64
local LIST_WIDTH, PANEL_GAP = 344, 10
local LIST_CONTENT_WIDTH = LIST_WIDTH - 8 - 28
local DETAIL_WIDTH = WINDOW_WIDTH - 2 * SIDE_MARGIN - LIST_WIDTH - PANEL_GAP
local BOSS_CONTENT_WIDTH = DETAIL_WIDTH - 12 - 28
local QUEST_CONTENT_WIDTH = DETAIL_WIDTH - 18 - 30
local QUEST_HEADER_HEIGHT = 64
-- faction crests: the list's filter toggles (they fill the 34 px title strip) and the quest header
local FACTION_TOGGLE_WIDTH, FACTION_TOGGLE_HEIGHT, FACTION_TOGGLE_ICON = 40, 30, 28
local QUEST_HEADER_CREST = 26
local BUG_BUTTON_SIZE = 22
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP_X, CARD_GAP_Y, CARD_COLUMNS = 388, 120, 12, 10, 2
local REFRESH_DELAY = 0.25
local MAP_TOP_STRIP = 30
local FILTERS = { { "all", L["All"] }, { "classic", L["Classic"] }, { "forever", L["Forever"] }, { "favourites", "", TEX.FAVOURITE } }
local REFRESH_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP",
    "QUEST_WATCH_LIST_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
local QUEST_BUTTON_SIZE = 22
-- Inset of art inside bordered panels and cards.
local PANEL_INSET = 4
local HEADER_ICON_SIZE, HEADER_ICON_LEFT = 44, 10
local MENU_WIDTH = 150
local SEARCH_RESULTS, SEARCH_ROW_HEIGHT, SEARCH_WIDTH = 6, 24, 330
local FAVOURITE_OFF_ALPHA = 0.35
local ITEM_EVENTS = { "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }

-- What the page shows; kept for the whole session.
local selection = { instanceID = nil, tab = "bosses", boss = nil, bossIndex = nil, quest = nil, step = nil,
    showAlliance = true, showHorde = true, expanded = {} }

local frame, home, page, search, grid, levelTag
local filterButtons, cards = {}, {}
local filter, query = "all", ""
local ui = {}

local function Bosses() return ns.BOSSES[selection.instanceID] or {} end
local function Quests() return ns.QUESTS[selection.instanceID] or {} end
local function CurrentDungeon() return ns.GetDungeon(selection.instanceID) end

local function FactionVisible(quest)
    if quest.faction == "Alliance" then return selection.showAlliance end
    if quest.faction == "Horde" then return selection.showHorde end
    return selection.showAlliance or selection.showHorde
end

local function IsFavourite(instanceID)
    local favourites = ns.Setting("favourites")
    return type(favourites) == "table" and favourites[instanceID] == true
end

local function ToggleFavourite(instanceID)
    local favourites = ns.Setting("favourites")
    if type(favourites) ~= "table" then favourites = {} end
    favourites[instanceID] = not favourites[instanceID] or nil
    ns.SetSetting("favourites", favourites)
    Journal:Refresh(true)
end

-- Gold star when the dungeon is a favourite, a faint grey one when not; words in the tooltip.
local function SetStar(star, instanceID)
    local favourite = IsFavourite(instanceID)
    star.Icon:SetDesaturated(not favourite)
    star.Icon:SetAlpha(favourite and 1 or FAVOURITE_OFF_ALPHA)
    W.Tooltip(star, favourite and L["Remove from favourites"] or L["Add to favourites"])
end

local function MakeStar(parent, size)
    local star = W.IconButton(parent, size, TEX.FAVOURITE, 2)
    star:SetScript("OnClick", function(self) ToggleFavourite(self.instanceID) end)
    return star
end

-- Title words that do not identify a boss in a quest objective.
local IGNORED_WORDS = { lord = 1, lady = 1, the = 1, captain = 1, master = 1, commander = 1, high = 1, general = 1,
    prince = 1, princess = 1, king = 1, chief = 1, guard = 1, baron = 1, baroness = 1 }

-- Quests whose objective mentions the boss.
local function RelatedQuests(boss)
    local related, words = {}, {}
    for word in boss.name:gmatch("[%a'%-]+") do
        if #word >= 4 and not IGNORED_WORDS[word:lower()] then words[#words + 1] = word:lower() end
    end
    for _, quest in ipairs(Quests()) do
        local objective = (quest.objective or ""):lower()
        for _, word in ipairs(words) do
            if objective:find(word, 1, true) then
                related[#related + 1] = quest
                break
            end
        end
    end
    return related
end

local function StateOrder(state) return W.STATE_ORDER[state] or 9 end

-- Visible quests grouped by chain: chain -> { members = { quest -> true }, list = { quest... } }.
local function GroupByChain()
    local groups, order = {}, {}
    for _, quest in ipairs(Quests()) do
        if FactionVisible(quest) then
            local chain = W.QuestChain(quest)
            if not groups[chain] then
                groups[chain] = { members = {}, list = {} }
                order[#order + 1] = chain
            end
            groups[chain].members[quest.id] = quest
            groups[chain].list[#groups[chain].list + 1] = quest
        end
    end
    return groups, order
end

-- One list entry per chain: headed by its first step in this dungeon, with the most urgent state
-- of its steps here (a ready step 2 makes the whole row "ready").
local function ChainEntry(chain, group)
    local head
    for _, questID in ipairs(chain) do
        head = head or group.members[questID]
    end
    head = head or group.list[1]
    local entry = { quest = head, state = W.QuestState(head), members = group.members }
    for _, quest in ipairs(group.list) do
        local state = W.QuestState(quest)
        if StateOrder(state) < StateOrder(entry.state) then entry.state = state end
        if state == "ready" then entry.readyQuest = quest end
    end
    return entry
end

-- Visible quests in display order: ready, in log, available, locked, done, other faction/class.
-- A chain is one entry; its other steps hang under it.
local function SortedQuests()
    local sorted = {}
    local groups, order = GroupByChain()
    for _, chain in ipairs(order) do sorted[#sorted + 1] = ChainEntry(chain, groups[chain]) end
    table.sort(sorted, function(first, second)
        local firstOrder, secondOrder = StateOrder(first.state), StateOrder(second.state)
        if firstOrder ~= secondOrder then return firstOrder < secondOrder end
        local firstLevel, secondLevel = W.QuestLevel(first.quest) or 0, W.QuestLevel(second.quest) or 0
        if firstLevel ~= secondLevel then return firstLevel < secondLevel end
        return first.quest.name < second.quest.name
    end)
    return sorted
end
Journal.SortedQuests = SortedQuests

local function EmptyQuestMessage()
    if #Quests() == 0 then
        return CurrentDungeon().comingSoon and L["Coming soon: no quests recorded yet."] or L["No quests recorded for this dungeon."]
    end
    if selection.showAlliance ~= selection.showHorde then
        return L["No %s quests recorded for this dungeon."]:format(selection.showAlliance and L["Alliance"] or L["Horde"])
    end
    return L["No quests for this filter."]
end

local function RenderQuestList()
    local list, quests = ui.list, SortedQuests()
    ui.listTitle:SetText(L["Quests"])
    ui.listCount:SetText(#quests)
    if #quests == 0 then list:Empty(EmptyQuestMessage()) end
    for _, entry in ipairs(quests) do
        local quest = entry.quest
        local selected = selection.quest ~= nil and entry.members[selection.quest.id] ~= nil
        local onLaterStep = selected and selection.quest ~= quest
        if selection.scrollToQuest and entry.members[selection.scrollToQuest] then
            selection.scrollToQuest = nil
            list.scrollTarget = list.y
        end
        list:Quest(quest, entry.state, { selected = selected, readyQuest = entry.readyQuest,
            expanded = selection.expanded[quest.id] or onLaterStep,
            selectedStep = selected and (selection.step or (onLaterStep and selection.quest.id)) or nil })
    end
end

local function RenderBossList()
    local list = ui.list
    ui.listTitle:SetText(L["Bosses"])
    ui.listCount:SetText(#Bosses() > 0 and #Bosses() or "")
    if #Bosses() == 0 then
        list:Empty(L["No bosses known."])
    end
    for index, boss in ipairs(Bosses()) do list:Boss(boss, index, selection.instanceID, boss == selection.boss) end
end

local function UpdateFactionToggles()
    local questTab = selection.tab == "quests"
    for faction, toggle in pairs({ Alliance = ui.allianceToggle, Horde = ui.hordeToggle }) do
        local shown = faction == "Alliance" and selection.showAlliance or (faction == "Horde" and selection.showHorde)
        toggle:SetShown(questTab)
        toggle:SetSelected(shown)
        toggle.Icon:SetDesaturated(not shown)
    end
end

local function RenderList(keepScroll)
    local list = ui.list
    list:Reset(keepScroll)
    if selection.tab == "quests" then RenderQuestList() else RenderBossList() end
    list:Finish()
    if list.scrollTarget then
        list.scroll:SetVerticalScroll(math.min(list:ScrollRange(), list.scrollTarget))
        list.scrollTarget = nil
    end
    UpdateFactionToggles()
end

-- Slot name of an item ("Chest", "One-Hand"...), "" for items without a slot.
local function SlotName(itemID)
    local _, _, equipLocation = W.ItemType(itemID)
    return equipLocation and equipLocation ~= "" and _G[equipLocation] or ""
end

local function PassesLootFilter(itemID)
    if selection.usableOnly and not W.CanUseItem(itemID) then return false end
    return selection.slot == nil or SlotName(itemID) == selection.slot
end

-- Distinct slot names of a loot list, sorted.
local function LootSlots(loot)
    local seen, slots = {}, {}
    for _, itemID in ipairs(loot) do
        local slot = SlotName(itemID)
        if slot ~= "" and not seen[slot] then
            seen[slot] = true
            slots[#slots + 1] = slot
        end
    end
    table.sort(slots)
    return slots
end

-- Small menu under the slot button: L["All slots"] and every slot of the boss's loot.
local function ToggleSlotMenu(anchor, loot)
    local slots = LootSlots(loot)
    table.insert(slots, 1, false)
    local choices = {}
    for index, slot in ipairs(slots) do
        choices[index] = { label = slot or L["All slots"], selected = (slot or nil) == selection.slot }
    end
    ui.slotMenu:Toggle(anchor, choices, function(index)
        selection.slot = slots[index] or nil
        Journal:Refresh(true)
    end)
end

-- Loot heading ("shown/total" while filtered), the filter bar and the loot rows.
local function RenderLoot(canvas, boss)
    local loot, shown = boss.loot or {}, {}
    for _, itemID in ipairs(loot) do
        if PassesLootFilter(itemID) then shown[#shown + 1] = itemID end
    end
    local filtered = #shown ~= #loot
    canvas:Heading(L["Loot"], filtered and ("%d/%d"):format(#shown, #loot) or #loot)
    if #loot == 0 then
        canvas:Text(CurrentDungeon().forever and L["Loot not known yet."] or L["No known drops."], ns.Font("disable"), C.MUTED)
        return
    end
    canvas:LootFilter({ usableOnly = selection.usableOnly, slotLabel = selection.slot or L["All slots"], slotSelected = selection.slot ~= nil,
        onToggleUsable = function()
            selection.usableOnly = not selection.usableOnly
            Journal:Refresh(true)
        end,
        onSlotMenu = function(button) ToggleSlotMenu(button, loot) end })
    if #shown == 0 then canvas:Text(L["Nothing for this filter."], ns.Font("disable"), C.MUTED) end
    for _, itemID in ipairs(shown) do canvas:Item(itemID) end
end

local function RenderBoss(keepScroll)
    local canvas = ui.bossDetail
    canvas:Reset(keepScroll)
    local boss = selection.boss
    if not boss then
        canvas:Empty(#Bosses() == 0 and L["No bosses known for this dungeon."] or L["Pick a boss on the left."], ns.Font("disableLarge"))
        canvas:Finish()
        return
    end
    local hasPosition = ns.GetBossPos(selection.instanceID, boss.name) ~= nil
    canvas:BossHead(boss, selection.bossIndex or 1, #Bosses(), selection.instanceID,
        hasPosition and function() Journal:ShowOnMap(boss) end or nil)
    RenderLoot(canvas, boss)
    local related = RelatedQuests(boss)
    if #related > 0 then
        canvas:Heading(L["Quests for this boss"], #related)
        for _, quest in ipairs(related) do canvas:Quest(quest, nil, { selected = false }) end
    end
    canvas:Finish()
end

local function ClearQuestHeader()
    ui.questTitle:SetText("")
    ui.questMeta:SetText("")
    ui.questFaction1:Hide()
    ui.questFaction2:Hide()
    ui.questClass:Hide()
    ui.questDone:Hide()
end

-- Track (quest in the log) and Share (in the log and in a group) icon buttons.
local function UpdateQuestButtons(quest)
    local inLog = W.InLog(quest.id)
    ui.trackButton.questID, ui.shareButton.questID = quest.id, quest.id
    ui.trackButton:SetShown(not quest.stub)
    ui.shareButton:SetShown(not quest.stub)
    W.SetDisabled(ui.trackButton, not inLog)
    ui.trackButton:SetSelected(inLog and W.IsQuestTracked(quest.id))
    if inLog then
        W.Tooltip(ui.trackButton, W.IsQuestTracked(quest.id) and L["Stop tracking"] or L["Track quest"])
    else
        W.Tooltip(ui.trackButton, L["Track quest"], L["Only quests in your quest log can be tracked."])
    end
    local canShare, reason = W.CanShareQuest(quest.id)
    W.SetDisabled(ui.shareButton, not canShare)
    W.Tooltip(ui.shareButton, L["Share quest"], not canShare and reason or L["Offer this quest to your group."])
end

-- Fixed quest header: title, "Available from Level N", faction crests, tick when done.
local function SetQuestHeader(quest)
    ui.questTitle:SetText(quest.name)
    ui.questMeta:SetText((W.QuestLevelText(quest)))
    local factions = W.QuestFactions(quest)
    W.SetFactionIcon(ui.questFaction1, factions[1])
    ui.questFaction1:ClearAllPoints()
    ui.questFaction1:SetPoint("LEFT", ui.questMeta, "LEFT", ui.questMeta:GetStringWidth() + 8, 0)
    ui.questFaction1:Show()
    ui.questFaction2:SetShown(factions[2] ~= nil)
    if factions[2] then W.SetFactionIcon(ui.questFaction2, factions[2]) end
    local class = quest.classes and quest.classes[1]
    ui.questClass:SetShown(class ~= nil)
    if class then
        ui.questClass:ClearAllPoints()
        ui.questClass:SetPoint("LEFT", factions[2] and ui.questFaction2 or ui.questFaction1, "RIGHT", 6, 0)
        W.SetClassIcon(ui.questClass.texture, class)
        W.Tooltip(ui.questClass, L["Class quest"], table.concat(quest.classes, ", "))
    end
    ui.questDone:SetShown(W.IsQuestDone(quest.id))
    UpdateQuestButtons(quest)
end

local function ShowLocationButton(canvas, location, label, text)
    if location and location.map and location.x and location.y then
        canvas:Action(text, function() Journal:ShowLocation(location, label) end)
    end
end

-- "Step 2 of 4 - part of <quest>" and the way back, on the page of a chain step.
local function RenderStepIntro(canvas, quest)
    local steps = W.QuestChain(quest)
    local stepIndex = 1
    for i, questID in ipairs(steps) do
        if questID == selection.step then stepIndex = i end
    end
    canvas:Text(L["Step %d of %d - part of %s"]:format(stepIndex, #steps, quest.name), ns.Font("questSmall"), C.PARCH_MUTED)
    canvas:Link(L["Back to %s"]:format(quest.name), function()
        selection.step = nil
        Journal:Refresh(true)
    end, C.PARCH_LINK)
end

-- Objective text and, for a quest in the log, one line per objective with a tick or a cross.
local function RenderObjective(canvas, quest)
    local objectives = W.QuestObjectives(quest.id)
    if not quest.objective and #objectives == 0 then return end
    canvas:Heading(L["Objective"])
    if quest.objective then canvas:Text(quest.objective, nil, C.PARCH_TEXT) end
    for _, objective in ipairs(objectives) do
        local mark = objective.finished and { TEX.TICK, L["Completed"] } or { TEX.CROSS, L["Not completed yet"] }
        canvas:Link(objective.text or "", nil, objective.finished and C.DONE_PARCH or C.PARCH_TEXT, mark)
    end
end

-- How to find the spot inside the dungeon: one note, or every place a randomly placed starter can be.
local function RenderSpots(canvas, location)
    if not location then return end
    if type(location.note) == "string" then canvas:Text(location.note, ns.Font("questSmall"), C.PARCH_MUTED) end
    local spots = location.spots
    if type(spots) ~= "table" or #spots == 0 then return end
    canvas:Text(L["It appears in one of these places:"], ns.Font("questSmall"), C.PARCH_MUTED)
    for _, spot in ipairs(spots) do canvas:Text("• " .. spot, nil, C.PARCH_TEXT, 12) end
end

local IN_DUNGEON_MARKER = { dungeon = true, title = L["In Dungeon"], text = L["This quest starts inside the dungeon."] }

local function RenderStart(canvas, quest)
    local start = W.Location(quest, "start", selection.instanceID)
    canvas:Heading(L["Starts at"], nil, W.InDungeon(quest) and IN_DUNGEON_MARKER or nil)
    if start and start.kind == "item" and start.itemID then canvas:ItemButton(start.itemID) end
    canvas:Text(W.LocationText(start) or L["Unknown"], nil, C.PARCH_TEXT)
    RenderSpots(canvas, start)
    ShowLocationButton(canvas, start, quest.name, L["Show on Map"])
end

local function RenderTurnIn(canvas, quest)
    local finish = W.Location(quest, "finish", selection.instanceID)
    if not finish then return end
    canvas:Heading(L["Turn in"])
    canvas:Text(W.LocationText(finish), nil, C.PARCH_TEXT)
    RenderSpots(canvas, finish)
    ShowLocationButton(canvas, finish, quest.name, L["Show Turn In"])
end

-- Every step of the chain, numbered, with tick / grey ? / cross; the other steps open their own
-- page, this one is highlighted; L["Show Quest Chain"] unfolds it in the list.
local function RenderChain(canvas, quest)
    local steps = W.QuestChain(quest)
    if #steps < 2 then return end
    canvas:Heading(L["Quest chain"])
    for i, questID in ipairs(steps) do
        local label = ("%d. %s"):format(i, W.QuestName(questID))
        if questID == quest.id then
            canvas:Link(label, nil, C.PARCH_HEAD)
        else
            local markTexture, markWords = W.ProgressMark(questID)
            canvas:Link(label, function()
                selection.step = questID
                Journal:Refresh(true)
            end, W.IsQuestDone(questID) and C.DONE_PARCH or C.PARCH_LINK, { markTexture, markWords },
                { L["Quest chain"], L["Click: where it starts and ends"] })
        end
    end
    canvas:Action(L["Show Quest Chain"], function()
        selection.expanded[quest.id] = true
        selection.scrollToQuest = quest.id
        Journal:Refresh(true)
    end, 132)
end

-- XP and money pills from ns.Rewards (learned in game or estimated), when it is loaded.
local function RewardPills(quest)
    local rewards = ns.Rewards
    if not (rewards and rewards.Get) then return {} end
    local ok, values = pcall(rewards.Get, quest.id)
    if not ok or type(values) ~= "table" then return {} end
    local pills = {}
    if values.xp and rewards.FormatExperience then
        pills[#pills + 1] = { icon = TEX.EXPERIENCE, iconCoords = TEX.EXPERIENCE_COORDS,
            text = rewards.FormatExperience(values.xp, values.approximate), tooltipTitle = L["Experience"],
            tooltipText = values.approximate and L["Estimated for your level"] or L["At your level"] }
    end
    if values.money and rewards.FormatMoney then
        pills[#pills + 1] = { text = rewards.FormatMoney(values.money), tooltipTitle = L["Money"] }
    end
    return pills
end

-- Reward items: what the game showed on the quest frame (WoW Forever's own), else the shipped list.
local function RewardItems(quest)
    local choices, rewards
    if ns.Rewards and ns.Rewards.Items then choices, rewards = ns.Rewards.Items(quest.id) end
    if choices then return choices, rewards end
    return quest.choices or {}, quest.rewards or {}
end

local function RenderRewards(canvas, quest)
    local choices, rewards = RewardItems(quest)
    local hasChoices, hasItems = #choices > 0, #rewards > 0
    local pills = RewardPills(quest)
    if hasChoices then
        canvas:Heading(L["Choose one reward"])
        canvas:ItemGrid(choices)
    end
    if hasItems or (#pills > 0 and not hasChoices) then
        canvas:Heading(hasChoices and L["You will also receive:"] or L["Rewards"])
    end
    if hasItems then canvas:ItemGrid(rewards) end
    canvas:Pills(pills)
end

-- Parchment quest page in FDJ order: Objective, Starts at, Turn in, Quest chain, Rewards.
local function RenderQuest(keepScroll)
    local canvas, quest = ui.questDetail, selection.quest
    canvas:Reset(keepScroll)
    if not quest then
        ClearQuestHeader()
        canvas:Empty(#Quests() == 0 and L["No quests recorded for this dungeon."] or L["Pick a quest on the left."])
        canvas:Finish()
        return
    end
    local isStep = selection.step ~= nil and selection.step ~= quest.id
    local shown = isStep and W.QuestByID(selection.step) or quest
    SetQuestHeader(shown)
    if isStep then RenderStepIntro(canvas, quest) end
    RenderObjective(canvas, shown)
    RenderStart(canvas, shown)
    RenderTurnIn(canvas, shown)
    if not isStep then RenderChain(canvas, quest) end
    RenderRewards(canvas, shown)
    canvas:Finish()
end

local function HeaderSubText(dungeon)
    local parts = { ns.RangeText(dungeon), ns.Hex(C.MUTED) .. L["%d bosses · %d quests"]:format(#Bosses(), #Quests()) .. "|r" }
    if dungeon.forever then parts[#parts + 1] = ns.Hex(C.FOREVER) .. L["WoW Forever"] .. "|r" end
    if dungeon.comingSoon then parts[#parts + 1] = ns.Hex(C.FOREVER) .. L["Coming soon"] .. "|r" end
    if ns.instanceID == selection.instanceID then parts[#parts + 1] = ns.Hex(C.DONE) .. L["You are here"] .. "|r" end
    return table.concat(parts, "  ·  ")
end

local function RenderHeader()
    local dungeon = CurrentDungeon()
    W.SetHeaderArt(ui.headerArt, selection.instanceID)
    W.SetDungeonIcon(ui.headerIcon, selection.instanceID)
    ui.headerName:SetText(dungeon.name)
    ui.headerSub:SetText(HeaderSubText(dungeon))
    ui.entranceButton:SetShown(ns.GetEntrance(dungeon) ~= nil)
    ui.entranceButton:ClearAllPoints()
    ui.entranceButton:SetPoint("LEFT", ui.headerName, "LEFT", math.min(360, ui.headerName:GetStringWidth()) + 10, 0)
    ui.headerStar.instanceID = selection.instanceID
    ui.headerStar:ClearAllPoints()
    ui.headerStar:SetPoint("LEFT", ui.entranceButton, "RIGHT", 6, 0)
    SetStar(ui.headerStar, selection.instanceID)
    ui.mapTab:SetSelected(selection.tab == "map")
    ui.bossTab:SetSelected(selection.tab == "bosses")
    ui.questTab:SetSelected(selection.tab == "quests")
    ui.questTab.Label:SetText(L["Quests %d"]:format(#Quests()))
end

-- Map tab: a repaint keeps floor and zoom; a new dungeon or a tab switch shows it fresh.
local function RenderMapTab(keepScroll)
    local map = ui.journalMap
    if keepScroll and map.state.instanceID == selection.instanceID then map:Layout() else map:SetDungeon(selection.instanceID) end
    if selection.mapFocus then
        map:FocusBoss(selection.mapFocus)
        selection.mapFocus = nil
    end
end

local function RenderDetail(keepScroll)
    local questTab = selection.tab == "quests"
    ui.bossDetail.scroll:SetShown(not questTab)
    ui.questDetail.scroll:SetShown(questTab)
    ui.questHeader:SetShown(questTab)
    ui.parchment:SetShown(questTab)
    if questTab then
        ns.Paint(ui.detailPanel, C.PARCH_BG, C.PARCH_EDGE)
        ui.lore:Hide()
        RenderQuest(keepScroll)
        return
    end
    ns.Paint(ui.detailPanel, C.INK, C.EDGE_PANEL)
    local art = ns.ART and ns.ART[selection.instanceID]
    local lore = art and (art.lore or art.bg)
    ui.lore:SetShown(lore ~= nil)
    if lore then ui.lore:SetTexture(lore) end
    RenderBoss(keepScroll)
end

local function RenderPage(keepScroll)
    if not page or not page:IsShown() or not selection.instanceID then return end
    if not keepScroll then ui.slotMenu:Hide() end
    RenderHeader()
    local mapTab = selection.tab == "map"
    ui.listPanel:SetShown(not mapTab)
    ui.detailPanel:SetShown(not mapTab)
    ui.mapPanel:SetShown(mapTab)
    if mapTab then
        RenderMapTab(keepScroll)
        return
    end
    RenderList(keepScroll)
    RenderDetail(keepScroll)
end

local function CreateEntranceButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(22, 22)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints()
    button.Icon:SetTexture(TEX.LFG_DUNGEON)
    W.Mask(button, button.Icon)
    button.Ring = button:CreateTexture(nil, "OVERLAY")
    button.Ring:SetSize(26, 26)
    button.Ring:SetPoint("CENTER")
    button.Ring:SetTexture(TEX.GOLD_RING)
    button:SetHighlightTexture(TEX.RING_HOVER, "ADD")
    W.Tooltip(button, L["Show entrance on map"], L["Opens the world map with the entrance marked."])
    button:SetScript("OnClick", function()
        local dungeon = CurrentDungeon()
        local entrance = ns.GetEntrance(dungeon)
        if entrance then Journal:ShowLocation({ map = entrance.map, x = entrance.x, y = entrance.y, name = dungeon.name }, L["%s entrance"]:format(dungeon.name)) end
    end)
    return button
end

local function CreateHeaderTabs(head)
    ui.questTab = W.Tab(head, L["Quests"], TEX.QUEST_AVAILABLE)
    ui.questTab:SetPoint("RIGHT", -10, 0)
    ui.questTab:SetScript("OnClick", function() Journal:SetTab("quests") end)
    ui.bossTab = W.Tab(head, L["Bosses"], TEX.SKULL)
    ui.bossTab:SetPoint("RIGHT", ui.questTab, "LEFT", -6, 0)
    ui.bossTab:SetScript("OnClick", function() Journal:SetTab("bosses") end)
    ui.mapTab = W.Tab(head, L["Map"], TEX.MAP)
    ui.mapTab:SetPoint("RIGHT", ui.bossTab, "LEFT", -6, 0)
    ui.mapTab:SetScript("OnClick", function() Journal:SetTab("map") end)
end

-- Header band: dungeon art strip, round icon, name, sub-line, entrance button, tabs.
local function CreateHeaderBand()
    local head = W.Panel(page)
    head:SetPoint("TOPLEFT", SIDE_MARGIN, -HEADER_TOP)
    head:SetPoint("TOPRIGHT", -SIDE_MARGIN, -HEADER_TOP)
    head:SetHeight(HEADER_HEIGHT)
    ui.headerArt = W.CreateHeaderArt(head)
    ui.headerIcon = W.CreateRoundIcon(head, HEADER_ICON_SIZE)
    ui.headerIcon:SetPoint("LEFT", HEADER_ICON_LEFT, 0)
    ui.headerName = head:CreateFontString(nil, "OVERLAY", ns.Font("title"))
    ui.headerName:SetPoint("TOPLEFT", HEADER_ICON_LEFT + HEADER_ICON_SIZE + 8, -12)
    ui.headerName:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
    ui.headerName:SetWordWrap(false)
    ui.headerSub = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.headerSub:SetPoint("TOPLEFT", ui.headerName, "BOTTOMLEFT", 0, -4)
    ui.entranceButton = CreateEntranceButton(head)
    ui.headerStar = MakeStar(head, 22)
    CreateHeaderTabs(head)
end

local function MakeFactionToggle(parent, faction)
    local toggle = CreateFrame("Button", nil, parent, "BackdropTemplate")
    toggle:SetSize(FACTION_TOGGLE_WIDTH, FACTION_TOGGLE_HEIGHT)
    toggle.Icon = toggle:CreateTexture(nil, "ARTWORK")
    toggle.Icon:SetSize(FACTION_TOGGLE_ICON, FACTION_TOGGLE_ICON)
    toggle.Icon:SetPoint("CENTER")
    W.SetFactionIcon(toggle.Icon, faction)
    W.Hoverable(toggle, "row")
    W.Tooltip(toggle, L["Show %s quests"]:format(L[faction]), L["Click to toggle"])
    return toggle
end

local function CreateListPanel(body, handlers)
    local panel = W.Panel(body)
    panel:SetPoint("TOPLEFT")
    panel:SetPoint("BOTTOMLEFT")
    panel:SetWidth(LIST_WIDTH)
    ui.listTitle = panel:CreateFontString(nil, "OVERLAY", ns.Font("panelTitle"))
    ui.listTitle:SetPoint("TOPLEFT", 12, -11)
    ui.listTitle:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
    ui.listCount = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.listCount:SetPoint("BOTTOMLEFT", ui.listTitle, "BOTTOMRIGHT", 8, 0)
    local divider = W.Divider(panel)
    divider:SetPoint("TOPLEFT", 8, -34)
    divider:SetPoint("TOPRIGHT", -8, -34)
    ui.hordeToggle = MakeFactionToggle(panel, "Horde")
    ui.hordeToggle:SetPoint("TOPRIGHT", -10, -4)
    ui.hordeToggle:SetScript("OnClick", function() selection.showHorde = not selection.showHorde; Journal:Refresh() end)
    ui.allianceToggle = MakeFactionToggle(panel, "Alliance")
    ui.allianceToggle:SetPoint("RIGHT", ui.hordeToggle, "LEFT", -4, 0)
    ui.allianceToggle:SetScript("OnClick", function() selection.showAlliance = not selection.showAlliance; Journal:Refresh() end)
    ui.list = Canvas.New("ForeverDungeonMapJournalList", panel, { width = LIST_CONTENT_WIDTH, handlers = handlers, wheelStep = 60 })
    ui.list.scroll:SetPoint("TOPLEFT", 8, -40)
    ui.list.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    ui.listPanel = panel
end

-- Track and Share icon buttons left of the done tick.
local function CreateQuestButtons(header)
    ui.shareButton = W.IconButton(header, QUEST_BUTTON_SIZE, TEX.SHARE)
    ui.shareButton:SetPoint("TOPRIGHT", -38, -8)
    ui.shareButton:SetScript("OnClick", function(self) W.ShareQuest(self.questID) end)
    ui.trackButton = W.IconButton(header, QUEST_BUTTON_SIZE, TEX.TRACK)
    ui.trackButton:SetPoint("RIGHT", ui.shareButton, "LEFT", -4, 0)
    ui.trackButton:SetScript("OnClick", function(self)
        W.ToggleQuestTracking(self.questID)
        Journal:Refresh(true)
    end)
end

-- Fixed quest header (does not scroll): title, level line, crests, tick, parchment break.
local function CreateQuestHeader(panel)
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", PANEL_INSET, -PANEL_INSET)
    header:SetPoint("TOPRIGHT", -PANEL_INSET, -PANEL_INSET)
    header:SetHeight(QUEST_HEADER_HEIGHT)
    ui.questTitle = header:CreateFontString(nil, "OVERLAY", ns.Font("questTitle"))
    ui.questTitle:SetPoint("TOPLEFT", 14, -10)
    ui.questTitle:SetPoint("RIGHT", header, "TOPRIGHT", -100, 0)
    ui.questTitle:SetJustifyH("LEFT")
    ui.questTitle:SetWordWrap(false)
    ui.questTitle:SetTextColor(C.PARCH_HEAD[1], C.PARCH_HEAD[2], C.PARCH_HEAD[3])
    ui.questTitle:SetShadowOffset(0, 0)
    ui.questMeta = header:CreateFontString(nil, "OVERLAY", ns.Font("questBody"))
    ui.questMeta:SetPoint("TOPLEFT", ui.questTitle, "BOTTOMLEFT", 0, -6)
    ui.questMeta:SetTextColor(C.PARCH_MUTED[1], C.PARCH_MUTED[2], C.PARCH_MUTED[3])
    ui.questMeta:SetShadowOffset(0, 0)
    ui.questFaction1 = header:CreateTexture(nil, "ARTWORK")
    ui.questFaction1:SetSize(QUEST_HEADER_CREST, QUEST_HEADER_CREST)
    ui.questFaction2 = header:CreateTexture(nil, "ARTWORK")
    ui.questFaction2:SetSize(QUEST_HEADER_CREST, QUEST_HEADER_CREST)
    ui.questFaction2:SetPoint("LEFT", ui.questFaction1, "RIGHT", 4, 0)
    ui.questClass = W.IconWithTooltip(header, 20)
    ui.questDone = header:CreateTexture(nil, "ARTWORK")
    ui.questDone:SetSize(24, 24)
    ui.questDone:SetPoint("TOPRIGHT", -8, -7)
    ui.questDone:SetTexture(TEX.TICK)
    CreateQuestButtons(header)
    local horizontalBreak = header:CreateTexture(nil, "ARTWORK")
    horizontalBreak:SetPoint("BOTTOMLEFT", 8, -2)
    horizontalBreak:SetPoint("BOTTOMRIGHT", -8, -2)
    horizontalBreak:SetHeight(12)
    horizontalBreak:SetTexture(TEX.HORIZONTAL_BREAK)
    horizontalBreak:SetAlpha(ns.ALPHA.divider)
    header:Hide()
    ui.questHeader = header
end

local function CreateDetailBackgrounds(panel)
    ui.lore = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    W.Inset(ui.lore, PANEL_INSET)
    ui.lore:SetAlpha(ns.ALPHA.lore)
    ui.lore:SetDesaturated(true)
    ui.parchment = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    W.Inset(ui.parchment, PANEL_INSET)
    ui.parchment:SetTexture(TEX.PARCHMENT)
    ui.parchment:SetTexCoord(unpack(TEX.PARCHMENT_COORDS))
    ui.parchment:Hide()
end

local function CreateDetailPanel(body, handlers)
    local panel = W.Panel(body)
    panel:SetPoint("TOPLEFT", ui.listPanel, "TOPRIGHT", PANEL_GAP, 0)
    panel:SetPoint("BOTTOMRIGHT")
    CreateDetailBackgrounds(panel)
    ui.bossDetail = Canvas.New("ForeverDungeonMapJournalBoss", panel, { width = BOSS_CONTENT_WIDTH, handlers = handlers })
    ui.bossDetail.scroll:SetPoint("TOPLEFT", 12, -12)
    ui.bossDetail.scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    CreateQuestHeader(panel)
    ui.questDetail = Canvas.New("ForeverDungeonMapJournalQuest", panel,
        { width = QUEST_CONTENT_WIDTH, parchment = true, handlers = handlers })
    ui.questDetail.scroll:SetPoint("TOPLEFT", 18, -(QUEST_HEADER_HEIGHT + 6))
    ui.questDetail.scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    ui.detailPanel = panel
    ui.slotMenu = W.CreateChoiceMenu(frame, MENU_WIDTH)
end

local function CreateMapPanel(body)
    local panel = W.Panel(body, C.MAP_BG, C.EDGE_PANEL)
    panel:SetAllPoints(body)
    panel:SetClipsChildren(true)
    local holder = CreateFrame("Frame", nil, panel)
    W.Inset(holder, PANEL_INSET)
    ui.journalMap = ns.MapCanvas.Create(holder, {
        top = MAP_TOP_STRIP,
        onBoss = function(boss, index) Journal:ShowBoss(selection.instanceID, boss, index) end,
        onRightClick = function() Journal:SetTab("bosses") end,
    })
    Journal.map = ui.journalMap
    panel:Hide()
    ui.mapPanel = panel
end

-- What clicks on list and page rows do.
local function CreateHandlers()
    return {
        boss = function(boss, index) Journal:ShowBoss(selection.instanceID, boss, index) end,
        quest = function(quest) Journal:ShowQuest(selection.instanceID, quest) end,
        chain = function(quest)
            selection.expanded[quest.id] = not selection.expanded[quest.id] or nil
            Journal:Refresh(true)
        end,
        step = function(quest, questID)
            selection.quest, selection.step = quest, (questID ~= quest.id) and questID or nil
            Journal:Refresh(true)
        end,
        pin = function(location, label) Journal:ShowLocation(location, label) end,
        turnIn = function(quest)
            local finish = W.Location(quest, "finish", selection.instanceID)
            if finish then Journal:ShowLocation(finish, quest.name) end
        end,
    }
end

local function CreatePage()
    page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    local back = W.Tab(page, L["Dungeons"], TEX.PREVIOUS_UP, 120, 22)
    back:SetPoint("TOPLEFT", 20, -50)
    back:SetScript("OnClick", function() Journal:ShowHome() end)
    CreateHeaderBand()
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", SIDE_MARGIN, -BODY_TOP)
    body:SetPoint("BOTTOMRIGHT", -SIDE_MARGIN, SIDE_MARGIN)
    local handlers = CreateHandlers()
    CreateListPanel(body, handlers)
    CreateDetailPanel(body, handlers)
    CreateMapPanel(body)
end

local function Matches(instanceID, dungeon)
    if query == "" then return true end
    if dungeon.name:lower():find(query, 1, true) then return true end
    for _, boss in ipairs(ns.BOSSES[instanceID] or {}) do
        if boss.name:lower():find(query, 1, true) then return true end
    end
    for _, quest in ipairs(ns.QUESTS[instanceID] or {}) do
        if quest.name:lower():find(query, 1, true) then return true end
    end
    return false
end

-- Dungeons for the filter and search: the current instance first, then by level and name.
local function SortedDungeons()
    local sorted = {}
    for instanceID, dungeon in pairs(ns.DUNGEONS) do
        local passesFilter = filter == "all" or (filter == "favourites" and IsFavourite(instanceID))
            or (filter ~= "favourites" and (filter == "forever") == (dungeon.forever == true))
        if passesFilter and Matches(instanceID, dungeon) then sorted[#sorted + 1] = { instanceID = instanceID, dungeon = dungeon } end
    end
    table.sort(sorted, function(first, second)
        local firstHere, secondHere = first.instanceID == ns.instanceID, second.instanceID == ns.instanceID
        if firstHere ~= secondHere then return firstHere end
        local firstLevel, secondLevel = first.dungeon.min or 0, second.dungeon.min or 0
        if firstLevel ~= secondLevel then return firstLevel < secondLevel end
        return first.dungeon.name < second.dungeon.name
    end)
    return sorted
end

local function MakeCardShades(card)
    card.TopShade = card:CreateTexture(nil, "BORDER")
    card.TopShade:SetPoint("TOPLEFT", PANEL_INSET, -PANEL_INSET)
    card.TopShade:SetPoint("TOPRIGHT", -PANEL_INSET, -PANEL_INSET)
    card.TopShade:SetHeight(40)
    W.ShadeVertical(card.TopShade, 0, 0.55)
    card.Shade = card:CreateTexture(nil, "BORDER")
    card.Shade:SetPoint("BOTTOMLEFT", PANEL_INSET, PANEL_INSET)
    card.Shade:SetPoint("BOTTOMRIGHT", -PANEL_INSET, PANEL_INSET)
    card.Shade:SetHeight(56)
    W.ShadeVertical(card.Shade, 0.9, 0)
end

local function MakeCardTexts(card)
    card.Name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.Name:SetPoint("TOPLEFT", 38, -12)
    card.Name:SetPoint("RIGHT", card, "TOPRIGHT", -150, 0)
    card.Name:SetJustifyH("LEFT")
    card.Name:SetWordWrap(false)
    card.Name:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
    card.Counts = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.Counts:SetPoint("TOPRIGHT", -14, -12)
    card.Tag = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.Tag:SetPoint("TOPRIGHT", card.Counts, "BOTTOMRIGHT", 0, -4)
    card.Level = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.Level:SetPoint("BOTTOMLEFT", 14, 10)
    card.Bosses = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.Bosses:SetPoint("LEFT", card.Level, "RIGHT", 8, 0)
    card.Bosses:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
end

local function Card(index)
    if cards[index] then return cards[index] end
    local card = CreateFrame("Button", nil, grid, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    card.Art = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    W.Inset(card.Art, PANEL_INSET)
    MakeCardShades(card)
    MakeCardTexts(card)
    card.Icon = W.CreateRoundIcon(card, 40)
    card.Icon:SetPoint("BOTTOMRIGHT", -12, 10)
    card.Star = MakeStar(card, 22)
    card.Star:SetPoint("TOPLEFT", 10, -9)
    card:SetScript("OnClick", function(self) Journal:OpenDungeon(self.instanceID) end)
    card.OnVisual = function(self, hover)
        local brightness = hover and 1 or ns.ALPHA.cardArt
        self.Art:SetVertexColor(brightness, brightness, brightness)
    end
    W.Hoverable(card, "card")
    cards[index] = card
    return card
end

-- done, total quests of a dungeon for the player's faction and class.
local function QuestProgress(instanceID)
    local done, total = 0, 0
    for _, quest in ipairs(ns.QUESTS[instanceID] or {}) do
        if W.QuestState(quest) ~= "other" then
            total = total + 1
            if W.IsQuestDone(quest.id) then done = done + 1 end
        end
    end
    return done, total
end

local function CardTag(instanceID, dungeon)
    if ns.instanceID == instanceID then return ns.Hex(C.DONE) .. L["You are here"] .. "|r" end
    if dungeon.comingSoon then return ns.Hex(C.FOREVER) .. L["WoW Forever"] .. " · " .. L["Coming soon"] .. "|r" end
    if dungeon.forever then return ns.Hex(C.FOREVER) .. L["WoW Forever"] .. "|r" end
    return ""
end

local function FillCard(card, instanceID, dungeon)
    card.instanceID, card.dungeon = instanceID, dungeon
    local art = ns.ART and ns.ART[instanceID]
    local texture = art and (art.card or art.bg)
    card.Art:SetShown(texture ~= nil)
    if texture then
        card.Art:SetTexture(texture)
        card.Art:SetTexCoord(unpack((art.card and art.cardCoords) or art.bgCoords or TEX.FULL_COORDS))
    end
    W.SetDungeonIcon(card.Icon, instanceID)
    card.Name:SetText(dungeon.name)
    local done, total = QuestProgress(instanceID)
    local allDone = total > 0 and done == total
    card.Counts:SetText(allDone and (ns.IconString(TEX.TICK, 14) .. (" " .. L["%d/%d quests"]):format(done, total))
        or L["%d quests"]:format(#(ns.QUESTS[instanceID] or {})))
    card.Level:SetText(ns.RangeText(dungeon) or "")
    local bossCount = #(ns.BOSSES[instanceID] or {})
    card.Bosses:SetText(bossCount == 1 and L["1 boss"] or L["%d bosses"]:format(bossCount))
    card.Tag:SetText(CardTag(instanceID, dungeon))
    card.Star.instanceID = instanceID
    SetStar(card.Star, instanceID)
end

local function RenderHome()
    local items = SortedDungeons()
    for index, item in ipairs(items) do
        local card = Card(index)
        FillCard(card, item.instanceID, item.dungeon)
        local column, row = (index - 1) % CARD_COLUMNS, math.floor((index - 1) / CARD_COLUMNS)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", column * (CARD_WIDTH + CARD_GAP_X), -row * (CARD_HEIGHT + CARD_GAP_Y))
        card:Show()
        W.ApplyVisual(card)
    end
    for index = #items + 1, #cards do cards[index]:Hide() end
    grid:SetHeight(math.max(1, math.ceil(#items / CARD_COLUMNS) * (CARD_HEIGHT + CARD_GAP_Y)))
    levelTag:SetText(L["Your level: %d"]:format(UnitLevel("player") or 1))
    for key, button in pairs(filterButtons) do button:SetSelected(key == filter) end
end

local function CreateHome()
    home = CreateFrame("Frame", nil, frame)
    home:SetAllPoints()
    local previous
    for _, entry in ipairs(FILTERS) do
        local chip = W.Tab(home, entry[2], entry[3], entry[3] and 36 or 80, 22)
        if entry[3] then W.Tooltip(chip, L["Favourites"], L["Only your favourite dungeons"]) end
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 20, -50) end
        chip:SetScript("OnClick", function()
            filter = entry[1]
            RenderHome()
        end)
        filterButtons[entry[1]] = chip
        previous = chip
    end
    levelTag = home:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelTag:SetPoint("TOPRIGHT", -24, -54)
    local gridScroll = CreateFrame("ScrollFrame", "ForeverDungeonMapJournalGrid", home, "UIPanelScrollFrameTemplate")
    gridScroll:SetPoint("TOPLEFT", SIDE_MARGIN, -HEADER_TOP)
    gridScroll:SetPoint("BOTTOMRIGHT", -32, SIDE_MARGIN)
    grid = CreateFrame("Frame", nil, gridScroll)
    grid:SetSize(CARD_COLUMNS * CARD_WIDTH + CARD_GAP_X, 10)
    gridScroll:SetScrollChild(grid)
end

local function MatchesQuery(text) return text:lower():find(query, 1, true) ~= nil end

-- Up to SEARCH_RESULTS matches: { kind = "dungeon" | "boss" | "quest", instanceID, boss, index, quest }.
local function SearchResults()
    local results = {}
    local function Add(result) if #results < SEARCH_RESULTS then results[#results + 1] = result end end
    local ids = {}
    for instanceID in pairs(ns.DUNGEONS) do ids[#ids + 1] = instanceID end
    table.sort(ids, function(first, second) return ns.DUNGEONS[first].name < ns.DUNGEONS[second].name end)
    for _, instanceID in ipairs(ids) do
        if MatchesQuery(ns.DUNGEONS[instanceID].name) then Add({ kind = "dungeon", instanceID = instanceID }) end
    end
    for _, instanceID in ipairs(ids) do
        for index, boss in ipairs(ns.BOSSES[instanceID] or {}) do
            if MatchesQuery(boss.name) then Add({ kind = "boss", instanceID = instanceID, boss = boss, index = index }) end
        end
    end
    for _, instanceID in ipairs(ids) do
        for _, quest in ipairs(ns.QUESTS[instanceID] or {}) do
            if MatchesQuery(quest.name) then Add({ kind = "quest", instanceID = instanceID, quest = quest }) end
        end
    end
    return results
end

local function OpenResult(result)
    search:SetText("")
    search:ClearFocus()
    if result.kind == "boss" then Journal:ShowBoss(result.instanceID, result.boss, result.index)
    elseif result.kind == "quest" then Journal:ShowQuest(result.instanceID, result.quest)
    else Journal:OpenDungeon(result.instanceID) end
end

local RESULT_ICONS = { boss = TEX.SKULL, quest = TEX.QUEST_AVAILABLE }

local function MakeResultRow(index)
    local row = CreateFrame("Button", nil, ui.searchResults, "BackdropTemplate")
    row:SetSize(SEARCH_WIDTH - 8, SEARCH_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * SEARCH_ROW_HEIGHT)
    row.Icon = W.CreateRoundIcon(row, 16)
    row.Icon:SetPoint("LEFT", 6, 0)
    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
    row.Name:SetPoint("RIGHT", -110, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Where:SetPoint("RIGHT", -6, 0)
    row.Where:SetWidth(100)
    row.Where:SetJustifyH("RIGHT")
    row.Where:SetWordWrap(false)
    row.Where:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
    row:SetScript("OnClick", function(self) OpenResult(self.result) end)
    W.Hoverable(row, "row")
    return row
end

local function FillResultRow(row, result)
    row.result = result
    local dungeon = ns.DUNGEONS[result.instanceID]
    if RESULT_ICONS[result.kind] then
        row.Icon.Icon:SetTexture(RESULT_ICONS[result.kind])
        row.Icon.Icon:SetTexCoord(unpack(TEX.FULL_COORDS))
    else
        W.SetDungeonIcon(row.Icon, result.instanceID)
    end
    row.Name:SetText((result.boss and result.boss.name) or (result.quest and result.quest.name) or dungeon.name)
    row.Where:SetText(result.kind ~= "dungeon" and dungeon.name or "")
    row:Show()
end

-- Results dropdown under the search box while there is a query.
local function UpdateSearchResults()
    local results = query ~= "" and SearchResults() or {}
    ui.searchRows = ui.searchRows or {}
    for index, result in ipairs(results) do
        ui.searchRows[index] = ui.searchRows[index] or MakeResultRow(index)
        FillResultRow(ui.searchRows[index], result)
    end
    for index = #results + 1, #ui.searchRows do ui.searchRows[index]:Hide() end
    ui.searchResults:SetHeight(#results * SEARCH_ROW_HEIGHT + 8)
    ui.searchResults:SetShown(#results > 0)
    ui.searchResultList = results
end

-- Search box: filters the home cards and lists matches; Enter opens the first match.
local function CreateSearch()
    search = CreateFrame("EditBox", "ForeverDungeonMapJournalSearch", frame, "SearchBoxTemplate")
    search:SetSize(250, 20)
    search:SetPoint("TOPLEFT", 24, -20)
    search:SetAutoFocus(false)
    if search.Instructions then search.Instructions:SetText(L["Search dungeons, bosses, quests..."]) end
    search:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        if text == query then return end
        query = text
        if query ~= "" and page and page:IsShown() then Journal:ShowHome() else RenderHome() end
        UpdateSearchResults()
    end)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local first = ui.searchResultList and ui.searchResultList[1]
        if query ~= "" and first then OpenResult(first) end
    end)
    ui.searchResults = W.Panel(frame)
    ui.searchResults:SetFrameStrata("FULLSCREEN_DIALOG")
    ui.searchResults:SetWidth(SEARCH_WIDTH)
    ui.searchResults:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -2)
    ui.searchResults:Hide()
end

local refreshPending = false
-- One repaint per burst of events, keeping scroll and hover.
local function QueueRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        Journal:Refresh(true)
    end)
end

-- Item data arrived: refill only the rows that show the item.
local function OnItemData(itemID, success)
    if type(itemID) ~= "number" then return end
    for _, canvas in ipairs({ ui.bossDetail, ui.questDetail, ui.list }) do
        canvas:RefreshItem(itemID, success)
    end
end

local function CreateEvents()
    local listener = CreateFrame("Frame", nil, frame)
    local itemEvents = {}
    for _, event in ipairs(ITEM_EVENTS) do itemEvents[event] = true end
    for _, event in ipairs(REFRESH_EVENTS) do pcall(listener.RegisterEvent, listener, event) end
    for _, event in ipairs(ITEM_EVENTS) do pcall(listener.RegisterEvent, listener, event) end
    listener:SetScript("OnEvent", function(_, event, itemID, success)
        if not frame:IsShown() then return end
        if itemEvents[event] then OnItemData(itemID, success) else QueueRefresh() end
    end)
end

-- Note icon left of the close button: opens the bug report.
local function CreateBugButton()
    ui.bugButton = W.IconButton(frame, BUG_BUTTON_SIZE, TEX.BUG_REPORT)
    ui.bugButton:SetPoint("RIGHT", frame.CloseButton, "LEFT", -4, 0)
    ui.bugButton:SetScript("OnClick", function() ns.BugReport.Open() end)
    W.Tooltip(ui.bugButton, L["Report a bug"], L["Copy the details of a problem to send them in."])
end

local function Create()
    if frame then return end
    frame = W.Window("ForeverDungeonMapJournal", WINDOW_WIDTH, WINDOW_HEIGHT, "Dungeon Journal")
    frame:SetPoint("CENTER", 0, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:Hide()
    tinsert(UISpecialFrames, "ForeverDungeonMapJournal")
    W.MarkOwned(frame)
    W.SetupTooltipBacking()
    CreateSearch()
    CreateBugButton()
    local hairline = W.Divider(frame)
    hairline:SetPoint("TOPLEFT", 18, -76)
    hairline:SetPoint("TOPRIGHT", -18, -76)
    CreateHome()
    CreatePage()
    CreateEvents()
end

local function ShowFrame()
    frame:Show()
    frame:Raise()
end

function Journal:ShowHome()
    Create()
    page:Hide()
    home:Show()
    ShowFrame()
    RenderHome()
end

-- A newly opened dungeon lists only the quests the player's faction can do; the crest toggles
-- above the list add the other faction.
local function SelectDungeon(instanceID)
    selection.instanceID, selection.boss, selection.bossIndex, selection.quest, selection.step = instanceID, nil, nil, nil, nil
    local faction = UnitFactionGroup("player")
    selection.showAlliance, selection.showHorde = faction ~= "Horde", faction ~= "Alliance"
end

-- Open a dungeon page on a tab ("bosses", "quests" or "map"); first boss / quest preselected.
function Journal:OpenDungeon(instanceID, tab)
    Create()
    if not ns.DUNGEONS[instanceID] then return end
    local switched = selection.instanceID ~= instanceID
    if switched then SelectDungeon(instanceID) end
    local tabChanged = tab ~= nil and tab ~= selection.tab
    selection.tab = tab or selection.tab or "bosses"
    if not selection.boss then selection.boss, selection.bossIndex = Bosses()[1], 1 end
    if not selection.quest then
        local first = SortedQuests()[1]
        selection.quest = first and first.quest
    end
    home:Hide()
    page:Show()
    ShowFrame()
    RenderPage(not (switched or tabChanged))
end

function Journal:SetTab(tab)
    if not selection.instanceID then return end
    local changed = tab ~= selection.tab
    selection.tab = tab
    RenderPage(not changed)
end

function Journal:ShowBoss(instanceID, boss, index)
    if selection.instanceID ~= instanceID then self:OpenDungeon(instanceID, "bosses") end
    local changed = selection.boss ~= boss or selection.tab ~= "bosses"
    if selection.boss ~= boss then selection.slot = nil end
    selection.boss, selection.bossIndex = boss, index
    self:OpenDungeon(instanceID, "bosses")
    if changed then
        ui.bossDetail.scroll:SetVerticalScroll(0)
        ui.slotMenu:Hide()
    end
    if ns.View:IsShown() then ns.View:FocusBoss(boss) end
end

function Journal:ShowQuest(instanceID, quest)
    if selection.instanceID ~= instanceID then self:OpenDungeon(instanceID, "quests") end
    local changed = selection.quest ~= quest or selection.step ~= nil
    selection.quest, selection.step = quest, nil
    self:OpenDungeon(instanceID, "quests")
    if changed then ui.questDetail.scroll:SetVerticalScroll(0) end
end

-- The dungeon's map in the journal (on the floor of `boss`).
function Journal:ShowOnMap(boss)
    if not selection.instanceID then return end
    selection.mapFocus = boss
    self:OpenDungeon(selection.instanceID, "map")
end

-- Waypoint with the navigation arrow on a quest giver / turn-in spot, and show it on its zone map.
function Journal:ShowLocation(location, label)
    if not (location and location.map and location.x and location.y) then return end
    ns.SetWaypoint(location, (location.name or "") .. " - " .. (label or ""))
    if InCombatLockdown() then
        ns.Print(L["the map opens after combat"])
        ns.AfterCombat("spot", function() Journal:ShowLocation(location, label) end)
        return
    end
    ns.View:ShowSpot({ map = location.map, x = location.x, y = location.y, title = location.name or label, text = label })
end

function Journal:Toggle()
    Create()
    if frame:IsShown() then
        frame:Hide()
    elseif ns.instanceID and ns.DUNGEONS[ns.instanceID] then
        self:OpenDungeon(ns.instanceID)
    else
        self:ShowHome()
    end
end

function Journal:IsShown() return frame ~= nil and frame:IsShown() end

-- Repaint what is visible (keeps scroll positions and hover unless keepScroll is false).
function Journal:Refresh(keepScroll)
    if not frame or not frame:IsShown() then return end
    if page:IsShown() then RenderPage(keepScroll ~= false) else RenderHome() end
end

-- The current selection (tests and other modules read it).
function Journal:State() return selection end

ns.OnBossKilled(function() Journal:Refresh(true) end)

ns.OnLoad(function()
    if ns.Rewards and ns.Rewards.OnLearned then ns.Rewards.OnLearned(function() Journal:Refresh(true) end) end
end)
