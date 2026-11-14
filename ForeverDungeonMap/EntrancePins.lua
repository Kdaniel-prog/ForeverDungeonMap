-- ForeverDungeonMap - pins on zone and continent maps:
-- dungeon entrances (left-click: the dungeon's map, shift-click: journal, right-click: one map up)
-- and one highlighted spot (a quest giver picked in the journal).
-- The taint guards, tooltip/click wiring and the provider come from PinBase.lua.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local W, C, TEX = ns.W, ns.C, ns.TEX

local TEMPLATE = "ForeverDungeonMapEntrancePinTemplate"
-- pin size while the map zooms, relative to the template size
local PIN_SCALE_MIN, PIN_SCALE_MAX = 1.0, 1.25
local KIND_ENTRANCE, KIND_SPOT = "entrance", "quest"

local highlight
-- The spot { map, x, y, title, text } to mark on its zone map.
function ns.SetHighlight(spot) highlight = spot end

-- Mixin used by Pins.xml (must be global and defined before the XML loads).
ForeverDungeonMapEntrancePinMixin = ns.PinBase.CreatePinMixin()
local Pin = ForeverDungeonMapEntrancePinMixin

function Pin:OnLoad()
    W.MarkOwned(self)
    self:ApplyScalingLimits(PIN_SCALE_MIN, PIN_SCALE_MAX)
    if not self.iconMasked then
        self.iconMasked = true
        W.Mask(self, self.Icon)
    end
end

-- kind "entrance": (instanceID, dungeon, x, y); kind "quest": (spot, x, y)
function Pin:OnAcquired(kind, first, second, x, y)
    self.kind = kind
    if kind == KIND_SPOT then
        self.spot = first
        x, y = second, x
        self.Icon:SetTexture(TEX.QUEST_AVAILABLE)
        self.Icon:SetTexCoord(unpack(TEX.FULL_COORDS))
        self.Glow:Show()
    else
        self.instanceID, self.dungeon = first, second
        self.Glow:Hide()
        W.SetDungeonIcon(self, self.instanceID)
    end
    self:SetPosition(x, y)
end

local function AddColoredLine(tooltip, text, color)
    tooltip:AddLine(text, color[1], color[2], color[3])
end

-- Name, level range, boss and quest counts, WoW Forever tag, click hints.
local function FillDungeonTooltip(tooltip, instanceID, dungeon)
    tooltip:SetText(dungeon.name, C.GOLD[1], C.GOLD[2], C.GOLD[3])
    if dungeon.min then tooltip:AddLine(("Level %d-%d"):format(dungeon.min, dungeon.max), ns.RangeColor(dungeon.min, dungeon.max)) end
    local counts = ("%d bosses · %d quests"):format(#(ns.BOSSES[instanceID] or {}), #(ns.QUESTS[instanceID] or {}))
    AddColoredLine(tooltip, counts, C.MUTED)
    if dungeon.forever then AddColoredLine(tooltip, "WoW Forever", C.FOREVER) end
    AddColoredLine(tooltip, "Left-click: open the dungeon map", C.HINT)
    AddColoredLine(tooltip, "Shift-click: Dungeon Journal", C.HINT)
end

local function FillSpotTooltip(tooltip, spot)
    tooltip:SetText(spot.title or "", C.GOLD[1], C.GOLD[2], C.GOLD[3])
    if spot.text then AddColoredLine(tooltip, spot.text, C.WHITE) end
    AddColoredLine(tooltip, "Click: hide", C.HINT)
end

function Pin:FillTooltip(tooltip)
    if self.kind == KIND_SPOT then
        FillSpotTooltip(tooltip, self.spot)
    else
        FillDungeonTooltip(tooltip, self.instanceID, self.dungeon)
    end
end

-- Spot: hide it. Entrance: the dungeon's map, or its journal page with Shift.
function Pin:OnPinClick()
    if self.kind == KIND_SPOT then
        highlight = nil
        ns.RefreshPins()
    elseif IsShiftKeyDown() then
        ns.Journal:OpenDungeon(self.instanceID)
    else
        ns.View:Open(self.instanceID, self.dungeon.name)
    end
end

-- Where a dungeon's entrance pin goes on map `mapID` (0..1), or nil.
local function EntranceOnMap(dungeon, mapID)
    local entrance = ns.GetEntrance(dungeon)
    if entrance and entrance.map == mapID then return ns.Normalized(entrance) end
    if dungeon.cont == mapID and dungeon.cx then return ns.Normalized({ x = dungeon.cx, y = dungeon.cy }) end
end

local function BuildPins(map, mapID)
    for instanceID, dungeon in pairs(ns.DUNGEONS) do
        local x, y = EntranceOnMap(dungeon, mapID)
        if x then map:AcquirePin(TEMPLATE, KIND_ENTRANCE, instanceID, dungeon, x, y) end
    end
    if highlight and highlight.map == mapID then
        local x, y = ns.Normalized(highlight)
        map:AcquirePin(TEMPLATE, KIND_SPOT, highlight, x, y)
    end
end

local provider = ns.PinBase.CreateProvider(TEMPLATE, BuildPins)

function ns.RefreshPins()
    provider:Refresh()
end

-- Put the pins on the world map (called again once Blizzard_WorldMap has loaded).
function ns.SetupPins()
    provider:Attach()
end

ns.OnLoad(function() ns.SetupPins() end)
