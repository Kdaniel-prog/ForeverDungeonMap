-- taint_scenario.lua - taint scenarios for the live view and the dungeon map (docs/taint-report.md)
-- Run: python -I tools/harness/run.py tools/harness/taint_scenario.lua   (and with --combat: login in combat)
-- Taint features added on top of wowmock.lua (all set up here, before the addon's ADDON_LOADED):
--  * Blizzard OnShow/OnHide scripts on MinimapCluster, its buttons and the Minimap's own children
--    that report ADDON_ACTION_FORBIDDEN when they run in tainted execution (an addon Hide()/Show()
--    makes Edit Mode / menu / layout code run tainted - the popup's usual cause);
--  * Hide/Show of those Blizzard frames from addon code is reported even out of combat;
--  * SetScript on the Minimap from addon code is reported (the script slot stays tainted);
--  * a small EditModeManagerFrame whose Enter/Exit check that the minimap is at home.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step
local LOGIN_IN_COMBAT = M.combat

local ROUND_MASK = "Interface\\Masks\\CircleMaskScalable"
local LEATRIX_SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local DUNGEON_UI_MAP = 279
local ZONE_UI_MAP = 1413

-- Blizzard side of the mock (secure code: this file is not addon code)

-- A Blizzard script that must never run inside the addon's tainted call.
local function Sentinel(label)
    return function()
        M.ProtectedCall(label .. " ran in tainted execution", "forbidden", label)
    end
end

local function GuardScripts(frame, label)
    frame:SetScript("OnShow", Sentinel(label .. ":OnShow"))
    frame:SetScript("OnHide", Sentinel(label .. ":OnHide"))
end

-- Addon code may not Hide()/Show() these frames at all (not only in combat).
local function GuardVisibility(frame, label)
    for _, method in ipairs({ "Hide", "Show" }) do
        local original = frame[method]
        rawset(frame, method, function(self, ...)
            M.ProtectedCall(("%s:%s from addon code"):format(label, method), "forbidden", label)
            return original(self, ...)
        end)
    end
end

local function GuardBlizzardFrame(frame, label)
    GuardScripts(frame, label)
    GuardVisibility(frame, label)
end

-- wowmock's IsMouseClickEnabled/IsMouseMotionEnabled read `x ~= nil and x or ...`, which
-- answers true after SetMouseClickEnabled(false); these frames get the client's behaviour.
local function RealMouseState(frame)
    rawset(frame, "IsMouseClickEnabled", function(self)
        if self._mouseClick ~= nil then return self._mouseClick end
        return self._mouse or false
    end)
    rawset(frame, "IsMouseMotionEnabled", function(self)
        if self._mouseMotion ~= nil then return self._mouseMotion end
        return self._mouse or false
    end)
end

-- Cluster buttons like the retail ones: tracking (click only), addon compartment (dropdown).
local tracking = M.CreateFrameRaw("Button", nil, MinimapCluster)
tracking:SetMouseClickEnabled(true)
tracking:SetMouseMotionEnabled(false)
local compartment = M.CreateFrameRaw("Button", "AddonCompartmentFrame", MinimapCluster)
compartment:EnableMouse(true)
local zoneText = M.CreateFrameRaw("Button", nil, MinimapCluster)
zoneText:EnableMouse(true)
zoneText:SetAlpha(0.8)

for _, frame in ipairs({ MinimapCluster, tracking, compartment, zoneText, MinimapBackdrop, Minimap.ZoomIn,
    Minimap.ZoomOut, Minimap.ZoomHitArea }) do
    RealMouseState(frame)
end
GuardBlizzardFrame(MinimapCluster, "MinimapCluster")
GuardBlizzardFrame(tracking, "MinimapCluster.Tracking")
GuardBlizzardFrame(compartment, "AddonCompartmentFrame")
GuardBlizzardFrame(zoneText, "MinimapCluster.ZoneTextButton")
GuardBlizzardFrame(MinimapBackdrop, "MinimapBackdrop")
GuardBlizzardFrame(Minimap.ZoomIn, "Minimap.ZoomIn")
GuardBlizzardFrame(Minimap.ZoomOut, "Minimap.ZoomOut")
GuardBlizzardFrame(Minimap.ZoomHitArea, "Minimap.ZoomHitArea")
Minimap.ZoomIn:EnableMouse(true)
Minimap.ZoomOut:EnableMouse(true)

-- Blizzard's own wheel zoom on the Minimap (retail has one).
local function BlizzardMinimapWheel(minimap, delta)
    local zoom = minimap:GetZoom() + (delta > 0 and 1 or -1)
    minimap:SetZoom(math.max(0, math.min(minimap:GetZoomLevels() - 1, zoom)))
end
Minimap:SetScript("OnMouseWheel", BlizzardMinimapWheel)
Minimap:EnableMouseWheel(true)
Minimap:SetMaskTexture(ROUND_MASK)
do
    local originalSetScript = Minimap.SetScript
    rawset(Minimap, "SetScript", function(self, script, handler)
        M.ProtectedCall("Minimap:SetScript(" .. tostring(script) .. ") from addon code", "forbidden", "Minimap")
        return originalSetScript(self, script, handler)
    end)
end

-- Edit Mode: entering it applies the layout to the cluster, which must hold the minimap.
local minimapHome = Minimap:GetParent()
EditModeManagerFrame = M.CreateFrameRaw("Frame", "EditModeManagerFrame", UIParent)
EditModeManagerFrame:Hide()
local editModeProblems = {}
function EditModeManagerFrame:EnterEditMode()
    self:Show()
    if Minimap:GetParent() ~= minimapHome then editModeProblems[#editModeProblems + 1] = "minimap not in its cluster" end
    MinimapCluster:ClearAllPoints()
    MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
end
function EditModeManagerFrame:ExitEditMode()
    self:Hide()
end

-- snapshot of everything the live view touches

local function PointsText(frame)
    local parts = {}
    for i = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        parts[#parts + 1] = ("%s>%s:%s(%s,%s)"):format(point, tostring(relativeTo), relativePoint, x, y)
    end
    return table.concat(parts, ";")
end

local function WidgetText(widget)
    local text = ("shown=%s alpha=%s"):format(tostring(widget:IsShown()), tostring(widget:GetAlpha()))
    if widget.IsMouseClickEnabled then
        text = text .. (" click=%s motion=%s"):format(tostring(widget:IsMouseClickEnabled()), tostring(widget:IsMouseMotionEnabled()))
    end
    return text
end

-- stable names for unnamed widgets: reparenting reorders GetChildren()
local widgetLabels, labelCount = {}, 0
local function WidgetLabel(widget)
    if not widgetLabels[widget] then
        labelCount = labelCount + 1
        widgetLabels[widget] = ("%s#%d"):format(tostring(widget), labelCount)
    end
    return widgetLabels[widget]
end

local function AddWidgetLines(lines, ...)
    local sorted = {}
    for i = 1, select("#", ...) do
        local widget = select(i, ...)
        if widget ~= Minimap then sorted[#sorted + 1] = WidgetLabel(widget) .. " " .. WidgetText(widget) end
    end
    table.sort(sorted)
    for _, line in ipairs(sorted) do lines[#lines + 1] = line end
end

local function MinimapSnapshot()
    local width, height = Minimap:GetSize()
    local lines = {
        "parent=" .. tostring(Minimap:GetParent()), "points=" .. PointsText(Minimap),
        ("size=%sx%s scale=%s"):format(width, height, Minimap:GetScale()),
        ("strata=%s level=%s"):format(Minimap:GetFrameStrata(), Minimap:GetFrameLevel()),
        ("mask=%s zoom=%s wheel=%s"):format(tostring(Minimap._mask), Minimap:GetZoom(), tostring(Minimap:IsMouseWheelEnabled())),
        "wheelScript=" .. tostring(Minimap:GetScript("OnMouseWheel") == BlizzardMinimapWheel),
        "ground=" .. tostring(C_Minimap.GetDrawGroundTextures()),
        "cluster=" .. WidgetText(MinimapCluster), "clusterPoints=" .. PointsText(MinimapCluster),
    }
    AddWidgetLines(lines, MinimapCluster:GetChildren())
    AddWidgetLines(lines, Minimap:GetChildren())
    AddWidgetLines(lines, Minimap:GetRegions())
    return lines
end

-- every line that differs from the snapshot taken before the live view was used
local function Differences(before, after)
    local diff = {}
    for i = 1, math.max(#before, #after) do
        if before[i] ~= after[i] then diff[#diff + 1] = tostring(before[i]) .. " -> " .. tostring(after[i]) end
    end
    return table.concat(diff, " | ")
end

local function CheckAtHome(label, before)
    -- let the redraw timer put the zoom back first
    M.Advance(0.1)
    local diff = Differences(before, MinimapSnapshot())
    Check(label .. ": minimap given back exactly", diff == "" and not ns.Live:IsBorrowing(), diff)
end

local function CheckNoViolations(label)
    local count = #M.report.protected
    Check(label .. ": no blocked/forbidden action", count == 0, count .. " so far")
end

-- player actions

local function EnterCombat() M.combat = true end
local function LeaveCombat()
    M.combat = false
    Step("PLAYER_REGEN_ENABLED", function() M.FireEvent("PLAYER_REGEN_ENABLED") end)
    M.Advance(1)
end
local function OpenMap()
    WorldMapFrame.mapID = DUNGEON_UI_MAP
    Step("user opens world map (M)", function() if not WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
    M.Advance(0.5)
end
local function CloseMap()
    Step("user closes world map (M)", function() if WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
    M.Advance(0.5)
end
local function NavigateMap(mapID)
    Step("user navigates the world map to " .. mapID, function() WorldMapFrame:SetMapID(mapID) end)
    M.Advance(0.5)
end
local function WheelOverMinimap(delta)
    Step("wheel over the live minimap", function() M.FireScript(Minimap, "OnMouseWheel", delta) end)
end

-- login (in combat with --combat: /reload during a fight)
Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(6)
if LOGIN_IN_COMBAT then LeaveCombat() end
Check("inside Wailing Caverns", ns.instanceID == 43, tostring(ns.instanceID))
local home = MinimapSnapshot()

-- 1. map opened out of combat, then combat starts and the player navigates
OpenMap()
Check("1: live view shown out of combat", ns.Live:IsShown() and ns.Live:IsBorrowing())
Check("1: cluster faded, not hidden", MinimapCluster:IsShown() and MinimapCluster:GetAlpha() == 0)
Check("1: cluster buttons click-through", not compartment:IsMouseClickEnabled() and not tracking:IsMouseClickEnabled())
EnterCombat()
local zoomBefore = Minimap:GetZoom()
WheelOverMinimap(1)
Check("1: wheel zooms once in combat", Minimap:GetZoom() == zoomBefore + 1 and ns.db.liveZoom == zoomBefore + 1,
    zoomBefore .. " -> " .. Minimap:GetZoom())
Step("world map resized in combat", function() M.FireScript(WorldMapFrame, "OnSizeChanged") end)
NavigateMap(ZONE_UI_MAP)
Check("1: dungeon view steps aside on navigation", not ns.View:IsShown())
Check("1: minimap stays in the live view during combat", ns.Live:IsBorrowing() and Minimap:GetParent() ~= minimapHome)
CloseMap()
Check("1: minimap still not moved in combat", ns.Live:IsBorrowing())
LeaveCombat()
Check("1: live view closed after combat", not ns.Live:IsShown())
CheckAtHome("1", home)
CheckNoViolations("1")

-- 2. map opened in combat
EnterCombat()
OpenMap()
Check("2: dungeon view shown in combat", ns.View:IsShown())
Check("2: live view waits for the end of combat", not ns.Live:IsShown() and not ns.Live:IsBorrowing())
LeaveCombat()
Check("2: live view opens after combat (map still open)", ns.Live:IsShown() and ns.Live:IsBorrowing())
CloseMap()
CheckAtHome("2", home)
EnterCombat()
OpenMap()
CloseMap()
LeaveCombat()
Check("2: opened and closed in combat: live view never opened", not ns.Live:IsShown())
CheckAtHome("2b", home)
CheckNoViolations("2")

-- 3. live view show/hide in and out of combat
OpenMap()
Step("Live:Hide", function() ns.Live:Hide() end)
CheckAtHome("3 hide", home)
Step("Live:Show", function() ns.Live:Show() end)
Step("Live:Show again", function() ns.Live:Show() end)
Check("3: shown again", ns.Live:IsShown() and ns.Live:IsBorrowing())
EnterCombat()
Step("Live:Hide in combat", function() ns.Live:Hide() end)
Step("Live:Show in combat", function() ns.Live:Show() end)
Step("Live:Hide in combat (last wish)", function() ns.Live:Hide() end)
Check("3: nothing moved in combat", ns.Live:IsBorrowing())
LeaveCombat()
CheckAtHome("3 hide after combat", home)
Step("Live:Show", function() ns.Live:Show() end)
Step("close button", function() M.Click(_G.ForeverDungeonMapLiveCloseButton) end)
Check("3: close button gives the minimap back", not ns.Live:IsShown())
CheckAtHome("3 close button", home)
Step("Live:Show after the player closed it", function() ns.Live:Show() end)
Check("3: stays closed until the map reopens", not ns.Live:IsShown())
CloseMap()
OpenMap()
Check("3: reopened map shows it again", ns.Live:IsShown())
CloseMap()
CheckAtHome("3", home)
CheckNoViolations("3")

-- 4. Edit Mode after the live view was used (and while it is open)
Step("enter Edit Mode", function() EditModeManagerFrame:EnterEditMode() end)
Step("exit Edit Mode", function() EditModeManagerFrame:ExitEditMode() end)
Check("4: Edit Mode finds the minimap at home after the live view was used", #editModeProblems == 0,
    table.concat(editModeProblems, "; "))
-- Edit Mode re-anchors the cluster itself: that is the new home
home = MinimapSnapshot()
OpenMap()
Step("enter Edit Mode while the live view is open", function() EditModeManagerFrame:EnterEditMode() end)
Check("4: Edit Mode takes the minimap back", not ns.Live:IsShown())
CheckAtHome("4 Edit Mode", home)
Step("exit Edit Mode", function() EditModeManagerFrame:ExitEditMode() end)
CloseMap()
CheckNoViolations("4")

-- 5. another addon's square mask survives the live view
Step("Leatrix sets a square mask", function() Minimap:SetMaskTexture(LEATRIX_SQUARE_MASK) end)
home = MinimapSnapshot()
OpenMap()
CloseMap()
CheckAtHome("5 square mask", home)

-- 6. the "Live view in dungeons" option
local function SetLiveViewOption(enabled)
    Step("option liveView = " .. tostring(enabled), function() ns.Settings.Set("liveView", enabled) end)
end
OpenMap()
SetLiveViewOption(false)
Check("6: switched off: minimap home at once", not ns.Live:IsShown())
CheckAtHome("6 switched off", home)
CloseMap()
OpenMap()
Check("6: stays off on the next map open", not ns.Live:IsShown() and not ns.Live:IsBorrowing())
CloseMap()
SetLiveViewOption(true)
OpenMap()
Check("6: switched on again: shown on map open", ns.Live:IsShown())
EnterCombat()
SetLiveViewOption(false)
Check("6: switched off in combat: nothing moves yet", ns.Live:IsBorrowing())
LeaveCombat()
Check("6: given back after combat", not ns.Live:IsShown())
CheckAtHome("6 switched off in combat", home)
CloseMap()
SetLiveViewOption(true)
CheckNoViolations("6")

Check("no WorldMapFrame:SetMapID from addon code", (M.mapStateTainted or 0) == 0, tostring(M.mapStateTainted))
