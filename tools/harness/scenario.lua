-- scenario.lua - default end-to-end scenario for ForeverDungeonMap (v0.6 UI, docs/ui-spec.md)
-- Run with and without --combat; every check must pass in both.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step
local COMBAT = M.combat

-- map art: floors listed in ns.DUNGEONS (and the Forever tile floors) exist, others do not
M.FileExists = function(path)
    local art, n = path:match("Interface\\WorldMap\\([^\\]+)\\[^\\]-(%d+)_1$")
    if not art then return true end
    -- like the client: Zul'Farrak's tiles carry no floor number (ZulFarrak\ZulFarrak1..12)
    if art == "ZulFarrak" then return false end
    for _, d in pairs(ns.DUNGEONS or {}) do
        if d.art == art then return tonumber(n) <= (d.floors or 1) end
        for _, floor in ipairs(d.tileFloors or {}) do
            if floor.tiles and floor.tiles .. "1" == path then return true end
        end
    end
    return false
end

local function sortedIDs(t)
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function colorEq(a, b) return a and b and math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01 end
local function border(w) if not w.GetBackdropBorderColor then return nil end return { w:GetBackdropBorderColor() } end
local GOLD = ns.C and ns.C.GOLD

---------------------------------------------------------------------------
-- login
---------------------------------------------------------------------------
Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(6)
GOLD = ns.C.GOLD
Check("syntax: every addon .lua file parses", (M.syntaxChecked or 0) > 10, M.syntaxChecked)
Check("instance detected", ns.instanceID == 43, "ns.instanceID=" .. tostring(ns.instanceID))
Check("saved variables created", type(ForeverDungeonMapDB) == "table")
Check("palette replaces per-dungeon moods", ns.GetTheme == nil and ns.C ~= nil)

-- Forever data merged
for _, id in ipairs({ 2959, 2998, 2999, 3065, 2970, 2974, 2994, 3001, 3039 }) do
    local d = ns.DUNGEONS[id]
    Check("forever dungeon " .. id .. " in the journal", d ~= nil and d.forever == true, d and d.name)
end
if ns.FOREVER then
    Check("new forever dungeons are 'coming soon' without quests/loot", ns.DUNGEONS[2970] and ns.DUNGEONS[2970].comingSoon == true)
    Check("forever bosses get levels", ns.BossLevel(2959, "Arcane Anomaly") ~= nil)
end

---------------------------------------------------------------------------
-- hover helper: every hoverable row/button gets a gold border on hover
---------------------------------------------------------------------------
local function CheckHoverAll(label, root)
    local bad, n = {}, 0
    for _, w in ipairs(M.Descendants(root)) do
        if rawget(w, "style") and w.style.edge and w:IsVisible() and w.SetBackdrop then
            n = n + 1
            M.Enter(w)
            local b = border(w)
            if not colorEq(b, GOLD) then bad[#bad + 1] = tostring(w) .. " border " .. table.concat(b or {}, ",") end
            M.Leave(w)
            if w.hovered then bad[#bad + 1] = tostring(w) .. " still hovered after leave" end
        end
    end
    GameTooltip:Hide()
    Check(label .. ": gold hover border on every row/button (" .. n .. ")", #bad == 0 and n > 0, table.concat(bad, "; "):sub(1, 300))
end

---------------------------------------------------------------------------
-- journal home
---------------------------------------------------------------------------
Step("Journal:ShowHome", function() ns.Journal:ShowHome() end)
local journal = _G.ForeverDungeonMapJournal
Check("journal frame shown, 860x632 (600 + bug report footer)", journal and journal:IsVisible() and journal:GetWidth() == 860 and journal:GetHeight() == 632)
local grid = _G.ForeverDungeonMapJournalGrid and _G.ForeverDungeonMapJournalGrid:GetScrollChild()
if grid then
    local cardsShown = M.Shown(grid._children or {})
    Check("home: one card per dungeon", #cardsShown == count(ns.DUNGEONS), ("%d cards, %d dungeons"):format(#cardsShown, count(ns.DUNGEONS)))
    M.CheckRows("home grid", grid, { width = grid:GetWidth() })
    local first = cardsShown[1]
    Check("home: current instance first", first and rawget(first, "instanceID") == 43, first and rawget(first, "instanceID"))
    local lefts = {}
    for _, c in ipairs(cardsShown) do lefts[math.floor(M.RelLeft(grid, c) or -1)] = true end
    Check("home: two columns of 388 px cards", count(lefts) == 2 and first:GetWidth() == 388 and first:GetHeight() == 120)
    local artless, soonTag = {}, false
    for _, c in ipairs(cardsShown) do
        if not c.Art:IsShown() or not c.Art:GetTexture() then artless[#artless + 1] = c.dungeon.name end
        if c.dungeon.comingSoon and (c.Tag:GetText() or ""):find("Coming soon", 1, true) then soonTag = true end
    end
    Check("home: every card has art", #artless == 0, table.concat(artless, ", "))
    if ns.FOREVER then Check("home: coming soon badge", soonTag) end
    CheckHoverAll("home", journal)
end
local search = _G.ForeverDungeonMapJournalSearch
if search then
    local handle = _G.ForeverDungeonMapJournal.dragHandle
    Check("search box sits above the window's drag strip (clickable)", handle == nil or search:GetFrameLevel() > handle:GetFrameLevel(),
        handle and (search:GetFrameLevel() .. " vs " .. handle:GetFrameLevel()))
    Step("search 'verdan'", function() M.TypeText(search, "verdan") end)
    Check("search by boss name finds Wailing Caverns", grid and #M.Shown(grid._children or {}) == 1)
    Step("search quest name", function() M.TypeText(search, "deviate eradication") end)
    Check("search by quest name", grid and #M.Shown(grid._children or {}) == 1)
    Step("search clear", function() M.TypeText(search, "") end)
end

---------------------------------------------------------------------------
-- every dungeon: boss pages, sorted quest list, quest pages, map tab
---------------------------------------------------------------------------
local bossScroll = function() return _G.ForeverDungeonMapJournalBoss end
local questScroll = function() return _G.ForeverDungeonMapJournalQuest end
local listScroll = function() return _G.ForeverDungeonMapJournalList end

local function itemRows(content)
    local rows = {}
    for _, r in ipairs(M.Rows(content)) do
        if rawget(r.w, "itemID") and rawget(r.w, "Sub") then rows[#rows + 1] = r end
    end
    return rows
end

local function checkBossPage(id, boss, label)
    local sf = bossScroll()
    if not Check(label .. ": boss detail visible", sf and sf:IsVisible()) then return {} end
    local content = sf:GetScrollChild()
    M.CheckRows(label .. " detail", content, { width = sf:GetWidth() })
    local items = itemRows(content)
    local want = boss.loot and #boss.loot or 0
    Check(label .. ": one loot row per item", #items == want, ("%d rows for %d items"):format(#items, want))
    local prevTop = -1
    for i, r in ipairs(items) do
        local name = r.w.Name and r.w.Name:GetText()
        if not (r.height == 46 and r.top and r.top > prevTop and r.width == 434) then
            Check(label .. ": loot row " .. i .. " geometry", false, ("top=%s h=%s w=%s"):format(tostring(r.top), tostring(r.height), tostring(r.width)))
        end
        if not (name and name ~= "") then Check(label .. ": loot row " .. i .. " has a name", false) end
        if rawget(r.w, "itemID") ~= boss.loot[i] then Check(label .. ": loot row " .. i .. " order", false) end
        prevTop = r.top or prevTop
    end
    local text = M.TextOf(content)
    Check(label .. ": header shows the boss name", text:find(boss.name, 1, true) ~= nil, text:sub(1, 80))
    local lv = ns.BossLevel(id, boss.name)
    if lv then Check(label .. ": header shows the level", text:find("Level", 1, true) ~= nil, text:sub(1, 120)) end
    return items
end

local function headingOrder(content)
    local out = {}
    for _, r in ipairs(M.Rows(content)) do
        if rawget(r.w, "Line") and rawget(r.w, "Text") and rawget(r.w, "Count") then out[#out + 1] = r.w.Text:GetText() end
    end
    return out
end

local SECTION_ORDER = { ["Objective"] = 1, ["Starts at"] = 2, ["Turn in"] = 3, ["Quest chain"] = 4,
    ["Choose one reward"] = 5, ["Rewards"] = 5, ["You will also receive:"] = 6 }

local errorsBefore = #M.report.errors
for _, id in ipairs(sortedIDs(ns.DUNGEONS)) do
    local d = ns.DUNGEONS[id]
    local bosses = ns.BOSSES[id] or {}
    Step(("OpenDungeon(%d bosses)"):format(id), function() ns.Journal:OpenDungeon(id, "bosses") end)
    local ls = listScroll()
    M.CheckRows(d.name .. " boss list", ls:GetScrollChild(), { width = ls:GetWidth() })
    for i, b in ipairs(bosses) do
        local label = ("%s / %s"):format(d.name, b.name)
        Step("ShowBoss " .. label, function() ns.Journal:ShowBoss(id, b, i) end)
        checkBossPage(id, b, label)
    end
    Step(("SetTab(quests) %d"):format(id), function() ns.Journal:SetTab("quests") end)
    local rows = M.Rows(ls:GetScrollChild())
    M.CheckRows(d.name .. " quest list", ls:GetScrollChild(), { width = ls:GetWidth() })
    local prevOrder, sorted, headers = 0, true, 0
    for _, r in ipairs(rows) do
        local q = rawget(r.w, "quest")
        if q then
            local o = ns.W.STATE_ORDER[ns.W.QuestState(q)]
            if o < prevOrder then sorted = false end
            prevOrder = o
        else
            headers = headers + 1
        end
    end
    Check(d.name .. ": quest list sorted by state, no group headers", sorted and (headers == 0 or #rows == 1), headers .. " non-quest rows")
    for _, e in ipairs(ns.Journal.SortedQuests()) do
        local q = e.quest
        local label = ("%s / quest %d %s"):format(d.name, q.id, q.name)
        Step("ShowQuest " .. label, function() ns.Journal:ShowQuest(id, q) end)
        local qs = questScroll()
        Check(label .. ": quest page visible", qs:IsVisible())
        M.CheckRows(label, qs:GetScrollChild(), { width = qs:GetWidth() })
        local titleFS = M.FindChild(qs:GetParent(), function() return false end)
        local order, ok = headingOrder(qs:GetScrollChild()), true
        local last = 0
        for _, h in ipairs(order) do
            local o = SECTION_ORDER[h] or 0
            if o < last then ok = false end
            last = math.max(last, o)
        end
        Check(label .. ": sections in FDJ order", ok, table.concat(order, " > "))
    end
    Step(("SetTab(map) %d"):format(id), function() ns.Journal:SetTab("map") end)
    local jm = ns.Journal.map
    Check(d.name .. ": map tab visible", jm and jm.frame:IsVisible())
    local floors = ns.GetFloors(id, d)
    local want = 0
    if floors[1] and not floors[1].overview then
        for _, b in ipairs(bosses) do
            local pos = ns.GetBossPos(id, b.name)
            -- a boss without a known spot sits in the row at the map's bottom, on every floor
            if not pos or (pos.floor or 1) == floors[1].index then want = want + 1 end
        end
    end
    Check(d.name .. ": map tab boss pins (placed + the row of unknown spots)", (jm.numPins or 0) == want,
        ("%s pins, %d expected"):format(tostring(jm.numPins), want))
    M.Advance(1)
end
Check("no Lua errors while rendering every journal page", #M.report.errors == errorsBefore,
    (#M.report.errors - errorsBefore) .. " new errors")

---------------------------------------------------------------------------
-- the reported case: Wailing Caverns, Verdan the Everliving - loot, hover, clicks
---------------------------------------------------------------------------
local wc = ns.BOSSES[43]
local verdanIndex, verdan
for i, b in ipairs(wc) do if b.name == "Verdan the Everliving" then verdanIndex, verdan = i, b end end
M.itemCache[6631] = nil
Step("ShowBoss Verdan", function() ns.Journal:ShowBoss(43, verdan, verdanIndex) end)
local items = checkBossPage(43, verdan, "WC / Verdan")
Check("Verdan: loot rows for 6630, 6631, 6629", #items >= 3 and rawget(items[1].w, "itemID") == 6630
    and rawget(items[2].w, "itemID") == 6631 and rawget(items[3].w, "itemID") == 6629)
if items[2] then
    local row = items[2].w
    Check("uncached item shows Loading...", row.Name:GetText() == "Loading...", row.Name:GetText())
    M.WatchHide(row)
    Step("hover loot row", function() M.Enter(row) end)
    Check("hover: tooltip shown", GameTooltip:IsShown() and GameTooltip:GetOwner() == row)
    Check("hover: gold border", colorEq(border(row), GOLD))
    M.Advance(1) -- item data arrives
    Check("item data arrival refills the row", row.Name:GetText() == "Living Root", row.Name:GetText())
    Check("hover survives item data arrival: row never hidden", row._hideCount == 0, row._hideCount)
    Check("hover survives item data arrival: gold border", colorEq(border(row), GOLD))
    Step("QUEST_LOG_UPDATE (hovered)", function() M.FireEvent("QUEST_LOG_UPDATE") end)
    M.Advance(1)
    Check("hover survives a repaint: row never hidden, border gold", row._hideCount == 0 and colorEq(border(row), GOLD))
    Step("leave loot row", function() M.Leave(row) end)
    Check("leave: border back to normal", not colorEq(border(row), GOLD))
    M.mod.shift = true
    Step("shift-click loot", function() M.Click(row, "LeftButton") end)
    M.mod.shift = false
    Check("shift-click inserts the item link", M.lastChatLink and M.lastChatLink:find("Living Root", 1, true) ~= nil, M.lastChatLink)
    M.mod.ctrl = true
    Step("ctrl-click loot", function() M.Click(row, "LeftButton") end)
    M.mod.ctrl = false
    Check("ctrl-click tries the item on", M.lastDressUp and M.lastDressUp:find("Living Root", 1, true) ~= nil, M.lastDressUp)
end
-- scroll position survives a repaint (longest boss page)
do
    local bestD, bestI, bestB
    for _, id in ipairs(sortedIDs(ns.BOSSES)) do
        for i, b in ipairs(ns.BOSSES[id]) do
            if ns.DUNGEONS[id] and b.loot and (not bestB or #b.loot > #bestB.loot) then bestD, bestI, bestB = id, i, b end
        end
    end
    Step("ShowBoss longest loot", function() ns.Journal:ShowBoss(bestD, bestB, bestI) end)
    local sf = bossScroll()
    local range = sf:GetScrollChild():GetHeight() - sf:GetHeight()
    if Check("a boss page long enough to scroll", range > 20, range) then
        sf:SetVerticalScroll(20)
        Step("QUEST_LOG_UPDATE (scrolled)", function() M.FireEvent("QUEST_LOG_UPDATE") end)
        M.Advance(1)
        Check("QUEST_LOG_UPDATE keeps the boss page scroll position", sf:GetVerticalScroll() == 20, sf:GetVerticalScroll())
    end
    Step("ShowBoss Verdan again", function() ns.Journal:ShowBoss(43, verdan, verdanIndex) end)
end
-- an item that does not exist in the client
Step("ITEM_DATA_LOAD_RESULT false", function() M.FireEvent("ITEM_DATA_LOAD_RESULT", 253938, false) end)
local unknown = itemRows(bossScroll():GetScrollChild())[4]
Check("missing item shows 'Unknown item #id'", unknown and (unknown.w.Name:GetText() or ""):find("Unknown item", 1, true) ~= nil,
    unknown and unknown.w.Name:GetText())
-- boss row: portrait, level badge, order number
local bossRow
for _, r in ipairs(M.Rows(listScroll():GetScrollChild())) do if rawget(r.w, "boss") == verdan then bossRow = r.w end end
Check("boss row: level badge with the boss level", bossRow and bossRow.Portrait.LevelBadge:IsShown()
    and bossRow.Portrait.LevelBadge.Text:GetText() ~= nil)
Check("boss row: selected look", bossRow and bossRow.selected and bossRow.selectedBar:IsShown())
CheckHoverAll("bosses tab", journal)

---------------------------------------------------------------------------
-- quest list: chain, steps, pick-up pins, markers, faction toggles, states
---------------------------------------------------------------------------
-- a quest with a chain for the player's faction that heads its row (no earlier step in the same dungeon)
local function IsChainHead(id, q)
    for _, stepID in ipairs(ns.W.QuestChain(q)) do
        if stepID == q.id then return true end
        for _, other in ipairs(ns.QUESTS[id]) do if other.id == stepID then return false end end
    end
end
local chainDungeon, chainQuest
for _, id in ipairs(sortedIDs(ns.QUESTS)) do
    for _, q in ipairs(ns.QUESTS[id]) do
        if not chainQuest and q.pre and #q.pre >= 2 and ns.W.QuestState(q) ~= "other" and ns.DUNGEONS[id]
            and IsChainHead(id, q) then
            chainDungeon, chainQuest = id, q
        end
    end
end
Check("data: a quest with a chain exists for the player", chainQuest ~= nil)
local function questRow(q)
    for _, r in ipairs(M.Rows(listScroll():GetScrollChild())) do if rawget(r.w, "quest") == q then return r end end
end
if chainQuest then
    Step("ShowQuest chain quest", function() ns.Journal:ShowQuest(chainDungeon, chainQuest) end)
    local r = questRow(chainQuest)
    Check("chain toggle shown after the level text", r and r.w.ChainToggle:IsShown())
    Step("hover chain toggle", function() M.Enter(r.w.ChainToggle) end)
    Check("chain toggle tooltip 'Quest chain'", GameTooltip:IsShown() and GameTooltip._lines[1] == "Quest chain"
        and GameTooltip._lines[2] == "Click to show the whole quest chain")
    Step("leave chain toggle", function() M.Leave(r.w.ChainToggle) end)
    Step("click chain toggle", function() M.Click(r.w.ChainToggle) end)
    r = questRow(chainQuest)
    local n = #ns.W.QuestChain(chainQuest)
    Check("inline chain expands the row", r and r.height == 48 + 10 + n * 18 + 10, r and r.height)
    M.CheckRows("quest list with an open chain", listScroll():GetScrollChild(), { width = listScroll():GetWidth() })
    local lines = M.Shown(r.w.lines)
    Check("one chain line per step of the whole chain", #lines == n, #lines)
    local marked = true
    for _, line in ipairs(lines) do
        local texture = line.Mark:IsShown() and line.Mark.texture:GetTexture()
        if texture ~= ns.TEX.TICK and texture ~= ns.TEX.CROSS and texture ~= ns.TEX.QUEST_INCOMPLETE then marked = false end
        if (line.Text:GetText() or ""):lower():find("done", 1, true) then marked = false end
    end
    Check("chain steps use tick / cross icons, never the word 'done'", marked)
    local step1 = lines[1]
    Check("chain line text '1. <name>'", step1 and (step1.Text:GetText() or ""):find("^1%. ") ~= nil, step1 and step1.Text:GetText())
    Step("click chain step 1", function() M.Click(step1) end)
    local qs = questScroll()
    local pageText = M.TextOf(qs:GetScrollChild())
    Check("step page: 'Step 1 of n - part of'", pageText:find("Step 1 of " .. n, 1, true) ~= nil, pageText:sub(1, 80))
    Check("step page: Back link", pageText:find("Back to " .. chainQuest.name, 1, true) ~= nil)
    if step1.Pin:IsShown() then
        local before = M.openWorldMapCalls or 0
        Step("click step pick-up pin", function() M.Click(step1.Pin) end)
        if COMBAT then
            Check("pick-up pin in combat: no map change (queued)", (M.openWorldMapCalls or 0) == before)
        else
            Check("pick-up pin opens the world map via C_Map.OpenWorldMap", (M.openWorldMapCalls or 0) == before + 1
                and WorldMapFrame:IsShown())
            Check("quest spot pin on the step's map", WorldMapFrame:GetNumActivePinsByTemplate("ForeverDungeonMapEntrancePinTemplate") > 0)
            Check("dungeon view not covering the spot", not ns.View:IsShown())
            Step("close world map", function() M.UserToggleWorldMap() end)
        end
    end
    Step("ShowQuest chain quest again", function() ns.Journal:ShowQuest(chainDungeon, chainQuest) end)
    local order = headingOrder(qs:GetScrollChild())
    local pageText = M.TextOf(qs:GetScrollChild()):lower()
    Check("quest page never writes 'done'", not pageText:find("done", 1, true), pageText:sub(1, 120))
    Check("chain quest page has 'Quest chain'", table.concat(order, ","):find("Quest chain", 1, true) ~= nil, table.concat(order, ","))
    CheckHoverAll("quests tab", journal)
end

-- reported case: a chain is one row (Ragefire Chasm: Searching for / Returning the Lost Satchel)
Step("ShowQuest Ragefire satchel chain", function() ns.Journal:ShowQuest(389, ns.W.QuestByID(5724)) end)
local satchelRows, returningRows = 0, 0
for _, entry in ipairs(ns.Journal.SortedQuests()) do
    if entry.quest.id == 5722 then satchelRows = satchelRows + 1 end
    if entry.quest.id == 5724 then returningRows = returningRows + 1 end
end
Check("chain is one row headed by its first step", satchelRows == 1 and returningRows == 0, satchelRows .. "/" .. returningRows)
local satchelRow = questRow(ns.W.QuestByID(5722))
Check("a later step selected opens its chain under the head row", satchelRow and satchelRow.w.Chain:IsShown()
    and satchelRow.w.selected)

-- checked Forever quest data (Data/ForeverQuests.lua) beats the DungeonMaster-based one
local crestStart = ns.W.Location(ns.W.QuestByID(95189), "start", 2999)
Check("Crest of Lordaeron: inside the dungeon, five possible spots", crestStart and crestStart.inside ~= nil
    and type(crestStart.spots) == "table" and #crestStart.spots == 5)
local rathmaelStart = ns.W.Location(ns.W.QuestByID(92422), "start", 2999)
Check("The Wrath of Rath'mael starts at Deathguard Kristof", rathmaelStart and rathmaelStart.name == "Deathguard Kristof",
    rathmaelStart and rathmaelStart.name)
local tormentChain = ns.W.QuestChain(ns.W.QuestByID(97288))
Check("Unending Torment: the whole five-step chain", #tormentChain == 5 and tormentChain[1] == 97288, #tormentChain)
Step("ShowQuest Crest of Lordaeron", function() ns.Journal:ShowQuest(2999, ns.W.QuestByID(95189)) end)
local crestPage = M.TextOf(questScroll():GetScrollChild())
Check("quest page lists the crest's possible spots", crestPage:find("It appears in one of these places:", 1, true) ~= nil)

-- every step of every chain in every dungeon has a name (never "Quest 92742")
local unnamed = {}
for _, quests in pairs(ns.QUESTS) do
    for _, quest in ipairs(quests) do
        for _, stepID in ipairs(ns.W.QuestChain(quest)) do
            if ns.W.QuestName(stepID) == ("Quest %d"):format(stepID) then unnamed[#unnamed + 1] = stepID end
        end
    end
end
Check("every quest chain step has a name", #unnamed == 0, table.concat(unnamed, ", "))

-- Forever quests look like the classic ones: the boss drops the starter item, givers on the map
local baronLoot = {}
for _, boss in ipairs(ns.BOSSES[2999]) do
    if boss.name == "The Baron" then for _, itemID in ipairs(boss.loot or {}) do baronLoot[itemID] = true end end
end
Check("The Baron's loot has the Abominable Head that starts Unending Torment", baronLoot[280438] == true)
local trumanSpot
for _, spot in ipairs(ns.QUEST_NPC_ON_ART[2999] or {}) do if spot.name == "Captain Truman" then trumanSpot = spot end end
Check("Captain Truman is a quest spot on the Ruins of Lordaeron map", trumanSpot ~= nil and #trumanSpot.starts == 1)

-- bug report: journal button and /fdmap bug
local bugButton = M.FindChild(_G.ForeverDungeonMapJournal, function(child)
    return child.Icon and child.Icon.GetTexture and child.Icon:GetTexture() == ns.TEX.BUG_REPORT
end)
Check("journal has a bug report button", bugButton ~= nil and bugButton:IsShown())
Step("/fdmap bug", function() SlashCmdList.FOREVERDUNGEONMAP("bug") end)
local bugWindow = _G.ForeverDungeonMapBugReport
local details = bugWindow and bugWindow.Details.EditBox
local bugText = details and details:GetText() or ""
Check("bug report window shows the details", bugWindow and bugWindow:IsShown()
    and bugText:find("---- ForeverDungeonMap bug report ----", 1, true) ~= nil and bugText:find("Journal: ", 1, true) ~= nil,
    bugText:sub(1, 200))
Check("empty description box shows its placeholder", bugWindow.Description.Placeholder:IsShown())
Step("player tries to type into the details", function()
    details:SetText("changed")
    M.FireScript(details, "OnTextChanged", true)
end)
Check("details are read-only", details:GetText() == bugText)
Step("player writes a description", function()
    bugWindow.Description.EditBox:SetText("The map is empty")
    M.FireScript(bugWindow.Description.EditBox, "OnTextChanged", true)
end)
Check("placeholder hides once there is text", not bugWindow.Description.Placeholder:IsShown())
Step("click Copy everything", function() M.Click(bugWindow.CopyButton) end)
Check("copy puts description + details together", details:GetText():find("^The map is empty\n\n%-%-%-%- ForeverDungeonMap") ~= nil,
    details:GetText():sub(1, 80))
Step("close bug report", function() bugWindow:Hide() end)
-- reported: the button did nothing - the window opened hidden behind the journal (same strata)
Step("click Report a bug", function() M.Click(bugButton) end)
Check("Report a bug button opens the window above the journal", bugWindow:IsShown()
    and bugWindow:GetFrameStrata() == "FULLSCREEN_DIALOG" and journal:GetFrameStrata() == "DIALOG",
    tostring(bugWindow:GetFrameStrata()) .. " over " .. tostring(journal:GetFrameStrata()))
Step("close bug report again", function() bugWindow:Hide() end)

-- "In Dungeon" marker
local insideDungeon, insideQuest
for _, id in ipairs(sortedIDs(ns.QUESTS)) do
    for _, q in ipairs(ns.QUESTS[id]) do
        if not insideQuest and ns.W.InDungeon(q) and ns.W.QuestState(q) ~= "other" and ns.DUNGEONS[id] then insideDungeon, insideQuest = id, q end
    end
end
if Check("data: a quest starting inside a dungeon", insideQuest ~= nil) then
    Step("ShowQuest inside quest", function() ns.Journal:ShowQuest(insideDungeon, insideQuest) end)
    local r = questRow(insideQuest)
    Check("'In Dungeon' icon on the row", r and r.w.Inside:IsShown())
    Step("hover In Dungeon", function() M.Enter(r.w.Inside) end)
    Check("'In Dungeon' tooltip", GameTooltip._lines[1] == "In Dungeon")
    Step("leave In Dungeon", function() M.Leave(r.w.Inside) end)
end

-- faction toggles + empty state + count
Step("OpenDungeon(43 quests)", function() ns.Journal:OpenDungeon(43, "quests") end)
local P = ns.Journal:State()
local function questCount() local n = 0 for _, r in ipairs(M.Rows(listScroll():GetScrollChild())) do if rawget(r.w, "quest") then n = n + 1 end end return n end
local hordeCount = questCount()
Check("own faction shown by default, other hidden", P.showHorde == true and P.showAlliance == false)
local facH = M.FindChild(listScroll():GetParent(), function(c) return c.Icon and c.Icon:GetTexture() == ns.TEX.HORDE and c.GetBackdrop end)
local facA = M.FindChild(listScroll():GetParent(), function(c) return c.Icon and c.Icon:GetTexture() == ns.TEX.ALLIANCE and c.GetBackdrop end)
if facA and facH then
    Step("toggle Alliance on", function() M.Click(facA) end)
    Check("Alliance toggle adds quests", questCount() >= hordeCount, questCount())
    Step("toggle both off", function() M.Click(facA); M.Click(facH) end)
    Check("empty state message", questCount() == 0 and M.TextOf(listScroll():GetScrollChild()):find("No quests for this filter", 1, true) ~= nil)
    Step("toggle Horde on", function() M.Click(facH) end)
end
-- quest states: ready to turn in sorts first and shows "Turn in"; done shows the tick
local wcq = ns.QUESTS[43]
local readyQ, doneQ
for _, q in ipairs(wcq) do
    if ns.W.QuestState(q) == "avail" then
        if not readyQ then readyQ = q elseif not doneQ then doneQ = q end
    end
end
if readyQ and doneQ then
    M.questsInLog[readyQ.id], M.questsReady[readyQ.id] = 1, true
    M.questsDone[doneQ.id] = true
    Step("QUEST_LOG_UPDATE states", function() M.FireEvent("QUEST_LOG_UPDATE") end)
    M.Advance(1)
    local rows = M.Rows(listScroll():GetScrollChild())
    Check("ready-to-turn-in quest sorts first", rawget(rows[1].w, "quest") == readyQ)
    Check("ready quest shows the big ? and 'Turn in'", rows[1].w.TurnIn:IsShown())
    local dr = questRow(doneQ)
    Check("completed quest shows the tick", dr and dr.w.Done:IsShown())
    M.questsInLog[readyQ.id], M.questsReady[readyQ.id], M.questsDone[doneQ.id] = nil, nil, nil
end
-- quest page buttons
local q1 = ns.Journal.SortedQuests()[1].quest
Step("ShowQuest WC first", function() ns.Journal:ShowQuest(43, q1) end)
local showBtn = M.FindChild(questScroll():GetScrollChild(), function(c) return c:IsShown() and c.Label and c.Label:GetText() == "Show on Map" end)
local info = ns.QUEST_INFO[q1.id]
if info and info.start and info.start.map and not COMBAT then
    Check("quest page has 'Show on Map'", showBtn ~= nil)
    if showBtn then
        Step("click Show on Map", function() M.Click(showBtn) end)
        Check("Show on Map opens the start zone", WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == info.start.map, WorldMapFrame:GetMapID())
        Check("Show on Map sets a tracked waypoint on the start NPC",
            M.waypoint ~= nil and M.waypoint.tracked and M.waypoint.map == info.start.map, M.waypoint and M.waypoint.map)
        Step("close world map", function() M.UserToggleWorldMap() end)
    end
end
-- quest tooltip (rewards) works
local rewardQ
for _, q in ipairs(wcq) do if (q.rewards or q.choices) and not rewardQ then rewardQ = q end end
if rewardQ then
    local before = #M.report.errors
    P.showAlliance, P.showHorde = true, true
    Step("refresh", function() ns.Journal:Refresh() end)
    local r = questRow(rewardQ)
    Step("hover quest row with rewards", function() M.Enter(r.w) end)
    Check("quest tooltip: no error and shown", #M.report.errors == before and GameTooltip:IsShown() and GameTooltip:NumLines() > 2)
    Step("leave quest row", function() M.Leave(r.w) end)
end

---------------------------------------------------------------------------
-- journal Map tab
---------------------------------------------------------------------------
Step("OpenDungeon(43 map)", function() ns.Journal:OpenDungeon(43, "map") end)
local jm = ns.Journal.map
-- 8 journal bosses + the Deviate Faerie Dragon rare (spawn point from classic-db)
Check("WC map tab: 9 boss pins", jm.numPins == 9, jm.numPins)
local pin = jm.pins[1]
Check("map boss pins have no ring", pin ~= nil and pin.Ring == nil and pin.RingHover == nil)
Check("dungeon icons have no ring", ns.W.CreateRoundIcon(UIParent, 40).Ring == nil)
local framesMatchUnknown = true
for i = 1, jm.numPins do
    local each = jm.pins[i]
    if not each.EliteFrame:IsShown() then framesMatchUnknown = false end
end
Check("every map pin has the elite frame (with or without a portrait)", framesMatchUnknown)
local unknownPin
Step("portrait-less rare boss on a pin", function()
    unknownPin = ns.W.CreatePortrait(UIParent, 40)
    ns.W.SetPortrait(unknownPin, { name = "Nobody", rare = true }, false, 43)
end)
Check("portrait-less rare pin: '?' in a silver frame", unknownPin.Unknown:IsShown()
    and unknownPin.EliteFrame:IsShown() and unknownPin.EliteFrame:IsDesaturated())
if pin then
    Step("hover map pin", function() M.Enter(pin) end)
    Check("map pin tooltip: name, boss i of n, loot", GameTooltip:NumLines() >= 3 and (GameTooltip._lines[2] or ""):find("Boss 1 of", 1, true) ~= nil,
        table.concat(GameTooltip._lines, " | "))
    Step("leave map pin", function() M.Leave(pin) end)
    Step("click map pin", function() M.Click(pin, "LeftButton") end)
    Check("map pin click opens the boss page", P.tab == "bosses" and P.boss == pin.boss)
end
Step("BossHead Show on map", function() ns.Journal:ShowOnMap(verdan) end)
Check("Show on map switches to the Map tab", P.tab == "map" and jm.frame:IsVisible())
Step("right-click journal map", function() M.FireScript(jm.area, "OnMouseUp", "RightButton") end)
Check("right-click on the journal map goes back to Bosses", P.tab == "bosses")
Step("OpenDungeon(36 map)", function() ns.Journal:OpenDungeon(36, "map") end)
Check("Deadmines: level dropdown shows Level 1", jm.floorButton:IsShown() and jm.floorButton.Label:GetText() == "Level 1",
    jm.floorButton.Label:GetText())
Step("open level dropdown", function() M.Click(jm.floorButton) end)
Check("level menu lists both levels", jm.floorMenu:IsShown() and jm.floorMenu.rows[2] and jm.floorMenu.rows[2]:IsShown()
    and jm.floorMenu.rows[2].Label:GetText() == "Level 2")
Step("pick Level 2", function() M.Click(jm.floorMenu.rows[2]) end)
Check("Deadmines floor 2 pins", jm.state.floor == 2 and jm.numPins == 5 and not jm.floorMenu:IsShown(), jm.numPins)
Check("dropdown shows Level 2", jm.floorButton.Label:GetText() == "Level 2")
Step("back to Level 1", function() jm:SetFloor(1) end)

---------------------------------------------------------------------------
-- world map overlay / live view
---------------------------------------------------------------------------
local minimapParent = Minimap:GetParent()
local minimapPoints = Minimap:GetNumPoints()
WorldMapFrame.mapID = 279 -- inside WC the Blizzard map opens on the dungeon's own uiMap
Step("user opens world map (M)", function() M.UserToggleWorldMap() end)
M.Advance(0.5)
local view = _G.ForeverDungeonMapView
Check("dungeon view shown on map open inside WC", view and view:IsVisible())
Check("map open did not change the world map", WorldMapFrame:GetMapID() == 279)
if COMBAT then
    Check("in combat the live view opens without the minimap", ns.Live:IsShown() and not ns.Live:IsBorrowing()
        and Minimap:GetParent() == minimapParent)
else
    Check("live view shown", ns.Live:IsShown())
    Check("minimap moved into live view", Minimap:GetParent() ~= minimapParent)
    Step("enter an area of the dungeon", function()
        M.player.subZone = "Pit of Fangs"
        ns.FLOOR_BY_AREA = { [43] = { ["Pit of Fangs"] = 1 } }
        M.FireEvent("ZONE_CHANGED_INDOORS")
    end)
    local footer = ns.Live.locationLabel and ns.Live.locationLabel:GetText() or ""
    Check("live view footer names the area", footer:find("Pit of Fangs", 1, true) ~= nil, footer)
    Check("no floor number in a one-floor dungeon", footer:find("/", 1, true) == nil, footer)
    Step("leave the area", function()
        M.player.subZone, ns.FLOOR_BY_AREA = nil, nil
        M.FireEvent("ZONE_CHANGED_INDOORS")
    end)
end
local vm = ns.View.map
Check("overlay: 9 boss pins", vm and vm.numPins == 9, vm and vm.numPins)
local function PinsApart(map)
    for i = 1, map.numPins do
        for j = i + 1, map.numPins do
            local _, _, _, ax, ay = map.pins[i]:GetPoint(1)
            local _, _, _, bx, by = map.pins[j]:GetPoint(1)
            local scale = map.pins[i]:GetScale()
            local gap = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) * scale
            if gap < 40 * scale * 0.89 then return false, ("%s / %s: %.1f"):format(map.pins[i].boss.name, map.pins[j].boss.name, gap) end
        end
    end
    return true
end
Check("overlay: no boss pin covers another", PinsApart(vm))
-- header: Bosses and Quests tabs, then the Dungeons button on the right (no menus here)
local headerButtons = M.Descendants(view, function(c)
    return c:IsVisible() and rawget(c, "Underline") ~= nil and c ~= vm.floorButton and c:GetParent():GetFrameStrata() ~= "FULLSCREEN_DIALOG"
end)
local dungeonsButton
for _, button in ipairs(headerButtons) do if button.Label:GetText() == "Dungeons" then dungeonsButton = button end end
Check("overlay header has the Dungeons button", dungeonsButton ~= nil)
local maxRight = 0
for _, t in ipairs(headerButtons) do
    if t ~= dungeonsButton then local l, w = M.RelLeft(view, t); if l then maxRight = math.max(maxRight, l + w) end end
end
Check("overlay tabs stay left of the Dungeons button", #headerButtons == 3 and maxRight <= view:GetWidth() - 136,
    #headerButtons .. " buttons, " .. maxRight .. " / " .. view:GetWidth())
if dungeonsButton then
    Step("click Dungeons", function() M.Click(dungeonsButton) end)
    Check("Dungeons opens the journal's home page", journal:IsShown() and not _G.ForeverDungeonMapJournalBoss:IsVisible())
    Step("close journal", function() journal:Hide() end)
end
Step("click overlay boss pin", function() M.Click(vm.pins[1], "LeftButton") end)
Check("overlay pin opens the journal on the boss", journal:IsShown() and P.boss == vm.pins[1].boss)

Step("View:Open(3065) Hall of Thanes", function() ns.View:Open(3065) end)
local hot = vm.state.floors
-- its art is the client's minimap pieces (Data/Forever.lua); shown once the canvas draws pieces
local thanesFloor = ns.FOREVER and ns.FOREVER.dungeons[3065].floors[1]
Check("Hall of Thanes: Forever minimap floor", ns.FOREVER == nil or (thanesFloor.pieces ~= nil and #hot >= 1 and hot[1].pieces ~= nil))
Check("Hall of Thanes: minimap pieces drawn, 4 boss pins", ns.FOREVER == nil or (vm.pieces and vm.pieces[1]:IsShown()
    and vm.pieces[1]:GetTexture() == thanesFloor.pieces[1][1] and vm.numPins == 4), vm.numPins)
Step("View:Open(2959) City of Dalaran", function() ns.View:Open(2959) end)
local dalaranFloors = vm.state.floors
Check("City of Dalaran: Underbelly and city tile floors", ns.FOREVER == nil or (#dalaranFloors == 2
    and tostring(dalaranFloors[1].base):find("Dalaran2_", 1, true) ~= nil and tostring(dalaranFloors[2].base):find("Dalaran1_", 1, true) ~= nil))
Step("View:Open(2999) Ruins of Lordaeron", function() ns.View:Open(2999) end)
Check("Ruins of Lordaeron: 7 boss pins on its minimap floor", ns.FOREVER == nil or vm.numPins == 7, vm.numPins)
Check("Ruins of Lordaeron: entrance marker", ns.FOREVER == nil or vm.entrance:IsShown())
Step("Ruins of Lordaeron overview floor", function() vm:SetFloor(2) end)
Check("Ruins of Lordaeron overview: no boss pins, no minimap pieces", vm.numPins == 0 and not vm.pieces[1]:IsShown())
Step("View:Open(209) Zul'Farrak", function() ns.View:Open(209) end)
Check("Zul'Farrak: its unnumbered tiles are the map", #vm.state.floors == 1 and vm.state.floors[1].base == "Interface\\WorldMap\\ZulFarrak\\ZulFarrak",
    vm.state.floors[1] and vm.state.floors[1].base)
Step("View:Open(43) Wailing Caverns for the rare", function() ns.View:Open(43) end)
local dragonPin
for i = 1, vm.numPins do if vm.pins[i].boss.name == "Deviate Faerie Dragon" then dragonPin = vm.pins[i] end end
Check("Deviate Faerie Dragon: on the map with its own portrait", dragonPin ~= nil and not dragonPin.Unknown:IsShown()
    and ns.W.BossDisplay(dragonPin.boss) == ns.CREATURE_DISPLAY[5912])
Step("View:Open(47) Razorfen Kraul", function() ns.View:Open(47) end)
Check("Razorfen Kraul: all 9 bosses on the map", vm.numPins == 9, vm.numPins)
Check("Razorfen Kraul: quest givers inside (Willix)", (vm.numQuestSpots or 0) >= 1, vm.numQuestSpots)
Check("Razorfen Kraul: entrance marker", vm.entrance:IsShown())
local questSpot = vm.questSpots and vm.questSpots[1]
if questSpot then
    Step("hover quest spot", function() M.Enter(questSpot) end)
    Check("quest spot tooltip: NPC and quest", GameTooltip:IsShown() and GameTooltip:NumLines() >= 3, table.concat(GameTooltip._lines, " | "))
    Step("leave quest spot", function() M.Leave(questSpot) end)
end
Step("View:Open(189) Scarlet Monastery", function() ns.View:Open(189) end)
Check("Scarlet Monastery: the Graveyard entrance on floor 1", vm.entrance:IsShown())
for _, id in ipairs(sortedIDs(ns.DUNGEONS)) do Step("View:Open " .. id, function() ns.View:Open(id) end) end
Step("View:Open(43) again", function() ns.View:Open(43) end)
Step("wheel zoom", function() M.FireScript(vm.area, "OnMouseWheel", 1) end)
Step("wheel zoom out", function() M.FireScript(vm.area, "OnMouseWheel", -1) end)

local openCalls = M.openWorldMapCalls or 0
Step("right-click overlay (GoUp)", function() M.FireScript(vm.area, "OnMouseUp", "RightButton") end)
Check("view closed after GoUp", not ns.View:IsShown())
if COMBAT then
    Check("GoUp in combat: world map change waits", WorldMapFrame:GetMapID() == 279 and (M.openWorldMapCalls or 0) == openCalls)
else
    Check("GoUp: world map on the entrance zone via C_Map.OpenWorldMap", WorldMapFrame:GetMapID() == 1413 and (M.openWorldMapCalls or 0) == openCalls + 1)
    M.Advance(0.1)
    Check("the live view stays next to the map after GoUp", ns.Live:IsShown() and ns.Live:IsBorrowing())
end

-- after going out: "Dungeons", the dungeon's map and its quests after the last nav bar crumb
local function NavChip(text)
    return M.FindChild(WorldMapFrame, function(c) return c:IsVisible() and c.Label and c.Label:GetText() == text end)
end
local dungeonsChip, mapChip = NavChip("Dungeons"), NavChip("Wailing Caverns")
Check("nav bar: Dungeons and the dungeon's map after going out", dungeonsChip ~= nil and mapChip ~= nil)
if dungeonsChip and mapChip then
    local _, anchor = dungeonsChip:GetPoint(1)
    Check("nav bar chips start after the last crumb", anchor == WorldMapFrame.NavBar.navList[3])
    Check("nav bar: the dungeon's quests", NavChip("Quests (9)") ~= nil)
    Step("click the dungeon's map chip", function() M.Click(mapChip) end)
    Check("map chip reopens the dungeon view", ns.View:IsShown() and ns.View.map.state.instanceID == 43)
    Check("nav bar chips hidden while the view is shown", not mapChip:IsVisible() and not dungeonsChip:IsVisible())
    Step("right-click overlay (GoUp) again", function() M.FireScript(vm.area, "OnMouseUp", "RightButton") end)
end

if not COMBAT then
    Step("Live:Show", function() ns.Live:Show() end)
    Check("Live:Show works", ns.Live:IsShown())
    Step("Live:Hide", function() ns.Live:Hide() end)
    Check("Live:Hide gives the minimap back", Minimap:GetParent() == minimapParent and Minimap:GetNumPoints() == minimapPoints)
end

---------------------------------------------------------------------------
-- entrance pins
---------------------------------------------------------------------------
local TEMPLATE = "ForeverDungeonMapEntrancePinTemplate"
for _, mapID in ipairs({ 1413, 1414 }) do
    Step("user navigates map to " .. mapID, function() M.Dispatch(function() WorldMapFrame:SetMapID(mapID) end) end)
    local n = WorldMapFrame:GetNumActivePinsByTemplate(TEMPLATE)
    Check(("entrance pins on map %d"):format(mapID), n > 0, n .. " pins")
end
local epin = WorldMapFrame:EnumeratePinsByTemplate(TEMPLATE)()
if epin then
    Check("entrance pin has an icon", epin.Icon and (epin.Icon:GetTexture() or epin.Icon:GetAtlas()) ~= nil)
    Step("hover entrance pin", function() M.Enter(epin) end)
    Check("entrance pin tooltip", GameTooltip:IsShown() and GameTooltip:NumLines() >= 2)
    Step("leave entrance pin", function() M.Leave(epin) end)
    Step("left-click entrance pin", function() M.FireScript(epin, "OnMouseUp", "LeftButton") end)
    Check("entrance click opens the dungeon view", ns.View:IsShown())
    Step("close view", function() ns.View:Close() end)
    M.mod.shift = true
    Step("shift-click entrance pin", function() M.FireScript(epin, "OnMouseUp", "LeftButton") end)
    M.mod.shift = false
    Check("shift-click entrance opens the journal", journal:IsShown() and P.instanceID == epin.instanceID)
    Step("right-click entrance pin", function() M.FireScript(epin, "OnMouseUp", "RightButton") end)
    if not COMBAT then Check("right-click goes one map up", WorldMapFrame:GetMapID() == 947) end
end

---------------------------------------------------------------------------
-- boss kill
---------------------------------------------------------------------------
Step("ENCOUNTER_END Verdan", function() M.FireEvent("ENCOUNTER_END", verdan.encounter, verdan.name, 1, 5, 1) end)
Check("Verdan marked killed", ns.IsKilled(43, verdan.name))
Step("ShowBoss Verdan after kill", function() ns.Journal:ShowBoss(43, verdan, verdanIndex) end)
Check("journal shows Defeated", M.TextOf(bossScroll():GetScrollChild()):find("Defeated", 1, true) ~= nil)
for _, r in ipairs(M.Rows(listScroll():GetScrollChild())) do
    if rawget(r.w, "boss") == verdan then Check("boss row: red X on the portrait", r.w.Portrait.Dead:IsShown()) end
end
local kresh = wc[3]
Step("BOSS_KILL Kresh", function() M.FireEvent("BOSS_KILL", kresh.encounter, kresh.name) end)
Check("BOSS_KILL marks the boss", ns.IsKilled(43, kresh.name))
Step("target a living rare", function()
    M.target = { guid = "Creature-0-1-43-1-5912-0000000000", dead = false }
    M.FireEvent("PLAYER_TARGET_CHANGED")
end)
Check("a living target is not a kill", not ns.IsKilled(43, "Deviate Faerie Dragon"))
Step("target the rare's corpse", function()
    M.target = { guid = "Creature-0-1-43-1-5912-0000000000", dead = true }
    M.FireEvent("PLAYER_TARGET_CHANGED")
    M.target = nil
end)
Check("rare marked killed from its corpse", ns.IsKilled(43, "Deviate Faerie Dragon"))
Check("the combat log is never registered (forbidden on this client)", not (function()
    for _, entry in ipairs(M.report and M.report.protected or {}) do
        if tostring(entry.func):find("COMBAT_LOG", 1, true) then return true end
    end
end)())

---------------------------------------------------------------------------
-- slash command / compartment / leaving the dungeon / end of combat
---------------------------------------------------------------------------
Step("close world map", function() if WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
Step("/fdmap journal", function() SlashCmdList.FOREVERDUNGEONMAP("journal") end)
Step("/fdmap journal (toggle)", function() SlashCmdList.FOREVERDUNGEONMAP("journal") end)
Step("/fdmap", function() SlashCmdList.FOREVERDUNGEONMAP("") end)
if COMBAT then
    Check("/fdmap in combat opens the journal Map tab", journal:IsShown() and P.tab == "map" and not WorldMapFrame:IsShown())
else
    Check("/fdmap opens the world map with the dungeon view", WorldMapFrame:IsShown() and ns.View:IsShown())
end
Step("/fdmap resetkills", function() SlashCmdList.FOREVERDUNGEONMAP("resetkills") end)
Step("compartment enter", function() ForeverDungeonMap_OnAddonCompartmentEnter(nil, UIParent) end)
Step("compartment leave", function() ForeverDungeonMap_OnAddonCompartmentLeave() end)
Step("compartment click", function() ForeverDungeonMap_OnAddonCompartmentClick(nil, "LeftButton") end)

if COMBAT then
    -- combat ends: queued work runs, minimap still home
    M.combat = false
    Step("PLAYER_REGEN_ENABLED", function() M.FireEvent("PLAYER_REGEN_ENABLED") end)
    M.Advance(1)
    if WorldMapFrame:IsShown() and ns.View:IsShown() then
        Check("after combat: live view shown with the map", ns.Live:IsShown())
    end
    Step("close world map after combat", function() if WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
    M.Advance(0.1)
    Check("after combat: minimap back home", Minimap:GetParent() == minimapParent)
    M.combat = true
end

Step("close world map", function() if WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
M.player.inInstance = false
Step("ZONE_CHANGED_NEW_AREA (left)", function() M.FireEvent("ZONE_CHANGED_NEW_AREA") end)
Check("left the instance", ns.instanceID == nil)
Step("PLAYER_LEAVING_WORLD", function() M.FireEvent("PLAYER_LEAVING_WORLD") end)
M.Advance(5)
Check("no WorldMapFrame:SetMapID from addon code", (M.mapStateTainted or 0) == 0,
    (M.mapStateTainted or 0) .. " tainted WorldMapFrame:SetMapID calls")
