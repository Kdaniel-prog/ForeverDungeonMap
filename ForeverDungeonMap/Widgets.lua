-- ForeverDungeonMap - shared UI pieces of the "Gilded Codex" skin (docs/ui-spec.md sections 0 and 6):
-- hover/selection look, window, panels, tabs, action buttons, round portraits and icons,
-- item and quest helpers.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L

-- The WoW Forever client only has the C_Item versions of the item API.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemQualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor

local C, TEX, ALPHA = ns.C, ns.TEX, ns.ALPHA
local W = {}
ns.W = W

-- the "?" of a boss without a portrait, relative to the portrait size
local BARE_UNKNOWN_SCALE = 0.7
-- the elite frame around a portrait, relative to the portrait size
local ELITE_FRAME_SCALE = 1.12
-- round badge: the dark disc inside the gold ring, and the icon's inset, relative to the size
local BADGE_DISC_INSET, BADGE_ICON_INSET = 0.14, 0.24
local RARE_ELITE_RANK = 2
local TAB_WIDTH, TAB_HEIGHT = 108, 30
-- rows of a choice menu (slot filter, map floor) and the menu's inner padding
local MENU_ROW_HEIGHT, MENU_INSET, MENU_GAP = 22, 4, 2
local ACTION_WIDTH, ACTION_HEIGHT = 112, 22
-- width a tab needs besides its label: with an icon (8 + 20 + 6 + 6), or the padding of a plain one
local TAB_ICON_ROOM, TAB_TEXT_ROOM = 40, 20

-- Looks of hoverable frames (spec 0.4).
local STYLES = {
    row = { fill = C.ROW, hover = C.ROW_HOVER, selected = C.ROW_SEL, pressed = C.ROW_PRESS,
        edge = C.EDGE, edgeHover = C.GOLD, edgeSelected = C.GOLD_SOFT, glow = ALPHA.rowGlow },
    card = { fill = C.INK, hover = C.INK, selected = C.ROW_SEL, pressed = C.ROW_PRESS,
        edge = C.EDGE, edgeHover = C.GOLD, edgeSelected = C.GOLD_SOFT, glow = ALPHA.cardGlow, glowTexture = TEX.SQUARE_HIGHLIGHT },
    parchment = { fill = C.PARCH_ROW, hover = C.PARCH_ROW_HOVER, selected = C.PARCH_ROW_SEL, pressed = C.ROW_PRESS,
        edge = C.PARCH_EDGE, edgeHover = C.GOLD, edgeSelected = C.GOLD_SOFT, glow = ALPHA.parchmentGlow },
    action = { fill = C.CLEAR, hover = C.CLEAR, selected = C.CLEAR, pressed = C.PRESS_SHADE,
        edge = C.EDGE, edgeHover = C.GOLD, edgeSelected = C.GOLD_SOFT },
    line = { fill = C.CLEAR, hover = C.LINE_HOVER, selected = C.LINE_SEL, pressed = C.LINE_PRESS },
}
W.STYLES = STYLES

-- Fill and border for the frame's current hover / selected / pressed state.
local function VisualColors(style, hover, selected, pressed)
    if pressed then return style.pressed, style.edgeHover end
    if selected and hover then return style.selected, style.edgeHover end
    if selected then return style.selected, style.edgeSelected end
    if hover then return style.hover, style.edgeHover end
    return style.fill, style.edge
end

-- Repaint a hoverable frame from its state; every repaint goes through here, so the hover look stays.
function W.ApplyVisual(frame)
    local style = frame.style
    if not style then return end
    local hover, selected = frame.hovered == true, frame.selected == true
    local fill, edge = VisualColors(style, hover, selected, frame.pressed == true and hover)
    if frame.SetBackdrop and style.edge then
        ns.Paint(frame, fill, edge, frame.backdropStyle)
    else
        if not frame.fillTexture then
            frame.fillTexture = frame:CreateTexture(nil, "BACKGROUND")
            frame.fillTexture:SetAllPoints()
        end
        frame.fillTexture:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
    end
    if frame.selectedBar then frame.selectedBar:SetShown(selected) end
    if frame.hoverLabel then
        local color = (hover or selected) and C.WHITE or C.GOLD
        frame.hoverLabel:SetTextColor(color[1], color[2], color[3])
    end
    frame:SetAlpha(frame.disabled and ALPHA.disabled or 1)
    if frame.OnVisual then frame:OnVisual(hover, selected) end
end

local function AddSelectedBar(frame)
    frame.selectedBar = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    frame.selectedBar:SetPoint("TOPLEFT", 3, -3)
    frame.selectedBar:SetPoint("BOTTOMLEFT", 3, 3)
    frame.selectedBar:SetWidth(3)
    frame.selectedBar:SetColorTexture(C.GOLD_SOFT[1], C.GOLD_SOFT[2], C.GOLD_SOFT[3], 1)
    frame.selectedBar:Hide()
end

local function SetSelected(frame, selected)
    frame.selected = selected and true or false
    W.ApplyVisual(frame)
end

-- Make a frame react to hover / press / selection with the gold border.
-- options: { selectedBar = true } adds the 3 px gold bar of selected rows; { backdrop = ... }.
function W.Hoverable(frame, styleName, options)
    frame.style = type(styleName) == "table" and styleName or STYLES[styleName or "row"]
    frame.backdropStyle = options and options.backdrop or frame.backdropStyle
    if frame.SetHighlightTexture and frame.style.glow then
        frame:SetHighlightTexture(frame.style.glowTexture or TEX.ROW_GLOW, "ADD")
        local highlight = frame:GetHighlightTexture()
        if highlight then highlight:SetAlpha(frame.style.glow) end
    end
    if options and options.selectedBar then AddSelectedBar(frame) end
    frame:HookScript("OnEnter", function(self) self.hovered = true; W.ApplyVisual(self) end)
    frame:HookScript("OnLeave", function(self) self.hovered = false; self.pressed = false; W.ApplyVisual(self) end)
    frame:HookScript("OnMouseDown", function(self) self.pressed = true; W.ApplyVisual(self) end)
    frame:HookScript("OnMouseUp", function(self) self.pressed = false; W.ApplyVisual(self) end)
    frame.SetSelected = SetSelected
    W.ApplyVisual(frame)
    return frame
end

function W.SetDisabled(frame, disabled)
    frame.disabled = disabled and true or false
    if frame.SetEnabled then frame:SetEnabled(not disabled) end
    W.ApplyVisual(frame)
end

-- Informational tooltip: title in gold, lines in white. Calling again replaces the text.
function W.Tooltip(frame, title, ...)
    frame.tooltipTitle, frame.tooltipLines = title, { ... }
    if frame.tooltipHooked then return end
    frame.tooltipHooked = true
    if not frame:IsMouseEnabled() then frame:EnableMouse(true) end
    frame:HookScript("OnEnter", function(self)
        if not self.tooltipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipTitle, C.GOLD[1], C.GOLD[2], C.GOLD[3])
        for _, line in ipairs(self.tooltipLines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Square icon button with the gold hover border (Track, Share, favourite star, scale +/-).
function W.IconButton(parent, size, texture, iconInset)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(size, size)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetPoint("TOPLEFT", iconInset or 3, -(iconInset or 3))
    button.Icon:SetPoint("BOTTOMRIGHT", -(iconInset or 3), iconInset or 3)
    button.Icon:SetTexture(texture)
    button.backdropStyle = ns.BACKDROP_THIN
    W.Hoverable(button, "row")
    return button
end

-- Round icon button: the icon on a dark disc inside the gold ring, the ring lights up under the
-- mouse (favourite star, hide toggle). badge.hovered is true while the mouse is on it.
function W.RoundBadge(parent, size, texture)
    local badge = CreateFrame("Button", nil, parent)
    badge:SetSize(size, size)
    badge.Disc = badge:CreateTexture(nil, "BACKGROUND")
    W.Inset(badge.Disc, size * BADGE_DISC_INSET)
    badge.Disc:SetColorTexture(C.BADGE_BG[1], C.BADGE_BG[2], C.BADGE_BG[3], C.BADGE_BG[4])
    W.Mask(badge, badge.Disc)
    badge.Icon = badge:CreateTexture(nil, "ARTWORK")
    W.Inset(badge.Icon, size * BADGE_ICON_INSET)
    badge.Icon:SetTexture(texture)
    badge.Ring = badge:CreateTexture(nil, "OVERLAY")
    badge.Ring:SetAllPoints()
    badge.Ring:SetTexture(TEX.GOLD_RING)
    badge:SetHighlightTexture(TEX.RING_HOVER, "ADD")
    badge:HookScript("OnEnter", function(self) self.hovered = true end)
    badge:HookScript("OnLeave", function(self) self.hovered = false end)
    return badge
end

-- Mark a frame tree as ours: tooltips opened from it get the solid dark backing.
function W.MarkOwned(frame)
    frame.foreverDungeonMapOwned = true
end

local function OwnedByUs(owner)
    for _ = 1, 12 do
        if not owner then return false end
        if owner.foreverDungeonMapOwned then return true end
        owner = owner.GetParent and owner:GetParent()
    end
    return false
end

-- Solid backing behind GameTooltip while its owner is one of our frames (secure post-hooks only).
function W.SetupTooltipBacking()
    if W.tooltipBacking or not GameTooltip then return end
    local backing = GameTooltip:CreateTexture(nil, "BACKGROUND", nil, -7)
    backing:SetPoint("TOPLEFT", 3, -3)
    backing:SetPoint("BOTTOMRIGHT", -3, 3)
    backing:SetColorTexture(C.TOOLTIP_BG[1], C.TOOLTIP_BG[2], C.TOOLTIP_BG[3], C.TOOLTIP_BG[4])
    backing:Hide()
    W.tooltipBacking = backing
    GameTooltip:HookScript("OnShow", function(self) backing:SetShown(OwnedByUs(self:GetOwner())) end)
    GameTooltip:HookScript("OnHide", function() backing:Hide() end)
end

-- Small icon that explains itself in a tooltip (state, faction, markers).
function W.IconWithTooltip(parent, size, layer)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.texture = holder:CreateTexture(nil, layer or "ARTWORK")
    holder.texture:SetAllPoints()
    return holder
end

-- Fill the parent with a region, `inset` pixels in from every edge.
function W.Inset(region, inset)
    region:SetPoint("TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", -inset, inset)
end

-- Gradient from dark (left) to light over a texture.
function W.ShadeHorizontal(texture)
    texture:SetTexture(TEX.WHITE)
    if texture.SetGradient and CreateColor then
        local dark, light = C.SHADE_DARK, C.SHADE_LIGHT
        texture:SetGradient("HORIZONTAL", CreateColor(dark[1], dark[2], dark[3], dark[4]), CreateColor(light[1], light[2], light[3], light[4]))
    else
        texture:SetColorTexture(C.SHADE_FLAT[1], C.SHADE_FLAT[2], C.SHADE_FLAT[3], C.SHADE_FLAT[4])
    end
end

-- Vertical gradient from `bottomAlpha` to `topAlpha` black.
function W.ShadeVertical(texture, bottomAlpha, topAlpha)
    texture:SetTexture(TEX.WHITE)
    if texture.SetGradient and CreateColor then
        local black = C.BLACK
        texture:SetGradient("VERTICAL", CreateColor(black[1], black[2], black[3], bottomAlpha), CreateColor(black[1], black[2], black[3], topAlpha))
    else
        texture:SetColorTexture(0, 0, 0, (bottomAlpha + topAlpha) / 2)
    end
end

local HEADER_ART_INSET = 3

-- Shared with the journal's header (Journal.lua): a dungeon art strip under a dark gradient,
-- inset inside the panel's border. Returns the art texture for W.SetHeaderArt.
function W.CreateHeaderArt(panel)
    local art = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    W.Inset(art, HEADER_ART_INSET)
    art:SetAlpha(ns.ALPHA.headerArt)
    local shade = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    shade:SetAllPoints(art)
    W.ShadeHorizontal(shade)
    return art
end

-- Show a dungeon's header art (ns.ART[instanceID].bg); hidden when it has none.
function W.SetHeaderArt(art, instanceID)
    local dungeonArt = ns.ART and ns.ART[instanceID]
    local texture = dungeonArt and dungeonArt.bg
    art:SetShown(texture ~= nil)
    if texture then
        art:SetTexture(texture)
        art:SetTexCoord(unpack(dungeonArt.bgCoords or TEX.FULL_COORDS))
    end
end

-- Header band of a dungeon: art strip, round icon, its name in the title font and a sub-line
-- (head.Art, head.Icon, head.Name, head.Sub); W.SetDungeonHeader fills it.
function W.DungeonHeader(parent, iconSize, iconLeft)
    local head = W.Panel(parent)
    head.Art = W.CreateHeaderArt(head)
    head.Icon = W.CreateRoundIcon(head, iconSize)
    head.Icon:SetPoint("LEFT", iconLeft, 0)
    head.Name = head:CreateFontString(nil, "OVERLAY", ns.Font("title"))
    head.Name:SetPoint("TOPLEFT", iconLeft + iconSize + 8, -12)
    head.Name:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
    head.Name:SetWordWrap(false)
    head.Sub = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head.Sub:SetPoint("TOPLEFT", head.Name, "BOTTOMLEFT", 0, -4)
    return head
end

function W.SetDungeonHeader(head, instanceID, name, subText)
    W.SetHeaderArt(head.Art, instanceID)
    W.SetDungeonIcon(head.Icon, instanceID)
    head.Name:SetText(name)
    head.Sub:SetText(subText or "")
end

-- windows made movable, for W.ResetWindowPositions
local movableWindows = {}

-- Put a window where the player dragged it; false when it was never moved.
function W.RestorePosition(window)
    local position = ns.db.windowPositions[window.positionKey]
    if not position then return false end
    window:ClearAllPoints()
    window:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    return true
end

-- The window's spot on the screen (point, x, y) unless the player moved it somewhere else.
function W.PlaceWindow(window, point, x, y)
    window.defaultPlace = { point, x or 0, y or 0 }
    if W.RestorePosition(window) then return end
    window:ClearAllPoints()
    window:SetPoint(point, x or 0, y or 0)
end

local function OnWindowDragStart(window)
    window.isMoving = not window.canMove or window.canMove()
    if window.isMoving then window:StartMoving() end
end

-- A drag that was refused left the window on its anchor: there is no new spot to keep.
local function OnWindowDragStop(window)
    if not window.isMoving then return end
    window.isMoving = false
    window:StopMovingOrSizing()
    -- the spot is kept in our saved settings, not in the client's own layout cache
    window:SetUserPlaced(false)
    local point, _, relativePoint, x, y = window:GetPoint(1)
    ns.db.windowPositions[window.positionKey] = { point, relativePoint, x, y }
end

-- Drag the window by any part of it that is not a control; the spot is kept across sessions
-- under `key` (ns.db.windowPositions). canMove (optional): a drag is refused while it returns false.
function W.MakeMovable(window, key, canMove)
    window.positionKey = key
    window.canMove = canMove
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", OnWindowDragStart)
    window:SetScript("OnDragStop", OnWindowDragStop)
    movableWindows[#movableWindows + 1] = window
end

-- Dragging `handle`, a frame inside a movable window, moves the window.
function W.AddDragHandle(window, handle)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() OnWindowDragStart(window) end)
    handle:SetScript("OnDragStop", function() OnWindowDragStop(window) end)
end

-- Forget every dragged spot; windows with a fixed default spot go back to it at once.
function W.ResetWindowPositions()
    wipe(ns.db.windowPositions)
    for _, window in ipairs(movableWindows) do
        if window.defaultPlace then W.PlaceWindow(window, unpack(window.defaultPlace)) end
    end
end

-- Gilded dialog window: gold border, dark rock background, title ribbon, close button;
-- movable, its spot kept under its name.
function W.Window(name, width, height, title)
    local window = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    window:SetSize(width, height)
    window:SetBackdrop(ns.BACKDROP_WINDOW)
    window.rock = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    window.rock:SetPoint("TOPLEFT", 11, -11)
    window.rock:SetPoint("BOTTOMRIGHT", -11, 11)
    window.rock:SetTexture(TEX.ROCK, "REPEAT", "REPEAT")
    window.rock:SetHorizTile(true)
    window.rock:SetVertTile(true)
    window.rock:SetVertexColor(C.ROCK_TINT[1], C.ROCK_TINT[2], C.ROCK_TINT[3])
    window.ribbon = window:CreateTexture(nil, "ARTWORK")
    window.ribbon:SetSize(300, 64)
    window.ribbon:SetPoint("TOP", 0, 13)
    window.ribbon:SetTexture(TEX.RIBBON)
    window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.Title:SetPoint("TOP", window.ribbon, "TOP", 0, -14)
    window.Title:SetText(title or "")
    window.CloseButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.CloseButton:SetPoint("TOPRIGHT", -5, -5)
    -- our windows are not UI panels: a plain Hide keeps the secure panel manager out of it
    window.CloseButton:SetScript("OnClick", function(button) button:GetParent():Hide() end)
    window:SetClampedToScreen(true)
    W.MakeMovable(window, name)
    return window
end

-- text boxes: padding inside the frame, room for the scroll bar
local TEXT_BOX_PADDING, TEXT_BOX_SCROLL_BAR = 8, 22
-- copyable text window: inset of the box, its top under the title ribbon
local TEXT_WINDOW_INSET, TEXT_WINDOW_TOP = 18, -44

-- Framed, scrolling multi-line text box (box.EditBox). options = { readOnly, placeholder }:
-- a read-only box can be selected and copied but keeps its text; a click anywhere in the frame
-- puts the cursor in it; the placeholder shows while the box is empty.
function W.TextBox(parent, options)
    options = options or {}
    local box = W.Panel(parent, options.readOnly and C.INK or C.TOOLTIP_BG, options.readOnly and C.EDGE or C.EDGE_PANEL)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", TEXT_BOX_PADDING, -TEXT_BOX_PADDING)
    scroll:SetPoint("BOTTOMRIGHT", -TEXT_BOX_SCROLL_BAR, TEXT_BOX_PADDING)
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ns.Font("GameFontHighlightSmall"))
    local color = options.readOnly and C.MUTED or C.TEXT
    editBox:SetTextColor(color[1], color[2], color[3])
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editBox)
    box:SetScript("OnSizeChanged", function(_, width) editBox:SetWidth(width - TEXT_BOX_PADDING - TEXT_BOX_SCROLL_BAR) end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    box.EditBox = editBox
    if options.placeholder then
        box.Placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        box.Placeholder:SetPoint("TOPLEFT", TEXT_BOX_PADDING + 2, -TEXT_BOX_PADDING - 1)
        box.Placeholder:SetText(options.placeholder)
    end
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if options.readOnly and userInput then self:SetText(box.fixedText or "") end
        if box.Placeholder then box.Placeholder:SetShown(self:GetText() == "") end
    end)
    return box
end

-- Text of a W.TextBox (a read-only one keeps exactly this).
function W.SetBoxText(box, text)
    box.fixedText = text
    box.EditBox:SetText(text)
end

-- Window with one read-only text box (window.Box, window.EditBox); Escape closes it.
function W.TextWindow(name, width, height, title)
    local window = W.Window(name, width, height, title)
    W.PlaceWindow(window, "CENTER")
    -- one layer above the journal (DIALOG, raised on every click), or it opens hidden behind it
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetToplevel(true)
    window.Box = W.TextBox(window, { readOnly = true })
    window.Box:SetPoint("TOPLEFT", TEXT_WINDOW_INSET, TEXT_WINDOW_TOP)
    window.Box:SetPoint("BOTTOMRIGHT", -TEXT_WINDOW_INSET, TEXT_WINDOW_INSET)
    window.EditBox = window.Box.EditBox
    window.EditBox:SetScript("OnEscapePressed", function() window:Hide() end)
    tinsert(UISpecialFrames, name)
    return window
end

-- Fill a W.TextWindow and show it with all text selected for Ctrl+C.
function W.ShowText(window, text)
    W.SetBoxText(window.Box, text)
    window:Show()
    window:Raise()
    window.EditBox:SetFocus()
    window.EditBox:HighlightText()
end

-- Inset panel (ink fill, bronze edge).
function W.Panel(parent, fill, edge)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.Paint(panel, fill or C.INK, edge or C.EDGE_PANEL)
    return panel
end

-- Small movable window (live view): panel skin, title and close button.
function W.CreateWindow(name, parent, title)
    local window = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    ns.Paint(window, C.INK, C.EDGE_PANEL)
    window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.Title:SetPoint("TOP", 0, -7)
    window.Title:SetText(title or "")
    window.CloseButton = CreateFrame("Button", name and (name .. "CloseButton") or nil, window, "UIPanelCloseButton")
    window.CloseButton:SetPoint("TOPRIGHT", 2, 2)
    -- our windows are not UI panels: a plain Hide keeps the secure panel manager out of it
    window.CloseButton:SetScript("OnClick", function(button) button:GetParent():Hide() end)
    window:SetClampedToScreen(true)
    return window
end

-- Gold hairline divider texture.
function W.Divider(parent, layer)
    local divider = parent:CreateTexture(nil, layer or "ARTWORK")
    divider:SetTexture(TEX.DIVIDER)
    divider:SetHeight(4)
    return divider
end

-- Gilded tab / chip: icon + label, gold hover border, selected look with an underline.
function W.Tab(parent, text, icon, width, height)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    height = height or TAB_HEIGHT
    tab:SetSize(width or TAB_WIDTH, height)
    tab.Label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.Label:SetWordWrap(false)
    if icon then
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetSize(math.min(20, height - 8), math.min(20, height - 8))
        tab.Icon:SetPoint("LEFT", 8, 0)
        tab.Icon:SetTexture(icon)
        tab.Label:SetPoint("LEFT", tab.Icon, "RIGHT", 6, 0)
        tab.Label:SetPoint("RIGHT", -6, 0)
        tab.Label:SetJustifyH("LEFT")
    else
        tab.Label:SetPoint("CENTER")
    end
    tab.Label:SetText(text or "")
    tab.Underline = tab:CreateTexture(nil, "OVERLAY")
    tab.Underline:SetPoint("BOTTOMLEFT", 5, 4)
    tab.Underline:SetPoint("BOTTOMRIGHT", -5, 4)
    tab.Underline:SetHeight(2)
    tab.Underline:SetColorTexture(C.GOLD_SOFT[1], C.GOLD_SOFT[2], C.GOLD_SOFT[3], 0.9)
    tab.Underline:Hide()
    tab.hoverLabel = tab.Label
    tab.OnVisual = function(self, _, selected) self.Underline:SetShown(selected) end
    W.Hoverable(tab, "row")
    return tab
end

-- Make a tab as wide as its label (plus room for its icon).
function W.FitTab(tab)
    tab:SetWidth(tab.Label:GetStringWidth() + (tab.Icon and TAB_ICON_ROOM or TAB_TEXT_ROOM))
end

-- Icon-only tab (no room for the label): the icon centred; false puts icon and label back.
function W.SetTabCompact(tab, compact)
    if not tab.Icon then return end
    tab.Label:SetShown(not compact)
    tab.Icon:ClearAllPoints()
    if compact then tab.Icon:SetPoint("CENTER") else tab.Icon:SetPoint("LEFT", 8, 0) end
end

local ChoiceMenu = {}

function ChoiceMenu:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = W.Tab(self, "", nil, self.menuWidth - 2 * MENU_INSET, MENU_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", MENU_INSET, -MENU_INSET - (index - 1) * MENU_ROW_HEIGHT)
    self.rows[index] = row
    return row
end

-- Open under `anchor`, or close when open. choices = { { label, selected }, ... }; onPick(index).
function ChoiceMenu:Toggle(anchor, choices, onPick)
    if self:IsShown() then
        self:Hide()
        return
    end
    for index, choice in ipairs(choices) do
        local row = self:Row(index)
        row.Label:SetText(choice.label)
        row:SetSelected(choice.selected and true or false)
        row:SetScript("OnClick", function()
            self:Hide()
            onPick(index)
        end)
        row:Show()
    end
    for index = #choices + 1, #self.rows do self.rows[index]:Hide() end
    self:SetSize(self.menuWidth, #choices * MENU_ROW_HEIGHT + 2 * MENU_INSET)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -MENU_GAP)
    self:Show()
end

-- Small pick list that opens under a button (loot slot filter, map floor).
function W.CreateChoiceMenu(parent, width)
    local menu = W.Panel(parent)
    Mixin(menu, ChoiceMenu)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu.menuWidth, menu.rows = width, {}
    menu:Hide()
    return menu
end

-- Gilded dropdown button: label and a small arrow on the right; the click opens a menu.
function W.DropdownButton(parent, icon, width, height)
    local button = W.Tab(parent, "", icon, width, height)
    button.Arrow = button:CreateTexture(nil, "OVERLAY")
    button.Arrow:SetSize(12, 12)
    button.Arrow:SetPoint("RIGHT", -6, 0)
    button.Arrow:SetTexture(TEX.DROPDOWN_ARROW)
    return button
end

-- Gold action button ("Show on Map", "Show Turn In" ...).
function W.ActionButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or ACTION_WIDTH, height or ACTION_HEIGHT)
    button:SetNormalTexture(TEX.ACTION_UP)
    button:SetPushedTexture(TEX.ACTION_DOWN)
    button:SetDisabledTexture(TEX.ACTION_DISABLED)
    for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture() }) do
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", 2, -2)
        texture:SetPoint("BOTTOMRIGHT", -2, 2)
        texture:SetTexCoord(unpack(TEX.ACTION_COORDS))
    end
    button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.Label:SetPoint("CENTER", 0, 0)
    button.Label:SetText(text or "")
    button.Label:SetWordWrap(false)
    button.backdropStyle = ns.BACKDROP_THIN
    W.Hoverable(button, "action")
    return button
end

-- Circle mask on a texture (portraits, round icons).
function W.Mask(owner, texture)
    if not owner.CreateMaskTexture then return end
    local mask = owner:CreateMaskTexture()
    mask:SetAllPoints(texture)
    mask:SetTexture(TEX.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:AddMaskTexture(mask)
    return mask
end

-- Round level badge on the lower left of a portrait.
local function AddLevelBadge(portrait, size)
    local badge = CreateFrame("Frame", nil, portrait)
    badge:SetSize(size, size)
    badge:SetPoint("CENTER", portrait, "BOTTOMLEFT", 6, 4)
    badge:SetFrameLevel(portrait:GetFrameLevel() + 3)
    badge.Background = badge:CreateTexture(nil, "ARTWORK")
    badge.Background:SetPoint("TOPLEFT", 2, -2)
    badge.Background:SetPoint("BOTTOMRIGHT", -2, 2)
    badge.Background:SetColorTexture(C.BADGE_BG[1], C.BADGE_BG[2], C.BADGE_BG[3], 1)
    W.Mask(badge, badge.Background)
    badge.Ring = badge:CreateTexture(nil, "OVERLAY")
    badge.Ring:SetAllPoints()
    badge.Ring:SetTexture(TEX.GOLD_RING)
    badge.Text = badge:CreateFontString(nil, "OVERLAY", ns.Font("numberSmall"))
    badge.Text:SetPoint("CENTER", 0, 0)
    portrait.LevelBadge = badge
end

-- Square order number on the lower right (map pins).
local function AddOrderBadge(portrait)
    local badge = CreateFrame("Frame", nil, portrait, "BackdropTemplate")
    badge:SetSize(16, 16)
    badge:SetPoint("BOTTOMRIGHT", 3, -3)
    badge:SetFrameLevel(portrait:GetFrameLevel() + 4)
    badge:SetBackdrop(ns.BACKDROP_LINE)
    badge:SetBackdropColor(C.ORDER_BG[1], C.ORDER_BG[2], C.ORDER_BG[3], 1)
    badge:SetBackdropBorderColor(C.GOLD_SOFT[1], C.GOLD_SOFT[2], C.GOLD_SOFT[3], 1)
    badge.Text = badge:CreateFontString(nil, "OVERLAY", ns.Font("numberSmall"))
    badge.Text:SetPoint("CENTER", 0, 0)
    portrait.Badge = badge
end

-- The "?" of a boss without a portrait (outlined) and the elite frame: a ring around the portrait.
local function AddUnknownMark(portrait, size)
    portrait.Unknown = portrait:CreateFontString(nil, "OVERLAY", size >= 40 and "GameFontNormalHuge" or "GameFontNormal")
    portrait.Unknown:SetPoint("CENTER")
    portrait.Unknown:SetText("?")
    portrait.Unknown:Hide()
    local font = portrait.Unknown:GetFont()
    portrait.Unknown:SetFont(font, size * BARE_UNKNOWN_SCALE, "THICKOUTLINE")
    portrait.EliteFrame = portrait:CreateTexture(nil, "OVERLAY")
    portrait.EliteFrame:SetSize(size * ELITE_FRAME_SCALE, size * ELITE_FRAME_SCALE)
    portrait.EliteFrame:SetPoint("CENTER")
    portrait.EliteFrame:SetTexture(TEX.GOLD_RING)
    portrait.EliteFrame:Hide()
end

-- True for a rare elite (silver frame); bosses and other elites get the gold one.
local function IsRareElite(boss, instanceID)
    if boss.rare then return true end
    local level = instanceID and ns.BossLevel and ns.BossLevel(instanceID, boss.name)
    return level ~= nil and level[3] == RARE_ELITE_RANK
end

-- The elite frame: around a "?" portrait, and around every portrait made with
-- { eliteFrame = true } (map pins). Gold, silver for rare elites, grey once the boss is dead.
-- Nothing is drawn over the portrait itself.
local function SetEliteLook(portrait, boss, unknown, instanceID, killed)
    local frame = portrait.EliteFrame
    frame:SetShown(unknown or portrait.alwaysElite)
    local silver = IsRareElite(boss, instanceID)
    frame:SetDesaturated((silver or killed) and true or false)
    local tint = killed and C.ELITE_FRAME_KILLED or silver and C.ELITE_FRAME_SILVER or C.WHITE
    frame:SetVertexColor(tint[1], tint[2], tint[3], 1)
end

-- Round boss portrait without a ring (its art has a dark fill that hides the portrait).
-- options: { levelBadge = size, orderBadge = true, mouse = true, eliteFrame = true }
function W.CreatePortrait(parent, size, options)
    options = options or {}
    local portrait = CreateFrame("Button", nil, parent)
    portrait:SetSize(size, size)
    portrait.alwaysElite = options.eliteFrame and true or false
    portrait.Portrait = portrait:CreateTexture(nil, "ARTWORK")
    portrait.Portrait:SetAllPoints()
    W.Mask(portrait, portrait.Portrait)
    AddUnknownMark(portrait, size)
    portrait.Dead = portrait:CreateTexture(nil, "OVERLAY", nil, 2)
    portrait.Dead:SetPoint("CENTER")
    portrait.Dead:SetSize(size * 0.7, size * 0.7)
    portrait.Dead:SetTexture(TEX.CROSS)
    portrait.Dead:Hide()
    if options.levelBadge then AddLevelBadge(portrait, options.levelBadge) end
    if options.orderBadge then AddOrderBadge(portrait) end
    if not options.mouse then portrait:EnableMouse(false) end
    return portrait
end

-- CreatureDisplayID of a boss portrait: the boss record, the creature table of rares
-- (Data/DungeonSpots.lua), then the WoW Forever data.
function W.BossDisplay(boss)
    if boss.display then return boss.display end
    local byCreature = ns.CREATURE_DISPLAY and boss.npcID and ns.CREATURE_DISPLAY[boss.npcID]
    if byCreature then return byCreature end
    local forever = ns.FOREVER
    return forever and type(forever.bossDisplay) == "table" and forever.bossDisplay[boss.name] or nil
end

local function SetLevelBadge(portrait, boss, instanceID)
    local badge = portrait.LevelBadge
    if not badge then return end
    local level = instanceID and ns.BossLevel and ns.BossLevel(instanceID, boss.name)
    local value = level and (level[2] or level[1])
    if value then
        badge.Text:SetText(value)
        badge.Text:SetTextColor(ns.LevelColor(value))
        badge:Show()
    else
        badge:Hide()
    end
end

-- Creature portrait (or the Encounter Journal placeholder with "?"), defeated look, level badge.
function W.SetPortrait(portrait, boss, killed, instanceID)
    local display = W.BossDisplay(boss)
    local ok = display and SetPortraitTextureFromCreatureDisplayID
        and pcall(SetPortraitTextureFromCreatureDisplayID, portrait.Portrait, display)
    if ok then
        portrait.Portrait:SetTexCoord(unpack(TEX.FULL_COORDS))
        portrait.Unknown:Hide()
    else
        portrait.Portrait:SetTexture(TEX.BOSS_DEFAULT)
        portrait.Portrait:SetTexCoord(unpack(TEX.BOSS_DEFAULT_COORDS))
        portrait.Unknown:Show()
    end
    SetEliteLook(portrait, boss, not ok, instanceID, killed)
    portrait.Portrait:SetDesaturated(killed and true or false)
    local shade = killed and 0.55 or 1
    portrait.Portrait:SetVertexColor(shade, shade, shade)
    portrait.Dead:SetShown(killed and true or false)
    SetLevelBadge(portrait, boss, instanceID)
end

local RANKS = { L["Elite"], L["Rare Elite"], L["Boss"] }

-- "Level 21 Elite", or nil when the level is unknown.
function W.BossLevelText(instanceID, boss)
    local level = ns.BossLevel and ns.BossLevel(instanceID, boss.name)
    if not level then return nil end
    local minimum, maximum, rank = level[1], level[2], level[3]
    local text = (minimum and maximum and minimum ~= maximum) and (minimum .. "-" .. maximum) or tostring(maximum or minimum)
    return L["Level %s%s"]:format(text, RANKS[rank or 0] and (" " .. RANKS[rank]) or "")
end

-- Round dungeon icon (LFG icon, or a crop of the loading screen for Forever dungeons).
function W.CreateRoundIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetAllPoints()
    W.Mask(frame, frame.Icon)
    return frame
end

-- Put a dungeon's round icon on frame.Icon.
function W.SetDungeonIcon(frame, instanceID)
    local art = ns.ART and ns.ART[instanceID]
    if art and art.icon then
        frame.Icon:SetTexture(art.icon)
        frame.Icon:SetTexCoord(unpack(art.iconCoords or TEX.SQUARE_CROP_COORDS))
        return
    end
    local icon = ns.ICONS and ns.ICONS[instanceID]
    frame.Icon:SetTexture(icon and (TEX.LFG_PREFIX .. icon) or TEX.LFG_DUNGEON)
    frame.Icon:SetTexCoord(unpack(TEX.FULL_COORDS))
end

-- Dungeon marker icon: the "Dungeon" atlas when the client has it, else the LFG icon.
function W.SetDungeonMarker(texture)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(TEX.DUNGEON_ATLAS) then
        texture:SetAtlas(TEX.DUNGEON_ATLAS)
    else
        texture:SetTexture(TEX.LFG_DUNGEON)
    end
end

-- Item quality colour: r, g, b.
function W.QualityColor(quality)
    quality = quality or 1
    if GetItemQualityColor then
        local ok, red, green, blue = pcall(GetItemQualityColor, quality)
        if ok and red then return red, green, blue end
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

-- name, link, quality, icon, "Slot, Type" (name is nil until the client has the item cached).
function W.ItemData(itemID)
    local name, link, quality, _, _, itemType, subType, _, equipLocation, icon
    if GetItemInfo then name, link, quality, _, _, itemType, subType, _, equipLocation, icon = GetItemInfo(itemID) end
    if not icon and GetItemInfoInstant then
        local _, instantType, instantSubType, instantLocation, instantIcon = GetItemInfoInstant(itemID)
        icon, equipLocation = instantIcon, equipLocation or instantLocation
        itemType, subType = itemType or instantType, subType or instantSubType
    end
    local slot = equipLocation and equipLocation ~= "" and _G[equipLocation] or nil
    local description = (slot and subType) and (slot .. ", " .. subType) or slot or subType or itemType or ""
    return name, link, quality, icon, description
end

-- Item class, subclass and equip slot (instant, no item data needed).
function W.ItemType(itemID)
    if not GetItemInfoInstant then return nil end
    local _, _, _, equipLocation, _, classID, subClassID = GetItemInfoInstant(itemID)
    return classID, subClassID, equipLocation
end

-- false when the player's class cannot wear / wield the item; true otherwise (also when unknown).
function W.CanUseItem(itemID)
    local classID, subClassID = W.ItemType(itemID)
    local _, class = UnitClass("player")
    local gear = ns.CLASS_GEAR and ns.CLASS_GEAR[class]
    if not (gear and classID and subClassID) then return true end
    if classID == ns.ITEM_CLASS_ARMOR then return gear.armor[subClassID] == true end
    if classID == ns.ITEM_CLASS_WEAPON then return gear.weapon[subClassID] == true end
    return true
end

local TITLE_ICON_SIZE = 14
-- Pixel size of the class icon sheet (inline texture crops are given in pixels).
local CLASS_SHEET_SIZE = 256

-- Inline "|T...|t" string of a class icon.
function W.ClassIconString(class, size)
    local coords = (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or TEX.CLASS_COORDS[class] or TEX.FULL_COORDS
    local function Pixel(value) return math.floor(value * CLASS_SHEET_SIZE + 0.5) end
    return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t"):format(TEX.CLASS_ICONS, size, size, CLASS_SHEET_SIZE, CLASS_SHEET_SIZE,
        Pixel(coords[1]), Pixel(coords[2]), Pixel(coords[3]), Pixel(coords[4]))
end

-- Class icon on a texture (Blizzard's crop table, our copy as fallback).
function W.SetClassIcon(texture, class)
    local coords = (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or TEX.CLASS_COORDS[class]
    texture:SetTexture(TEX.CLASS_ICONS)
    texture:SetTexCoord(unpack(coords or TEX.FULL_COORDS))
end

function W.RequestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

function W.ShowItemTooltip(owner, itemID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
    if IsShiftKeyDown and IsShiftKeyDown() and GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem) end
end

-- Shift-click: link in chat; Ctrl-click: try on.
function W.ItemClick(itemID)
    if not itemID then return end
    local _, link = W.ItemData(itemID)
    if not link then return end
    if IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    elseif IsModifiedClick("DRESSUP") and DressUpItemLink then
        DressUpItemLink(link)
    end
end

function W.SetFactionIcon(texture, faction)
    texture:SetTexture(faction == "Horde" and TEX.HORDE or TEX.ALLIANCE)
    texture:SetTexCoord(unpack(TEX.FULL_COORDS))
end

-- Factions a quest is for.
function W.QuestFactions(quest)
    if quest.faction == "Alliance" or quest.faction == "Horde" then return { quest.faction } end
    return { "Alliance", "Horde" }
end

local function IsDone(questID)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(questID) and true or false end
    return false
end
W.IsQuestDone = IsDone

local function InLog(questID)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil end
    if GetQuestLogIndexByID then return (GetQuestLogIndexByID(questID) or 0) > 0 end
    return false
end
W.InLog = InLog

local function LogIndex(questID)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(questID) end
    if GetQuestLogIndexByID then
        local index = GetQuestLogIndexByID(questID)
        return index and index > 0 and index or nil
    end
end

-- Call the first API that exists (C_QuestLog by quest ID, else the old global by log index).
local function CallQuestApi(modernName, legacyName, questID)
    local modern = C_QuestLog and C_QuestLog[modernName]
    if modern then return pcall(modern, questID) end
    local legacy, index = _G[legacyName], LogIndex(questID)
    if legacy and index then return pcall(legacy, index) end
    return false
end

function W.IsQuestTracked(questID)
    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        local ok, watchType = pcall(C_QuestLog.GetQuestWatchType, questID)
        return ok and watchType ~= nil
    end
    local index = LogIndex(questID)
    return index ~= nil and IsQuestWatched ~= nil and IsQuestWatched(index) and true or false
end

-- Track / untrack a quest of the log in the objective tracker.
function W.ToggleQuestTracking(questID)
    if not InLog(questID) then return end
    if W.IsQuestTracked(questID) then
        CallQuestApi("RemoveQuestWatch", "RemoveQuestWatch", questID)
    else
        CallQuestApi("AddQuestWatch", "AddQuestWatch", questID)
    end
end

-- true, or false and why the quest cannot be shared now.
function W.CanShareQuest(questID)
    if not InLog(questID) then return false, L["Only quests in your quest log can be shared."] end
    if not (IsInGroup and IsInGroup()) then return false, L["You are not in a group."] end
    if InCombatLockdown() then return false, L["Not in combat."] end
    if C_QuestLog and C_QuestLog.IsPushableQuest then
        local ok, pushable = pcall(C_QuestLog.IsPushableQuest, questID)
        if ok and not pushable then return false, L["This quest cannot be shared."] end
    end
    return QuestLogPushQuest ~= nil, L["Sharing is not available on this client."]
end

-- Share a quest with the group: select its log entry, then push it.
function W.ShareQuest(questID)
    if not W.CanShareQuest(questID) then return end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, questID)
    elseif SelectQuestLogEntry and LogIndex(questID) then
        pcall(SelectQuestLogEntry, LogIndex(questID))
    end
    pcall(QuestLogPushQuest)
end

-- Objectives of a quest in the log: { { text, fulfilled, required, finished } }, empty otherwise.
function W.QuestObjectives(questID)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives and InLog(questID)) then return {} end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    return ok and type(objectives) == "table" and objectives or {}
end

-- fulfilled, required summed over the counted objectives (nil when there are none).
function W.QuestProgress(questID)
    local fulfilled, required = 0, 0
    for _, objective in ipairs(W.QuestObjectives(questID)) do
        if type(objective.numRequired) == "number" and objective.numRequired > 0 then
            fulfilled = fulfilled + math.min(objective.numFulfilled or 0, objective.numRequired)
            required = required + objective.numRequired
        end
    end
    if required == 0 then return nil end
    return fulfilled, required
end

local function ReadyForTurnIn(questID)
    for _, name in ipairs({ "ReadyForTurnIn", "IsComplete" }) do
        local api = C_QuestLog and C_QuestLog[name]
        if api then
            local ok, ready = pcall(api, questID)
            if ok then return ready and true or false end
        end
    end
    return false
end

local function OtherFactionOrClass(quest)
    if (quest.faction == "Alliance" or quest.faction == "Horde") and quest.faction ~= UnitFactionGroup("player") then return true end
    if quest.classes then
        local _, class = UnitClass("player")
        return not tContains(quest.classes, class)
    end
    return false
end

-- "ready" | "log" | "avail" | "locked" | "done" | "other"
function W.QuestState(quest)
    if OtherFactionOrClass(quest) then return "other" end
    if IsDone(quest.id) then return "done" end
    if InLog(quest.id) then return ReadyForTurnIn(quest.id) and "ready" or "log" end
    for _, previousID in ipairs(quest.pre or {}) do
        if not IsDone(previousID) then return "locked" end
    end
    return "avail"
end

W.STATE_ORDER = { ready = 1, log = 2, avail = 3, locked = 4, done = 5, other = 6 }

-- State icon, its words (for tooltips), alpha, desaturated.
local STATES = {
    ready = { TEX.QUEST_ACTIVE, L["Ready to turn in"], 1, false },
    log = { TEX.QUEST_INCOMPLETE, L["In your quest log"], 1, false },
    avail = { TEX.QUEST_AVAILABLE, L["Available"], 1, false },
    locked = { TEX.QUEST_AVAILABLE, L["Needs the previous quests"], 0.5, true },
    done = { TEX.QUEST_AVAILABLE, L["Completed"], 0.6, false },
    other = { TEX.QUEST_AVAILABLE, L["Other faction or class"], 0.5, true },
}
-- Icon texture of a quest state.
function W.StateTexture(state)
    return (STATES[state] or STATES.avail)[1]
end

function W.SetStateIcon(texture, state)
    local look = STATES[state] or STATES.avail
    texture:SetTexture(look[1])
    texture:SetAlpha(look[3])
    texture:SetDesaturated(look[4])
    texture:Show()
end
function W.StateLabel(state) return STATES[state] and STATES[state][2] or "" end

-- Tick for a completed quest, grey "?" when it is in the log, cross otherwise; with the words for a tooltip.
function W.ProgressMark(questID)
    if IsDone(questID) then return TEX.TICK, L["Completed"] end
    if InLog(questID) then return TEX.QUEST_INCOMPLETE, L["In your quest log"] end
    return TEX.CROSS, L["Not completed yet"]
end

function W.QuestInfo(quest) return ns.QUEST_INFO and ns.QUEST_INFO[quest.id] end

function W.QuestLevel(quest)
    local info = W.QuestInfo(quest)
    return (info and info.lvl) or quest.level
end

function W.QuestRequiredLevel(quest)
    local info = W.QuestInfo(quest)
    return info and info.req
end

-- "Available from Level 13" (or the quest level when the minimum is unknown), required level.
function W.QuestLevelText(quest)
    local required = W.QuestRequiredLevel(quest)
    if required then return L["Available from Level %d"]:format(required), required end
    local level = W.QuestLevel(quest)
    return level and L["Quest level %s"]:format(tostring(level)) or "", nil
end

-- The quest record of an ID (from any dungeon) or a stub with its name.
function W.QuestByID(questID)
    for _, quests in pairs(ns.QUESTS) do
        for _, quest in ipairs(quests) do
            if quest.id == questID then return quest end
        end
    end
    return { id = questID, name = ns.QUEST_NAMES and ns.QUEST_NAMES[questID] or L["Quest %d"]:format(questID), stub = true }
end

function W.QuestName(questID) return W.QuestByID(questID).name end

-- One quest's own chain: prerequisites, the quest, then its follow-ups.
local function OwnChain(quest)
    local steps = {}
    for _, questID in ipairs(quest.pre or {}) do steps[#steps + 1] = questID end
    steps[#steps + 1] = quest.id
    for _, questID in ipairs(quest.next or {}) do steps[#steps + 1] = questID end
    return steps
end

-- questID -> the longest chain it is a step of; the data never changes after loading, so built once.
local chainOfQuest
local function BuildChains()
    chainOfQuest = {}
    for _, quests in pairs(ns.QUESTS) do
        for _, quest in ipairs(quests) do
            local steps = OwnChain(quest)
            for _, questID in ipairs(steps) do
                local known = chainOfQuest[questID]
                if not known or #known < #steps then chainOfQuest[questID] = steps end
            end
        end
    end
end

-- Every step of the chain `quest` belongs to, in order (just the quest itself when it has none).
-- Quests of one chain share the same table, so it can be used as a key.
function W.QuestChain(quest)
    if not chainOfQuest then BuildChains() end
    return chainOfQuest[quest.id] or OwnChain(quest)
end

-- Start / finish location: { kind, name, map, x, y, inside, dropBy, itemID }. Sources in order:
-- QUEST_INFO (with Data/Forever.lua merged in), learned in play, the quest giver of Generated.lua.
function W.Location(quest, which, instanceID)
    local info = W.QuestInfo(quest)
    local location = info and info[which]
    if location then return location end
    if ns.Learn then location = ns.Learn.Location(quest.id, which) end
    if location then return location end
    if which ~= "start" then return nil end
    local dungeon = instanceID and ns.GetDungeon(instanceID)
    if quest.npc then
        return { kind = "npc", name = quest.npc, map = quest.map, x = quest.x, y = quest.y,
            inside = quest.inside and dungeon and dungeon.name or nil }
    elseif quest.drop then
        return { kind = "item", name = quest.name, inside = dungeon and dungeon.name }
    end
end

local UNKNOWN_SOURCE = { item = L["an item found in the dungeon"], object = L["an object"] }

-- "Name\nZone (x, y)\nDrops from Boss".
function W.LocationText(location)
    if not location then return nil end
    local who = location.name or UNKNOWN_SOURCE[location.kind] or L["unknown"]
    if location.kind == "item" and location.name then who = L["Item: %s"]:format(who)
    elseif location.kind == "object" and location.name then who = L["Object: %s"]:format(who) end
    local where
    if location.inside then
        where = L["inside %s"]:format(location.inside)
    elseif location.map then
        local info = C_Map.GetMapInfo(location.map)
        where = info and info.name or nil
        if where and location.x and location.y then where = ("%s  (%.1f, %.1f)"):format(where, location.x, location.y) end
    end
    local text = where and (who .. "\n" .. where) or who
    if location.dropBy then text = text .. "\n" .. L["Drops from %s"]:format(location.dropBy) end
    return text
end

-- The quest starts inside the dungeon (NPC, object or item drop).
function W.InDungeon(quest)
    local info = W.QuestInfo(quest)
    if info and info.start and info.start.inside then return true end
    return quest.inside == true or quest.drop == true
end

local function RewardNames(itemIDs)
    local names = {}
    for _, itemID in ipairs(itemIDs) do
        local name, _, quality = W.ItemData(itemID)
        if name then
            local red, green, blue = W.QualityColor(quality)
            names[#names + 1] = ("|cff%02x%02x%02x%s|r"):format(red * 255, green * 255, blue * 255, name)
        else
            names[#names + 1] = L["item %d"]:format(itemID)
            W.RequestItem(itemID)
        end
    end
    return table.concat(names, ", ")
end

local function ChainText(quest)
    local parts = {}
    for _, previousID in ipairs(quest.pre) do
        parts[#parts + 1] = ns.IconString(W.ProgressMark(previousID), 12) .. W.QuestName(previousID)
    end
    parts[#parts + 1] = "|cffffffff" .. quest.name .. "|r"
    return table.concat(parts, " > ")
end

-- "Label:" in gold followed by the text, for tooltip lines.
local function GoldLabel(label, text) return ns.Hex(C.GOLD) .. label .. ":|r " .. text end

-- Quest name with its level, in the difficulty colour: text, red, green, blue.
-- Quest name with its level in the difficulty colour, followed by faction crests and the class icon
-- as inline textures: text, red, green, blue.
function W.QuestTitleLine(quest)
    local level = W.QuestLevel(quest)
    local red, green, blue = ns.LevelColor(level)
    local title = level and ("[%s] %s"):format(tostring(level), quest.name) or quest.name
    local parts = { ns.Hex({ red, green, blue }) .. title .. "|r" }
    for _, faction in ipairs(W.QuestFactions(quest)) do
        parts[#parts + 1] = ns.IconString(faction == "Horde" and TEX.HORDE or TEX.ALLIANCE, TITLE_ICON_SIZE)
    end
    local class = quest.classes and quest.classes[1]
    if class then parts[#parts + 1] = W.ClassIconString(class, TITLE_ICON_SIZE) end
    return table.concat(parts, " "), red, green, blue
end

-- Full quest tooltip.
function W.ShowQuestTooltip(owner, quest)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(quest.name, C.GOLD[1], C.GOLD[2], C.GOLD[3])
    local factions = {}
    for _, faction in ipairs(W.QuestFactions(quest)) do factions[#factions + 1] = ns.IconString(faction == "Horde" and TEX.HORDE or TEX.ALLIANCE, 14) end
    GameTooltip:AddLine(W.QuestLevelText(quest) .. "  " .. table.concat(factions, ""), 1, 1, 1)
    if quest.classes then GameTooltip:AddLine(L["Class: %s"]:format(table.concat(quest.classes, ", ")), C.SUBTLE[1], C.SUBTLE[2], C.SUBTLE[3]) end
    if quest.objective then GameTooltip:AddLine(quest.objective, C.TOOLTIP_TEXT[1], C.TOOLTIP_TEXT[2], C.TOOLTIP_TEXT[3], true) end
    local start = W.Location(quest, "start")
    if start then GameTooltip:AddLine(GoldLabel(L["Starts at"], ((W.LocationText(start) or "?"):gsub("\n", " · "))), 1, 1, 1, true) end
    if quest.pre and #quest.pre > 0 then GameTooltip:AddLine(GoldLabel(L["Chain"], ChainText(quest)), 1, 1, 1, true) end
    local rewards = quest.choices or quest.rewards
    if rewards and #rewards > 0 then
        GameTooltip:AddLine(GoldLabel(quest.choices and L["Reward (choose)"] or L["Reward"], RewardNames(rewards)), 1, 1, 1, true)
    end
    GameTooltip:AddLine(W.StateLabel(W.QuestState(quest)), C.HINT[1], C.HINT[2], C.HINT[3])
    GameTooltip:AddLine(L["Click: quest details"], C.HINT[1], C.HINT[2], C.HINT[3])
    GameTooltip:Show()
end
