-- ForeverDungeonMap - live view
-- Inside instances the game gives addons no positions at all. The minimap is
-- drawn by the client itself and still shows the player and the group, so
-- while the dungeon map is open we borrow the real Minimap, enlarge it in a
-- movable window next to the world map and give it back unchanged afterwards.
-- Taint rules kept here (docs/taint-report.md):
--  * nothing of Blizzard's is moved, resized or reparented in combat; the
--    change waits for the end of combat (ns.AfterCombat);
--  * no Blizzard frame is Hide()n or Show()n: that would run its OnHide/OnShow
--    (Edit Mode, menus, managed frame layout) inside our tainted call. The
--    MinimapCluster and the minimap's decorations are faded (alpha 0, mouse
--    off) instead and get their exact alpha and mouse state back;
--  * no Blizzard script is replaced: the mouse wheel is a HookScript.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local _, ns = ...
local W, C, TEX = ns.W, ns.C, ns.TEX
local L = ns.L

local Live = {}
ns.Live = Live

-- Blizzard's own minimap mask, put back when no addon set another one (path until Theme has it)
local ROUND_MASK = TEX.MINIMAP_ROUND_MASK or "Interface\\Masks\\CircleMaskScalable"
local SQUARE_MASK = TEX.WHITE
local WINDOW_NAME = "ForeverDungeonMapLive"
local WINDOW_TITLE = "Live view"
local WINDOW_TITLE_CLOSING = WINDOW_TITLE .. " " .. ns.Hex(C.MUTED) .. "(closes after combat)|r"
-- above the world map (HIGH), which raises itself on every open
local WINDOW_STRATA = "DIALOG"
local MINIMUM_SIDE = 200
local TITLE_HEIGHT, FOOTER_HEIGHT = 26, 22
local CONTENT_INSET = 8
local WINDOW_GAP = 6
local MINIMAP_LEVEL_ABOVE_WINDOW = 5
-- how deep below MinimapCluster clickable frames get their mouse turned off
local CLUSTER_SCAN_DEPTH = 3
local SOLO_TEXT = ns.Hex(C.MUTED) .. "solo|r"
-- "|cffRRGGBB" of offline or dead members, and of members without a class colour
local OFFLINE_COLOR = ns.Hex(C.MUTED)
local DEFAULT_NAME_COLOR = ns.Hex(C.WHITE)
local NAME_SEPARATOR = "   "
-- room between the group names and the area / floor label on the footer
local FOOTER_GAP = 8
local LOCATION_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
-- ns.AfterCombat keys: the last show/hide wish wins, the size follows the map
local COMBAT_KEY_VISIBILITY = "liveView"
local COMBAT_KEY_SIZE = "liveViewSize"

-- Other addons' pins live on the Minimap too: they stay visible.
local KEEP_VISIBLE = { "Questie", "TomTom", "HereBeDragons", "HBD", "GatherMate" }

local window, content, groupLabel, locationLabel
-- the Minimap's own state while it is in our window; nil when it is at home
local borrowed
-- last mask any addon set (Minimap:GetMaskTexture does not exist on this client)
local lastMaskTexture
local applyingMask = false
-- true when Blizzard's own Minimap OnMouseWheel already zooms
local blizzardWheelZooms = false

local function SetMask(texture)
    applyingMask = true
    Minimap:SetMaskTexture(texture)
    applyingMask = false
end

local function HighestZoom()
    return math.max(0, Minimap:GetZoomLevels() - 1)
end

-- zoom the next frame puts back after a redraw (the latest redraw wins)
local zoomAfterRedraw

-- Make the client redraw the minimap after a size or parent change.
local function RedrawMinimap()
    zoomAfterRedraw = Minimap:GetZoom()
    Minimap:SetZoom(zoomAfterRedraw > 0 and zoomAfterRedraw - 1 or math.min(1, HighestZoom()))
    C_Timer.After(0, function() Minimap:SetZoom(zoomAfterRedraw) end)
end

-- Ratio between the world map's and UIParent's coordinates.
local function WorldMapScale()
    return WorldMapFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Wheel over the borrowed minimap: zoom (unless Blizzard already does) and remember it.
local function OnMinimapWheel(minimap, delta)
    if not borrowed then return end
    if not blizzardWheelZooms then
        local step = delta > 0 and 1 or -1
        minimap:SetZoom(math.max(0, math.min(HighestZoom(), minimap:GetZoom() + step)))
    end
    ns.db.liveZoom = minimap:GetZoom()
end

-- only frames are checked: textures of the minimap never take the mouse
local function TakesMouse(object)
    return object:IsObjectType("Frame") and (object:IsMouseClickEnabled() or object:IsMouseMotionEnabled())
end

-- Remember a frame's mouse state, then make it click-through.
local function DisableMouse(fadedList, object)
    if not TakesMouse(object) then return end
    fadedList[#fadedList + 1] = { object = object,
        click = object:IsMouseClickEnabled(), motion = object:IsMouseMotionEnabled() }
    object:SetMouseClickEnabled(false)
    object:SetMouseMotionEnabled(false)
end

-- Remember an object's alpha and mouse state, then make it invisible and click-through.
local function Fade(fadedList, object)
    DisableMouse(fadedList, object)
    fadedList[#fadedList + 1] = { object = object, alpha = object:GetAlpha() }
    object:SetAlpha(0)
end

-- Newest first, so an object faded twice ends with its very first state.
local function Unfade(fadedList)
    for i = #fadedList, 1, -1 do
        local record = fadedList[i]
        if record.alpha then record.object:SetAlpha(record.alpha) end
        if record.click ~= nil then
            record.object:SetMouseClickEnabled(record.click)
            record.object:SetMouseMotionEnabled(record.motion)
        end
    end
end

-- Minimap buttons and borders are faded; other addons' map pins stay.
local function IsDecoration(child)
    if child == MinimapBackdrop or child == Minimap.ZoomHitArea then return true end
    if child == Minimap.ZoomIn or child == Minimap.ZoomOut then return true end
    local name = child:GetName()
    if not name then return false end
    for _, keptName in ipairs(KEEP_VISIBLE) do
        if name:find(keptName) then return false end
    end
    if name:find("LibDBIcon") or name:find("MinimapButton") or name:find("MiniMap") then return true end
    return child:IsObjectType("Button")
end

local function FadeMinimapDecorations(fadedList)
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if IsDecoration(child) then Fade(fadedList, child) end
    end
    for _, region in ipairs({ Minimap:GetRegions() }) do Fade(fadedList, region) end
end

-- Clickable frames below `frame` (the Minimap itself excluded) stop taking the mouse.
local function DisableClusterMouse(fadedList, frame, depth)
    if depth > CLUSTER_SCAN_DEPTH then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= Minimap then
            DisableMouse(fadedList, child)
            DisableClusterMouse(fadedList, child, depth + 1)
        end
    end
end

-- The Edit Mode managed cluster stays shown and in place: it only turns invisible.
local function FadeCluster(fadedList)
    if not MinimapCluster then return end
    DisableClusterMouse(fadedList, MinimapCluster, 1)
    Fade(fadedList, MinimapCluster)
end

local function SaveMinimapState()
    local state = {
        parent = Minimap:GetParent(), points = {}, strata = Minimap:GetFrameStrata(),
        level = Minimap:GetFrameLevel(), scale = Minimap:GetScale(), zoom = Minimap:GetZoom(),
        wheelEnabled = Minimap:IsMouseWheelEnabled(), shown = Minimap:IsShown(), faded = {},
    }
    state.width, state.height = Minimap:GetSize()
    for i = 1, Minimap:GetNumPoints() do state.points[i] = { Minimap:GetPoint(i) } end
    if C_Minimap and C_Minimap.GetDrawGroundTextures then
        state.groundTextures = C_Minimap.GetDrawGroundTextures()
    end
    return state
end

-- Square, unscaled, wheel zoom, ground textures, the live view's own zoom.
local function ApplyLiveLook()
    Minimap:SetScale(1)
    SetMask(SQUARE_MASK)
    Minimap:EnableMouseWheel(true)
    if C_Minimap and C_Minimap.SetDrawGroundTextures then C_Minimap.SetDrawGroundTextures(true) end
    Minimap:SetZoom(math.min(ns.db.liveZoom or 0, HighestZoom()))
end

local function MoveMinimapIntoWindow()
    Minimap:SetParent(content)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", content, "CENTER")
    Minimap:SetFrameStrata(window:GetFrameStrata())
    Minimap:SetFrameLevel(window:GetFrameLevel() + MINIMAP_LEVEL_ABOVE_WINDOW)
    -- another addon may keep the minimap hidden; inside our window it shows
    if not Minimap:IsShown() then Minimap:Show() end
end

local function Borrow()
    if borrowed then return end
    borrowed = SaveMinimapState()
    FadeMinimapDecorations(borrowed.faded)
    FadeCluster(borrowed.faded)
    ApplyLiveLook()
    MoveMinimapIntoWindow()
end

local function RestoreMinimapLayout(state)
    Minimap:SetParent(state.parent)
    Minimap:ClearAllPoints()
    for _, point in ipairs(state.points) do Minimap:SetPoint(unpack(point)) end
    Minimap:SetSize(state.width, state.height)
    Minimap:SetScale(state.scale)
    Minimap:SetFrameStrata(state.strata)
    Minimap:SetFrameLevel(state.level)
    if not state.shown then Minimap:Hide() end
end

local function RestoreMinimapLook(state)
    SetMask(lastMaskTexture or ROUND_MASK)
    Minimap:EnableMouseWheel(state.wheelEnabled)
    if state.groundTextures ~= nil and C_Minimap and C_Minimap.SetDrawGroundTextures then
        C_Minimap.SetDrawGroundTextures(state.groundTextures)
    end
    Minimap:SetZoom(state.zoom)
end

local function GiveBack()
    if not borrowed or InCombatLockdown() then return end
    local state = borrowed
    borrowed = nil
    RestoreMinimapLayout(state)
    RestoreMinimapLook(state)
    Unfade(state.faded)
    RedrawMinimap()
end

-- "|cffRRGGBBName|r" of a group member in class colour, grey when offline or dead.
local function ColoredMemberName(unit)
    local _, class = UnitClass(unit)
    local classColor = class and RAID_CLASS_COLORS[class]
    local color = classColor and ("|c" .. classColor.colorStr) or DEFAULT_NAME_COLOR
    if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then color = OFFLINE_COLOR end
    return color .. (UnitName(unit) or "?") .. "|r"
end

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function UpdateGroupNames()
    local names = {}
    for _, unit in ipairs(GroupUnits()) do
        if not UnitIsUnit(unit, "player") then names[#names + 1] = ColoredMemberName(unit) end
    end
    groupLabel:SetText(#names > 0 and table.concat(names, NAME_SEPARATOR) or SOLO_TEXT)
end

-- Floor number of the area we are in, when the data ties that area to a floor.
local function FloorOfArea(instanceID, area)
    local floorsByArea = ns.FLOOR_BY_AREA and ns.FLOOR_BY_AREA[instanceID]
    return floorsByArea and floorsByArea[area]
end

-- "Area · Floor 2/3": the client tells addons no floor or position inside instances, only the
-- area name; the floor shows when the data knows that area's floor (multi-floor dungeons only).
local function LocationText()
    local area = GetSubZoneText and GetSubZoneText() or ""
    local instanceID = ns.instanceID
    local dungeon = instanceID and ns.GetDungeon(instanceID, ns.instanceName)
    local floorCount = dungeon and #ns.GetFloors(instanceID, dungeon) or 0
    local floor = floorCount > 1 and FloorOfArea(instanceID, area)
    local floorText = floor and (ns.Hex(C.GOLD) .. L["Floor %d/%d"]:format(floor, floorCount) .. "|r") or nil
    if area == "" then return floorText or "" end
    return ns.Hex(C.MUTED) .. area .. "|r" .. (floorText and ("  " .. floorText) or "")
end

-- The dungeon map follows us to the floor of the area we walked into (the player can still pick
-- another floor; it changes again only on the next area change).
local function FollowFloor()
    local floor = ns.instanceID and FloorOfArea(ns.instanceID, GetSubZoneText and GetSubZoneText() or "")
    local map = ns.View and ns.View.map
    if not (floor and map and ns.View:IsShown() and map.state.instanceID == ns.instanceID) then return end
    local slot = ns.FloorSlot(map.state.floors or {}, floor)
    if slot and slot ~= map.state.floor then map:SetFloor(slot) end
end

local function UpdateFooter(_, event)
    UpdateGroupNames()
    locationLabel:SetText(LocationText())
    if event and event:find("^ZONE_CHANGED") then FollowFloor() end
end

local function SavePosition()
    local point, _, relativePoint, x, y = window:GetPoint(1)
    ns.db.livePos = { point, relativePoint, x, y }
end

-- Saved spot, or next to the world map: right side if there is room, otherwise left.
local function PlaceWindow()
    window:ClearAllPoints()
    local position = ns.db.livePos
    if position then
        window:SetPoint(position[1], UIParent, position[2], position[3], position[4])
        return
    end
    local scale = WorldMapScale()
    local mapRight = (WorldMapFrame:GetRight() or 0) * scale
    local neededWidth = WorldMapFrame:GetHeight() * scale + WINDOW_GAP
    if mapRight + neededWidth <= UIParent:GetWidth() then
        window:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", WINDOW_GAP, 0)
    else
        window:SetPoint("TOPRIGHT", WorldMapFrame, "TOPLEFT", -WINDOW_GAP, 0)
    end
end

-- Same height as the world map window; the minimap inside stays square.
local function ApplySize()
    if not borrowed then return end
    if InCombatLockdown() then
        ns.AfterCombat(COMBAT_KEY_SIZE, ApplySize)
        return
    end
    local height = math.floor(WorldMapFrame:GetHeight() * WorldMapScale() + 0.5)
    local side = math.max(MINIMUM_SIDE, height - TITLE_HEIGHT - FOOTER_HEIGHT - 2 * CONTENT_INSET)
    if window.side == side then return end
    window.side = side
    window:SetSize(side + 2 * CONTENT_INSET, height)
    Minimap:SetSize(side, side)
    RedrawMinimap()
end

local function SetTitle(text)
    if window.Title then window.Title:SetText(text) end
end

local function MakeDraggable()
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        SavePosition()
    end)
end

-- Footer: group names on the left, area and floor on the right.
local function CreateFooter()
    locationLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    locationLabel:SetPoint("BOTTOMRIGHT", -CONTENT_INSET - 2, FOOTER_HEIGHT / 2 - 2)
    locationLabel:SetJustifyH("RIGHT")
    locationLabel:SetWordWrap(false)
    groupLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupLabel:SetPoint("BOTTOMLEFT", CONTENT_INSET + 2, FOOTER_HEIGHT / 2 - 2)
    groupLabel:SetPoint("RIGHT", locationLabel, "LEFT", -FOOTER_GAP, 0)
    groupLabel:SetJustifyH("LEFT")
    groupLabel:SetWordWrap(false)
    window:RegisterEvent("GROUP_ROSTER_UPDATE")
    window:RegisterEvent("UNIT_CONNECTION")
    for _, event in ipairs(LOCATION_EVENTS) do window:RegisterEvent(event) end
    window:SetScript("OnEvent", UpdateFooter)
    -- tests read the footer
    Live.locationLabel = locationLabel
end

local function CreateWindow()
    window = W.CreateWindow(WINDOW_NAME, UIParent, WINDOW_TITLE)
    window:SetFrameStrata(WINDOW_STRATA)
    window:SetToplevel(true)
    MakeDraggable()
    window:Hide()
    if window.CloseButton then
        window.CloseButton:SetScript("OnClick", function() Live:Hide(true) end)
    end
    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", CONTENT_INSET, -TITLE_HEIGHT)
    content:SetPoint("BOTTOMRIGHT", -CONTENT_INSET, FOOTER_HEIGHT + 4)
    CreateFooter()
    -- follow the world map's size (quest log opened, map maximized)
    WorldMapFrame:HookScript("OnSizeChanged", function()
        if window:IsShown() then ApplySize() end
    end)
end

-- The window is visible before the minimap moves in and after it moved out, so the
-- minimap's own children never get an OnShow/OnHide from our code.
local function ShowNow()
    PlaceWindow()
    window:Show()
    window:Raise()
    Borrow()
    -- the minimap was given back meanwhile: always resize
    window.side = nil
    ApplySize()
    UpdateFooter()
end

local function HideNow()
    SetTitle(WINDOW_TITLE)
    GiveBack()
    window:Hide()
end

-- The player's "Live view in dungeons" option (on unless switched off).
local function LiveViewEnabled()
    return not (ns.Settings and ns.Settings.Get("liveView") == false)
end

-- After combat: show if the dungeon map is still open, otherwise give the minimap back.
local function ShowIfMapStillOpen()
    SetTitle(WINDOW_TITLE)
    if not Live.closedByUser and LiveViewEnabled() and WorldMapFrame:IsShown() and ns.View:IsShown() then
        ShowNow()
    else
        HideNow()
    end
end

function Live:Show()
    if not window then CreateWindow() end
    if self.closedByUser or not LiveViewEnabled() then return end
    if InCombatLockdown() then
        -- borrowed already: it stays; otherwise it opens when combat ends
        SetTitle(WINDOW_TITLE)
        ns.AfterCombat(COMBAT_KEY_VISIBILITY, ShowIfMapStillOpen)
        return
    end
    SetTitle(WINDOW_TITLE)
    ShowNow()
end

-- byUser: the player closed it; it stays closed until the map is reopened.
function Live:Hide(byUser)
    if byUser then self.closedByUser = true end
    if not window then return end
    if InCombatLockdown() then
        -- the minimap stays in our window (still useful) until combat ends
        if borrowed then SetTitle(WINDOW_TITLE_CLOSING) else window:Hide() end
        ns.AfterCombat(COMBAT_KEY_VISIBILITY, HideNow)
        return
    end
    HideNow()
end

function Live:IsShown() return window ~= nil and window:IsShown() end

-- true while the real Minimap is inside the live view
function Live:IsBorrowing() return borrowed ~= nil end

-- Edit Mode works on the cluster: the minimap goes home as soon as Edit Mode opens.
local function GiveBackForEditMode()
    if EditModeManagerFrame and EditModeManagerFrame.EnterEditMode then
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() Live:Hide() end)
    end
end

-- Wheel zoom on the borrowed minimap, as a hook so Blizzard's own script stays untouched.
local function HookMinimapWheel()
    blizzardWheelZooms = Minimap:GetScript("OnMouseWheel") ~= nil
    Minimap:HookScript("OnMouseWheel", OnMinimapWheel)
end

-- Switched off in the options: the minimap goes home now (after combat in combat).
local function FollowLiveViewSetting()
    if not (ns.Settings and ns.Settings.OnChanged) then return end
    ns.Settings.OnChanged("liveView", function(enabled)
        if enabled == false then Live:Hide() end
    end)
end

ns.OnLoad(function()
    FollowLiveViewSetting()
    -- remember masks set by other addons (e.g. square minimap options)
    hooksecurefunc(Minimap, "SetMaskTexture", function(_, texture)
        if not applyingMask then lastMaskTexture = texture end
    end)
    HookMinimapWheel()
    GiveBackForEditMode()
    local leavingWorld = CreateFrame("Frame")
    leavingWorld:RegisterEvent("PLAYER_LEAVING_WORLD")
    leavingWorld:SetScript("OnEvent", function() Live:Hide() end)
end)
