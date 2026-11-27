-- ForeverDungeonMap - creature display IDs of bosses no shipped table knows (the new WoW Forever
-- bosses; no public source lists them): a model frame nobody sees loads each boss by its creature
-- ID and reads the display ID the round portrait needs. Learned IDs are kept in
-- ForeverDungeonMapDB.learnedDisplays and go into /fdmap export, so a release can ship them.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

local BossModels = {}
ns.BossModels = BossModels

-- a model frame must be shown to load anything: 1x1 and fully transparent
local PROBE_SIZE, PROBE_ALPHA = 1, 0
-- a creature the client has not seen yet comes from the server: look again a few times
local RETRY_DELAY, MAX_TRIES = 0.5, 8
-- a creature not found is asked for again after this long (the server may know it by then)
local ASK_AGAIN_SECONDS = 60

-- the model frame loading the creature asked for now (a fresh one each time: a used one keeps
-- answering with the creature it showed before, which gave five bosses one and the same model)
local probe
-- learned IDs of older versions came from such a reused frame: they are dropped once
local LEARNED_VERSION = 2
-- queue of creature IDs, and GetTime() each one was last asked for
local queue, askedAt = {}, {}
local busy, learnedSomething = false, false

local function Learned()
    if type(ns.db) ~= "table" then return {} end
    if ns.db.learnedDisplaysVersion ~= LEARNED_VERSION then
        ns.db.learnedDisplays, ns.db.learnedDisplaysVersion = {}, LEARNED_VERSION
    end
    ns.db.learnedDisplays = ns.db.learnedDisplays or {}
    return ns.db.learnedDisplays
end

-- Display ID learned in play for a creature, or nil.
function BossModels.Display(npcID)
    return npcID and Learned()[npcID] or nil
end

local function NewProbe()
    local model = CreateFrame("PlayerModel", nil, UIParent)
    model:SetSize(PROBE_SIZE, PROBE_SIZE)
    model:SetPoint("BOTTOMLEFT")
    model:SetAlpha(PROBE_ALPHA)
    model:EnableMouse(false)
    return model
end

-- The model API this client offers, or nil (then nothing is learned).
local function ModelApiPresent(model)
    return type(model.SetCreature) == "function" and type(model.GetDisplayInfo) == "function"
end

-- Whether this client's model frames can load a creature (looked at once, on a frame of its own).
local apiPresent
local function ApiPresent()
    if apiPresent == nil then apiPresent = ModelApiPresent(NewProbe()) end
    return apiPresent
end

local function ReadDisplay(model)
    local ok, display = pcall(model.GetDisplayInfo, model)
    return ok and type(display) == "number" and display > 0 and display or nil
end

-- Open windows repaint once the queue is done, so new portraits show.
local function RepaintWindows()
    if ns.Journal and ns.Journal:IsShown() then ns.Journal:Refresh(true) end
    if ns.View and ns.View:IsShown() then ns.View:Refresh() end
end

local NextInQueue

-- Display IDs that are no boss's own: the stand-in model the client shows for a creature it has
-- not loaded yet. 142144 came back for five different Drowned City bosses in play.
local placeholders = { [142144] = true }

-- Another creature already learned with this display ID, or nil.
local function OwnerOf(display, npcID)
    for otherID, known in pairs(Learned()) do
        if otherID ~= npcID and known == display then return otherID end
    end
end

-- Keep a display ID; one two different bosses came back with is a stand-in: kept for neither.
local function Keep(npcID, display)
    local owner = OwnerOf(display, npcID)
    if owner then
        placeholders[display] = true
        Learned()[owner] = nil
    end
    if placeholders[display] then return end
    Learned()[npcID] = display
    learnedSomething = true
end

local function Finish(npcID, display)
    if display then Keep(npcID, display) end
    busy = false
    NextInQueue()
end

-- Look for the display ID until it is there or the tries run out.
local function Await(npcID, tries)
    local display = ReadDisplay(probe)
    if display or tries >= MAX_TRIES then return Finish(npcID, display) end
    C_Timer.After(RETRY_DELAY, function()
        pcall(probe.SetCreature, probe, npcID)
        Await(npcID, tries + 1)
    end)
end

function NextInQueue()
    if busy then return end
    local npcID = table.remove(queue, 1)
    if not npcID then
        if learnedSomething then RepaintWindows() end
        learnedSomething = false
        return
    end
    busy = true
    if probe then probe:Hide() end
    probe = NewProbe()
    pcall(probe.SetCreature, probe, npcID)
    Await(npcID, 1)
end

-- Put the boss's creature on a model frame (its display ID when known); false when it cannot.
function BossModels.ShowCreature(model, boss)
    if not (boss.npcID or boss.display) or not ModelApiPresent(model) then
        model:Hide()
        return false
    end
    model:Show()
    local display = ns.W.BossDisplay(boss)
    local ok = display and model.SetDisplayInfo and pcall(model.SetDisplayInfo, model, display)
    if not ok and boss.npcID then ok = pcall(model.SetCreature, model, boss.npcID) end
    if not ok then model:Hide() end
    return ok and true or false
end

-- Ask for a boss's display ID; kept once found, asked for again a minute after a miss.
function BossModels.Request(npcID)
    if type(npcID) ~= "number" or BossModels.Display(npcID) then return end
    if askedAt[npcID] and GetTime() - askedAt[npcID] < ASK_AGAIN_SECONDS then return end
    askedAt[npcID] = GetTime()
    if not ApiPresent() then return end
    table.insert(queue, npcID)
    NextInQueue()
end
