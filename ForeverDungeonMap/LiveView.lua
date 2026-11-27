-- ForeverDungeonMap - live view
-- Inside instances the game gives addons no positions at all. The minimap is
-- drawn by the client itself and still shows the player and the group, so
-- we borrow the real Minimap, enlarge it in a movable window with zoom
-- buttons and give it back unchanged afterwards. Inside a dungeon the window
-- stands on its own (top right until dragged, no world map needed); elsewhere,
-- or with that option off, it opens next to the world map while the map is
-- open (everywhere, or only inside dungeons: the player's choice).
-- Taint rules kept here (docs/taint-report.md):
--  * nothing of Blizzard's is moved, resized or reparented in combat; the
--    change waits for the end of combat (ns.AfterCombat);
--  * the Minimap never moves inside the world map's own opening or closing:
--    the live view follows on the next frame (Live:Update);
--  * no Blizzard frame is Hide()n or Show()n: that would run its OnHide/OnShow
--    (Edit Mode, menus, managed frame layout) inside our tainted call. The
--    MinimapCluster and the minimap's decorations are faded (alpha 0, mouse
--    off) instead and get their exact alpha and mouse state back. The one
--    exception: a Minimap another addon keeps hidden is shown while it is in
--    our window and hidden again afterwards;
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
local WINDOW_NAME = ns.LIVE_WINDOW_NAME
local WINDOW_TITLE = "Live view"
local WINDOW_TITLE_CLOSING = WINDOW_TITLE .. " " .. ns.Hex(C.MUTED) .. "(closes after combat)|r"
-- in the empty window while combat keeps the minimap at home
local COMBAT_NOTICE = ns.Hex(C.MUTED) .. L["The minimap cannot move in combat. It appears here when the fight ends."] .. "|r"
local COMBAT_NOTICE_INSET = 24
-- above the world map (HIGH), which raises itself on every open
local WINDOW_STRATA = "DIALOG"
local MINIMUM_SIDE = 200
local TITLE_HEIGHT, FOOTER_HEIGHT = 26, 22
local CONTENT_INSET = 8
-- room under the minimap's place for the footer
local CONTENT_BOTTOM = FOOTER_HEIGHT + 4
-- the window's fill starts where its border's own fill would, and reaches the minimap's place
local FILL_INSET = ns.BACKDROP.insets.left
local SIDE_GAP = CONTENT_INSET - FILL_INSET
-- the title bar leaves this corner to the close button
local CLOSE_BUTTON_ROOM = 32
local WINDOW_GAP = 6
-- the window on its own inside a dungeon: side of the minimap, distance from the screen's top right
local ALONE_SIDE = 360
local ALONE_RIGHT, ALONE_TOP = -16, -16
-- zoom in / out buttons in the footer's left corner
local ZOOM_BUTTON_SIZE, ZOOM_BUTTON_GAP = 18, 4
local MINIMAP_LEVEL_ABOVE_WINDOW = 5
-- other addons put the minimap back on their own terms within this time after it moved in
local LAYERS_KEPT_AFTER_SECONDS = 1
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
-- ns.AfterCombat keys: the last show/hide wish wins, the size follows the map, and a minimap
-- another addon moved in combat comes back into the window
local COMBAT_KEY_VISIBILITY = "liveView"
local COMBAT_KEY_SIZE = "liveViewSize"
local COMBAT_KEY_HOLD = "liveViewHold"
-- the client stores sizes as floats: this close to our size is our size
local SIZE_TOLERANCE = 0.5

-- Other addons' pins live on the Minimap too: they stay visible.
local KEEP_VISIBLE = { "Questie", "TomTom", "HereBeDragons", "HBD", "GatherMate" }

local window, content, backing, combatNotice, groupLabel, locationLabel
-- the Minimap's own state while it is in our window; nil when it is at home
local borrowed
-- last mask any addon set (Minimap:GetMaskTexture does not exist on this client)
local lastMaskTexture
local applyingMask = false
-- true while we anchor / size the borrowed minimap ourselves: HoldMinimap answers only other addons
local anchoringMinimap, sizingMinimap = false, false
-- true while a second look at the borrowed minimap waits for the next frame
local holdQueued = false
-- true when Blizzard's own Minimap OnMouseWheel already zooms
local blizzardWheelZooms = false
-- true between Edit Mode's opening and closing: it works on the minimap's cluster
local editModeOpen = false
-- true while Live:Update waits for the next frame
local updateQueued = false

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

-- Zoom the borrowed minimap one step in (1) or out (-1).
local function ZoomBy(step)
    if not borrowed then return end
    Minimap:SetZoom(math.max(0, math.min(HighestZoom(), Minimap:GetZoom() + step)))
end

-- Wheel over the borrowed minimap: zoom, unless Blizzard already does.
local function OnMinimapWheel(_, delta)
    if blizzardWheelZooms then return end
    ZoomBy(delta > 0 and 1 or -1)
end

-- The window stands on its own: inside a dungeon, unless the player wants it with the world map only.
local function IsAlone()
    return ns.instanceID ~= nil and ns.Setting("liveViewAlone") ~= false
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
        wheelEnabled = Minimap:IsMouseWheelEnabled(), shown = Minimap:IsShown(), faded = {}, covered = {},
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

-- A frame whose strata or level is locked (SetFixedFrameStrata / SetFixedFrameLevel) ignores
-- SetFrameStrata and SetFrameLevel. EllesmereUI locks the minimap's: it stayed on its own layer,
-- under our window's dark fill. (EllesmereUI's own source takes the locks off LibDBIcon's
-- buttons before it moves those.) The locks come off for the change and go back on as they
-- were; keepLocked leaves both on, for a frame of ours that must not follow its parent's layer.
local function SetLayer(frame, strata, level, keepLocked)
    local canUnlock = frame.HasFixedFrameStrata ~= nil and frame.HasFixedFrameLevel ~= nil
    local strataLocked = canUnlock and (keepLocked or frame:HasFixedFrameStrata())
    local levelLocked = canUnlock and (keepLocked or frame:HasFixedFrameLevel())
    if canUnlock then
        frame:SetFixedFrameStrata(false)
        frame:SetFixedFrameLevel(false)
    end
    frame:SetFrameStrata(strata)
    frame:SetFrameLevel(level)
    if canUnlock then
        frame:SetFixedFrameStrata(strataLocked)
        frame:SetFixedFrameLevel(levelLocked)
    end
end

-- The dark ground fills the minimap's place only while the minimap is not there. With the
-- minimap inside, nothing of ours is drawn in its place: the client put a ground meant to lie
-- under EllesmereUI's minimap over it instead (screenshot 2026-11-17: the minimap behind exactly
-- our INK colour at its 0.94 alpha), so whatever layer the minimap ends up on, it stays in view.
local function PlaceBacking()
    backing:SetShown(borrowed == nil)
    if not borrowed then SetLayer(backing, window:GetFrameStrata(), window:GetFrameLevel() + 1, true) end
end

-- Centred in our window, a few levels above it.
local function AnchorMinimap()
    anchoringMinimap = true
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", content, "CENTER")
    anchoringMinimap = false
    SetLayer(Minimap, window:GetFrameStrata(), window:GetFrameLevel() + MINIMAP_LEVEL_ABOVE_WINDOW)
    PlaceBacking()
end

-- Another addon may keep the minimap hidden (EllesmereUI's visibility rules: on mouse-over
-- only, in combat only); inside our window it shows.
local function ShowMinimap()
    if not Minimap:IsShown() then Minimap:Show() end
end

local function MoveMinimapIntoWindow()
    Minimap:SetParent(content)
    -- EllesmereUI's minimap takes it back from any other parent at once: it is then not our
    -- child, and a click that raises the window would put the window above it
    window:SetToplevel(Minimap:GetParent() == content)
    AnchorMinimap()
    ShowMinimap()
end

-- Blizzard's cluster belongs to Edit Mode: nothing inside it is ever resized by us.
local function IsInsideCluster(frame)
    while frame do
        if frame == MinimapCluster then return true end
        frame = frame:GetParent()
    end
    return false
end

-- EllesmereUI keeps its minimap under a crop frame of the visible size and refuses any other
-- parent; by its source the client draws the player and the group only inside the parent's
-- rectangle. Such a frame grows to our size while we have the minimap; RestoreMinimapLayout
-- gives its size back.
local function CoverMinimap()
    local parent = Minimap:GetParent()
    if not parent or parent == content or parent == UIParent or IsInsideCluster(parent) then return end
    local covered = borrowed.covered
    if not covered[parent] then covered[parent] = { parent:GetSize() } end
    parent:SetSize(math.max(covered[parent][1], window.side), math.max(covered[parent][2], window.side))
end

local function SizeMinimap()
    sizingMinimap = true
    Minimap:SetSize(window.side, window.side)
    sizingMinimap = false
    CoverMinimap()
end

local function HasOurSize()
    local width, height = Minimap:GetSize()
    return math.abs(width - window.side) <= SIZE_TOLERANCE and math.abs(height - window.side) <= SIZE_TOLERANCE
end

-- While we have the minimap, its anchor, layer, mask, size and being shown are ours whatever
-- another addon sets: EllesmereUI puts it back on its own spot after every resize, resizes it on
-- every apply pass and hides it by its visibility rules. In combat nothing of the minimap moves:
-- it comes back when combat ends.
local function HoldMinimap()
    if not borrowed then return end
    if InCombatLockdown() then
        ns.AfterCombat(COMBAT_KEY_HOLD, HoldMinimap)
        return
    end
    AnchorMinimap()
    SetMask(SQUARE_MASK)
    ShowMinimap()
    if not window.side then return end
    if HasOurSize() then
        CoverMinimap()
    else
        SizeMinimap()
        RedrawMinimap()
    end
end

-- Another addon moved, resized, masked or hid the borrowed minimap: ours again now, and once
-- more on the next frame, when the rest of that addon's pass has run.
local function OnForeignChange()
    if not borrowed then return end
    HoldMinimap()
    if holdQueued then return end
    holdQueued = true
    C_Timer.After(0, function()
        holdQueued = false
        HoldMinimap()
    end)
end

-- True when the minimap moved in just now, false when it was inside already.
local function Borrow()
    if borrowed then return false end
    borrowed = SaveMinimapState()
    FadeMinimapDecorations(borrowed.faded)
    FadeCluster(borrowed.faded)
    ApplyLiveLook()
    MoveMinimapIntoWindow()
    return true
end

local function RestoreMinimapLayout(state)
    Minimap:SetParent(state.parent)
    Minimap:ClearAllPoints()
    for _, point in ipairs(state.points) do Minimap:SetPoint(unpack(point)) end
    Minimap:SetSize(state.width, state.height)
    Minimap:SetScale(state.scale)
    SetLayer(Minimap, state.strata, state.level)
    if not state.shown then Minimap:Hide() end
    for frame, size in pairs(state.covered) do frame:SetSize(size[1], size[2]) end
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
    -- whoever zoomed it (our wheel hook, Blizzard's, EllesmereUI's wheel layer over the
    -- minimap): the live view opens on this zoom again
    ns.db.liveZoom = Minimap:GetZoom()
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

local function UpdateFooter()
    UpdateGroupNames()
    locationLabel:SetText(LocationText())
end

-- Where the player dragged it; on its own at the screen's top right; else next to the world map:
-- right side if there is room, otherwise left.
local function PlaceWindow()
    if W.RestorePosition(window) then return end
    window:ClearAllPoints()
    if IsAlone() then
        window:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", ALONE_RIGHT, ALONE_TOP)
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

-- Height of the window: its own on its own, else the world map window's.
local function WindowHeight()
    if IsAlone() then return ALONE_SIDE + TITLE_HEIGHT + FOOTER_HEIGHT + 2 * CONTENT_INSET end
    return math.floor(WorldMapFrame:GetHeight() * WorldMapScale() + 0.5)
end

-- The minimap inside stays square. A window that holds the minimap is resized after combat only.
local function ApplySize()
    if borrowed and InCombatLockdown() then
        ns.AfterCombat(COMBAT_KEY_SIZE, ApplySize)
        return
    end
    local height = WindowHeight()
    local side = math.max(MINIMUM_SIDE, height - TITLE_HEIGHT - FOOTER_HEIGHT - 2 * CONTENT_INSET)
    if window.side == side then return end
    window.side = side
    window:SetSize(side + 2 * CONTENT_INSET, height)
    backing:SetSize(side, side)
    if not borrowed then return end
    SizeMinimap()
    RedrawMinimap()
end

local function SetTitle(text)
    if window.Title then window.Title:SetText(text) end
end

-- Zoom in, then zoom out, in the footer's left corner; returns the last one.
local function CreateZoomButtons()
    local zoomIn = W.IconButton(window, ZOOM_BUTTON_SIZE, TEX.PLUS, 1)
    zoomIn:SetPoint("BOTTOMLEFT", CONTENT_INSET, (FOOTER_HEIGHT - ZOOM_BUTTON_SIZE) / 2 + 2)
    zoomIn:SetScript("OnClick", function() ZoomBy(1) end)
    W.Tooltip(zoomIn, L["Zoom in"])
    local zoomOut = W.IconButton(window, ZOOM_BUTTON_SIZE, TEX.MINUS, 1)
    zoomOut:SetPoint("LEFT", zoomIn, "RIGHT", ZOOM_BUTTON_GAP, 0)
    zoomOut:SetScript("OnClick", function() ZoomBy(-1) end)
    W.Tooltip(zoomOut, L["Zoom out"])
    -- tests press them
    Live.zoomButtons = { zoomIn, zoomOut }
    return zoomOut
end

-- Footer: zoom buttons and group names on the left, area and floor on the right.
local function CreateFooter()
    locationLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    locationLabel:SetPoint("BOTTOMRIGHT", -CONTENT_INSET - 2, FOOTER_HEIGHT / 2 - 2)
    locationLabel:SetJustifyH("RIGHT")
    locationLabel:SetWordWrap(false)
    local lastZoomButton = CreateZoomButtons()
    groupLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupLabel:SetPoint("LEFT", lastZoomButton, "RIGHT", FOOTER_GAP, 0)
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

-- The protected Minimap hangs on the window: while it is inside, the window stays put in combat.
local function CanMoveWindow()
    return not (borrowed and InCombatLockdown())
end

local function InkTexture(frame)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetColorTexture(C.INK[1], C.INK[2], C.INK[3], C.INK[4])
    return texture
end

-- The minimap's place: a square in the middle of the content, with its own dark ground
-- (PlaceBacking) and the notice shown there while combat keeps the minimap at home.
local function CreateContent()
    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", CONTENT_INSET, -TITLE_HEIGHT)
    content:SetPoint("BOTTOMRIGHT", -CONTENT_INSET, CONTENT_BOTTOM)
    backing = CreateFrame("Frame", nil, window)
    backing:SetPoint("CENTER", content, "CENTER")
    InkTexture(backing):SetAllPoints()
    combatNotice = backing:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    combatNotice:SetPoint("LEFT", COMBAT_NOTICE_INSET, 0)
    combatNotice:SetPoint("RIGHT", -COMBAT_NOTICE_INSET, 0)
    combatNotice:SetJustifyH("CENTER")
    combatNotice:SetText(COMBAT_NOTICE)
    combatNotice:Hide()
    -- tests read the notice and the ground
    Live.combatNotice, Live.backing = combatNotice, backing
end

-- The window's dark fill is four strips around the minimap's place, never over it: whatever
-- layer another addon keeps the minimap on, the window cannot paint over it.
local function CreateFill()
    window:SetBackdropColor(C.INK[1], C.INK[2], C.INK[3], 0)
    local top, bottom, left, right = InkTexture(window), InkTexture(window), InkTexture(window), InkTexture(window)
    top:SetPoint("TOPLEFT", window, "TOPLEFT", FILL_INSET, -FILL_INSET)
    top:SetPoint("BOTTOMRIGHT", backing, "TOPRIGHT", SIDE_GAP, 0)
    bottom:SetPoint("TOPLEFT", backing, "BOTTOMLEFT", -SIDE_GAP, 0)
    bottom:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -FILL_INSET, FILL_INSET)
    left:SetPoint("TOPLEFT", backing, "TOPLEFT", -SIDE_GAP, 0)
    left:SetPoint("BOTTOMRIGHT", backing, "BOTTOMLEFT")
    right:SetPoint("TOPLEFT", backing, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", backing, "BOTTOMRIGHT", SIDE_GAP, 0)
    -- tests check that no strip reaches into the minimap's place
    Live.fillStrips = { top, bottom, left, right }
end

-- With the minimap inside, the window itself lets the mouse through (FitWindow), so the mouse
-- reaches the minimap on whatever layer it is; the title bar and the footer take the drag.
local function CreateDragHandles()
    local titleBar = CreateFrame("Frame", nil, window)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", -CLOSE_BUTTON_ROOM, -TITLE_HEIGHT)
    local footerBar = CreateFrame("Frame", nil, window)
    footerBar:SetPoint("BOTTOMLEFT")
    footerBar:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, CONTENT_BOTTOM)
    W.AddDragHandle(window, titleBar)
    W.AddDragHandle(window, footerBar)
    -- tests drag the window by them
    Live.dragHandles = { titleBar, footerBar }
end

local function CreateWindow()
    window = W.CreateWindow(WINDOW_NAME, UIParent, WINDOW_TITLE)
    window:SetFrameStrata(WINDOW_STRATA)
    window:SetToplevel(true)
    W.MakeMovable(window, WINDOW_NAME, CanMoveWindow)
    window:Hide()
    if window.CloseButton then
        window.CloseButton:SetScript("OnClick", function() Live:Hide(true) end)
    end
    CreateContent()
    CreateFill()
    CreateDragHandles()
    CreateFooter()
    -- follow the world map's size (quest log opened, map maximized)
    WorldMapFrame:HookScript("OnSizeChanged", function()
        if window:IsShown() then ApplySize() end
    end)
end

-- The window is visible before the minimap moves in and after it moved out, so the
-- minimap's own children never get an OnShow/OnHide from our code.
local function OpenWindow()
    PlaceWindow()
    window:Show()
    window:Raise()
end

local function FitWindow()
    local empty = borrowed == nil
    combatNotice:SetShown(empty)
    window:EnableMouse(empty)
    PlaceBacking()
    ApplySize()
    UpdateFooter()
end

-- The layers of the open live view, kept in the saved settings (ns.db.liveViewLayers): what the
-- client really did can be read after the next /reload, without a screenshot.
local function KeepLayers()
    if borrowed then ns.db.liveViewLayers = { time = date("%Y-%m-%d %H:%M:%S"), lines = Live:Describe() } end
end

local function ShowNow()
    OpenWindow()
    -- the minimap was given back meanwhile: always resize
    if Borrow() then window.side = nil end
    -- raised just now: a minimap that is not our child (MoveMinimapIntoWindow) would stay on its
    -- old level, under the window's dark background
    AnchorMinimap()
    FitWindow()
    C_Timer.After(LAYERS_KEPT_AFTER_SECONDS, KeepLayers)
end

-- In combat the protected Minimap cannot move: the window opens with a notice in its place.
local function ShowWaitingForCombatEnd()
    OpenWindow()
    FitWindow()
end

local function HideNow()
    SetTitle(WINDOW_TITLE)
    GiveBack()
    window:Hide()
end

-- The live view stands on its own inside a dungeon, else it belongs next to the open world map:
-- everywhere, or only inside a dungeon or raid when the player chose that. Not after the player
-- closed it, and not in Edit Mode.
local function IsWanted()
    if Live.closedByUser or editModeOpen or ns.Setting("liveView") == false then return false end
    if IsAlone() then return true end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return false end
    return ns.instanceID ~= nil or ns.Setting("liveViewOnlyInDungeons") ~= true
end

-- After combat: the minimap moves in if the live view is still wanted, otherwise it goes home.
local function ShowIfStillWanted()
    SetTitle(WINDOW_TITLE)
    if IsWanted() then ShowNow() else HideNow() end
end

function Live:Show()
    if not window then CreateWindow() end
    if self.closedByUser or ns.Setting("liveView") == false then return end
    SetTitle(WINDOW_TITLE)
    if not InCombatLockdown() then
        ShowNow()
        return
    end
    -- a minimap that is inside already stays; otherwise it moves in when combat ends
    if not borrowed then ShowWaitingForCombatEnd() end
    ns.AfterCombat(COMBAT_KEY_VISIBILITY, ShowIfStillWanted)
end

-- byUser: the player closed it; it stays closed until the map is reopened or a new dungeon starts.
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

local function ShowOrHideAsWanted()
    updateQueued = false
    if IsWanted() then Live:Show() else Live:Hide() end
end

-- Show or hide to match the world map, the dungeon and the options, on the next frame: several
-- reasons in one frame are one change, and the Minimap never moves inside the world map's own
-- opening (EllesmereUI's source: reparenting it in there taints the map and blocks its pins).
function Live:Update()
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0, ShowOrHideAsWanted)
end

function Live:IsShown() return window ~= nil and window:IsShown() end

-- true while the real Minimap is inside the live view
function Live:IsBorrowing() return borrowed ~= nil end

local function FrameLabel(object)
    if not object then return "none" end
    return object:GetName() or object:GetObjectType()
end

-- "DIALOG level 6 alpha 1.00 702x702": where a frame is drawn, and how.
local function LayerText(frame)
    local width, height = frame:GetSize()
    local seenAlpha = frame.GetEffectiveAlpha and frame:GetEffectiveAlpha() or frame:GetAlpha()
    return ("%s level %d alpha %.2f (seen %.2f) %dx%d"):format(frame:GetFrameStrata(), frame:GetFrameLevel(),
        frame:GetAlpha(), seenAlpha, width, height)
end

-- " (strata locked, level locked)" when another addon locked the frame's layer.
local function LockText(frame)
    local locks = {}
    if frame.HasFixedFrameStrata and frame:HasFixedFrameStrata() then locks[#locks + 1] = "strata locked" end
    if frame.HasFixedFrameLevel and frame:HasFixedFrameLevel() then locks[#locks + 1] = "level locked" end
    return #locks > 0 and (" (" .. table.concat(locks, ", ") .. ")") or ""
end

-- Every visible child and region of the minimap: what else is drawn on the live view.
local function AddDrawnOnMinimap(lines)
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if child:IsShown() and child:GetAlpha() > 0 then
            lines[#lines + 1] = ("  child %s: %s"):format(FrameLabel(child), LayerText(child))
        end
    end
    for _, region in ipairs({ Minimap:GetRegions() }) do
        if region:IsShown() and region:GetAlpha() > 0 then
            lines[#lines + 1] = ("  region %s: alpha %.2f"):format(FrameLabel(region), region:GetAlpha())
        end
    end
end

-- The layers of the open live view for the bug report: which frame is drawn over which.
function Live:Describe()
    if not borrowed then
        return { Live:IsShown() and "Live view: waiting for the end of combat" or "Live view: closed" }
    end
    local parent = Minimap:GetParent()
    local lines = {
        ("Live view: side %s, minimap %s"):format(tostring(window.side), parent == content and "is our child" or "is kept by another addon"),
        "  window: " .. LayerText(window),
        "  minimap: " .. LayerText(Minimap) .. LockText(Minimap),
        "  ground: " .. (backing:IsShown() and LayerText(backing) or "hidden"),
        ("  minimap parent %s: %s"):format(FrameLabel(parent), parent and LayerText(parent) or "-"),
    }
    AddDrawnOnMinimap(lines)
    return lines
end

-- Edit Mode works on the cluster: the minimap goes home as soon as Edit Mode opens and stays
-- there until it closes (only when the client tells us both).
local function GiveBackForEditMode()
    local editMode = EditModeManagerFrame
    if not (editMode and editMode.EnterEditMode and editMode.ExitEditMode) then return end
    hooksecurefunc(editMode, "EnterEditMode", function()
        editModeOpen = true
        Live:Hide()
    end)
    hooksecurefunc(editMode, "ExitEditMode", function()
        editModeOpen = false
        Live:Update()
    end)
end

-- Wheel zoom on the borrowed minimap, as a hook so Blizzard's own script stays untouched.
local function HookMinimapWheel()
    blizzardWheelZooms = Minimap:GetScript("OnMouseWheel") ~= nil
    Minimap:HookScript("OnMouseWheel", OnMinimapWheel)
end

-- Secure post-hooks that tell us when another addon touches the minimap; our own calls are skipped.
local function WatchMinimap()
    hooksecurefunc(Minimap, "SetPoint", function()
        if not anchoringMinimap then OnForeignChange() end
    end)
    Minimap:HookScript("OnSizeChanged", function()
        if not sizingMinimap then OnForeignChange() end
    end)
    Minimap:HookScript("OnHide", OnForeignChange)
    -- masks set by other addons (e.g. square minimap options) are remembered for the way home
    hooksecurefunc(Minimap, "SetMaskTexture", function(_, texture)
        if applyingMask then return end
        lastMaskTexture = texture
        OnForeignChange()
    end)
end

-- The dungeon map follows the floor also while the live view is closed or switched off.
local function WatchLocation()
    local watcher = CreateFrame("Frame")
    for _, event in ipairs(LOCATION_EVENTS) do watcher:RegisterEvent(event) end
    watcher:SetScript("OnEvent", FollowFloor)
end

-- The live view opens and closes with the world map.
local function FollowWorldMap()
    WorldMapFrame:HookScript("OnShow", function()
        -- a live view the player closed comes back with the next map
        Live.closedByUser = false
        Live:Update()
    end)
    WorldMapFrame:HookScript("OnHide", function() Live:Update() end)
end

ns.WatchSetting("liveView", function() Live:Update() end)
ns.WatchSetting("liveViewOnlyInDungeons", function() Live:Update() end)

-- On its own or next to the map: another place and size.
local function PlaceAndSizeAgain()
    if window then window.side = nil end
    Live:Update()
end

ns.WatchSetting("liveViewAlone", PlaceAndSizeAgain)
ns.OnInstanceChanged(function()
    Live.closedByUser = false
    PlaceAndSizeAgain()
end)

ns.OnLoad(function()
    WatchMinimap()
    HookMinimapWheel()
    GiveBackForEditMode()
    WatchLocation()
    ns.WhenWorldMapLoaded(FollowWorldMap)
    local leavingWorld = CreateFrame("Frame")
    leavingWorld:RegisterEvent("PLAYER_LEAVING_WORLD")
    leavingWorld:SetScript("OnEvent", function() Live:Hide() end)
end)
