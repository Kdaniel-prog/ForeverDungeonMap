-- liveview_scenario.lua - when the live view opens (bug report: "sometimes I am in a dungeon and
-- the live view does not come up"). It follows the world map, not the dungeon view: everywhere,
-- or only inside dungeons when the player chose that; in combat it opens without the minimap;
-- a zone event the client skipped does not leave M without the dungeon.
-- Run: python -I tools/harness/run.py tools/harness/liveview_scenario.lua   (and with --combat)
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step
local LOGIN_IN_COMBAT = M.combat

local DUNGEON_UI_MAP, ZONE_UI_MAP = 279, 1413
local WAILING_CAVERNS = 43
-- a dungeon with two floors; the data ties this area to the lower one
local DEADMINES, DEADMINES_LOWER_AREA = 36, "Ironclad Cove"
local LIVE_ZOOM = 3
local WORLD_MAP_GROWTH = 120
-- longer than the dungeon view's grace time after opening and its "expected map change" time
local SETTLE_SECONDS = 3

-- Blizzard's side of the mock (this file is not addon code): the client's minimap is round
Minimap:SetMaskTexture("Interface\\Masks\\CircleMaskScalable")

local function Snapshot()
    local point, relativeTo, relativePoint, x, y = Minimap:GetPoint(1)
    return table.concat({
        "parent=" .. tostring(Minimap:GetParent()),
        ("points=%d %s>%s:%s(%s,%s)"):format(Minimap:GetNumPoints(), point, tostring(relativeTo), relativePoint, x, y),
        ("size=%sx%s scale=%s"):format(Minimap:GetWidth(), Minimap:GetHeight(), Minimap:GetScale()),
        ("strata=%s level=%s"):format(Minimap:GetFrameStrata(), Minimap:GetFrameLevel()),
        ("mask=%s zoom=%s shown=%s"):format(tostring(Minimap._mask), Minimap:GetZoom(), tostring(Minimap:IsShown())),
    }, " | ")
end

local function CheckAtHome(label, before)
    M.Advance(1)
    local after = Snapshot()
    Check(label .. ": minimap given back exactly", after == before and not ns.Live:IsBorrowing(), before .. "  ->  " .. after)
end

local function CheckLiveView(label)
    Check(label .. ": live view shown with the minimap inside", ns.Live:IsShown() and ns.Live:IsBorrowing()
        and not ns.Live.combatNotice:IsShown())
end

local function CheckNoLiveView(label)
    Check(label .. ": no live view", not ns.Live:IsShown() and not ns.Live:IsBorrowing())
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
local function OpenMap(mapID)
    WorldMapFrame.mapID = mapID
    Step("user opens world map (M)", function() if not WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
    M.Advance(1)
end
local function CloseMap()
    Step("user closes world map (M)", function() if WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
    M.Advance(1)
end
local function NavigateMap(mapID)
    Step("user navigates the world map to " .. mapID, function() WorldMapFrame:SetMapID(mapID) end)
    M.Advance(1)
end
local function SetOption(key, value)
    Step(("option %s = %s"):format(key, tostring(value)), function() ns.Settings.Set(key, value) end)
    M.Advance(0.1)
end
local function LeaveDungeon()
    M.player.inInstance = false
    Step("ZONE_CHANGED_NEW_AREA (left the dungeon)", function() M.FireEvent("ZONE_CHANGED_NEW_AREA") end)
    M.Advance(0.1)
end
local function EnterDungeon()
    M.player.inInstance = true
    Step("ZONE_CHANGED_NEW_AREA (entered the dungeon)", function() M.FireEvent("ZONE_CHANGED_NEW_AREA") end)
    M.Advance(0.1)
end

Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(6)
if LOGIN_IN_COMBAT then LeaveCombat() end
Check("inside Wailing Caverns", ns.instanceID == WAILING_CAVERNS, tostring(ns.instanceID))
local home = Snapshot()

-- 1. inside a dungeon the live view does not depend on the dungeon view
OpenMap(DUNGEON_UI_MAP)
Check("1: dungeon view shown", ns.View:IsShown())
CheckLiveView("1 map opened")
NavigateMap(ZONE_UI_MAP)
Check("1: the dungeon view steps aside when the player navigates", not ns.View:IsShown())
CheckLiveView("1 dungeon view closed")
CloseMap()
CheckAtHome("1", home)
SetOption("autoDungeonMap", false)
OpenMap(DUNGEON_UI_MAP)
Check("1: no dungeon view with its option off", not ns.View:IsShown())
CheckLiveView("1 dungeon view switched off")
CloseMap()
SetOption("autoDungeonMap", true)
CheckAtHome("1 dungeon view switched off", home)

-- 2. outside a dungeon: with the map everywhere, unless the player limited it to dungeons
LeaveDungeon()
Check("2: outside", ns.instanceID == nil)
OpenMap(ZONE_UI_MAP)
CheckLiveView("2 outside, live view everywhere")
SetOption("liveViewOnlyInDungeons", true)
CheckNoLiveView("2 outside, only inside dungeons")
CheckAtHome("2 option switched with the map open", home)
CloseMap()
OpenMap(ZONE_UI_MAP)
CheckNoLiveView("2 outside, map reopened")
EnterDungeon()
CheckLiveView("2 entered the dungeon with the map open")
LeaveDungeon()
CheckNoLiveView("2 left the dungeon with the map open")
CloseMap()
CheckAtHome("2", home)

-- 3. the client skipped the zone event: the instance is read again when the map opens
M.player.inInstance = true
Check("3: the addon has not heard of the dungeon yet", ns.instanceID == nil)
OpenMap(DUNGEON_UI_MAP)
Check("3: the dungeon is known as soon as the map opens", ns.instanceID == WAILING_CAVERNS, tostring(ns.instanceID))
Check("3: dungeon view shown", ns.View:IsShown())
CheckLiveView("3 only inside dungeons")
CloseMap()
SetOption("liveViewOnlyInDungeons", false)
CheckAtHome("3", home)

-- 4. in combat the protected minimap cannot move: the window opens with a notice
EnterCombat()
OpenMap(DUNGEON_UI_MAP)
local window = _G.ForeverDungeonMapLive
Check("4: in combat the live view opens without the minimap", ns.Live:IsShown() and not ns.Live:IsBorrowing()
    and ns.Live.combatNotice:IsShown() and Snapshot() == home, Snapshot())
Check("4: the bug report says it waits", ns.Live:Describe()[1]:find("waiting", 1, true) ~= nil, ns.Live:Describe()[1])
Check("4: the empty window is solid: dark ground in the minimap's place, and it takes the mouse", window:IsMouseEnabled()
    and ns.Live.backing:IsShown() and ns.Live.backing:GetFrameStrata() == window:GetFrameStrata())
local widthInCombat = window:GetWidth()
Step("world map grows in combat", function()
    WorldMapFrame:SetSize(WorldMapFrame:GetWidth() + WORLD_MAP_GROWTH, WorldMapFrame:GetHeight() + WORLD_MAP_GROWTH)
    M.FireScript(WorldMapFrame, "OnSizeChanged")
end)
Check("4: the empty window follows the map's size in combat", window:GetWidth() == widthInCombat + WORLD_MAP_GROWTH,
    widthInCombat .. " -> " .. window:GetWidth())
CheckNoViolations("4 in combat")
LeaveCombat()
CheckLiveView("4 after combat")
Check("4: minimap has the live view's size", Minimap:GetWidth() == window.side, Minimap:GetWidth() .. " / " .. tostring(window.side))
Check("4: the minimap is drawn above the window, no dark ground in its place", Minimap:GetFrameStrata() == window:GetFrameStrata()
    and Minimap:GetFrameLevel() > window:GetFrameLevel() and not ns.Live.backing:IsShown())
Check("4: with the minimap inside the window lets the mouse through", not window:IsMouseEnabled())

-- 4b. while the minimap is inside, the window does not move in combat
local moves = 0
local startMoving = window.StartMoving
rawset(window, "StartMoving", function(self)
    moves = moves + 1
    return startMoving(self)
end)
local function DragWindow()
    Step("user drags the live view by its title bar", function()
        M.FireScript(ns.Live.dragHandles[1], "OnDragStart")
        M.FireScript(ns.Live.dragHandles[1], "OnDragStop")
    end)
end
EnterCombat()
DragWindow()
Check("4b: a drag in combat is refused and keeps no spot", moves == 0 and ns.db.windowPositions[ns.LIVE_WINDOW_NAME] == nil)
LeaveCombat()
DragWindow()
Check("4b: a drag out of combat moves it and keeps the spot", moves == 1 and ns.db.windowPositions[ns.LIVE_WINDOW_NAME] ~= nil)
ns.db.windowPositions[ns.LIVE_WINDOW_NAME] = nil
CloseMap()
CheckAtHome("4", home)
EnterCombat()
OpenMap(DUNGEON_UI_MAP)
CloseMap()
Check("4: closed in combat: the empty window closes at once", not ns.Live:IsShown())
LeaveCombat()
CheckNoLiveView("4 opened and closed in combat")
CheckAtHome("4 opened and closed in combat", home)
CheckNoViolations("4")

-- 5. the live view's zoom is remembered whoever zoomed (EllesmereUI's own wheel layer covers the minimap)
OpenMap(DUNGEON_UI_MAP)
Step("another addon zooms the borrowed minimap", function() Minimap:SetZoom(LIVE_ZOOM) end)
CloseMap()
Check("5: zoom remembered", ns.db.liveZoom == LIVE_ZOOM, tostring(ns.db.liveZoom))
CheckAtHome("5", home)
OpenMap(DUNGEON_UI_MAP)
Check("5: the live view opens on its own zoom again", Minimap:GetZoom() == LIVE_ZOOM, Minimap:GetZoom())
CloseMap()
CheckAtHome("5 reopened", home)

-- 6. a minimap another addon keeps hidden (EllesmereUI's visibility rules) shows inside the live view
Step("another addon hides the minimap", function() Minimap:Hide() end)
local hiddenHome = Snapshot()
OpenMap(DUNGEON_UI_MAP)
Check("6: the hidden minimap shows inside the live view", ns.Live:IsBorrowing() and Minimap:IsShown())
Step("the other addon hides it again", function() Minimap:Hide() end)
M.Advance(0.1)
Check("6: it shows again while the live view is open", Minimap:IsShown())
CloseMap()
CheckAtHome("6 hidden again at home", hiddenHome)
Step("the other addon shows the minimap", function() Minimap:Show() end)
CheckAtHome("6", home)

-- 6b. the dungeon map follows the floor of the area we walk into, also with the live view switched off
SetOption("liveView", false)
M.player.instanceID, M.player.instanceName = DEADMINES, "The Deadmines"
Step("ZONE_CHANGED_NEW_AREA (in the Deadmines)", function() M.FireEvent("ZONE_CHANGED_NEW_AREA") end)
OpenMap(DUNGEON_UI_MAP)
CheckNoLiveView("6b live view switched off")
local floorBefore = ns.View.map.state.floor
Step("walk down to the lower floor", function()
    M.player.subZone = DEADMINES_LOWER_AREA
    M.FireEvent("ZONE_CHANGED_INDOORS")
end)
Check("6b: the dungeon map follows to the lower floor", floorBefore == 1 and ns.View.map.state.floor == 2,
    tostring(floorBefore) .. " -> " .. tostring(ns.View.map.state.floor))
CloseMap()
M.player.subZone = nil
M.player.instanceID, M.player.instanceName = WAILING_CAVERNS, "Wailing Caverns"
Step("ZONE_CHANGED_NEW_AREA (back in Wailing Caverns)", function() M.FireEvent("ZONE_CHANGED_NEW_AREA") end)
SetOption("liveView", true)
CheckAtHome("6b", home)

-- 7. "show on the map" of a spot opens the zone without the dungeon view, once: when combat kept
-- the map closed, a later M shows the dungeon again
local spot = { map = ZONE_UI_MAP, x = 50, y = 50, title = "Spot" }
Step("show a spot on the map", function() ns.View:ShowSpot(spot) end)
M.Advance(1)
Check("7: the map opens on the spot's zone, not covered by the dungeon view", WorldMapFrame:IsShown() and not ns.View:IsShown()
    and WorldMapFrame:GetMapID() == ZONE_UI_MAP)
CheckLiveView("7 spot shown")
CloseMap()
EnterCombat()
Step("show a spot on the map in combat", function() ns.View:ShowSpot(spot) end)
Check("7: in combat the map stays closed", not WorldMapFrame:IsShown())
LeaveCombat()
M.Advance(SETTLE_SECONDS)
OpenMap(DUNGEON_UI_MAP)
Check("7: the next M shows the dungeon again", ns.View:IsShown())
CloseMap()
CheckAtHome("7", home)
CheckNoViolations("7")
