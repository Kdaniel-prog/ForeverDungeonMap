-- ForeverDungeonMap - dungeon map renderer shared by the world-map overlay (DungeonView.lua)
-- and the journal's Map tab: map art (client tiles or one custom texture), floors, wheel
-- zoom at the cursor, drag to pan, round boss pins with order badges, entrance pin.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local W, C, TEX, L = ns.W, ns.C, ns.TEX, ns.L

-- Visible part of the 4x3 grid of 256 px tiles.
local ART_WIDTH, ART_HEIGHT = 1002, 668
local TILE_SIZE, TILE_COLUMNS, TILE_COUNT = 256, 4, 12
local MIN_ZOOM, MAX_ZOOM, ZOOM_STEP = 1, 4, 1.25
local PIN_SIZE = 40
local DEFAULT_PIN_SCALE = 1.0
local MIN_PIN_SCALE, MAX_PIN_SCALE, PIN_SCALE_STEP = 0.6, 1.6, 0.1
local LOOT_IN_TOOLTIP = 3
local DEFAULT_HINT = ns.KeyHint({ { "Wheel", "zoom" }, { "Drag", "move" }, { "Right-click", "back" } })
-- the boss icon size is shown and stepped in whole tenths (90%, 100%...)
local SCALE_STEPS_PER_UNIT = 10
-- float slack when comparing the icon size with its limits
local SCALE_EPSILON = 0.001
-- zooming out snaps to the whole map within this factor of the minimum zoom
local ZOOM_SNAP = 1.05
local ENTRANCE_SIZE = 18
local FLOOR_BUTTON_WIDTH, FLOOR_BAR_HEIGHT, FLOOR_BAR_LEFT, FLOOR_BAR_GAP = 190, 26, 6, 4
local SCALE_BOX_WIDTH, SCALE_BOX_HEIGHT, SCALE_BUTTON_SIZE, SCALE_BOX_PADDING = 104, 44, 18, 8
local DEFEATED_ICON_SIZE = 14
-- frame levels above the map's base level: art, entrance pin, boss pins, controls on top
local LEVEL_AREA, LEVEL_ART, LEVEL_ENTRANCE, LEVEL_PINS, LEVEL_CONTROLS = 1, 2, 4, 5, 20

local MapCanvas = {}
MapCanvas.__index = MapCanvas
ns.MapCanvas = MapCanvas

-- Every map canvas, so a changed boss icon size reaches all of them.
local allMaps = {}

-- Boss pin scale from the setting (0.6 .. 1.6).
-- pins closer than this many pin widths are pushed apart; rounds of pushing per layout
local PIN_SPACING, SPREAD_ROUNDS = 0.9, 12

-- Push points { x, y } apart until no two are closer than `distance` (the first `fixedCount`
-- points stay put). Points on the same spot leave in a fixed direction per index.
function MapCanvas.SpreadApart(points, distance, fixedCount)
    fixedCount = fixedCount or 0
    for _ = 1, SPREAD_ROUNDS do
        local moved = false
        for i = 1, #points do
            for j = math.max(i + 1, fixedCount + 1), #points do
                local first, second = points[i], points[j]
                local dx, dy = second.x - first.x, second.y - first.y
                local gap = math.sqrt(dx * dx + dy * dy)
                if gap < distance then
                    if gap < 0.01 then dx, dy, gap = math.cos(j), math.sin(j), 1 end
                    local push = (distance - gap) / gap
                    local firstShare = i <= fixedCount and 0 or 0.5
                    first.x, first.y = first.x - dx * push * firstShare, first.y - dy * push * firstShare
                    second.x, second.y = second.x + dx * push * (1 - firstShare), second.y + dy * push * (1 - firstShare)
                    moved = true
                end
            end
        end
        if not moved then return end
    end
end

local function PinScale()
    local scale = ns.Setting("bossIconScale")
    if type(scale) ~= "number" then scale = DEFAULT_PIN_SCALE end
    return math.max(MIN_PIN_SCALE, math.min(MAX_PIN_SCALE, scale))
end

local function ChangePinScale(direction)
    local scale = math.floor((PinScale() + direction * PIN_SCALE_STEP) * SCALE_STEPS_PER_UNIT + 0.5) / SCALE_STEPS_PER_UNIT
    ns.SetSetting("bossIconScale", math.max(MIN_PIN_SCALE, math.min(MAX_PIN_SCALE, scale)))
end

-- Flat map background and the desaturated dungeon lore picture behind the art.
function MapCanvas:BuildBackground()
    local background = self.frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(C.MAP_BG[1], C.MAP_BG[2], C.MAP_BG[3], C.MAP_BG[4])
    self.lore = self.frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.lore:SetAllPoints()
    self.lore:SetAlpha(ns.ALPHA.mapLore)
end

-- The mouse area: wheel zoom, left drag to pan, right-click for the owner's "back".
function MapCanvas:BuildArea()
    local area = CreateFrame("Frame", nil, self.frame)
    area:SetAllPoints(self.frame)
    area:SetClipsChildren(true)
    area:EnableMouse(true)
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta) self:ZoomAtCursor(delta) end)
    area:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local x, y = self:CursorOffset()
        self.state.drag = { x = x, y = y, offsetX = self.state.offsetX, offsetY = self.state.offsetY }
        self.frame:SetScript("OnUpdate", function() self:DragUpdate() end)
    end)
    area:SetScript("OnMouseUp", function(_, button)
        self.state.drag = nil
        self.frame:SetScript("OnUpdate", nil)
        if button == "RightButton" and self.options.onRightClick then self.options.onRightClick() end
    end)
    self.area = area
end

-- The art canvas: 4x3 client tiles, or one custom texture for dungeons without tiles.
function MapCanvas:BuildArt()
    local canvas = CreateFrame("Frame", nil, self.area)
    canvas:SetSize(ART_WIDTH, ART_HEIGHT)
    canvas:SetClipsChildren(true)
    self.tiles = {}
    for i = 1, TILE_COUNT do
        local tile = canvas:CreateTexture(nil, "ARTWORK")
        tile:SetSize(TILE_SIZE, TILE_SIZE)
        tile:SetPoint("TOPLEFT", ((i - 1) % TILE_COLUMNS) * TILE_SIZE, -math.floor((i - 1) / TILE_COLUMNS) * TILE_SIZE)
        self.tiles[i] = tile
    end
    self.artTexture = canvas:CreateTexture(nil, "ARTWORK")
    self.artTexture:SetAllPoints(canvas)
    self.artTexture:Hide()
    self.canvas = canvas
end

-- One "Entrance" marker (the dungeon's portal arrival spot).
function MapCanvas:CreateEntranceMarker()
    local entrance = CreateFrame("Frame", nil, self.area)
    entrance:SetSize(ENTRANCE_SIZE, ENTRANCE_SIZE)
    entrance.Icon = entrance:CreateTexture(nil, "ARTWORK")
    entrance.Icon:SetAllPoints()
    W.SetDungeonMarker(entrance.Icon)
    entrance.Label = entrance:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    entrance.Label:SetPoint("RIGHT", entrance, "LEFT", -2, 0)
    entrance.Label:SetText("Entrance")
    entrance.Label:SetShadowOffset(1, -1)
    entrance:Hide()
    return entrance
end

-- Entrance markers: the main one first, more on demand (wings, back doors).
function MapCanvas:BuildEntrance()
    self.entrance = self:CreateEntranceMarker()
    self.entranceMarkers = { self.entrance }
end

function MapCanvas:EntranceMarker(i)
    if not self.entranceMarkers[i] then self.entranceMarkers[i] = self:CreateEntranceMarker() end
    return self.entranceMarkers[i]
end

-- Floor dropdown (top-left, below the reserved top strip): "Level 2" or the wing's name.
function MapCanvas:BuildFloorBar(top)
    local button = W.DropdownButton(self.area, TEX.FLOOR_ICON, FLOOR_BUTTON_WIDTH, FLOOR_BAR_HEIGHT)
    button:SetPoint("TOPLEFT", FLOOR_BAR_LEFT, -(top + FLOOR_BAR_GAP))
    W.Tooltip(button, L["Choose the level"])
    self.floorMenu = W.CreateChoiceMenu(self.area, FLOOR_BUTTON_WIDTH)
    button:SetScript("OnClick", function(clicked) self:ToggleFloorMenu(clicked) end)
    self.floorButton = button
    self.floorBar = button
end

-- "Level 2", or the wing's name with its level range.
local function FloorLabel(floor, index)
    if not floor.name then return L["Level %d"]:format(index) end
    return floor.name .. (floor.min and (" " .. ns.Hex(C.MUTED) .. "%d-%d|r"):format(floor.min, floor.max) or "")
end

function MapCanvas:ToggleFloorMenu(anchor)
    local choices = {}
    for index, floor in ipairs(self.state.floors or {}) do
        choices[index] = { label = FloorLabel(floor, index), selected = index == self.state.floor }
    end
    self.floorMenu:Toggle(anchor, choices, function(index) self:SetFloor(index) end)
end

-- Key hint line at the bottom right.
function MapCanvas:BuildFooter()
    local footer = CreateFrame("Frame", nil, self.area)
    footer:SetPoint("BOTTOMRIGHT", -8, 6)
    footer:SetSize(10, 14)
    self.hint = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.hint:SetPoint("BOTTOMRIGHT")
    self.hint:SetText(self.options.hint or DEFAULT_HINT)
    self.hint:SetTextColor(C.MUTED[1], C.MUTED[2], C.MUTED[3])
    self.hint:SetShadowOffset(1, -1)
    self.footer = footer
end

-- "Boss icons  - 90% +" box at the bottom left.
function MapCanvas:BuildScaleControl()
    local box = W.Panel(self.area, C.INK, C.EDGE)
    box:SetPoint("BOTTOMLEFT", SCALE_BOX_PADDING, SCALE_BOX_PADDING)
    box:SetSize(SCALE_BOX_WIDTH, SCALE_BOX_HEIGHT)
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", 0, -6)
    label:SetText("Boss icons")
    local minus = W.IconButton(box, SCALE_BUTTON_SIZE, TEX.MINUS, 1)
    minus:SetPoint("BOTTOMLEFT", SCALE_BOX_PADDING, 6)
    minus:SetScript("OnClick", function() ChangePinScale(-1) end)
    W.Tooltip(minus, "Smaller boss icons")
    local plus = W.IconButton(box, SCALE_BUTTON_SIZE, TEX.PLUS, 1)
    plus:SetPoint("BOTTOMRIGHT", -SCALE_BOX_PADDING, 6)
    plus:SetScript("OnClick", function() ChangePinScale(1) end)
    W.Tooltip(plus, "Larger boss icons")
    self.scaleText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.scaleText:SetPoint("BOTTOM", 0, 9)
    self.scaleBox, self.scaleMinus, self.scalePlus = box, minus, plus
    self:UpdateScaleText()
end

-- "90%" and the -/+ buttons disabled at the limits.
function MapCanvas:UpdateScaleText()
    local scale = PinScale()
    self.scaleText:SetText(("%d%%"):format(math.floor(scale * ns.PERCENT + 0.5)))
    W.SetDisabled(self.scaleMinus, scale <= MIN_PIN_SCALE + SCALE_EPSILON)
    W.SetDisabled(self.scalePlus, scale >= MAX_PIN_SCALE - SCALE_EPSILON)
end

-- options = { top = pixels reserved at the top (header), bottom = pixels at the bottom,
--             onBoss(boss, index), onRightClick(), hint = text }
function MapCanvas.Create(parent, options)
    local map = setmetatable({ options = options or {}, pins = {}, numPins = 0,
        state = { instanceID = nil, floors = nil, floor = 1, zoom = 1, offsetX = 0, offsetY = 0, fit = nil } }, MapCanvas)
    local top, bottom = map.options.top or 0, map.options.bottom or 0
    map.frame = CreateFrame("Frame", nil, parent)
    map.frame:SetAllPoints(parent)
    map:BuildBackground()
    map:BuildArea()
    map:BuildArt()
    map:BuildEntrance()
    map.noArt = map.area:CreateFontString(nil, "OVERLAY", ns.Font("disableLarge"))
    map.noArt:SetPoint("CENTER", 0, (bottom - top) / 2)
    map.noArt:SetText("No map for this dungeon yet.")
    map:BuildFloorBar(top)
    map:BuildFooter()
    map:BuildScaleControl()
    W.MarkOwned(map.frame)
    table.insert(allMaps, map)
    map.frame:SetScript("OnSizeChanged", function() map:Layout() end)
    map.frame:SetScript("OnHide", function()
        map.state.drag = nil
        map.frame:SetScript("OnUpdate", nil)
    end)
    return map
end

function MapCanvas:Bosses() return ns.BOSSES[self.state.instanceID] or {} end
function MapCanvas:HasArt() return self.state.floors ~= nil and #self.state.floors > 0 end
function MapCanvas:CurrentFloor() return self.state.floors and self.state.floors[self.state.floor] end

-- Cursor position relative to the map area's center.
function MapCanvas:CursorOffset()
    local scale = self.area:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local centerX, centerY = self.area:GetCenter()
    if not centerX then return 0, 0 end
    return x / scale - centerX, y / scale - centerY
end

-- Art coordinates (0..1, y down) -> offset from the area's center.
function MapCanvas:ArtToOffset(x, y)
    local scale = self.state.fit * self.state.zoom
    return self.state.offsetX + (x - 0.5) * ART_WIDTH * scale, self.state.offsetY - (y - 0.5) * ART_HEIGHT * scale
end

local function AddLootLines(loot)
    for i = 1, math.min(LOOT_IN_TOOLTIP, #loot) do
        local name, _, quality = W.ItemData(loot[i])
        if name then
            GameTooltip:AddLine(name, W.QualityColor(quality))
        else
            GameTooltip:AddLine("Loading...", C.MUTED[1], C.MUTED[2], C.MUTED[3])
            W.RequestItem(loot[i])
        end
    end
    if #loot > LOOT_IN_TOOLTIP then
        GameTooltip:AddLine(("+%d more"):format(#loot - LOOT_IN_TOOLTIP), C.MUTED[1], C.MUTED[2], C.MUTED[3])
    end
end

-- Pin tooltip: name, "Boss 3 of 8 · Level 20 Elite", defeated, first loot names, click hint.
function MapCanvas:ShowBossTooltip(owner, boss, index)
    local instanceID = self.state.instanceID
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(boss.name, C.GOLD[1], C.GOLD[2], C.GOLD[3])
    local line = ("Boss %d of %d"):format(index, #self:Bosses())
    local levelText = W.BossLevelText(instanceID, boss)
    if levelText then line = line .. " · " .. levelText end
    if boss.rare then line = line .. " · Rare" end
    GameTooltip:AddLine(line, 1, 1, 1)
    if ns.IsKilled(instanceID, boss.name) then
        GameTooltip:AddLine(ns.IconString(TEX.CROSS, DEFEATED_ICON_SIZE) .. " Defeated", C.DEFEATED[1], C.DEFEATED[2], C.DEFEATED[3])
    end
    AddLootLines(boss.loot or {})
    GameTooltip:AddLine("Click: loot & quests", C.HINT[1], C.HINT[2], C.HINT[3])
    GameTooltip:Show()
end

-- Boss pin number i (made on first use): click opens the boss, right-click is "back".
function MapCanvas:Pin(i)
    if self.pins[i] then return self.pins[i] end
    local pin = W.CreatePortrait(self.area, PIN_SIZE, { orderBadge = true, mouse = true, eliteDragon = true })
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnClick", function(clicked, button)
        if button == "RightButton" then
            if self.options.onRightClick then self.options.onRightClick() end
        elseif self.options.onBoss then
            self.options.onBoss(clicked.boss, clicked.index)
        end
    end)
    pin:SetScript("OnEnter", function(hovered) self:ShowBossTooltip(hovered, hovered.boss, hovered.index) end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.pins[i] = pin
    return pin
end

-- Put pin number `count` at offset x, y from the area's centre (portrait, killed mark, order badge).
function MapCanvas:PlacePin(count, boss, index, x, y, scale)
    local state = self.state
    local pin = self:Pin(count)
    pin.boss, pin.index = boss, index
    W.SetPortrait(pin, boss, ns.IsKilled(state.instanceID, boss.name), state.instanceID)
    pin.Badge.Text:SetText(index)
    pin:SetScale(scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", self.area, "CENTER", x / scale, y / scale)
    pin:SetFrameLevel(self.area:GetFrameLevel() + LEVEL_PINS - LEVEL_AREA)
    pin:Show()
end

-- Boss pins of the current floor (none on overview maps).
-- { boss, index, x, y } of the bosses on this floor, x, y as offsets from the area's centre.
function MapCanvas:BossSpotsOnFloor(floor)
    local spots = {}
    for index, boss in ipairs(self:Bosses()) do
        local position = ns.GetBossPos(self.state.instanceID, boss.name)
        if position and (position.floor or 1) == floor.index then
            local x, y = self:ArtToOffset(position.x, position.y)
            spots[#spots + 1] = { boss = boss, index = index, x = x, y = y }
        end
    end
    return spots
end

-- Boss pins of the current floor (none on overview maps), pushed apart so none hides another.
function MapCanvas:LayoutBossPins(floor)
    local spots, scale = {}, PinScale()
    if floor and self.state.fit and not floor.overview then spots = self:BossSpotsOnFloor(floor) end
    MapCanvas.SpreadApart(spots, PIN_SIZE * scale * PIN_SPACING)
    for count, spot in ipairs(spots) do self:PlacePin(count, spot.boss, spot.index, spot.x, spot.y, scale) end
    for i = #spots + 1, #self.pins do self.pins[i]:Hide() end
    self.numPins = #spots
    -- where the portraits ended up, so quest markers keep clear of them
    self.occupiedSpots = spots
    self.occupiedDistance = PIN_SIZE * scale
end

-- A marker frame centred on an art spot { x, y } (0..1), `levelAboveArea` levels over the map.
function MapCanvas:PlaceMarker(marker, spot, levelAboveArea)
    local x, y = self:ArtToOffset(spot.x, spot.y)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", self.area, "CENTER", x, y)
    marker:SetFrameLevel(self.area:GetFrameLevel() + levelAboveArea)
    marker:Show()
end

-- The dungeon's portal spots on the art: the main entrance, then wings and back doors.
local function EntranceSpots(instanceID)
    local entrance = ns.GetEntranceOnArt(instanceID)
    if not entrance then return {} end
    local spots = { entrance }
    for _, other in ipairs(entrance.others or {}) do spots[#spots + 1] = other end
    return spots
end

-- Entrance markers of the floor on screen.
function MapCanvas:LayoutEntrance(floor)
    local shown = 0
    if floor and self.state.fit then
        for _, spot in ipairs(EntranceSpots(self.state.instanceID)) do
            if (spot.floor or 1) == floor.index then
                shown = shown + 1
                self:PlaceMarker(self:EntranceMarker(shown), spot, LEVEL_ENTRANCE - LEVEL_AREA)
            end
        end
    end
    for i = shown + 1, #self.entranceMarkers do self.entranceMarkers[i]:Hide() end
end

function MapCanvas:LayoutPins()
    local floor = self:CurrentFloor()
    self:LayoutBossPins(floor)
    self:LayoutEntrance(floor)
    self:LayoutQuestSpots(floor)
end

-- Fit the art into the area below the top strip; zoom and pan stay inside the art.
function MapCanvas:Layout()
    local state = self.state
    local width, height = self.area:GetSize()
    local top, bottom = self.options.top or 0, self.options.bottom or 0
    local usableHeight = height - top - bottom
    self.canvas:SetShown(self:HasArt())
    self.noArt:SetShown(state.instanceID ~= nil and not self:HasArt())
    if not self:HasArt() or width <= 0 or usableHeight <= 0 then
        state.fit = nil
        self:LayoutPins()
        return
    end
    local fit = math.min(width / ART_WIDTH, usableHeight / ART_HEIGHT)
    local scale = fit * state.zoom
    local baseY = (bottom - top) / 2
    local slackX = math.max(0, (ART_WIDTH * scale - width) / 2)
    local slackY = math.max(0, (ART_HEIGHT * scale - usableHeight) / 2)
    if state.zoom == MIN_ZOOM then
        state.offsetX, state.offsetY = 0, baseY
    else
        state.offsetX = math.max(-slackX, math.min(slackX, state.offsetX))
        state.offsetY = math.max(baseY - slackY, math.min(baseY + slackY, state.offsetY))
    end
    state.fit = fit
    self.canvas:SetScale(scale)
    self.canvas:ClearAllPoints()
    self.canvas:SetPoint("CENTER", self.area, "CENTER", state.offsetX / scale, state.offsetY / scale)
    self:LayoutPins()
end


-- Piece texture i of a minimap floor (made on first use).
function MapCanvas:Piece(i)
    self.pieces = self.pieces or {}
    if not self.pieces[i] then self.pieces[i] = self.canvas:CreateTexture(nil, "ARTWORK") end
    return self.pieces[i]
end

-- A WoW Forever dungeon's own minimap textures: squares of pieceSize at { fileID, left, top }
-- pixels on the art canvas (the canvas clips what runs past its edge).
function MapCanvas:ShowPieces(floor)
    local pieces = floor and floor.pieces or {}
    for i, piece in ipairs(pieces) do
        local texture = self:Piece(i)
        texture:SetTexture(piece[1])
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", piece[2], -piece[3])
        texture:SetSize(floor.pieceSize, floor.pieceSize)
        texture:Show()
    end
    for i = #pieces + 1, #(self.pieces or {}) do self.pieces[i]:Hide() end
end

-- Client tiles (4x3), one custom texture, or minimap pieces; everything else hidden.
function MapCanvas:ShowFloorArt(floor)
    local tiled = floor and floor.base
    for i = 1, TILE_COUNT do
        if tiled then self.tiles[i]:SetTexture(floor.base .. i) end
        self.tiles[i]:SetShown(tiled and true or false)
    end
    self:ShowPieces(floor and floor.pieces and floor or nil)
    local single = floor and floor.texture
    if single then
        self.artTexture:SetTexture(floor.texture)
        self.artTexture:SetTexCoord(0, floor.texRight or 1, 0, floor.texBottom or 1)
    end
    self.artTexture:SetShown(single and true or false)
end

-- Show the current floor: art, floor name and arrows; zoom resets.
function MapCanvas:ApplyFloor()
    local state = self.state
    local count = #(state.floors or {})
    local floor = state.floors and state.floors[state.floor]
    self:ShowFloorArt(floor)
    self.floorButton.Label:SetText(floor and FloorLabel(floor, state.floor) or "")
    self.floorButton:SetShown(count > 1)
    self.floorMenu:Hide()
    state.zoom, state.offsetX, state.offsetY = MIN_ZOOM, 0, 0
    self:Layout()
end

-- Show floor `index` of the current dungeon (1 = first in the floor list).
function MapCanvas:SetFloor(index)
    if index < 1 or index > #(self.state.floors or {}) then return end
    self.state.floor = index
    self:ApplyFloor()
end

-- Show a dungeon's map (keeps floor and zoom when it is the same dungeon).
function MapCanvas:SetDungeon(instanceID, name)
    local state = self.state
    local dungeon = ns.GetDungeon(instanceID, name)
    if state.instanceID ~= instanceID then
        state.floor, state.zoom, state.offsetX, state.offsetY = 1, MIN_ZOOM, 0, 0
    end
    state.instanceID, state.dungeon = instanceID, dungeon
    state.floors = ns.GetFloors(instanceID, dungeon)
    if state.floor > #state.floors then state.floor = 1 end
    local art = ns.ART and ns.ART[instanceID]
    local lore = art and (art.lore or art.bg)
    self.lore:SetShown(lore ~= nil)
    if lore then
        self.lore:SetTexture(lore)
        self.lore:SetDesaturated(true)
    end
    self:ApplyFloor()
end

-- Show the floor a boss is on.
function MapCanvas:FocusBoss(boss)
    local position = ns.GetBossPos(self.state.instanceID, boss.name)
    local slot = position and ns.FloorSlot(self.state.floors or {}, position.floor or 1)
    if slot and slot ~= self.state.floor then
        self.state.floor = slot
        self:ApplyFloor()
    end
end

-- Wheel zoom that keeps the art point under the cursor in place.
function MapCanvas:ZoomAtCursor(delta)
    local state = self.state
    if not state.fit or not self:HasArt() then return end
    local zoom = state.zoom * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
    if zoom < MIN_ZOOM * ZOOM_SNAP then zoom = MIN_ZOOM end
    zoom = math.min(MAX_ZOOM, zoom)
    if zoom == state.zoom then return end
    local x, y = self:CursorOffset()
    local ratio = zoom / state.zoom
    state.offsetX = x - (x - state.offsetX) * ratio
    state.offsetY = y - (y - state.offsetY) * ratio
    state.zoom = zoom
    self:Layout()
end

-- While the left button is held: pan with the cursor (only when zoomed in).
function MapCanvas:DragUpdate()
    local drag = self.state.drag
    if not drag or not IsMouseButtonDown("LeftButton") then
        self.frame:SetScript("OnUpdate", nil)
        return
    end
    if self.state.zoom > MIN_ZOOM then
        local x, y = self:CursorOffset()
        self.state.offsetX = drag.offsetX + x - drag.x
        self.state.offsetY = drag.offsetY + y - drag.y
        self:Layout()
    end
end

-- Frame levels when the map lies on top of another canvas (world map overlay).
function MapCanvas:SetBaseLevel(base)
    self.frame:SetFrameLevel(base)
    self.area:SetFrameLevel(base + LEVEL_AREA)
    self.canvas:SetFrameLevel(base + LEVEL_ART)
    self.floorBar:SetFrameLevel(base + LEVEL_CONTROLS)
    self.footer:SetFrameLevel(base + LEVEL_CONTROLS)
    self.scaleBox:SetFrameLevel(base + LEVEL_CONTROLS)
end

ns.WatchSetting("bossIconScale", function()
    for _, map in ipairs(allMaps) do
        map:UpdateScaleText()
        map:LayoutPins()
    end
end)
