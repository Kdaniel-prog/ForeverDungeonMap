-- ForeverDungeonMap - scrollable page builder used by the Dungeon Journal.
-- Every row has a fixed, known height and is stacked top-down; rows are pooled per page and
-- reused in the same order on every repaint (no hide/show flicker), so hover and scroll
-- position survive a repaint. The width is fixed per page so text is measured right away.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L
local W, C, TEX = ns.W, ns.C, ns.TEX

local Canvas = {}
Canvas.__index = Canvas
ns.Canvas = Canvas

-- Row heights and gaps.
local SIZE = {
    loot = 46, lootIcon = 36, plate = 42, plateGap = 8, itemButton = 38, itemButtonWidth = 230,
    boss = 56, bossPortrait = 46, bossHead = 96, bossHeadPortrait = 72,
    quest = 48, chainLine = 18, chainPadding = 10, link = 20, action = 22, rowGap = 4, wheelStep = 52,
    -- quest markers (chain toggle, In Dungeon) share one size so they read as one set
    marker = 20, markerGap = 4,
}
Canvas.SIZE = SIZE

-- options = { width, parchment = bool, handlers = { boss, quest, chain, step, pin, turnIn }, wheelStep }
function Canvas.New(name, parent, options)
    local canvas = setmetatable({ pools = {}, used = {}, y = 0, options = options, itemRows = {} }, Canvas)
    canvas.width = options.width
    canvas.scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    canvas.scroll.scrollBarHideable = true
    canvas.content = CreateFrame("Frame", nil, canvas.scroll)
    canvas.content:SetSize(canvas.width, 10)
    canvas.scroll:SetScrollChild(canvas.content)
    canvas.scroll:EnableMouseWheel(true)
    canvas.scroll:SetScript("OnMouseWheel", function(_, delta) canvas:ScrollBy(-delta * (options.wheelStep or SIZE.wheelStep)) end)
    return canvas
end

function Canvas:ScrollRange()
    return math.max(0, self.content:GetHeight() - self.scroll:GetHeight())
end

function Canvas:ScrollBy(pixels)
    local target = self.scroll:GetVerticalScroll() + pixels
    self.scroll:SetVerticalScroll(math.max(0, math.min(self:ScrollRange(), target)))
end

-- Next pooled widget of a kind (made on first use); anchors cleared, shown.
function Canvas:Acquire(kind, make)
    self.pools[kind] = self.pools[kind] or {}
    self.used[kind] = (self.used[kind] or 0) + 1
    local widget = self.pools[kind][self.used[kind]]
    if not widget then
        widget = make(self.content)
        self.pools[kind][self.used[kind]] = widget
    end
    widget:ClearAllPoints()
    widget:Show()
    return widget
end

-- Start a repaint. Rows stay visible until Finish(), so the one under the mouse keeps its hover.
function Canvas:Reset(keepScroll)
    wipe(self.used)
    wipe(self.itemRows)
    self.y = 0
    if not keepScroll then self.scroll:SetVerticalScroll(0) end
end

-- End a repaint: hide unused pooled rows, size the content, clamp the scroll, show the bar if needed.
function Canvas:Finish()
    for kind, list in pairs(self.pools) do
        for i = (self.used[kind] or 0) + 1, #list do
            list[i]:Hide()
            list[i]:ClearAllPoints()
        end
    end
    self.content:SetHeight(math.max(1, self.y + 10))
    local scroll = self.scroll
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local range = self:ScrollRange()
    if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
    local bar = scroll.ScrollBar or (scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"])
    if bar and scroll:GetHeight() > 0 then bar:SetShown(range > 0) end
end

-- Put a widget of `height` at the cursor, full width minus `indent`.
function Canvas:Place(widget, height, indent, width)
    indent = indent or 0
    widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", indent, -self.y)
    widget:SetSize(width or (self.width - indent), height)
    self.y = self.y + height
end

function Canvas:Space(height) self.y = self.y + height end

local EMPTY_TOP, EMPTY_INDENT = 20, 8

-- Message for an empty list or page, in the disabled font of the page.
function Canvas:Empty(text, font, color)
    self:Space(EMPTY_TOP)
    local muted = select(3, self:TextColors())
    self:Text(text, font or (self.options.parchment and ns.Font("questBody") or ns.Font("disable")), color or muted, EMPTY_INDENT)
end

-- Run a row filler; one bad row must never blank the page.
local function Safe(filler, ...)
    local ok, problem = pcall(filler, ...)
    if not ok then geterrorhandler()(problem) end
    return ok
end
Canvas.Safe = Safe

-- Heading, body and muted colours of the page.
function Canvas:TextColors()
    if self.options.parchment then return C.PARCH_HEAD, C.PARCH_TEXT, C.PARCH_MUTED end
    return C.GOLD, C.TEXT, C.MUTED
end

local function MakeHeading(parent, parchment)
    local heading = CreateFrame("Frame", nil, parent)
    heading.Text = heading:CreateFontString(nil, "OVERLAY", parchment and ns.Font("questHeading") or ns.Font("panelTitle"))
    heading.Text:SetPoint("BOTTOMLEFT", 2, 7)
    heading.Count = heading:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    heading.Count:SetPoint("BOTTOMLEFT", heading.Text, "BOTTOMRIGHT", 8, 0)
    heading.Line = heading:CreateTexture(nil, "ARTWORK")
    heading.Line:SetPoint("BOTTOMLEFT", 0, 1)
    heading.Line:SetPoint("BOTTOMRIGHT", 0, 1)
    if parchment then
        heading.Line:SetHeight(1)
        heading.Line:SetColorTexture(C.PARCH_RULE[1], C.PARCH_RULE[2], C.PARCH_RULE[3], C.PARCH_RULE[4])
    else
        heading.Line:SetTexture(TEX.DIVIDER)
        heading.Line:SetHeight(4)
    end
    heading.Marker = W.IconWithTooltip(heading, SIZE.marker)
    return heading
end

-- Section heading with an optional count and an optional marker icon { atlas or texture, title, text }.
function Canvas:Heading(text, count, marker)
    local parchment = self.options.parchment
    local heading = self:Acquire("heading", function(parent) return MakeHeading(parent, parchment) end)
    local color = self:TextColors()
    heading.Text:SetText(text)
    heading.Text:SetTextColor(color[1], color[2], color[3])
    heading.Text:SetShadowOffset(parchment and 0 or 1, parchment and 0 or -1)
    heading.Count:SetText(count and tostring(count) or "")
    heading.Marker:SetShown(marker ~= nil)
    if marker then
        heading.Marker:ClearAllPoints()
        heading.Marker:SetPoint("LEFT", heading.Text, "RIGHT", (count and 8 + heading.Count:GetStringWidth() or 0) + 6, 0)
        if marker.dungeon then W.SetDungeonMarker(heading.Marker.texture) else heading.Marker.texture:SetTexture(marker.texture) end
        W.Tooltip(heading.Marker, marker.title, marker.text)
    end
    self:Space(parchment and 8 or 6)
    self:Place(heading, parchment and 24 or 28)
    self:Space(SIZE.rowGap)
end

local function MakeText(parent, font)
    local holder = CreateFrame("Frame", nil, parent)
    holder.Text = holder:CreateFontString(nil, "OVERLAY", font)
    holder.Text:SetPoint("TOPLEFT")
    holder.Text:SetJustifyH("LEFT")
    holder.Text:SetJustifyV("TOP")
    holder.Text:SetWordWrap(true)
    holder.Text:SetSpacing(2)
    return holder
end

-- Wrapped text; `font` defaults to the page body font, `color` to the page text colour.
function Canvas:Text(text, font, color, indent)
    local parchment = self.options.parchment
    font = font or (parchment and ns.Font("questBody") or "GameFontHighlight")
    local holder = self:Acquire("text:" .. font, function(parent) return MakeText(parent, font) end)
    local _, bodyColor = self:TextColors()
    color = color or bodyColor
    indent = indent or 4
    local width = self.width - indent - 6
    holder.Text:SetWidth(width)
    holder.Text:SetText(text)
    holder.Text:SetTextColor(color[1], color[2], color[3])
    holder.Text:SetShadowOffset(parchment and 0 or 1, parchment and 0 or -1)
    self:Place(holder, math.max(16, math.ceil(holder.Text:GetStringHeight()) + 6), indent, width)
end

function Canvas:Divider()
    local holder = self:Acquire("divider", function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame.Line = W.Divider(frame)
        frame.Line:SetPoint("LEFT")
        frame.Line:SetPoint("RIGHT")
        return frame
    end)
    self:Place(holder, 8)
end

-- Gold action button ("Show on Map"); tooltip optional.
function Canvas:Action(text, onClick, width, enabled, tooltip)
    local button = self:Acquire("action", function(parent) return W.ActionButton(parent, "") end)
    button.Label:SetText(text)
    button:SetScript("OnClick", onClick)
    button:SetSize(width or 112, SIZE.action)
    W.SetDisabled(button, enabled == false)
    W.Tooltip(button, tooltip and text or nil, tooltip)
    self:Space(2)
    button:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, -self.y)
    self.y = self.y + SIZE.action + 4
    return button
end

local function MakeLink(parent, parchment)
    local link = CreateFrame("Button", nil, parent)
    link.Bullet = link:CreateTexture(nil, "ARTWORK")
    link.Bullet:SetSize(12, 12)
    link.Bullet:SetPoint("LEFT", 0, 0)
    link.Bullet:SetTexture(TEX.BULLET)
    link.Mark = W.IconWithTooltip(link, 14)
    link.Text = link:CreateFontString(nil, "OVERLAY", parchment and ns.Font("questBody") or "GameFontHighlight")
    link.Text:SetPoint("LEFT", link.Bullet, "RIGHT", 4, 0)
    link.Text:SetJustifyH("LEFT")
    link.Text:SetWordWrap(false)
    W.Hoverable(link, "line")
    link.OnVisual = function(self, hover)
        local color = hover and (parchment and C.PARCH_HEAD or C.WHITE) or self.textColor
        if color then self.Text:SetTextColor(color[1], color[2], color[3]) end
    end
    return link
end

-- Clickable text line with an optional state mark { texture, words } after the text.
function Canvas:Link(text, onClick, color, mark, tooltip)
    local parchment = self.options.parchment
    local link = self:Acquire("link", function(parent) return MakeLink(parent, parchment) end)
    local width = self.width - 10
    link.textColor = color or (parchment and C.PARCH_LINK or C.TEXT)
    link.Text:SetWidth(width - 40)
    link.Text:SetText(text)
    link.Mark:SetShown(mark ~= nil)
    if mark then
        link.Mark:ClearAllPoints()
        link.Mark:SetPoint("LEFT", link.Text, "LEFT", link.Text:GetStringWidth() + 4, 0)
        link.Mark.texture:SetTexture(mark[1])
        W.Tooltip(link.Mark, mark[2])
    end
    link:SetScript("OnClick", onClick)
    link:EnableMouse(onClick ~= nil)
    W.Tooltip(link, tooltip and tooltip[1] or nil, tooltip and tooltip[2] or nil)
    W.ApplyVisual(link)
    self:Place(link, SIZE.link, 4, width)
    return link
end

local PILL_HEIGHT, PILL_GAP, PILL_ICON = 26, 8, 20

local function MakePill(parent)
    local pill = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.Paint(pill, C.PARCH_ROW, C.PILL_EDGE, ns.BACKDROP_THIN)
    pill.Icon = pill:CreateTexture(nil, "ARTWORK")
    pill.Icon:SetSize(PILL_ICON, PILL_ICON)
    pill.Icon:SetPoint("LEFT", 4, 0)
    pill.Label = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pill.Label:SetPoint("LEFT", pill.Icon, "RIGHT", 4, 0)
    return pill
end

-- One line of reward pills; each pill = { icon, iconCoords, text, tooltipTitle, tooltipText }.
function Canvas:Pills(pills)
    if #pills == 0 then return end
    local x = 4
    for _, entry in ipairs(pills) do
        local pill = self:Acquire("pill", MakePill)
        pill.Icon:SetShown(entry.icon ~= nil)
        if entry.icon then
            pill.Icon:SetTexture(entry.icon)
            pill.Icon:SetTexCoord(unpack(entry.iconCoords or TEX.FULL_COORDS))
        end
        pill.Label:ClearAllPoints()
        pill.Label:SetPoint("LEFT", entry.icon and pill.Icon or pill, entry.icon and "RIGHT" or "LEFT", entry.icon and 4 or 8, 0)
        pill.Label:SetText(entry.text)
        local width = pill.Label:GetStringWidth() + (entry.icon and PILL_ICON + 16 or 16)
        pill:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -self.y)
        pill:SetSize(width, PILL_HEIGHT)
        W.Tooltip(pill, entry.tooltipTitle, entry.tooltipText)
        x = x + width + PILL_GAP
    end
    self.y = self.y + PILL_HEIGHT + SIZE.rowGap
end

-- Fill an item row: icon, quality frame, quality-coloured name and "Slot, Type".
local function FillItem(row, itemID)
    row.itemID = itemID
    local name, _, quality, icon, description = W.ItemData(itemID)
    row.Icon:SetTexture(icon or TEX.QUESTION)
    local showQuality = name ~= nil and (quality or 1) > 1
    if showQuality then row.Quality:SetVertexColor(W.QualityColor(quality)) end
    row.Quality:SetShown(showQuality)
    if row.Sub then row.Sub:SetText(description or "") end
    if name then
        local red, green, blue = W.QualityColor(quality)
        if (quality or 1) <= 1 then red, green, blue = C.TEXT[1], C.TEXT[2], C.TEXT[3] end
        row.Name:SetText(name)
        row.Name:SetTextColor(red, green, blue)
        return
    end
    row.Name:SetText(row.missingItem == itemID and L["Unknown item #%d"]:format(itemID) or L["Loading..."])
    row.Name:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
    if row.missingItem == itemID then return end
    W.RequestItem(itemID)
    if Item and Item.CreateFromItemID then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            if row.itemID == itemID and row:IsShown() then Safe(FillItem, row, itemID) end
        end)
    end
end
Canvas.FillItem = FillItem

-- Tooltip, shift-link and ctrl try-on for item rows.
local function AddItemScripts(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self) if self.itemID then W.ShowItemTooltip(self, self.itemID) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button) if button == "LeftButton" then W.ItemClick(self.itemID) end end)
end

-- Item button base: icon with quality frame and a name; `nameFont`, `iconSize`, `style`.
local function MakeItemButton(parent, iconSize, nameFont, style)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(iconSize, iconSize)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Quality = row:CreateTexture(nil, "OVERLAY")
    row.Quality:SetSize(iconSize + 2, iconSize + 2)
    row.Quality:SetPoint("CENTER", row.Icon, "CENTER")
    row.Quality:SetTexture(TEX.QUALITY_FRAME)
    row.Quality:Hide()
    row.Name = row:CreateFontString(nil, "OVERLAY", nameFont)
    row.Name:SetJustifyH("LEFT")
    AddItemScripts(row)
    W.Hoverable(row, style)
    return row
end

function Canvas:TrackItem(row, itemID)
    self.itemRows[itemID] = self.itemRows[itemID] or {}
    table.insert(self.itemRows[itemID], row)
end

-- Refill the rows showing itemID (item data arrived); success == false: the item does not exist.
function Canvas:RefreshItem(itemID, success)
    for _, row in ipairs(self.itemRows[itemID] or {}) do
        if row.itemID == itemID and row:IsShown() then
            if success == false then row.missingItem = itemID end
            Safe(FillItem, row, itemID)
        end
    end
end

local function MakeLootFilter(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar.Usable = W.IconButton(bar, 24, TEX.CLASS_ICONS)
    bar.Usable:SetPoint("LEFT", 2, 0)
    bar.Slot = W.DropdownButton(bar, TEX.SLOT_FILTER, 150, 24)
    bar.Slot:SetPoint("LEFT", bar.Usable, "RIGHT", 6, 0)
    return bar
end

-- Loot filter: "usable by my class" toggle (class icon) and the slot menu button.
-- filter = { usableOnly, slotLabel, onToggleUsable(), onSlotMenu(button) }
function Canvas:LootFilter(filter)
    local bar = self:Acquire("lootfilter", MakeLootFilter)
    local _, class = UnitClass("player")
    W.SetClassIcon(bar.Usable.Icon, class)
    bar.Usable.Icon:SetDesaturated(not filter.usableOnly)
    bar.Usable:SetSelected(filter.usableOnly)
    W.Tooltip(bar.Usable, filter.usableOnly and L["Showing loot you can use"] or L["Showing all loot"], L["Click to toggle"])
    bar.Usable:SetScript("OnClick", filter.onToggleUsable)
    bar.Slot.Label:SetText(filter.slotLabel)
    bar.Slot:SetSelected(filter.slotSelected)
    W.Tooltip(bar.Slot, L["Slot"], L["Click: choose a slot"])
    bar.Slot:SetScript("OnClick", function(button) filter.onSlotMenu(button) end)
    self:Place(bar, 26)
    self:Space(SIZE.rowGap)
end

local function MakeLootRow(parent)
    local row = MakeItemButton(parent, SIZE.lootIcon, "GameFontNormal", "row")
    row.Icon:SetPoint("LEFT", 6, 0)
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 10, -3)
    row.Name:SetPoint("RIGHT", -90, 0)
    row.Name:SetWordWrap(false)
    row.Sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Sub:SetPoint("BOTTOMLEFT", row.Icon, "BOTTOMRIGHT", 10, 3)
    row.Sub:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
    row.Count = row:CreateFontString(nil, "OVERLAY", ns.Font("number"))
    row.Count:SetPoint("RIGHT", -10, 0)
    return row
end

-- One full-width loot row: icon + quality frame, quality-coloured name, "Slot, Type", and
-- "x3" on the right when `count` is more than one.
function Canvas:Item(itemID, count)
    local row = self:Acquire("item", MakeLootRow)
    self:TrackItem(row, itemID)
    Safe(FillItem, row, itemID)
    row.Count:SetText(count and count > 1 and ("x%d"):format(count) or "")
    W.ApplyVisual(row)
    self:Place(row, SIZE.loot)
    self:Space(SIZE.rowGap)
    return row
end

local function MakePlate(parent)
    local plate = MakeItemButton(parent, 34, "GameFontHighlightSmall", "parchment")
    plate.Name:SetPoint("LEFT", plate.Icon, "RIGHT", 6, 0)
    plate.Name:SetPoint("RIGHT", -6, 0)
    plate.Name:SetWordWrap(true)
    plate.Name:SetMaxLines(2)
    return plate
end

-- Reward plates, two per line.
function Canvas:ItemGrid(itemIDs)
    local columnWidth = math.floor((self.width - 8 - SIZE.plateGap) / 2)
    for i, itemID in ipairs(itemIDs) do
        local plate = self:Acquire("plate", MakePlate)
        self:TrackItem(plate, itemID)
        Safe(FillItem, plate, itemID)
        W.ApplyVisual(plate)
        local column = (i - 1) % 2
        plate:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4 + column * (columnWidth + SIZE.plateGap), -self.y)
        plate:SetSize(columnWidth, SIZE.plate)
        if column == 1 or i == #itemIDs then self.y = self.y + SIZE.plate + 6 end
    end
end

local function MakeStartItem(parent)
    local button = MakeItemButton(parent, 30, "GameFontHighlightSmall", "parchment")
    button.Name:SetPoint("LEFT", button.Icon, "RIGHT", 6, 0)
    button.Name:SetPoint("RIGHT", -6, 0)
    return button
end

-- The item that starts a quest.
function Canvas:ItemButton(itemID)
    local button = self:Acquire("itembutton", MakeStartItem)
    self:TrackItem(button, itemID)
    Safe(FillItem, button, itemID)
    W.ApplyVisual(button)
    self:Space(2)
    self:Place(button, SIZE.itemButton, 4, SIZE.itemButtonWidth)
    self:Space(SIZE.rowGap)
end

-- Order number box at the right of a boss row.
local function MakeOrderBox(row)
    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(18, 18)
    box:SetPoint("RIGHT", -8, 0)
    box:SetBackdrop(ns.BACKDROP_LINE)
    box:SetBackdropColor(C.CHAIN_BG[1], C.CHAIN_BG[2], C.CHAIN_BG[3], C.CHAIN_BG[4])
    box:SetBackdropBorderColor(C.EDGE[1], C.EDGE[2], C.EDGE[3], 1)
    box.Text = box:CreateFontString(nil, "OVERLAY", ns.Font("numberSmall"))
    box.Text:SetPoint("CENTER")
    return box
end

local function MakeBossRow(parent, handlers)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row.Portrait = W.CreatePortrait(row, SIZE.bossPortrait, { levelBadge = 24 })
    row.Portrait:SetPoint("LEFT", 8, 0)
    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Name:SetPoint("LEFT", row.Portrait, "RIGHT", 12, 7)
    row.Name:SetPoint("RIGHT", -34, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Sub:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -2)
    row.Order = MakeOrderBox(row)
    row:SetScript("OnClick", function(self) if handlers.boss then handlers.boss(self.boss, self.index) end end)
    W.Hoverable(row, "row", { selectedBar = true })
    return row
end

-- "Rare" or "3 drops" (a defeated boss shows the red cross on its portrait).
local function BossSubText(boss)
    if boss.rare then return ns.Hex(C.RARE) .. L["Rare"] .. "|r" end
    local count = boss.loot and #boss.loot or 0
    return count == 1 and L["1 drop"] or L["%d drops"]:format(count)
end

-- Boss row in the list: round portrait, level badge, name, rare / drops, order number.
function Canvas:Boss(boss, index, instanceID, selected)
    local handlers = self.options.handlers
    local row = self:Acquire("boss", function(parent) return MakeBossRow(parent, handlers) end)
    row.boss, row.index = boss, index
    local killed = ns.IsKilled(instanceID, boss.name)
    W.SetPortrait(row.Portrait, boss, killed, instanceID)
    row.Name:SetText(boss.name)
    local nameColor = killed and C.MUTED or C.TEXT
    row.Name:SetTextColor(nameColor[1], nameColor[2], nameColor[3])
    row.Sub:SetText(BossSubText(boss))
    row.Sub:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
    row.Order.Text:SetText(index)
    local orderColor = selected and C.GOLD or C.MUTED
    row.Order.Text:SetTextColor(orderColor[1], orderColor[2], orderColor[3])
    row:SetSelected(selected)
    self:Place(row, SIZE.boss)
    self:Space(SIZE.rowGap)
    return row
end

local function MakeBossHead(parent)
    local head = CreateFrame("Frame", nil, parent)
    head.Portrait = W.CreatePortrait(head, SIZE.bossHeadPortrait, { levelBadge = 30 })
    head.Portrait:SetPoint("TOPLEFT", 8, -10)
    head.ArtFrame = CreateFrame("Frame", nil, head, "BackdropTemplate")
    head.ArtFrame:SetSize(162, 82)
    head.ArtFrame:SetPoint("TOPRIGHT", -4, -6)
    head.ArtFrame:SetBackdrop({ edgeFile = TEX.WHITE, edgeSize = 1 })
    head.ArtFrame:SetBackdropBorderColor(C.EDGE[1], C.EDGE[2], C.EDGE[3], 1)
    head.Art = head.ArtFrame:CreateTexture(nil, "ARTWORK")
    head.Art:SetPoint("TOPLEFT", 1, -1)
    head.Art:SetPoint("BOTTOMRIGHT", -1, 1)
    head.Name = head:CreateFontString(nil, "OVERLAY", ns.Font("title"))
    head.Name:SetPoint("TOPLEFT", 92, -14)
    head.Name:SetJustifyH("LEFT")
    head.Name:SetWordWrap(false)
    head.Info = head:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    head.Info:SetPoint("TOPLEFT", head.Name, "BOTTOMLEFT", 0, -6)
    head.Info:SetJustifyH("LEFT")
    head.MapButton = W.ActionButton(head, L["Show on map"], 120)
    head.MapButton:SetPoint("TOPLEFT", head.Info, "BOTTOMLEFT", 0, -8)
    return head
end

-- "Boss 7 of 8 · Level 21 Elite · Rare spawn · Defeated"
local function BossInfoText(boss, index, total, instanceID, killed)
    local parts = { L["Boss %d of %d"]:format(index, total) }
    parts[#parts + 1] = W.BossLevelText(instanceID, boss)
    if boss.rare then parts[#parts + 1] = ns.Hex(C.RARE) .. L["Rare spawn"] .. "|r" end
    if killed then parts[#parts + 1] = ns.IconString(TEX.CROSS, 14) .. ns.Hex(C.DEFEATED) .. L["Defeated"] .. "|r" end
    return table.concat(parts, " · ")
end

-- Boss detail header: portrait, name, info line, Encounter Journal creature picture, Show on map.
function Canvas:BossHead(boss, index, total, instanceID, onShowOnMap)
    local head = self:Acquire("bosshead", MakeBossHead)
    local killed = ns.IsKilled(instanceID, boss.name)
    W.SetPortrait(head.Portrait, boss, killed, instanceID)
    head.Name:SetText(boss.name)
    head.Name:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
    local art = ns.BOSS_ART and ns.BOSS_ART[boss.name]
    head.ArtFrame:SetShown(art ~= nil)
    if art then
        head.Art:SetTexture(art)
        head.Art:SetDesaturated(killed and true or false)
        head.Name:SetPoint("RIGHT", head.ArtFrame, "LEFT", -8, 0)
    else
        head.Name:SetPoint("RIGHT", head, "RIGHT", -4, 0)
    end
    head.Info:SetText(BossInfoText(boss, index, total, instanceID, killed))
    head.Info:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
    head.MapButton:SetShown(onShowOnMap ~= nil)
    head.MapButton:SetScript("OnClick", onShowOnMap)
    self:Place(head, SIZE.bossHead)
    self:Divider()
end

-- Icon button on a row (chain toggle, pick-up pin, turn-in).
local function MakeIconButton(parent, size, texture)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints()
    button.texture:SetTexture(texture)
    button:SetHighlightTexture(TEX.ROUND_HIGHLIGHT, "ADD")
    return button
end

local function MakeChainLine(row)
    local line = CreateFrame("Button", nil, row.Chain)
    line:SetHeight(SIZE.chainLine)
    line.Bullet = line:CreateTexture(nil, "ARTWORK")
    line.Bullet:SetSize(10, 10)
    line.Bullet:SetPoint("LEFT", 4, 0)
    line.Bullet:SetTexture(TEX.BULLET)
    line.Text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.Text:SetPoint("LEFT", line.Bullet, "RIGHT", 3, 0)
    line.Text:SetPoint("RIGHT", -40, 0)
    line.Text:SetJustifyH("LEFT")
    line.Text:SetWordWrap(false)
    line.Mark = W.IconWithTooltip(line, 12)
    line.Pin = MakeIconButton(line, 14, TEX.QUEST_AVAILABLE)
    line.Pin:SetPoint("RIGHT", -4, 0)
    W.Hoverable(line, "line")
    return line
end

-- One chain step: "1. Name" + tick / grey ? / cross, pick-up pin, click opens the step's page.
local function FillChainLine(line, quest, stepID, index, total, handlers, selectedStep)
    local isThisQuest = stepID == quest.id
    line.Text:SetText(("%d. %s"):format(index, W.QuestName(stepID)))
    local markTexture, markWords = W.ProgressMark(stepID)
    local textColor = W.IsQuestDone(stepID) and C.DONE or (isThisQuest and C.GOLD or C.TEXT)
    line.Text:SetTextColor(textColor[1], textColor[2], textColor[3])
    line.Mark:ClearAllPoints()
    line.Mark:SetPoint("LEFT", line.Text, "LEFT", line.Text:GetStringWidth() + 4, 0)
    line.Mark.texture:SetTexture(markTexture)
    W.Tooltip(line.Mark, markWords)
    local start = W.Location(W.QuestByID(stepID), "start")
    local hasSpot = start ~= nil and start.map ~= nil and start.x ~= nil
    line.Pin:SetShown(hasSpot)
    W.Tooltip(line.Pin, L["Starts at"], start and (W.LocationText(start) or ""):gsub("\n", ", ") or "")
    line.Pin:SetScript("OnClick", function() if handlers.pin then handlers.pin(start, W.QuestName(stepID)) end end)
    line:SetScript("OnClick", function() if handlers.step then handlers.step(quest, stepID, index, total) end end)
    line:SetSelected(selectedStep == stepID)
    line:Show()
end

local function MakeQuestChain(row)
    row.Chain = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.Chain:SetPoint("TOPLEFT", 38, -(SIZE.quest - 2))
    row.Chain:SetPoint("RIGHT", -8, 0)
    row.Chain:SetBackdrop(ns.BACKDROP_THIN)
    row.Chain:SetBackdropColor(C.CHAIN_BG[1], C.CHAIN_BG[2], C.CHAIN_BG[3], C.CHAIN_BG[4])
    row.Chain:SetBackdropBorderColor(C.EDGE[1], C.EDGE[2], C.EDGE[3], 1)
    row.lines = {}
end

-- Right cluster of a quest row, from the right edge: done tick, two faction crests, class icon,
-- all centred on the title part of the row (the inline chain hangs below it).
local CLUSTER = { edge = 8, gap = 3, tick = 22, icon = 30, turnIn = 32 }
local function ClusterOffset(slot)
    return -(CLUSTER.edge + CLUSTER.tick + CLUSTER.gap + (slot - 1) * (CLUSTER.icon + CLUSTER.gap))
end

local function CentredTop(size) return -math.floor((SIZE.quest - size) / 2) end

local function MakeQuestRightCluster(row, handlers)
    row.Done = row:CreateTexture(nil, "ARTWORK")
    row.Done:SetSize(CLUSTER.tick, CLUSTER.tick)
    row.Done:SetPoint("TOPRIGHT", -CLUSTER.edge, CentredTop(CLUSTER.tick))
    row.Done:SetTexture(TEX.TICK)
    row.Faction2 = row:CreateTexture(nil, "ARTWORK")
    row.Faction2:SetSize(CLUSTER.icon, CLUSTER.icon)
    row.Faction2:SetPoint("TOPRIGHT", ClusterOffset(1), CentredTop(CLUSTER.icon))
    row.Faction1 = row:CreateTexture(nil, "ARTWORK")
    row.Faction1:SetSize(CLUSTER.icon, CLUSTER.icon)
    row.Faction1:SetPoint("TOPRIGHT", ClusterOffset(2), CentredTop(CLUSTER.icon))
    row.ClassIcon = W.IconWithTooltip(row, CLUSTER.icon)
    row.ClassIcon:SetPoint("TOPRIGHT", ClusterOffset(3), CentredTop(CLUSTER.icon))
    row.TurnIn = MakeIconButton(row, CLUSTER.turnIn, TEX.QUEST_ACTIVE)
    row.TurnIn:SetPoint("TOPRIGHT", -CLUSTER.edge, CentredTop(CLUSTER.turnIn))
    row.TurnIn:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        if handlers.turnIn then handlers.turnIn(parent.readyQuest or parent.quest) end
    end)
    W.Tooltip(row.TurnIn, L["Ready to turn in"], L["Click: show where to turn it in"])
end

local function MakeQuestRow(parent, handlers)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row.Mark = row:CreateTexture(nil, "ARTWORK")
    row.Mark:SetSize(22, 22)
    row.Mark:SetPoint("TOPLEFT", 8, -8)
    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", 38, -8)
    row.Name:SetPoint("RIGHT", row, "TOPRIGHT", ClusterOffset(3), 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Sub:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -3)
    row.ChainToggle = MakeIconButton(row, SIZE.marker, TEX.CHAIN)
    W.Tooltip(row.ChainToggle, L["Quest chain"], L["Click to show the whole quest chain"])
    row.ChainToggle:SetScript("OnClick", function(self) if handlers.chain then handlers.chain(self:GetParent().quest) end end)
    row.Progress = W.IconWithTooltip(row, 12)
    row.Progress.texture:SetTexture(TEX.QUEST_INCOMPLETE)
    row.Progress.Count = row.Progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Progress.Count:SetPoint("LEFT", row.Progress, "RIGHT", 2, 0)
    row.Inside = W.IconWithTooltip(row, SIZE.marker)
    W.SetDungeonMarker(row.Inside.texture)
    W.Tooltip(row.Inside, L["In Dungeon"], L["This quest starts inside the dungeon."])
    MakeQuestRightCluster(row, handlers)
    MakeQuestChain(row)
    row:SetScript("OnClick", function(self) if handlers.quest then handlers.quest(self.quest) end end)
    row:SetScript("OnEnter", function(self) W.ShowQuestTooltip(self, self.quest) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    W.Hoverable(row, "row", { selectedBar = true })
    return row
end

-- Title in difficulty colour; "Available from Level N" in red while the player is too low.
local function FillQuestTitle(row, quest, state)
    W.SetStateIcon(row.Mark, state)
    row.Name:SetText(quest.name)
    if state == "done" then
        row.Name:SetTextColor(C.DONE[1], C.DONE[2], C.DONE[3])
    elseif state == "other" then
        row.Name:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
    else
        row.Name:SetTextColor(ns.LevelColor(W.QuestLevel(quest)))
    end
    local levelText, required = W.QuestLevelText(quest)
    row.Sub:SetText(levelText)
    local subColor = (required and (UnitLevel("player") or 1) < required) and C.RED or C.MUTED
    row.Sub:SetTextColor(subColor[1], subColor[2], subColor[3])
end

-- Chain toggle and L["In Dungeon"] marker right after the level text.
local function FillQuestMarkers(row, quest, steps)
    local x = row.Sub:GetStringWidth() + 6
    local hasChain = #steps > 1
    row.ChainToggle:ClearAllPoints()
    row.ChainToggle:SetPoint("LEFT", row.Sub, "LEFT", x, 0)
    row.ChainToggle:SetShown(hasChain)
    if hasChain then x = x + SIZE.marker + SIZE.markerGap end
    local inDungeon = W.InDungeon(quest)
    row.Inside:ClearAllPoints()
    row.Inside:SetPoint("LEFT", row.Sub, "LEFT", x, 0)
    row.Inside:SetShown(inDungeon)
    if inDungeon then x = x + SIZE.marker + SIZE.markerGap end
    local fulfilled, required = W.QuestProgress(quest.id)
    row.Progress:SetShown(fulfilled ~= nil)
    if fulfilled then
        row.Progress:ClearAllPoints()
        row.Progress:SetPoint("LEFT", row.Sub, "LEFT", x, 0)
        row.Progress.Count:SetText(("%d/%d"):format(fulfilled, required))
        W.Tooltip(row.Progress, L["Progress"], L["%d of %d objectives done"]:format(fulfilled, required))
    end
end

-- Class icon of a class quest (all classes in the tooltip) in the next free slot; the title
-- ends before the last used slot.
local function FillQuestClass(row, quest, usedSlots)
    local class = quest.classes and quest.classes[1]
    row.ClassIcon:SetShown(class ~= nil)
    if class then
        usedSlots = usedSlots + 1
        row.ClassIcon:SetPoint("TOPRIGHT", ClusterOffset(usedSlots), CentredTop(CLUSTER.icon))
        W.SetClassIcon(row.ClassIcon.texture, class)
        W.Tooltip(row.ClassIcon, L["Class quest"], table.concat(quest.classes, ", "))
    end
    row.Name:SetPoint("RIGHT", row, "TOPRIGHT", ClusterOffset(usedSlots + 1), 0)
end

-- Done tick and faction crests, or the big "?" while the quest is ready to turn in; returns the
-- number of icon slots used.
local function FillQuestRightCluster(row, quest, state)
    local ready = state == "ready"
    row.TurnIn:SetShown(ready)
    row.Done:SetShown(state == "done")
    local factions = W.QuestFactions(quest)
    row.Faction1:SetShown(not ready and factions[2] ~= nil)
    row.Faction2:SetShown(not ready)
    W.SetFactionIcon(row.Faction2, factions[#factions])
    if factions[2] then W.SetFactionIcon(row.Faction1, factions[1]) end
    return ready and 1 or #factions
end

-- Inline chain under the row; returns the extra height.
local function FillQuestChain(row, quest, steps, expanded, handlers, selectedStep)
    if not (expanded and #steps > 1) then
        row.Chain:Hide()
        return 0
    end
    for i, stepID in ipairs(steps) do
        local line = row.lines[i] or MakeChainLine(row)
        row.lines[i] = line
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", row.Chain, "TOPLEFT", 2, -5 - (i - 1) * SIZE.chainLine)
        line:SetPoint("RIGHT", row.Chain, "RIGHT", -2, 0)
        FillChainLine(line, quest, stepID, i, #steps, handlers, selectedStep)
    end
    for i = #steps + 1, #row.lines do row.lines[i]:Hide() end
    row.Chain:SetHeight(#steps * SIZE.chainLine + SIZE.chainPadding)
    row.Chain:Show()
    return 2 * SIZE.chainPadding + #steps * SIZE.chainLine
end

-- Quest row: state icon, title, level text, chain toggle + inline chain, L["In Dungeon"] marker,
-- faction crests, done tick / turn-in. A chain is one row; its state may come from a later step.
-- options = { selected, expanded, selectedStep, readyQuest (the step to turn in) }
function Canvas:Quest(quest, state, options)
    options = options or {}
    local handlers = self.options.handlers
    local row = self:Acquire("quest", function(parent) return MakeQuestRow(parent, handlers) end)
    row.quest, row.readyQuest = quest, options.readyQuest
    state = state or W.QuestState(quest)
    local steps = W.QuestChain(quest)
    FillQuestTitle(row, quest, state)
    FillQuestMarkers(row, quest, steps)
    FillQuestClass(row, quest, FillQuestRightCluster(row, quest, state))
    local extra = FillQuestChain(row, quest, steps, options.expanded, handlers, options.selectedStep)
    row:SetSelected(options.selected)
    self:Place(row, SIZE.quest + extra)
    self:Space(SIZE.rowGap)
    return row
end
