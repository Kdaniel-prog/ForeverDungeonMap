-- ForeverDungeonMap Probe
-- Read-only diagnostic: reports which map/position APIs work inside dungeons
-- on the WoW Forever client. Results go to chat and to SavedVariables
-- (WTF\Account\<acc>\SavedVariables\ForeverDungeonMapProbeDB.lua).
--
--   /fdm probe        full report (run inside a dungeon, ideally in a group)
--   /fdm map [id]     open the world map on a uiMapID (default: best candidate)
--   /fdm watch        print player/party positions every second for 15 s
--   /fdm clear        delete saved reports

local ADDON = ...
local PREFIX = "|cff33ff99FDM|r "
local lines            -- current report buffer
local lastCandidates = {}

local function out(fmt, ...)
    local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    if lines then lines[#lines + 1] = s end
    -- every message also goes to a persistent log (saved on /reload or logout)
    if ForeverDungeonMapProbeDB then
        local log = ForeverDungeonMapProbeDB.log or {}
        ForeverDungeonMapProbeDB.log = log
        log[#log + 1] = date("%H:%M:%S ") .. s
        if #log > 500 then table.remove(log, 1) end
    end
    print(PREFIX .. s)
end

local function str(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = tostring((select(i, ...))) end
    return table.concat(t, ", ")
end

-- pcall wrapper that returns a printable string of all results.
local function try(f, ...)
    if type(f) ~= "function" then return "n/a (missing API)" end
    local function finish(ok, ...)
        if not ok then return "ERROR: " .. tostring((...)) end
        return str(...)
    end
    return finish(pcall(f, ...))
end

local function vec(v)
    if v == nil then return "nil" end
    if type(v) == "table" and v.GetXY then
        local x, y = v:GetXY()
        return string.format("%.4f, %.4f", x or -1, y or -1)
    end
    return tostring(v)
end

local function groupUnits()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function norm(s)
    if type(s) ~= "string" then return "" end
    return (s:lower():gsub("^the ", ""):gsub("[^%w\128-\255]", ""))
end

local function hasArt(id)
    local ok, layers = pcall(C_Map.GetMapArtLayers, id)
    return ok and type(layers) == "table" and #layers > 0, ok and type(layers) == "table" and #layers or 0
end

local function describeMap(id, indent)
    indent = indent or "  "
    local info = C_Map.GetMapInfo(id)
    if not info then out("%suiMap %s: GetMapInfo = nil", indent, tostring(id)); return end
    local art, nLayers = hasArt(id)
    out("%suiMap %d '%s' type=%s parent=%s art=%s layers=%d", indent, id, tostring(info.name),
        tostring(info.mapType), tostring(info.parentMapID), tostring(art), nLayers)
    if C_Map.GetMapGroupID then
        local gid = C_Map.GetMapGroupID(id)
        if gid then
            local members = C_Map.GetMapGroupMembersInfo and C_Map.GetMapGroupMembersInfo(gid) or {}
            local names = {}
            for _, m in ipairs(members) do names[#names + 1] = m.mapID .. "=" .. tostring(m.name) end
            out("%s  mapGroup %d: %s", indent, gid, table.concat(names, " | "))
        end
    end
end

-- Scan uiMap IDs for maps whose name matches the instance name.
local function findMapsByName(name)
    local wanted = norm(name)
    local found = {}
    if wanted == "" then return found end
    local function check(id)
        local info = C_Map.GetMapInfo(id)
        if info and norm(info.name) == wanted then found[#found + 1] = id end
    end
    for id = 1, 4000 do check(id) end
    for id = 900000, 900050 do check(id) end
    return found
end

local function probe()
    lines = {}
    out("==== PROBE %s ====", date("%Y-%m-%d %H:%M:%S"))
    out("client: %s", try(GetBuildInfo))
    out("IsInInstance: %s", try(IsInInstance))
    local name, instType, diffID, diffName, maxPlayers, dynDiff, isDyn, instanceID = GetInstanceInfo()
    out("GetInstanceInfo: name=%s type=%s diff=%s max=%s instanceID=%s",
        tostring(name), tostring(instType), tostring(diffID), tostring(maxPlayers), tostring(instanceID))
    out("zone: %s / %s / %s", tostring(GetZoneText()), tostring(GetSubZoneText()), tostring(GetMinimapZoneText()))

    -- 1) best map for the player
    local best = C_Map.GetBestMapForUnit("player")
    out("C_Map.GetBestMapForUnit(player) = %s", tostring(best))
    if best then describeMap(best) end

    -- 2) maps with the instance's name
    local candidates = findMapsByName(name)
    out("uiMaps named like the instance: %s", #candidates > 0 and table.concat(candidates, ", ") or "none")
    for _, id in ipairs(candidates) do describeMap(id) end
    lastCandidates = {}
    if best then lastCandidates[#lastCandidates + 1] = best end
    for _, id in ipairs(candidates) do
        if id ~= best then lastCandidates[#lastCandidates + 1] = id end
    end

    -- 3) positions of every group member
    out("--- unit positions (%d units) ---", #groupUnits())
    for _, unit in ipairs(groupUnits()) do
        local uname = UnitName(unit) or "?"
        local y, x, z, mapInst = UnitPosition(unit)
        out("%s (%s): UnitPosition y=%s x=%s z=%s inst=%s | connected=%s visible=%s",
            unit, uname, tostring(y), tostring(x), tostring(z), tostring(mapInst),
            tostring(UnitIsConnected(unit)), tostring(UnitIsVisible(unit)))
        local ubest = C_Map.GetBestMapForUnit(unit)
        out("   GetBestMapForUnit=%s", tostring(ubest))
        for _, id in ipairs(lastCandidates) do
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, id, unit)
            out("   GetPlayerMapPosition(%d) = %s", id, ok and vec(pos) or ("ERROR " .. tostring(pos)))
        end
        if ubest and not tContains(lastCandidates, ubest) then
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, ubest, unit)
            out("   GetPlayerMapPosition(%d) = %s", ubest, ok and vec(pos) or ("ERROR " .. tostring(pos)))
        end
    end

    -- 4) world -> map conversion (only meaningful if UnitPosition worked)
    local py, px, _, pinst = UnitPosition("player")
    if py and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        for _, id in ipairs(lastCandidates) do
            out("GetMapPosFromWorldPos(inst=%s, map=%d) = %s", tostring(pinst), id,
                try(function()
                    local m, p = C_Map.GetMapPosFromWorldPos(pinst, CreateVector2D(py, px), id)
                    return tostring(m) .. " / " .. vec(p)
                end))
        end
    end

    -- 5) what the world map currently does
    if WorldMapFrame then
        out("WorldMapFrame:GetMapID() = %s (shown=%s)", try(WorldMapFrame.GetMapID, WorldMapFrame),
            tostring(WorldMapFrame:IsShown()))
        local providers = 0
        for _ in pairs(WorldMapFrame.dataProviders or {}) do providers = providers + 1 end
        out("WorldMapFrame data providers: %d, GroupMembersDataProvider=%s, UnitPositionFrame template=%s",
            providers, tostring(GroupMembersDataProviderMixin ~= nil), tostring(UnitPositionFrameMixin ~= nil))
    end
    out("API present: GetPlayerMapPosition=%s GetMapPosFromWorldPos=%s SendAddonMessage=%s",
        tostring(C_Map.GetPlayerMapPosition ~= nil), tostring(C_Map.GetMapPosFromWorldPos ~= nil),
        tostring(C_ChatInfo and C_ChatInfo.SendAddonMessage ~= nil))
    out("Next: '/fdm map' opens the best candidate; check if party dots show and names appear on hover.")

    ForeverDungeonMapProbeDB.runs = ForeverDungeonMapProbeDB.runs or {}
    table.insert(ForeverDungeonMapProbeDB.runs, { name = name, instanceID = instanceID, lines = lines })
    out("Saved report #%d (written to disk on /reload or logout).", #ForeverDungeonMapProbeDB.runs)
    lines = nil
end

local function openMap(id)
    id = tonumber(id) or lastCandidates[1] or C_Map.GetBestMapForUnit("player")
    if not id then out("No map id. Run /fdm probe first or give an id: /fdm map 123"); return end
    describeMap(id)
    for _, unit in ipairs(groupUnits()) do
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, id, unit)
        out("  GetPlayerMapPosition(%d, %s %s) = %s", id, unit, UnitName(unit) or "?", ok and vec(pos) or ("ERROR " .. tostring(pos)))
    end
    if not WorldMapFrame:IsShown() then ToggleWorldMap() end
    WorldMapFrame:SetMapID(id)
    out("World map set to uiMap %d (GetMapID now %s). Look for YOUR ARROW and party dots, hover them for names.",
        id, tostring(WorldMapFrame:GetMapID()))
end

-- Test: blow the native minimap up to a big map in the middle of the screen.
-- The minimap is drawn by the client, so it may show the dungeon layout and
-- party blips even though the position APIs return nil. Run again to restore.
local bigState
local function bigMinimap(size)
    if bigState then
        Minimap:SetParent(bigState.parent)
        Minimap:ClearAllPoints()
        for _, p in ipairs(bigState.points) do Minimap:SetPoint(unpack(p)) end
        Minimap:SetSize(bigState.w, bigState.h)
        Minimap:SetFrameStrata(bigState.strata)
        Minimap:SetFrameLevel(bigState.level)
        Minimap:SetZoom(bigState.zoom)
        Minimap:SetMaskTexture(bigState.mask or "Interface\\Masks\\CircleMaskScalable")
        Minimap:SetScript("OnMouseWheel", bigState.wheel)
        if MinimapCluster then MinimapCluster:Show() end
        for _, obj in ipairs(bigState.hidden or {}) do obj:Show() end
        for _, btn in ipairs(bigState.faded or {}) do btn:SetAlpha(1); btn:EnableMouse(true) end
        if bigState.bg then bigState.bg:Hide() end
        Minimap:SetScale(bigState.scale or 1)
        local zoom = bigState.zoom
        out("Minimap restored (mask=%s).", tostring(bigState.mask))
        bigState = nil
        -- force the client to re-render the minimap at its old size
        Minimap:SetZoom(zoom == 0 and 1 or 0)
        C_Timer.After(0.1, function() Minimap:SetZoom(zoom) end)
        return
    end
    local s = { parent = Minimap:GetParent(), points = {}, strata = Minimap:GetFrameStrata(),
                level = Minimap:GetFrameLevel(), zoom = Minimap:GetZoom() }
    s.w, s.h = Minimap:GetSize()
    for i = 1, Minimap:GetNumPoints() do s.points[i] = { Minimap:GetPoint(i) } end
    bigState = s
    local sizeArg, scaleArg = (size or ""):match("^(%S*)%s*(%S*)$")
    size = tonumber(sizeArg) or 600
    local scale = tonumber(scaleArg) or 1
    s.scale = Minimap:GetScale()
    Minimap:SetScale(scale)
    Minimap:SetParent(UIParent)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    Minimap:SetSize(size, size)
    Minimap:SetFrameStrata("HIGH")
    -- square map, old round border (lives in MinimapCluster) hidden, wheel zoom
    s.mask = Minimap.GetMaskTexture and Minimap:GetMaskTexture() or nil
    out("original mask: %s (GetMaskTexture %s)", tostring(s.mask), Minimap.GetMaskTexture and "exists" or "missing")
    Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
    if MinimapCluster then MinimapCluster:Hide() end
    -- the round border, zoom buttons and tracking icons are children/regions of
    -- Minimap itself; hide them (party blips are drawn by the client, not by these)
    s.hidden = {}
    local names = {}
    for _, list in ipairs({ { Minimap:GetChildren() }, { Minimap:GetRegions() } }) do
        for _, obj in ipairs(list) do
            if obj:IsShown() then
                obj:Hide()
                s.hidden[#s.hidden + 1] = obj
                names[#names + 1] = obj:GetDebugName() or obj:GetObjectType()
            end
        end
    end
    -- zoom buttons only show on mouse-over, so they were hidden above; fade them out instead
    s.faded = {}
    for _, btn in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut, _G.MinimapZoomIn, _G.MinimapZoomOut }) do
        if btn and not tContains(s.faded, btn) then
            s.faded[#s.faded + 1] = btn
            btn:SetAlpha(0)
            btn:EnableMouse(false)
        end
    end
    out("hid %d Minimap children/regions: %s", #names, table.concat(names, ", "))
    s.wheel = Minimap:GetScript("OnMouseWheel")
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(self, delta)
        local z = math.max(0, math.min(self:GetZoomLevels() - 1, self:GetZoom() + delta))
        self:SetZoom(z)
    end)
    s.bg = s.bg or CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    s.bg:SetFrameStrata("MEDIUM")
    s.bg:SetPoint("TOPLEFT", Minimap, -6, 6)
    s.bg:SetPoint("BOTTOMRIGHT", Minimap, 6, -6)
    s.bg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                       insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    s.bg:SetBackdropColor(0, 0, 0, 0.85)
    s.bg:Show()
    -- nudge the zoom so the client re-renders at the new size, then zoom fully out
    Minimap:SetZoom(math.min(1, Minimap:GetZoomLevels() - 1))
    C_Timer.After(0.1, function() if bigState then Minimap:SetZoom(0) end end)
    out("Big minimap %dx%d, zoom levels=%d, rotate=%s. Hover the party dots! '/fdm bigmini' again restores.",
        size, size, Minimap:GetZoomLevels(), tostring(GetCVar("rotateMinimap")))
end

-- Test: draw a classic dungeon's world-map art straight from the client files
-- (Interface\WorldMap\<Name>\<Name><floor>_1..12, 4x3 grid of 256px tiles,
-- visible part 1002x668). Click the picture to close it.
local artFrame
local function showArt(arg)
    local name, floorNum = (arg or ""):match("^(%S*)%s*(%d*)$")
    if not name or name == "" then name = "WailingCaverns" end
    floorNum = tonumber(floorNum) or 1
    if not artFrame then
        artFrame = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        artFrame:SetSize(1002, 668)
        artFrame:SetScale(0.8)
        artFrame:SetPoint("CENTER")
        artFrame:SetFrameStrata("DIALOG")
        artFrame:SetClipsChildren(true)
        artFrame:SetScript("OnClick", function(self) self:Hide() end)
        artFrame.tiles = {}
        for i = 1, 12 do
            local t = artFrame:CreateTexture(nil, "ARTWORK")
            t:SetSize(256, 256)
            t:SetPoint("TOPLEFT", ((i - 1) % 4) * 256, -math.floor((i - 1) / 4) * 256)
            artFrame.tiles[i] = t
        end
    end
    local base = string.format("Interface\\WorldMap\\%s\\%s%d_", name, name, floorNum)
    local ok = 0
    for i = 1, 12 do
        local path = base .. i
        artFrame.tiles[i]:SetTexture(path)
        if artFrame.tiles[i]:GetTexture() then ok = ok + 1 end
    end
    artFrame:Show()
    out("art %s: %d/12 tiles loaded (click the picture to close)", base, ok)
    if name == "WailingCaverns" then describeMap(279) end
end

-- Test: does any Lua-readable object leak the player's facing inside a
-- dungeon? Turns on the rotating minimap for 15 s and logs the rotation of
-- every texture on the minimap (the compass ring is rotated by the client).
-- Also dumps all Minimap / C_Minimap functions to look for hidden helpers.
local compassTicker
local function compass()
    -- 1) API discovery
    local mt = getmetatable(Minimap)
    local names = {}
    for k in pairs(mt and mt.__index or {}) do names[#names + 1] = k end
    table.sort(names)
    ForeverDungeonMapProbeDB.minimapMethods = names
    local interesting = {}
    for _, n in ipairs(names) do
        local l = n:lower()
        if l:find("pos") or l:find("rot") or l:find("fac") or l:find("ping") or l:find("blip")
            or l:find("player") or l:find("unit") or l:find("arrow") or l:find("track") then
            interesting[#interesting + 1] = n
        end
    end
    out("Minimap methods: %d total. Interesting: %s", #names, table.concat(interesting, ", "))
    if C_Minimap then
        local c = {}
        for k in pairs(C_Minimap) do c[#c + 1] = k end
        table.sort(c)
        out("C_Minimap: %s", table.concat(c, ", "))
    else
        out("C_Minimap: missing")
    end
    out("ping position now: %s", try(Minimap.GetPingPosition, Minimap))

    -- 2) rotating minimap, watch every texture's rotation while the player turns
    local oldRotate = GetCVar("rotateMinimap")
    SetCVar("rotateMinimap", "1")
    local textures = {}
    local function collect(frame, depth)
        if not frame or depth > 3 then return end
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetRotation then textures[#textures + 1] = r end
        end
        for _, child in ipairs({ frame:GetChildren() }) do collect(child, depth + 1) end
    end
    collect(Minimap, 0)
    if MinimapBackdrop then collect(MinimapBackdrop, 0) end
    if MinimapCluster then collect(MinimapCluster, 0) end
    out("rotateMinimap=1 for 15 s, watching %d textures. TURN AROUND slowly now!", #textures)
    if compassTicker then compassTicker:Cancel() end
    local n = 0
    out("C_Minimap.GetUiMapID=%s GetViewRadius=%s GetDrawGroundTextures=%s",
        try(C_Minimap and C_Minimap.GetUiMapID), try(C_Minimap and C_Minimap.GetViewRadius),
        try(C_Minimap and C_Minimap.GetDrawGroundTextures))
    local function tick()
        n = n + 1
        local parts = {}
        for _, t in ipairs(textures) do
            local ok, rot = pcall(t.GetRotation, t)
            if ok and type(rot) == "number" and rot ~= 0 then
                local okName, name = pcall(t.GetDebugName, t)
                parts[#parts + 1] = string.format("%s=%.3f", okName and tostring(name) or "?", rot)
            end
        end
        local cr = _G.MinimapCompassTexture and _G.MinimapCompassTexture.GetRotation and _G.MinimapCompassTexture:GetRotation()
        out("%d: compass=%s facing=%s radius=%s nonzero(%d): %s", n, tostring(cr), tostring(GetPlayerFacing()),
            try(C_Minimap and C_Minimap.GetViewRadius), #parts, #parts > 0 and table.concat(parts, " ", 1, math.min(#parts, 8)) or "none")
    end
    compassTicker = C_Timer.NewTicker(1, function()
        local ok, err = pcall(tick)
        if not ok then out("tick ERROR: %s", tostring(err)) end
        if n >= 15 or not ok then
            if compassTicker then compassTicker:Cancel() end
            SetCVar("rotateMinimap", oldRotate)
            out("rotateMinimap restored to %s. Now /reload to save.", tostring(oldRotate))
        end
    end, 15)
end

local watcher
local function watch()
    if watcher then watcher:Cancel() end
    local ticks = 0
    watcher = C_Timer.NewTicker(1, function()
        ticks = ticks + 1
        local parts = {}
        local map = lastCandidates[1] or C_Map.GetBestMapForUnit("player")
        for _, unit in ipairs(groupUnits()) do
            local y, x = UnitPosition(unit)
            local mp = map and C_Map.GetPlayerMapPosition(map, unit)
            parts[#parts + 1] = string.format("%s w=%s map=%s", UnitName(unit) or unit,
                y and string.format("%.1f,%.1f", x, y) or "nil", vec(mp))
        end
        -- dead-reckoning inputs: facing (radians) and speed (yards/s), both may be restricted in instances
        local facing = GetPlayerFacing and GetPlayerFacing()
        local speed = GetUnitSpeed and GetUnitSpeed("player")
        out("%d: subzone='%s' facing=%s speed=%s moving=%s | %s", ticks, tostring(GetSubZoneText()),
            tostring(facing), tostring(speed), tostring(IsPlayerMoving and IsPlayerMoving()),
            table.concat(parts, " | "))
    end, 15)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    ForeverDungeonMapProbeDB = ForeverDungeonMapProbeDB or {}
    f:UnregisterEvent("ADDON_LOADED")
end)

SLASH_FOREVERDUNGEONMAPPROBE1 = "/fdm"
SlashCmdList.FOREVERDUNGEONMAPPROBE = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "probe" then probe()
    elseif cmd == "map" then openMap(arg)
    elseif cmd == "watch" then watch()
    elseif cmd == "bigmini" then bigMinimap(arg)
    elseif cmd == "art" then showArt(arg)
    elseif cmd == "compass" then compass()
    elseif cmd == "pois" then
        -- which map POIs does the client know for the shown (or given) map? looking for caves
        local mapID = tonumber(arg) or (WorldMapFrame and WorldMapFrame:GetMapID()) or C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo(mapID)
        out("POIs for map %s (%s):", tostring(mapID), info and info.name or "?")
        if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap then
            local ids = C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}
            out("  areaPOIs: %d", #ids)
            for _, id in ipairs(ids) do
                local p = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
                if p then
                    out("   %d '%s' atlas=%s tex=%s pos=%s", id, tostring(p.name), tostring(p.atlasName),
                        tostring(p.textureIndex), vec(p.position))
                end
            end
        else
            out("  C_AreaPoiInfo missing")
        end
        if C_Map.GetMapLinksForMap then
            local links = C_Map.GetMapLinksForMap(mapID) or {}
            out("  mapLinks: %d", #links)
            for _, l in ipairs(links) do out("   link '%s' atlas=%s -> %s", tostring(l.name), tostring(l.atlasName), tostring(l.linkedUiMapID)) end
        end
        if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
            local e = C_EncounterJournal.GetDungeonEntrancesForMap(mapID) or {}
            out("  dungeonEntrances: %d", #e)
        end
        local children = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(mapID) or {}
        local n = {}
        for _, c in ipairs(children) do
            if c.mapType and c.mapType >= 4 then n[#n + 1] = c.mapID .. "=" .. tostring(c.name) .. "(t" .. c.mapType .. ")" end
        end
        out("  child maps (micro/orphan/dungeon): %s", #n > 0 and table.concat(n, ", ") or "none")
    elseif cmd == "rotate" then
        SetCVar("rotateMinimap", arg == "1" and "1" or "0")
        out("rotateMinimap = %s", GetCVar("rotateMinimap"))
    elseif cmd == "ground" then
        -- toggle minimap terrain: blips only vs. normal
        local on = C_Minimap.GetDrawGroundTextures()
        C_Minimap.SetDrawGroundTextures(not on)
        out("minimap ground textures: %s", tostring(C_Minimap.GetDrawGroundTextures()))
    elseif cmd == "zoom" then
        -- try any zoom value, including below 0: /fdm zoom -1
        local z = tonumber(arg)
        if not z then out("usage: /fdm zoom <number>  (levels: %d, now: %s)", Minimap:GetZoomLevels(), tostring(Minimap:GetZoom())); return end
        local ok, err = pcall(Minimap.SetZoom, Minimap, z)
        out("SetZoom(%s): ok=%s err=%s -> GetZoom=%s levels=%d", tostring(z), tostring(ok), tostring(err),
            tostring(Minimap:GetZoom()), Minimap:GetZoomLevels())
    elseif cmd == "mask" then
        -- try round mask candidates on the normal minimap: /fdm mask 1|2|3
        local masks = {
            "Interface\\Masks\\CircleMaskScalable",
            "Textures\\MinimapMask",
            "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        }
        local m = masks[tonumber(arg) or 0]
        if not m then out("usage: /fdm mask 1|2|3"); return end
        Minimap:SetMaskTexture(m)
        local z = Minimap:GetZoom()
        Minimap:SetZoom(z == 0 and 1 or 0)
        C_Timer.After(0.1, function() Minimap:SetZoom(z) end)
        out("mask %s set: %s  -> is the minimap visible and round?", arg, m)
    elseif cmd == "clear" then ForeverDungeonMapProbeDB = {}; out("cleared")
    else
        out("/fdm probe | /fdm map [uiMapID] | /fdm watch | /fdm bigmini [size] | /fdm clear")
    end
end
