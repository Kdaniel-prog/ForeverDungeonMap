-- ForeverDungeonMap - shared base of our pins on Blizzard's world map canvas (zone and continent
-- maps): the taint guards every pin needs, tooltip / click / scaling pieces and the data
-- provider skeleton. A pin kind (EntrancePins.lua, QuestPins.lua) only adds its icon, tooltip
-- text and left-click.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

local PinBase = {}
ns.PinBase = PinBase

local TOOLTIP_ANCHOR = "ANCHOR_RIGHT"

-- Methods every pin mixin gets. The canvas calls the first three on its pins; they are only
-- allowed from Blizzard code, and on an addon pin they raise the "blocked from an action only
-- available to the Blizzard UI" popup. Our pins handle their own clicks, so they do nothing.
local PinGuards = {}
function PinGuards:SetPassThroughButtons() end
function PinGuards:SetPropagateMouseClicks() end
function PinGuards:CheckMouseButtonPassthrough() end

-- Blizzard's gamepad map cursor reads pin centers outside secure code and skips pins without
-- one, so our pins never taint it (Questie does the same on this client).
function PinGuards:GetCenter() return nil end

local PinMixin = {}

-- Pin size while the map zooms: from minimumScale to maximumScale of the template size.
function PinMixin:ApplyScalingLimits(minimumScale, maximumScale)
    if self.SetScalingLimits then self:SetScalingLimits(1, minimumScale, maximumScale) end
end

-- GameTooltip at the pin, filled by the kind's FillTooltip(tooltip).
function PinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, TOOLTIP_ANCHOR)
    self:FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

-- Right-click goes one map up (the pin keeps the click, so the map would not get it);
-- every other click is the kind's OnPinClick(button).
function PinMixin:OnMouseUp(button)
    if button == "RightButton" then
        ns.ShowParentMap(self:GetMap())
    elseif self.OnPinClick then
        self:OnPinClick(button)
    end
end

-- Kinds fill these in.
function PinMixin:FillTooltip(tooltip) end

-- A new pin mixin: Blizzard's MapCanvasPinMixin, the taint guards and the shared pieces.
-- The guards come last so nothing can put the forbidden calls back.
function PinBase.CreatePinMixin()
    return CreateFromMixins(MapCanvasPinMixin or {}, PinMixin, PinGuards)
end

local ProviderMixin = {}

function ProviderMixin:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(self.template)
end

-- Rebuild: buildPins(map, mapID) acquires the pins of the shown map.
function ProviderMixin:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if mapID then self.buildPins(map, mapID) end
end

function ProviderMixin:OnMapChanged()
    self:RefreshAllData()
end

-- Put the provider on the world map (once; false while Blizzard_WorldMap is not loaded).
function ProviderMixin:Attach()
    if self.attached then return true end
    if not WorldMapFrame then return false end
    self.attached = true
    WorldMapFrame:AddDataProvider(self)
    return true
end

-- Rebuild now if the provider is on the map.
function ProviderMixin:Refresh()
    if self.attached then self:RefreshAllData() end
end

-- A data provider for one pin template; buildPins(map, mapID) acquires the pins.
function PinBase.CreateProvider(template, buildPins)
    local provider = CreateFromMixins(MapCanvasDataProviderMixin or {}, ProviderMixin)
    provider.template, provider.buildPins = template, buildPins
    return provider
end
