-- recap_scenario.lua - the dungeon recap (Recap.lua): what a run records, when it ends, when it
-- goes on, and the recap window.
-- Run: python -I tools/harness/run.py tools/harness/recap_scenario.lua   (and with --combat)
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step

local WAILING_CAVERNS, SHADOWFANG_KEEP = 43, 33
local START_EXPERIENCE, EXPERIENCE_BAR, START_MONEY = 1000, 5000, 12345
local LINEN_CLOTH, OLD_SWORD, NEW_SWORD = 2589, 2000, 3000
local MAIN_HAND_SLOT = 16
-- the recap's own limits (Recap.lua)
local RESUME_SECONDS, MAX_RUNS = 600, 20

-- the mock's clock drives time() too, so pauses can be measured
time = function() return 1700000000 + math.floor(M.now) end

local function Runs() return ns.Character().runs end

-- player actions

local function EnterDungeon(instanceID, name)
    M.player.inInstance, M.player.instanceID, M.player.instanceName = true, instanceID, name
    Step("enter " .. name, function() M.FireEvent("PLAYER_ENTERING_WORLD", false, false) end)
end
local function LeaveDungeon()
    M.player.inInstance = false
    Step("leave the dungeon", function() M.FireEvent("PLAYER_ENTERING_WORLD", false, false) end)
end
local function GainExperience(amount)
    M.player.xp = M.player.xp + amount
    Step("gain " .. amount .. " experience", function() M.FireEvent("PLAYER_XP_UPDATE", "player") end)
end
local function ChangeMoney(amount)
    M.player.money = M.player.money + amount
    Step("money " .. amount, function() M.FireEvent("PLAYER_MONEY") end)
end
local function BagsChanged(label)
    Step(label, function() M.FireEvent("BAG_UPDATE_DELAYED") end)
end
local function CloseRecap()
    Step("close the recap", function() _G.ForeverDungeonMapRecap:Hide() end)
end

-- every visible text of a frame and the frames inside it
local function CollectTexts(frame, texts)
    for _, region in ipairs(frame._regions or {}) do
        if region.GetText and region:IsVisible() and region:GetText() then texts[#texts + 1] = region:GetText() end
    end
    for _, child in ipairs(frame._children or {}) do
        if child:IsVisible() then CollectTexts(child, texts) end
    end
    return texts
end

-- the window's texts, to see what it shows
local function PageTexts()
    return table.concat(CollectTexts(_G.ForeverDungeonMapRecap, {}), " | ")
end
local function PageShows(text) return PageTexts():find(text, 1, true) ~= nil end

M.player.xp, M.player.xpMax, M.player.money = START_EXPERIENCE, EXPERIENCE_BAR, START_MONEY
M.bags[0][1] = { itemID = 6948, stackCount = 1 }
M.equipped[MAIN_HAND_SLOT] = OLD_SWORD

Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(1)
if M.combat then
    M.combat = false
    Step("PLAYER_REGEN_ENABLED", function() M.FireEvent("PLAYER_REGEN_ENABLED") end)
end

-- 1. a run records what happens inside
local run = ns.Recap.Current()
Check("1: logging in inside a dungeon starts a run", run ~= nil and run.instanceID == WAILING_CAVERNS and run.name == "Wailing Caverns"
    and Runs()[1] == run, run and run.name)
GainExperience(400)
Check("1: experience is counted", run.xp == 400, run.xp)
M.player.level, M.player.xp, M.player.xpMax = M.player.level + 1, 100, 5500
Step("level up", function() M.FireEvent("PLAYER_XP_UPDATE", "player") end)
Check("1: a level up counts the rest of the old bar and the new one", run.xp == 400 + (EXPERIENCE_BAR - 1400) + 100, run.xp)
Check("1: the new level is remembered", run.endLevel == run.startLevel + 1, run.startLevel .. " > " .. run.endLevel)
ChangeMoney(250)
ChangeMoney(-100)
Check("1: money gained counts, money spent does not", run.money == 250, run.money)
M.bags[0][2] = { itemID = LINEN_CLOTH, stackCount = 3 }
BagsChanged("loot three linen cloth")
M.bags[0][2].stackCount = 5
BagsChanged("loot two more")
Check("1: looted items are counted", run.items[LINEN_CLOTH] == 5, run.items[LINEN_CLOTH])
M.bags[0][3] = { itemID = NEW_SWORD, stackCount = 1 }
BagsChanged("loot a sword")
M.bags[0][3], M.equipped[MAIN_HAND_SLOT] = { itemID = OLD_SWORD, stackCount = 1 }, NEW_SWORD
BagsChanged("put the new sword on")
Check("1: the old weapon dropping into the bags is not loot", run.items[NEW_SWORD] == 1 and run.items[OLD_SWORD] == nil,
    tostring(run.items[OLD_SWORD]))
local boss, quest = ns.BOSSES[WAILING_CAVERNS][1], ns.QUESTS[WAILING_CAVERNS][1]
Step("defeat " .. boss.name, function() M.FireEvent("ENCOUNTER_END", boss.encounter or 0, boss.name, 1, 5, 1) end)
Step("turn in a quest", function() M.FireEvent("QUEST_TURNED_IN", quest.id, 500, 0) end)
Step("die", function() M.FireEvent("PLAYER_DEAD") end)
Check("1: the boss's kill time is kept", run.killTimes and run.killTimes[boss.name] ~= nil, run.killTimes and tostring(run.killTimes[boss.name]))
M.party = { { name = "Healbot", class = "PRIEST" } }
Step("a priest joins", function() M.FireEvent("GROUP_ROSTER_UPDATE") end)
Check("1: the group is remembered", run.group and run.group.Healbot == "PRIEST")
M.party = {}
Check("1: boss, quest and death are recorded", run.bosses[1] == boss.name and run.quests[1] == quest.id and run.deaths == 1,
    ("%s %s %s"):format(tostring(run.bosses[1]), tostring(run.quests[1]), tostring(run.deaths)))

-- 2. the recap while the run is going on (journal home > Recap)
Step("Journal:ShowHome", function() ns.Journal:ShowHome() end)
local recapButton = M.FindChild(_G.ForeverDungeonMapJournal, function(child)
    return child:IsVisible() and child.Label and child.Label:GetText() == "Recap"
end)
Check("2: the journal's home page has a Recap button", recapButton ~= nil)
M.Advance(125)
if recapButton then M.Click(recapButton) end
Check("2: the button opens the recap window", ns.Recap.IsShown())
Check("2: the window shows the run in progress", PageShows("Wailing Caverns") and PageShows("In progress") and PageShows("2:0"), PageTexts())
Check("2: it lists the boss, the quest and the loot count", PageShows(boss.name) and PageShows(quest.name) and PageShows("x5"), PageTexts())
CloseRecap()
Step("close the journal", function() _G.ForeverDungeonMapJournal:Hide() end)

-- 3. leaving alive ends the run and shows the recap
LeaveDungeon()
Check("3: the run is over", ns.Recap.Current() == nil and Runs()[1] == run and not run.open, tostring(run.open))
Check("3: only the time inside counts", run.seconds >= 125 and run.seconds < 130, run.seconds)
Check("3: the recap opens", ns.Recap.IsShown() and not PageShows("In progress"), PageTexts())
CloseRecap()
M.Advance(300)
Check("3: time outside is not part of the run", run.seconds < 130, run.seconds)

-- 4. walking back in alive is a new run; one in which nothing happened is not kept
EnterDungeon(WAILING_CAVERNS, "Wailing Caverns")
Check("4: a new run", ns.Recap.Current() ~= run and #Runs() == 2, #Runs())
LeaveDungeon()
Check("4: an empty run is dropped, no recap for it", #Runs() == 1 and Runs()[1] == run and not ns.Recap.IsShown(), #Runs())

-- 5. a wipe: out as a ghost, back in, the same run goes on
EnterDungeon(SHADOWFANG_KEEP, "Shadowfang Keep")
local second = ns.Recap.Current()
GainExperience(200)
M.Advance(60)
M.player.ghost = true
LeaveDungeon()
Check("5: leaving as a ghost shows no recap and keeps the run open", not ns.Recap.IsShown() and second.open == true and #Runs() == 2)
M.Advance(120)
M.player.ghost = false
EnterDungeon(SHADOWFANG_KEEP, "Shadowfang Keep")
Check("5: back inside: the same run goes on", ns.Recap.Current() == second and #Runs() == 2, #Runs())
GainExperience(50)
Check("5: with what was gained before", second.xp == 250, second.xp)
Check("5: the run back is not counted as time inside", second.seconds == 60, second.seconds)

-- 6. a ghost who stays away too long gets a new run
M.player.ghost = true
LeaveDungeon()
M.Advance(RESUME_SECONDS + 60)
M.player.ghost = false
EnterDungeon(SHADOWFANG_KEEP, "Shadowfang Keep")
Check("6: too late: a new run, the old one is closed", ns.Recap.Current() ~= second and not second.open and #Runs() == 3, #Runs())

-- 7. /reload inside: the run goes on in the new session
local third = ns.Recap.Current()
GainExperience(70)
M.Advance(30)
Step("PLAYER_LOGOUT (/reload)", function() M.FireEvent("PLAYER_LOGOUT") end)
Check("7: the run is saved paused", ns.Recap.Current() == nil and third.open == true and third.pausedAt ~= nil)
-- a new session knows no instance yet
ns.instanceID = nil
Step("PLAYER_ENTERING_WORLD after the reload", function() M.FireEvent("PLAYER_ENTERING_WORLD", false, true) end)
Check("7: after the reload the same run goes on", ns.Recap.Current() == third and #Runs() == 3, #Runs())

-- 8. the recap can be switched off
Step("option recapPopup = false", function() ns.Settings.Set("recapPopup", false) end)
LeaveDungeon()
Check("8: no recap window with the option off, the run is still kept", not ns.Recap.IsShown() and Runs()[1] == third and not third.open)
Step("option recapPopup = true", function() ns.Settings.Set("recapPopup", true) end)

-- 9. the window steps through the runs
Step("/fdmap recap", function() SlashCmdList.FOREVERDUNGEONMAP("recap") end)
Check("9: /fdmap recap opens the newest run", ns.Recap.IsShown() and PageShows("Shadowfang Keep") and PageShows("Run 1 of 3"), PageTexts())
local function Navigation(text)
    return M.FindChild(_G.ForeverDungeonMapRecap, function(child) return child.Label and child.Label:GetText() == text end)
end
Step("Older", function() M.Click(Navigation("Older")) end)
Step("Older", function() M.Click(Navigation("Older")) end)
Check("9: Older reaches the first run", PageShows("Wailing Caverns") and PageShows("Run 3 of 3") and PageShows("x5"), PageTexts())
Step("Newer", function() M.Click(Navigation("Newer")) end)
Check("9: Newer goes back", PageShows("Run 2 of 3"), PageTexts())

-- 9b. the list on the left: one row per run, a click shows that run in full
local function RunRows()
    local rows = {}
    M.FindChild(_G.ForeverDungeonMapRecap, function(child)
        if child.index and child.Sub and child:IsVisible() then rows[#rows + 1] = child end
        return false
    end)
    table.sort(rows, function(first, second) return first.index < second.index end)
    return rows
end
local rows = RunRows()
Check("9b: the list has a row per run", #rows == 3, #rows)
if rows[3] then M.Click(rows[3]) end
Check("9b: a click on the oldest row shows it", PageShows("Run 3 of 3") and PageShows("Wailing Caverns") and PageShows("Healbot"), PageTexts())
Check("9b: the defeated boss shows when it fell", PageShows(boss.name .. "  ·  "), PageTexts())
CloseRecap()

-- 10. only the newest runs are kept
for index = 1, MAX_RUNS + 3 do
    EnterDungeon(WAILING_CAVERNS, "Wailing Caverns")
    GainExperience(10)
    LeaveDungeon()
end
Check("10: " .. MAX_RUNS .. " runs are kept", #Runs() == MAX_RUNS, #Runs())
CloseRecap()

-- 11. runs belong to the character
M.player.name = "Otherplayer"
Step("/fdmap recap on another character", function() SlashCmdList.FOREVERDUNGEONMAP("recap") end)
Check("11: another character has no runs", #Runs() == 0 and PageShows("No dungeon run recorded yet"), PageTexts())
