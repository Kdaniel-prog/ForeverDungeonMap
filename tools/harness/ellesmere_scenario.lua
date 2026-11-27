-- ellesmere_scenario.lua - the live view next to EllesmereUI's minimap module (bug report: the
-- enlarged minimap stayed on EllesmereUI's spot instead of moving into the live view window).
-- Run: python -I tools/harness/run.py tools/harness/ellesmere_scenario.lua   (and with --combat)
-- The module's side is rebuilt here from its 9.8.6 source, only what touches the Minimap frame:
--  * EUI_Minimap_Apply.lua: the minimap lives under a crop frame of the visible size (the client
--    draws the blips only inside the parent's rectangle); a SetParent hook takes it back from any
--    other parent; every apply pass sets the size, the mask and the crop frame's size again;
--  * EUI_UnlockMode_Anchors.lua: an OnSizeChanged hook puts the minimap back on its stored spot,
--    at once and once more when its 0.05 s throttle ends;
--  * EUI_Minimap_Apply.lua locks the minimap's strata and level (SetFixedFrameStrata/Level): a
--    locked frame ignores SetFrameStrata and SetFrameLevel (bug report "there is still a grey
--    patch": the minimap stayed on its own layer, under the live view window's dark fill).
local addonName, ns = ...

-- the live view next to the world map is checked here: the one on its own inside dungeons
-- (liveViewAlone) has its own part in liveview_scenario.lua
ForeverDungeonMapDB = ForeverDungeonMapDB or {}
ForeverDungeonMapDB.liveViewAlone = false
if ns.db then ns.db.liveViewAlone = false end
local M = MOCK
local Check, Step = M.Check, M.Step
local LOGIN_IN_COMBAT = M.combat

local DUNGEON_UI_MAP = 279
local MAP_SIZE, CROP = 140, 12
-- the spot stored by EllesmereUI's unlock mode: far from the world map and the live view
local STORED_X, STORED_Y = 800, 400
local ELLESMERE_SQUARE_MASK = 130937
local RESIZE_THROTTLE_SECONDS = 0.05
local WORLD_MAP_GROWTH = 120

-- EllesmereUI's side of the mock (this file is not addon code)

local cropFrame = M.CreateFrameRaw("Frame", nil, UIParent)

local function ApplyStoredPosition()
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", UIParent, "CENTER", STORED_X, STORED_Y)
end

local function ApplyMinimap()
    Minimap:SetScale(1)
    Minimap:SetSize(MAP_SIZE, MAP_SIZE)
    Minimap:SetMaskTexture(ELLESMERE_SQUARE_MASK)
    cropFrame:ClearAllPoints()
    cropFrame:SetPoint("CENTER", Minimap, "CENTER")
    cropFrame:SetSize(MAP_SIZE, MAP_SIZE - 2 * CROP)
end

-- in combat the real module queues its work for the end of combat
local function TakeMinimapBack()
    if Minimap:GetParent() ~= cropFrame and not M.combat then Minimap:SetParent(cropFrame) end
end

local function OnMinimapResized()
    if M.combat then return end
    ApplyStoredPosition()
    C_Timer.After(RESIZE_THROTTLE_SECONDS, function()
        if not M.combat then ApplyStoredPosition() end
    end)
end

local function EnableEllesmereMinimap()
    ApplyMinimap()
    Minimap:SetParent(cropFrame)
    MinimapCluster:SetAlpha(0)
    MinimapCluster:EnableMouse(false)
    ApplyStoredPosition()
    hooksecurefunc(Minimap, "SetParent", TakeMinimapBack)
    Minimap:SetFixedFrameStrata(true)
    Minimap:SetFixedFrameLevel(true)
    Minimap:HookScript("OnSizeChanged", OnMinimapResized)
end

-- what the live view must leave exactly as it found it
local function Snapshot()
    local point, relativeTo, relativePoint, x, y = Minimap:GetPoint(1)
    return table.concat({
        "parent=" .. tostring(Minimap:GetParent()),
        ("points=%d %s>%s:%s(%s,%s)"):format(Minimap:GetNumPoints(), point, tostring(relativeTo), relativePoint, x, y),
        ("size=%sx%s scale=%s"):format(Minimap:GetWidth(), Minimap:GetHeight(), Minimap:GetScale()),
        ("strata=%s level=%s"):format(Minimap:GetFrameStrata(), Minimap:GetFrameLevel()),
        ("locks=%s/%s"):format(tostring(Minimap:HasFixedFrameStrata()), tostring(Minimap:HasFixedFrameLevel())),
        ("mask=%s zoom=%s"):format(tostring(Minimap._mask), Minimap:GetZoom()),
        ("crop=%sx%s"):format(cropFrame:GetSize()),
        "cluster alpha=" .. MinimapCluster:GetAlpha(),
    }, " | ")
end

local function RectText(frame)
    local left, bottom, width, height = frame:GetRect()
    return ("%s,%s %sx%s"):format(tostring(left), tostring(bottom), tostring(width), tostring(height))
end

local function IsInside(inner, outer)
    local left, bottom, width, height = inner:GetRect()
    local outerLeft, outerBottom, outerWidth, outerHeight = outer:GetRect()
    if not (left and outerLeft) then return false end
    return left >= outerLeft and bottom >= outerBottom
        and left + width <= outerLeft + outerWidth and bottom + height <= outerBottom + outerHeight
end

local function Overlaps(first, second)
    local left, bottom, width, height = first:GetRect()
    local otherLeft, otherBottom, otherWidth, otherHeight = second:GetRect()
    if not (left and otherLeft) then return true end
    return left < otherLeft + otherWidth and otherLeft < left + width
        and bottom < otherBottom + otherHeight and otherBottom < bottom + height
end

local function Area(region)
    local _, _, width, height = region:GetRect()
    return (width or 0) * (height or 0)
end

-- The window's dark fill is strips around the minimap: none reaches over it, together with the
-- minimap they fill the window, and the minimap's own dark ground lies under the minimap.
local function CheckNothingCoversMinimap(label)
    local window, ground = _G.ForeverDungeonMapLive, ns.Live.backing
    local covering, filled = {}, Area(Minimap)
    for index, strip in ipairs(ns.Live.fillStrips) do
        if Overlaps(strip, Minimap) then covering[#covering + 1] = index .. ": " .. RectText(strip) end
        filled = filled + Area(strip)
    end
    Check(label .. ": no fill of the window lies over the minimap", #covering == 0,
        table.concat(covering, "; ") .. " / minimap " .. RectText(Minimap))
    local _, _, _, backdropAlpha = window:GetBackdropColor()
    Check(label .. ": the window's border has no fill of its own", backdropAlpha == 0, tostring(backdropAlpha))
    local inset = 2 * ns.BACKDROP.insets.left
    local inside = (window:GetWidth() - inset) * (window:GetHeight() - inset)
    Check(label .. ": the fill and the minimap leave no hole in the window", math.abs(filled - inside) < 1,
        filled .. " of " .. inside)
    Check(label .. ": no dark ground in the minimap's place while the minimap is there", not ground:IsShown())
    Check(label .. ": the window lets the mouse through to the minimap", not window:IsMouseEnabled())
end

-- The minimap is in our window, enlarged, square, and its crop frame does not cut the blips.
local function CheckInLiveView(label)
    local window = _G.ForeverDungeonMapLive
    Check(label .. ": minimap sits inside the live view window", IsInside(Minimap, window),
        ("minimap %s, window %s"):format(RectText(Minimap), RectText(window)))
    Check(label .. ": minimap has the live view's size", window.side > MAP_SIZE
        and Minimap:GetWidth() == window.side and Minimap:GetHeight() == window.side,
        ("%sx%s, wanted %s"):format(Minimap:GetWidth(), Minimap:GetHeight(), tostring(window.side)))
    Check(label .. ": live view keeps its square mask", Minimap._mask == ns.TEX.WHITE, tostring(Minimap._mask))
    Check(label .. ": EllesmereUI's crop frame covers the minimap", IsInside(Minimap, cropFrame),
        ("minimap %s, crop frame %s"):format(RectText(Minimap), RectText(cropFrame)))
    Check(label .. ": minimap is drawn above the window's background",
        Minimap:GetFrameStrata() == window:GetFrameStrata() and Minimap:GetFrameLevel() > window:GetFrameLevel(),
        ("minimap %s %d, window %s %d"):format(Minimap:GetFrameStrata(), Minimap:GetFrameLevel(),
            window:GetFrameStrata(), window:GetFrameLevel()))
    Check(label .. ": EllesmereUI's locks on the minimap's layer are on again",
        Minimap:HasFixedFrameStrata() and Minimap:HasFixedFrameLevel())
    CheckNothingCoversMinimap(label)
end

-- The client's Raise() lifts a frame above every other frame of its strata: also above a minimap
-- that is not its child. (The mock's Raise() leaves the level alone.)
local function RaiseLikeTheClient(window)
    rawset(window, "Raise", function(self)
        self:SetFrameLevel(math.max(self:GetFrameLevel(), Minimap:GetFrameLevel()) + 1)
    end)
end

local function CheckAtHome(label, before)
    -- let the redraw timer and EllesmereUI's delayed position run first
    M.Advance(1)
    local after = Snapshot()
    Check(label .. ": minimap given back exactly", after == before and not ns.Live:IsBorrowing(),
        before .. "  ->  " .. after)
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
    M.Advance(1)
end
local function CloseMap()
    Step("user closes world map (M)", function() if WorldMapFrame:IsShown() then M.UserToggleWorldMap() end end)
    M.Advance(1)
end

-- login: EllesmereUI enables its modules at PLAYER_LOGIN, after every addon has loaded
Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("EllesmereUI enables its minimap", EnableEllesmereMinimap)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(6)
if LOGIN_IN_COMBAT then LeaveCombat() end
Check("inside Wailing Caverns", ns.instanceID == 43, tostring(ns.instanceID))
local home = Snapshot()

-- 1. the reported bug: the map opens in a dungeon
OpenMap()
Check("1: live view shown", ns.Live:IsShown() and ns.Live:IsBorrowing())
CheckInLiveView("1")

-- 2. EllesmereUI runs a whole apply pass while the minimap is in the live view
Step("EllesmereUI applies its minimap again", ApplyMinimap)
M.Advance(1)
CheckInLiveView("2")

-- 3. the world map grows (quest log opened): the live view follows
Step("world map grows", function()
    WorldMapFrame:SetSize(WorldMapFrame:GetWidth() + WORLD_MAP_GROWTH, WorldMapFrame:GetHeight() + WORLD_MAP_GROWTH)
    M.FireScript(WorldMapFrame, "OnSizeChanged")
end)
M.Advance(1)
CheckInLiveView("3")

-- 3b. bug report "a grey thing over the live view": the live view is shown again while it is up
-- (a map closed and reopened in combat), which raises the window over the minimap
RaiseLikeTheClient(_G.ForeverDungeonMapLive)
Step("the live view is shown again while it is up", function() ns.Live:Show() end)
CheckInLiveView("3b")
Check("3b: the bug report describes the live view's layers", #ns.Live:Describe() >= 4, table.concat(ns.Live:Describe(), " / "))

-- 4. the minimap is put back on EllesmereUI's spot in combat: nothing of ours moves until combat ends
EnterCombat()
Step("the minimap moves to EllesmereUI's spot in combat", ApplyStoredPosition)
CheckNoViolations("4 in combat")
LeaveCombat()
CheckInLiveView("4 after combat")

-- 5. closing the map gives everything back, and it works a second time
CloseMap()
CheckAtHome("5", home)
OpenMap()
CheckInLiveView("5 reopened")
CloseMap()
CheckAtHome("5 reopened", home)
CheckNoViolations("5")

-- 6. the map opens in combat: the minimap stays on EllesmereUI's spot and moves in afterwards,
-- also when EllesmereUI's own queued apply pass runs at the end of the same combat
EnterCombat()
OpenMap()
Check("6: in combat the live view opens without the minimap", ns.Live:IsShown() and not ns.Live:IsBorrowing()
    and Snapshot() == home, Snapshot())
CheckNoViolations("6 in combat")
LeaveCombat()
Step("EllesmereUI's queued apply pass runs", ApplyMinimap)
M.Advance(1)
CheckInLiveView("6 after combat")
CloseMap()
CheckAtHome("6", home)

-- 7. outside a dungeon the live view opens with the map as well
M.player.inInstance = false
Step("ZONE_CHANGED_NEW_AREA (left the dungeon)", function() M.FireEvent("ZONE_CHANGED_NEW_AREA") end)
OpenMap()
CheckInLiveView("7 outside a dungeon")
CloseMap()
CheckAtHome("7", home)
CheckNoViolations("7")

-- 8. a minimap whose layer cannot be changed at all, whatever the reason: it stays under the
-- window, and still nothing of the window is drawn over it or takes its mouse
local setFrameStrata, setFrameLevel = rawget(Minimap, "SetFrameStrata"), rawget(Minimap, "SetFrameLevel")
rawset(Minimap, "SetFrameStrata", function() end)
rawset(Minimap, "SetFrameLevel", function() end)
OpenMap()
local liveWindow = _G.ForeverDungeonMapLive
Check("8: the minimap stayed on its own layer, under the window", ns.Live:IsBorrowing()
    and Minimap:GetFrameStrata() ~= liveWindow:GetFrameStrata(), Minimap:GetFrameStrata())
CheckNothingCoversMinimap("8 stuck layer")
M.Advance(1)
local kept = ns.db.liveViewLayers
Check("8: the layers are kept for the next look", kept and #kept.lines >= 4
    and table.concat(kept.lines, " "):find("seen", 1, true) ~= nil, kept and table.concat(kept.lines, " / "))
local moved = 0
local startMoving = liveWindow.StartMoving
rawset(liveWindow, "StartMoving", function(self)
    moved = moved + 1
    return startMoving(self)
end)
Step("user drags the live view by its title bar", function()
    M.FireScript(ns.Live.dragHandles[1], "OnDragStart")
    M.FireScript(ns.Live.dragHandles[1], "OnDragStop")
end)
Check("8: the title bar still drags the window", moved == 1 and ns.db.windowPositions[ns.LIVE_WINDOW_NAME] ~= nil)
ns.db.windowPositions[ns.LIVE_WINDOW_NAME] = nil
CloseMap()
rawset(Minimap, "SetFrameStrata", setFrameStrata)
rawset(Minimap, "SetFrameLevel", setFrameLevel)
CheckAtHome("8", home)
CheckNoViolations("8")
