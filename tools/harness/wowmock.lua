-- wowmock.lua - headless WoW API mock for ForeverDungeonMap tests (Lua 5.1)
-- Loaded by tools/harness/run.py before the addon. Everything the mock knows
-- lives in the global MOCK table; the report is collected in MOCK.report.
--
-- Design:
--  * widgets are tables with a per-type method table; real WoW widget methods
--    the mock does not model are no-ops (KNOWN_NOOP list), every other
--    capitalised key is nil -> calling it fails like in the client, and the
--    read is logged (MOCK.report.unknownKeys).
--  * reads of undefined globals from addon files are logged (missingGlobals).
--  * a simple layout engine resolves anchors (SetPoint/SetSize) to rects.
--  * a taint model: a debug call hook marks the current execution tainted as
--    soon as addon code runs; protected calls in tainted execution are logged
--    as ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN.

MOCK = MOCK or {}
local M = MOCK
M.config = M.config or {}
local CFG = M.config

M.report = {
    errors = {},          -- { msg, trace, where, count }
    missingGlobals = {},  -- name -> { [location] = count }
    unknownKeys = {},     -- "Type.Key" -> { [location] = count }
    protected = {},       -- { kind, func, where, trace }
    prints = {},
    globalsWritten = {},  -- name -> location
    log = {},
}
local R = M.report

M.addonSourcePattern = M.addonSourcePattern or "ForeverDungeonMap"

local function isAddonSource(src)
    return type(src) == "string" and src:find(M.addonSourcePattern, 1, true) ~= nil
        and not src:find("harness", 1, true)
end

-- first addon file:line on the current stack
local function addonWhere(level)
    level = level or 3
    for i = level, 40 do
        local info = debug.getinfo(i, "Sl")
        if not info then break end
        if isAddonSource(info.source) then
            return (info.short_src or info.source) .. ":" .. tostring(info.currentline)
        end
    end
    return nil
end
M.addonWhere = addonWhere

function M.Log(fmt, ...)
    local s = select("#", ...) > 0 and fmt:format(...) or fmt
    R.log[#R.log + 1] = s
end

local errIndex = {}
function M.RecordError(msg, trace)
    msg = tostring(msg)
    local key = msg
    local e = errIndex[key]
    if e then e.count = e.count + 1; return end
    e = { msg = msg, trace = trace or debug.traceback("", 2), count = 1, context = M.context }
    errIndex[key] = e
    R.errors[#R.errors + 1] = e
end

local function traceHandler(err)
    return { msg = err, trace = debug.traceback("", 2) }
end

-- run fn securely-dispatched (new execution path), record errors like the client
function M.SafeCall(fn, ...)
    local args, n = { ... }, select("#", ...)
    local ok, res = xpcall(function() return fn(unpack(args, 1, n)) end, traceHandler)
    if not ok then
        if type(res) == "table" then M.RecordError(res.msg, res.trace) else M.RecordError(res) end
    end
    return ok
end

---------------------------------------------------------------------------
-- taint model
---------------------------------------------------------------------------

M.taint = nil      -- addon name when the current execution is tainted
M.combat = false

local function callHook()
    if M.taint then return end
    local info = debug.getinfo(2, "S")
    if info and isAddonSource(info.source) then M.taint = "ForeverDungeonMap" end
end
debug.sethook(callHook, "c")

-- A new execution path starting in Blizzard code (event, user click, timer).
function M.Dispatch(fn, ...)
    local saved = M.taint
    M.taint = nil
    local ok = M.SafeCall(fn, ...)
    M.taint = saved
    return ok
end

-- secureexecuterange-style call: the callee's taint does not spread to the caller
function M.Isolated(fn, ...)
    local saved = M.taint
    local ok = M.SafeCall(fn, ...)
    M.taint = saved
    return ok
end

-- kind: "nocombat" (blocked from insecure code in combat) or "forbidden" (always)
function M.ProtectedCall(name, kind, objName)
    if not M.taint then return true end
    if kind == "nocombat" and not M.combat then return true end
    local ev = kind == "forbidden" and "ADDON_ACTION_FORBIDDEN" or "ADDON_ACTION_BLOCKED"
    R.protected[#R.protected + 1] = {
        event = ev, func = name, object = objName, where = addonWhere(3) or "?",
        trace = debug.traceback("", 3), context = M.context, combat = M.combat,
    }
    return false
end

---------------------------------------------------------------------------
-- timers & time
---------------------------------------------------------------------------

M.now = 1000
local timers = {}
function GetTime() return M.now end
function M.AddTimer(delay, fn, iterations, owner)
    local t = { at = M.now + math.max(0, delay or 0), fn = fn, delay = delay, left = iterations, owner = owner }
    timers[#timers + 1] = t
    return t
end
function M.Advance(seconds)
    local target = M.now + (seconds or 0)
    for _ = 1, 10000 do
        local best, bi
        for i, t in ipairs(timers) do
            if not t.cancelled and t.at <= target and (not best or t.at < best.at) then best, bi = t, i end
        end
        if not best then break end
        M.now = math.max(M.now, best.at)
        if best.left and best.left > 1 then
            best.left = best.left - 1
            best.at = best.at + math.max(0.001, best.delay or 0)
        elseif best.left == nil and best.ticker then
            best.at = best.at + math.max(0.001, best.delay or 0)
        else
            table.remove(timers, bi)
        end
        M.Dispatch(best.fn, best.owner)
    end
    M.now = target
    -- drop cancelled
    for i = #timers, 1, -1 do if timers[i].cancelled then table.remove(timers, i) end end
end

C_Timer = {}
function C_Timer.After(delay, fn)
    if type(fn) ~= "function" then error("Usage: C_Timer.After(seconds, callback)", 2) end
    M.AddTimer(delay, fn)
end
local TickerMT = { __index = {
    Cancel = function(self) self._t.cancelled = true end,
    IsCancelled = function(self) return self._t.cancelled == true end,
} }
function C_Timer.NewTicker(delay, fn, iterations)
    local h = setmetatable({}, TickerMT)
    local t = M.AddTimer(delay, function() fn(h) end, iterations)
    t.ticker = iterations == nil
    h._t = t
    return h
end
function C_Timer.NewTimer(delay, fn)
    local h = setmetatable({}, TickerMT)
    h._t = M.AddTimer(delay, function() fn(h) end, 1)
    return h
end

---------------------------------------------------------------------------
-- fonts
---------------------------------------------------------------------------

local FONT_SIZES = {
    GameFontNormal = 12, GameFontHighlight = 12, GameFontDisable = 12, GameFontRed = 12, GameFontGreen = 12,
    GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
    GameFontNormalLarge = 16, GameFontHighlightLarge = 16, GameFontDisableLarge = 16,
    GameFontNormalHuge = 20, GameFontHighlightHuge = 20,
    GameFontNormalMed1 = 13, GameFontNormalMed2 = 14, GameFontNormalMed3 = 14, GameFontHighlightMedium = 14,
    GameFontNormalOutline = 12, GameFontHighlightOutline = 12, GameFontNormalLeft = 12, GameFontHighlightLeft = 12,
    GameFontNormalSmallLeft = 10, GameFontHighlightSmallLeft = 10, GameFontWhite = 12, GameFontBlack = 12,
    GameFontNormalTiny = 9, GameFontHighlightExtraSmall = 9, GameFontNormalShadowHuge2 = 24,
    GameFontNormalLarge2 = 18, GameFontHighlightLarge2 = 18, GameFontNormalHuge2 = 24, GameFontNormalHuge3 = 28,
    QuestTitleFont = 18, QuestTitleFontBlackShadow = 18, QuestFont = 13, QuestFontNormalSmall = 12,
    QuestFontHighlight = 13, QuestFontLeft = 13,
    SystemFont_Small = 10, SystemFont_Med1 = 12, SystemFont_Med2 = 13, SystemFont_Med3 = 14, SystemFont_Large = 16,
    SystemFont_Huge1 = 20, SystemFont_Shadow_Med1 = 12, SystemFont_Shadow_Large = 16, SystemFont_Shadow_Huge1 = 20,
    NumberFontNormal = 12, NumberFontNormalSmall = 10, NumberFontNormalLarge = 14,
    ChatFontNormal = 14, ChatFontSmall = 12, Game12Font = 12, Game13Font = 13, Game15Font = 15, Game18Font = 18,
    Game20Font = 20, Game24Font = 24, Fancy16Font = 16, Fancy22Font = 22, Fancy24Font = 24,
    GameTooltipText = 12, GameTooltipHeaderText = 14, GameTooltipTextSmall = 10,
    MailTextFontNormal = 15, InvoiceTextFontNormal = 12,
}
M.FONT_SIZES = FONT_SIZES
for _, name in ipairs(CFG.missingFonts or {}) do FONT_SIZES[name] = nil end

local FontMT = { __index = {} }
local FontM = FontMT.__index
function FontM:GetFont() return "Fonts\\FRIZQT__.TTF", self._size, "" end
function FontM:SetFont(path, size) self._size = size or self._size; return true end
function FontM:GetName() return self._name end
function FontM:GetObjectType() return "Font" end
function FontM:IsObjectType(t) return t == "Font" end
function FontM:SetTextColor() end
function FontM:GetTextColor() return 1, 1, 1, 1 end
function FontM:SetShadowOffset() end
function FontM:SetShadowColor() end
function FontM:SetJustifyH() end
function FontM:SetJustifyV() end
function FontM:CopyFontObject(o) if type(o) == "string" then o = _G[o] end self._size = o and o._size or self._size end
function FontM:SetFontObject(o) self:CopyFontObject(o) end
function FontM:GetFontObjectForAlphabet() return self end
for name, size in pairs(FONT_SIZES) do _G[name] = setmetatable({ _name = name, _size = size, _isFont = true }, FontMT) end
function CreateFont(name)
    local f = setmetatable({ _name = name, _size = 12, _isFont = true }, FontMT)
    if name then _G[name] = f; FONT_SIZES[name] = 12 end
    return f
end

---------------------------------------------------------------------------
-- widgets
---------------------------------------------------------------------------

-- real WoW widget methods we accept as no-ops (return nil)
local KNOWN_NOOP = {}
for name in ([[
SetHitRectInsets GetHitRectInsets SetResizable SetResizeBounds SetMinResize SetMaxResize SetDontSavePosition
SetIgnoreParentScale SetIgnoreParentAlpha SetFixedFrameStrata SetFixedFrameLevel SetFlattensRenderLayers
EnableKeyboard SetPropagateKeyboardInput SetHyperlinksEnabled EnableDrawLayer DisableDrawLayer SetBlendMode
SetSnapToPixelGrid SetTexelSnappingBias SetHorizTile SetVertTile SetRotation SetMotionScriptsWhileDisabled
SetPropagateMouseMotion SetShadowColor SetIndentedWordWrap SetNonSpaceWrap SetMaxLines SetAlphaGradient
SetCollapsesLayout SetTextScale SetMultiLine SetCountInvisibleLetters SetHistoryLines SetBlinkSpeed
SetCursorPosition HighlightText SetTextInsets SetMaxLetters SetNumeric SetFocus ClearFocus SetUserPlaced
SetClampRectInsets SetDepth SetFrameBuffer SetIsFrameBuffer SetHighlightLocked SetButtonState SetDrawEdge
SetDrawBling SetSwipeColor SetReverse SetCooldown SetMinMaxValues SetValueStep SetObeyStepOnDrag
SetOrientation SetThumbTexture SetStatusBarTexture SetStatusBarColor SetToplevel SetClampedToScreen
SetMovable RegisterForDrag SetClipsChildren SetID SetAttribute SetAttributeNoHandler StopAnimating
SetDrawLayer SetBackdropBorderColor SetNormalFontObject SetHighlightFontObject SetDisabledFontObject
SetPushedTextOffset RegisterForClicks RegisterForMouse SetDesaturation SetDesaturated SetVertexColor
SetTexCoord SetGradient SetGradientAlpha SetMask SetAtlas SetSpacing SetShadowOffset SetJustifyH SetJustifyV
SetWordWrap SetTextColor SetAutoFocus SetMouseClickEnabled SetMouseMotionEnabled SetScalingLimits
SetPassThroughButtons SetPropagateMouseClicks StartMoving StopMovingOrSizing EnableMouse EnableMouseWheel
SetFrameStrata LockHighlight UnlockHighlight Enable Disable SetEnabled SetFormattedText SetFontObject SetFont
ClearHighlightTexture ClearNormalTexture ClearPushedTexture ClearDisabledTexture SetParentKey
UpdateScrollChildRect SetHorizontalScroll SetVerticalScroll RemoveMaskTexture SetTextHeight
]]):gmatch("%S+") do KNOWN_NOOP[name] = true end

local ANCHORS = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 } }
local STRATA = { WORLD = 1, BACKGROUND = 2, LOW = 3, MEDIUM = 4, HIGH = 5, DIALOG = 6, FULLSCREEN = 7,
    FULLSCREEN_DIALOG = 8, TOOLTIP = 9 }
local DRAW_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }

local Types = {}       -- type name -> { methods = {}, parent = typeName }
local function defType(name, parent)
    local t = { name = name, methods = {}, parent = parent }
    Types[name] = t
    return t.methods
end

local function findMethod(typeName, key)
    local t = Types[typeName]
    while t do
        local m = t.methods[key]
        if m ~= nil then return m end
        t = Types[t.parent]
    end
end

local noopCache = {}
local function noop(key)
    local f = noopCache[key]
    if not f then
        if key:find("^Is") or key:find("^Has") then f = function() return false end
        else f = function() return nil end end
        noopCache[key] = f
    end
    return f
end

local WidgetMT = {}
WidgetMT.__index = function(obj, key)
    local m = findMethod(rawget(obj, "_type"), key)
    if m ~= nil then return m end
    if type(key) == "string" then
        if KNOWN_NOOP[key] then return noop(key) end
        if key:match("^%u") then
            local where = addonWhere(3)
            if where then
                local k = rawget(obj, "_type") .. "." .. key
                R.unknownKeys[k] = R.unknownKeys[k] or {}
                R.unknownKeys[k][where] = (R.unknownKeys[k][where] or 0) + 1
            end
        end
    end
    return nil
end
WidgetMT.__tostring = function(o) return ("<%s %s>"):format(rawget(o, "_type"), tostring(rawget(o, "_name") or "")) end

local allWidgets = {}
M.allWidgets = allWidgets
local function isWidget(v) return type(v) == "table" and getmetatable(v) == WidgetMT end
M.isWidget = isWidget

local function typeErr(fname, n, want, got, level)
    error(("bad argument #%d to '%s' (%s expected, got %s)"):format(n, fname, want, type(got)), (level or 2) + 1)
end
local function checkNum(fname, n, v, optional)
    if v == nil and optional then return end
    if type(v) ~= "number" then typeErr(fname, n, "number", v, 2) end
    if v ~= v then error(("bad argument #%d to '%s' (number is NaN)"):format(n, fname), 3) end
end

local function newObject(otype, name, parent)
    local o = setmetatable({ _type = otype, _name = name, _parent = parent, _points = {}, _shown = true,
        _alpha = 1, _scale = 1 }, WidgetMT)
    allWidgets[#allWidgets + 1] = o
    return o
end

---------------------------------------------------------------------------
-- Region (common to frames, textures, font strings)
---------------------------------------------------------------------------

local Region = defType("Region")

function Region:GetName() return self._name end
function Region:GetDebugName() return self._name or tostring(self) end
function Region:GetParent() return self._parent end
function Region:GetObjectType() return self._type end
function Region:IsObjectType(t)
    local ty = Types[self._type]
    while ty do
        if ty.name == t then return true end
        ty = Types[ty.parent]
    end
    return false
end
function Region:IsForbidden() return false end
function Region:IsProtected() return self._protected or false, self._protected or false end
function Region:SetForbidden() end

local function resolveRel(self, rel)
    if rel == nil then return self._parent end
    if type(rel) == "string" then
        local name = rel:gsub("%$parent", self._parent and self._parent._name or "")
        local f = _G[name]
        if not isWidget(f) then error(("SetPoint(): Couldn't find region named '%s'"):format(rel), 3) end
        return f
    end
    if not isWidget(rel) then error("SetPoint(): bad relativeTo argument", 3) end
    return rel
end

function Region:SetPoint(point, a, b, c, d)
    if type(point) ~= "string" or not ANCHORS[point:upper()] then
        error(("bad argument #1 to 'SetPoint' (invalid anchor point '%s')"):format(tostring(point)), 2)
    end
    point = point:upper()
    local rel, relPoint, x, y
    if type(a) == "number" or a == nil and b == nil then
        rel, relPoint, x, y = nil, point, a or 0, b or 0
    elseif type(b) == "number" or b == nil and (c == nil) then
        -- SetPoint(point, rel, x, y) is NOT valid in WoW for regions? it is: (point, relativeTo, ofsx, ofsy)
        rel, relPoint, x, y = a, point, b or 0, c or 0
    else
        rel, relPoint, x, y = a, b, c or 0, d or 0
    end
    if type(relPoint) ~= "string" or not ANCHORS[relPoint:upper()] then
        error(("bad argument #3 to 'SetPoint' (invalid relative point '%s')"):format(tostring(relPoint)), 2)
    end
    checkNum("SetPoint", 4, x); checkNum("SetPoint", 5, y)
    local relObj = rel
    if rel ~= nil then relObj = resolveRel(self, rel) end
    if relObj == self then error("SetPoint(): Cannot anchor to itself", 2) end
    -- anchor-loop detection
    local seen, cur = {}, relObj
    local function dependsOn(r, target, depth)
        if not r or depth > 30 or seen[r] then return false end
        seen[r] = true
        if r == target then return true end
        for _, p in ipairs(r._points) do
            if dependsOn(p.rel or r._parent, target, depth + 1) then return true end
        end
        return false
    end
    if relObj and dependsOn(relObj, self, 0) and relObj ~= self._parent then
        -- relative to something anchored to us
        local seen2 = {}
        local function anchoredTo(r, target, depth)
            if not r or depth > 30 or seen2[r] then return false end
            seen2[r] = true
            for _, p in ipairs(r._points) do
                local t = p.rel or r._parent
                if t == target or anchoredTo(t, target, depth + 1) then return true end
            end
            return false
        end
        if anchoredTo(relObj, self, 0) then
            error(("SetPoint(): %s would create an anchor dependency loop"):format(tostring(self)), 2)
        end
    end
    for i, p in ipairs(self._points) do
        if p.point == point then table.remove(self._points, i) break end
    end
    table.insert(self._points, { point = point, rel = relObj, relPoint = relPoint:upper(), x = x, y = y })
end

function Region:SetAllPoints(rel)
    rel = rel and resolveRel(self, rel) or self._parent
    self:ClearAllPoints()
    self._points[1] = { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 }
    self._points[2] = { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 }
end
function Region:ClearAllPoints() self._points = {} end
function Region:ClearPoint(point)
    for i, p in ipairs(self._points) do if p.point == point then table.remove(self._points, i) return end end
end
function Region:GetNumPoints() return #self._points end
function Region:GetPoint(i)
    local p = self._points[i or 1]
    if not p then return nil end
    return p.point, p.rel or self._parent, p.relPoint, p.x, p.y
end
function Region:GetPointByName(name)
    for _, p in ipairs(self._points) do if p.point == name then return p.point, p.rel, p.relPoint, p.x, p.y end end
end

function Region:SetSize(w, h)
    checkNum("SetSize", 1, w); checkNum("SetSize", 2, h or w)
    local old = (self._w or -1) .. "x" .. (self._h or -1)
    self._w, self._h = w, h or w
    if old ~= self._w .. "x" .. self._h and self._scripts and self._scripts.OnSizeChanged then
        M.FireScript(self, "OnSizeChanged", self._w, self._h)
    end
end
-- simpler explicit-size bookkeeping
function Region:SetWidth(w) checkNum("SetWidth", 1, w); self._w = w end
function Region:SetHeight(h) checkNum("SetHeight", 1, h); self._h = h end

-- layout --------------------------------------------------------------------

M.SCREEN_W, M.SCREEN_H = 1920, 1080
local hspan, vspan

local spanDepth = 0
local spanStack = {}
local span
local function span1(self, horizontal)

    if self._isRoot then
        if horizontal then return 0, M.SCREEN_W end
        return 0, M.SCREEN_H
    end
    -- scroll child: positioned by its scroll frame
    local sf = rawget(self, "_scrollParent")
    if sf and #self._points == 0 then
        local a, sz = span(sf, horizontal)
        if not a then return nil end
        local own = horizontal and (self._w or 0) or (self._h or 0)
        if horizontal then return a - (sf._hscroll or 0), own end
        return a + sz - own + (sf._vscroll or 0), own
    end
    local lo, hi, mid
    for _, p in ipairs(self._points) do
        local target = p.rel or self._parent
        if target then
            local ta, tsz = span(target, horizontal)
            if ta then
                local rf = ANCHORS[p.relPoint][horizontal and 1 or 2]
                local of = ANCHORS[p.point][horizontal and 1 or 2]
                local coord = ta + tsz * rf + (horizontal and p.x or p.y)
                if of == 0 then lo = coord elseif of == 1 then hi = coord else mid = coord end
            end
        end
    end
    local own
    if horizontal then own = self._w else own = self._h end
    if own == nil and self._type == "FontString" then
        if horizontal then own = self:GetUnboundedStringWidth() else own = self:GetStringHeight() end
    end
    if lo and hi then return lo, hi - lo end
    own = own or 0
    if lo then return lo, own end
    if hi then return hi - own, own end
    if mid then return mid - own / 2, own end
    return nil
end
span = function(self, horizontal)
    spanDepth = spanDepth + 1
    spanStack[spanDepth] = tostring(self) .. (horizontal and "h" or "v")
    if spanDepth > 80 then
        local chain = table.concat(spanStack, " > ", math.max(1, spanDepth - 12), spanDepth)
        error(("layout: anchor loop: %s"):format(chain), 0)
    end
    local ok, a, b = pcall(span1, self, horizontal)
    spanStack[spanDepth] = nil
    spanDepth = spanDepth - 1
    if not ok then error(a, 0) end
    return a, b
end
hspan = function(r) return span(r, true) end
vspan = function(r) return span(r, false) end
M.hspan, M.vspan = hspan, vspan

function Region:GetWidth()
    local _, w = hspan(self)
    if w then return w end
    if self._type == "FontString" and not self._w then return self:GetStringWidth() end
    return self._w or 0
end
function Region:GetHeight()
    local _, h = vspan(self)
    if h then return h end
    if self._type == "FontString" and not self._h then return self:GetStringHeight() end
    return self._h or 0
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() local l = hspan(self); return l end
function Region:GetRight() local l, w = hspan(self); return l and l + w end
function Region:GetBottom() local b = vspan(self); return b end
function Region:GetTop() local b, h = vspan(self); return b and b + h end
function Region:GetCenter()
    local l, w = hspan(self); local b, h = vspan(self)
    if not l or not b then return nil end
    return l + w / 2, b + h / 2
end
function Region:GetRect()
    local l, w = hspan(self); local b, h = vspan(self)
    if not l or not b then return nil end
    return l, b, w, h
end
function Region:GetScaledRect() return self:GetRect() end
function Region:IsRectValid() return self:GetRect() ~= nil end
function Region:SetScale(s)
    checkNum("SetScale", 1, s)
    if s <= 0 then error("SetScale(): Scale must be > 0", 2) end
    self._scale = s
end
function Region:GetScale() return self._scale or 1 end
function Region:GetEffectiveScale()
    local s, f = 1, self
    while f do s = s * (f._scale or 1); f = f._parent end
    return s
end
function Region:SetAlpha(a) checkNum("SetAlpha", 1, a); self._alpha = a end
function Region:GetAlpha() return self._alpha end
function Region:GetEffectiveAlpha() return self._alpha end

-- visibility --------------------------------------------------------------

local function visible(o)
    while o do
        if not o._shown then return false end
        if o._isRoot then return true end
        o = o._parent
    end
    return false -- parentless frames (not UIParent) are visible in WoW if shown; treat orphans as visible
end
function Region:IsShown() return self._shown == true end
function Region:IsVisible()
    local o = self
    while o do
        if not o._shown then return false end
        o = o._parent
    end
    return true
end

local function propagate(o, script)
    -- fire OnShow/OnHide on o and visible descendants
    if o._scripts and (o._scripts[script] or (o._hooks and o._hooks[script])) then M.FireScript(o, script) end
    for _, c in ipairs(o._children or {}) do
        if c._shown then propagate(c, script) end
    end
end

function Region:Show()
    if self._protectedCheck then self:_protectedCheck("Show") end
    if self._shown then return end
    local parentVisible = not self._parent or self._parent:IsVisible()
    self._shown = true
    if parentVisible then propagate(self, "OnShow") end
end
function Region:Hide()
    if self._protectedCheck then self:_protectedCheck("Hide") end
    if not self._shown then return end
    local wasVisible = self:IsVisible()
    self._shown = false
    if wasVisible then propagate(self, "OnHide") end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsMouseOver() return M.mouseFocus == self end

function Region:SetParent(p)
    if type(p) == "string" then p = _G[p] end
    if p ~= nil and not isWidget(p) then error("SetParent(): bad argument", 2) end
    if self._protectedCheck then self:_protectedCheck("SetParent") end
    local old = self._parent
    if old then
        local list = (self._isRegion and old._regions) or old._children
        for i, c in ipairs(list or {}) do if c == self then table.remove(list, i) break end end
    end
    self._parent = p
    if p then
        if self._isRegion then
            p._regions = p._regions or {}; table.insert(p._regions, self)
        else
            p._children = p._children or {}; table.insert(p._children, self)
        end
    end
end

---------------------------------------------------------------------------
-- textures, mask textures, font strings
---------------------------------------------------------------------------

local Texture = defType("Texture", "Region")
local function texArg(fname, v)
    if v ~= nil and type(v) ~= "string" and type(v) ~= "number" then
        error(("bad argument #1 to '%s' (string or number expected, got %s)"):format(fname, type(v)), 3)
    end
end
function Texture:SetTexture(tex, wrapH, wrapV, filter)
    texArg("SetTexture", tex)
    self._texture, self._atlas, self._color = tex, nil, nil
    return tex ~= nil
end
function Texture:GetTexture() return self._texture end
function Texture:GetTextureFileID() return type(self._texture) == "number" and self._texture or nil end
function Texture:GetTextureFilePath() return self._texture end
function Texture:SetAtlas(atlas, useAtlasSize)
    if type(atlas) ~= "string" then typeErr("SetAtlas", 1, "string", atlas, 2) end
    if not (C_Texture.GetAtlasInfo(atlas)) then
        M.Log("SetAtlas: unknown atlas '%s' at %s", atlas, addonWhere(3) or "?")
    end
    self._atlas, self._texture = atlas, nil
end
function Texture:GetAtlas() return self._atlas end
function Texture:SetColorTexture(r, g, b, a)
    checkNum("SetColorTexture", 1, r); checkNum("SetColorTexture", 2, g); checkNum("SetColorTexture", 3, b)
    checkNum("SetColorTexture", 4, a, true)
    self._color = { r, g, b, a or 1 }; self._texture = "color"
end
function Texture:SetTexCoord(...)
    local n = select("#", ...)
    if n ~= 4 and n ~= 8 then error("SetTexCoord(): Usage: SetTexCoord(left, right, top, bottom) or 8 values", 2) end
    for i = 1, n do checkNum("SetTexCoord", i, (select(i, ...))) end
    self._coords = { ... }
end
function Texture:GetTexCoord() local c = self._coords or { 0, 1, 0, 1 } return unpack(c) end
function Texture:SetVertexColor(r, g, b, a)
    checkNum("SetVertexColor", 1, r); checkNum("SetVertexColor", 2, g); checkNum("SetVertexColor", 3, b)
    checkNum("SetVertexColor", 4, a, true)
    self._vertex = { r, g, b, a or 1 }
end
function Texture:GetVertexColor() local v = self._vertex or { 1, 1, 1, 1 } return unpack(v) end
function Texture:SetDesaturated(v) self._desat = v and true or false end
function Texture:IsDesaturated() return self._desat or false end
function Texture:SetGradient(orientation, minColor, maxColor)
    if orientation ~= "HORIZONTAL" and orientation ~= "VERTICAL" then
        error("bad argument #1 to 'SetGradient' (HORIZONTAL or VERTICAL expected)", 2)
    end
    if type(minColor) ~= "table" or type(maxColor) ~= "table" then
        error("SetGradient(): expected color objects (modern API: orientation, minColor, maxColor)", 2)
    end
end
function Texture:AddMaskTexture(mask)
    if not isWidget(mask) or mask._type ~= "MaskTexture" then error("AddMaskTexture(): argument must be a MaskTexture", 2) end
    self._masks = self._masks or {}; table.insert(self._masks, mask)
end
function Texture:GetNumMaskTextures() return self._masks and #self._masks or 0 end
function Texture:SetDrawLayer(layer, sub)
    if not DRAW_LAYERS[layer] then error(("SetDrawLayer(): invalid layer '%s'"):format(tostring(layer)), 2) end
    self._layer, self._sublevel = layer, sub
end
function Texture:GetDrawLayer() return self._layer, self._sublevel or 0 end

defType("MaskTexture", "Texture")

local FontString = defType("FontString", "Region")

local function plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", "WW"):gsub("|A.-|a", "WW"):gsub("|H.-|h(.-)|h", "%1")
    return s
end
M.PlainText = plain

local function needFont(self, fname)
    if not self._fontSize then
        error(("%s(): Font not set"):format(fname), 3)
    end
end
function FontString:SetText(t)
    if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then typeErr("SetText", 1, "string", t, 2) end
    needFont(self, "SetText")
    self._text = t ~= nil and tostring(t) or nil
end
function FontString:SetFormattedText(fmt, ...)
    needFont(self, "SetFormattedText")
    self._text = fmt:format(...)
end
function FontString:GetText() return self._text end
function FontString:SetTextColor(r, g, b, a)
    checkNum("SetTextColor", 1, r); checkNum("SetTextColor", 2, g); checkNum("SetTextColor", 3, b)
    checkNum("SetTextColor", 4, a, true)
    self._textColor = { r, g, b, a or 1 }
end
function FontString:GetTextColor() local c = self._textColor or { 1, 1, 1, 1 } return unpack(c) end
function FontString:SetFontObject(o)
    if type(o) == "string" then
        if not FONT_SIZES[o] then error(("SetFontObject(): Couldn't find font object '%s'"):format(o), 2) end
        o = _G[o]
    end
    if type(o) ~= "table" or not o._isFont then error("SetFontObject(): bad font object", 2) end
    self._fontObject, self._fontSize = o._name, o._size
end
function FontString:GetFontObject() return self._fontObject and _G[self._fontObject] end
function FontString:SetFont(path, size, flags)
    if type(path) ~= "string" and type(path) ~= "number" then typeErr("SetFont", 1, "string", path, 2) end
    checkNum("SetFont", 2, size)
    self._fontSize = size
    return true
end
function FontString:GetFont() return "Fonts\\FRIZQT__.TTF", self._fontSize, "" end
function FontString:SetWordWrap(v) self._wrap = v and true or false end
function FontString:CanWordWrap() return self._wrap ~= false end
function FontString:SetSpacing(s) checkNum("SetSpacing", 1, s); self._spacing = s end
function FontString:GetSpacing() return self._spacing or 0 end
function FontString:SetJustifyH(v) self._justifyH = v end
function FontString:GetJustifyH() return self._justifyH or "CENTER" end
function FontString:SetJustifyV(v) self._justifyV = v end
function FontString:GetJustifyV() return self._justifyV or "MIDDLE" end
function FontString:SetMaxLines(n) self._maxLines = n end
function FontString:GetMaxLines() return self._maxLines or 0 end

local function charW(self) return (self._fontSize or 12) * 0.5 end
function FontString:GetUnboundedStringWidth()
    local best = 0
    for line in (plain(self._text) .. "\n"):gmatch("(.-)\n") do best = math.max(best, #line * charW(self)) end
    return best
end
-- width the text is wrapped / truncated to: explicit width or two horizontal anchors
local function boundWidth(self)
    if self._w and self._w > 0 then return self._w end
    local l, r = false, false
    for _, p in ipairs(self._points) do
        local f = ANCHORS[p.point][1]
        if f == 0 then l = true elseif f == 1 then r = true end
    end
    if l and r then local _, w = hspan(self); return w end
    return nil
end
M.boundWidth = boundWidth
function FontString:GetStringWidth()
    local w = self:GetUnboundedStringWidth()
    local bw = boundWidth(self)
    if bw and bw > 0 then return math.min(w, bw) end
    return w
end
function FontString:GetNumLines()
    local text = plain(self._text)
    if text == "" then return 0 end
    local width = boundWidth(self)
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if width and width > 0 and self._wrap ~= false then
            lines = lines + math.max(1, math.ceil(#line * charW(self) / width))
        else
            lines = lines + 1
        end
    end
    if self._maxLines and self._maxLines > 0 then lines = math.min(lines, self._maxLines) end
    return lines
end
function FontString:GetStringHeight()
    local n = self:GetNumLines()
    if n == 0 then return 0 end
    local size = self._fontSize or 12
    return n * size + (n - 1) * (self._spacing or 0)
end
function FontString:IsTruncated()
    local width = boundWidth(self)
    return width ~= nil and self._wrap == false and self:GetUnboundedStringWidth() > width
end
function FontString:SetShadowOffset(x, y) checkNum("SetShadowOffset", 1, x); checkNum("SetShadowOffset", 2, y) end

local function newRegion(otype, parent, name, layer, template, sublevel)
    if layer ~= nil and not DRAW_LAYERS[layer] then
        error(("Create%s(): invalid draw layer '%s'"):format(otype, tostring(layer)), 3)
    end
    if sublevel ~= nil and (type(sublevel) ~= "number" or sublevel < -8 or sublevel > 7) then
        error(("Create%s(): sublevel must be between -8 and 7"):format(otype), 3)
    end
    if type(name) == "string" then name = name:gsub("%$parent", parent._name or "") end
    local o = newObject(otype, name, nil)
    o._isRegion = true
    o._layer, o._sublevel = layer or "ARTWORK", sublevel
    o:SetParent(parent)
    if name then _G[name] = o end
    return o
end

---------------------------------------------------------------------------
-- frames
---------------------------------------------------------------------------

local Frame = defType("Frame", "Region")

function Frame:CreateTexture(name, layer, template, sublevel)
    local t = newRegion("Texture", self, name, layer, template, sublevel)
    if template then M.ApplyTextureTemplate(t, template) end
    return t
end
function Frame:CreateMaskTexture(name, layer, template, sublevel)
    return newRegion("MaskTexture", self, name, layer, template, sublevel)
end
function Frame:CreateFontString(name, layer, template)
    local fs = newRegion("FontString", self, name, layer or "ARTWORK", nil, nil)
    if template ~= nil then
        if type(template) == "table" and template._isFont then
            fs._fontObject, fs._fontSize = template._name, template._size
        elseif type(template) == "string" and FONT_SIZES[template] then
            fs._fontObject, fs._fontSize = template, FONT_SIZES[template]
        else
            -- the client prints an error and leaves the font string without a font
            M.RecordError(("CreateFontString(): Couldn't find inherited node '%s' (at %s)"):format(tostring(template),
                addonWhere(3) or "?"), debug.traceback("", 2))
        end
    end
    return fs
end
function Frame:CreateAnimationGroup()
    local g = { _anims = {} }
    local mt = { __index = function(_, k)
        if k == "CreateAnimation" then
            return function() return setmetatable({}, { __index = function() return function() end end }) end
        end
        return function() end
    end }
    return setmetatable(g, mt)
end

-- scripts ------------------------------------------------------------------

local VALID_SCRIPTS = {}
for s in ([[OnEvent OnShow OnHide OnUpdate OnSizeChanged OnLoad OnEnter OnLeave OnMouseDown OnMouseUp OnMouseWheel
OnClick OnDoubleClick PreClick PostClick OnDragStart OnDragStop OnReceiveDrag OnTextChanged OnEnterPressed
OnEscapePressed OnEditFocusGained OnEditFocusLost OnValueChanged OnVerticalScroll OnHorizontalScroll
OnScrollRangeChanged OnKeyDown OnKeyUp OnChar OnAttributeChanged OnTooltipSetItem OnTooltipCleared OnHyperlinkClick
OnHyperlinkEnter OnHyperlinkLeave OnEnable OnDisable OnTabPressed OnSpacePressed OnCursorChanged OnArrowPressed
OnMinMaxChanged OnTooltipSetUnit OnTooltipSetSpell]]):gmatch("%S+") do VALID_SCRIPTS[s] = true end
local BUTTON_ONLY = { OnClick = true, OnDoubleClick = true, PreClick = true, PostClick = true }
local EDIT_ONLY = { OnTextChanged = true, OnEnterPressed = true, OnEscapePressed = true, OnEditFocusGained = true,
    OnEditFocusLost = true, OnChar = true, OnTabPressed = true, OnSpacePressed = true, OnCursorChanged = true, OnArrowPressed = true }

local function checkScript(self, script, fname)
    if not VALID_SCRIPTS[script] or (BUTTON_ONLY[script] and not self:IsObjectType("Button"))
        or (EDIT_ONLY[script] and not self:IsObjectType("EditBox")) then
        error(("%s(): %s doesn't have a \"%s\" script"):format(fname, self._type, tostring(script)), 3)
    end
end

function Frame:SetScript(script, fn)
    checkScript(self, script, "SetScript")
    if fn ~= nil and type(fn) ~= "function" then typeErr("SetScript", 2, "function", fn, 2) end
    self._scripts = self._scripts or {}
    self._scripts[script] = fn
    self._hooks = self._hooks or {}
    self._hooks[script] = nil
end
function Frame:GetScript(script) return self._scripts and self._scripts[script] end
function Frame:HasScript(script)
    return VALID_SCRIPTS[script] and not (BUTTON_ONLY[script] and not self:IsObjectType("Button")) or false
end
function Frame:HookScript(script, fn)
    checkScript(self, script, "HookScript")
    self._hooks = self._hooks or {}
    self._hooks[script] = self._hooks[script] or {}
    table.insert(self._hooks[script], fn)
    self._scripts = self._scripts or {}
end

-- Run a script + hooks (each its own execution path for taint, like the client)
function M.FireScript(f, script, ...)
    local h = f._scripts and f._scripts[script]
    local args, n = { ... }, select("#", ...)
    if h then
        if f._secureScripts and f._secureScripts[script] then
            M.SafeCall(h, f, unpack(args, 1, n))
        else
            M.SafeCall(h, f, unpack(args, 1, n))
        end
    end
    -- HookScript hooks are secure post-hooks: their taint does not spread to the caller
    for _, hook in ipairs(f._hooks and f._hooks[script] or {}) do
        local saved = M.taint
        M.SafeCall(hook, f, unpack(args, 1, n))
        M.taint = saved
    end
end

-- events ------------------------------------------------------------------

local eventFrames = {} -- event -> list
M.eventFrames = eventFrames
local KNOWN_EVENTS = {}
for e in ([[ADDON_LOADED PLAYER_LOGIN PLAYER_ENTERING_WORLD PLAYER_LEAVING_WORLD ZONE_CHANGED_NEW_AREA ZONE_CHANGED
ZONE_CHANGED_INDOORS ENCOUNTER_START ENCOUNTER_END COMBAT_LOG_EVENT_UNFILTERED QUEST_LOG_UPDATE QUEST_TURNED_IN
QUEST_ACCEPTED QUEST_REMOVED GET_ITEM_INFO_RECEIVED ITEM_DATA_LOAD_RESULT GROUP_ROSTER_UPDATE UNIT_CONNECTION
PLAYER_REGEN_ENABLED PLAYER_REGEN_DISABLED PLAYER_LEVEL_UP PLAYER_TARGET_CHANGED UPDATE_INSTANCE_INFO LOOT_READY
MINIMAP_UPDATE_ZOOM WORLD_MAP_OPEN ADDON_ACTION_BLOCKED ADDON_ACTION_FORBIDDEN UI_SCALE_CHANGED
DISPLAY_SIZE_CHANGED BOSS_KILL QUEST_WATCH_LIST_CHANGED QUEST_DETAIL QUEST_PROGRESS QUEST_COMPLETE QUEST_FINISHED INSTANCE_ENCOUNTER_ENGAGE_UNIT UNIT_NAME_UPDATE]]):gmatch("%S+") do KNOWN_EVENTS[e] = true end
if CFG.noCLEU then KNOWN_EVENTS.COMBAT_LOG_EVENT_UNFILTERED = nil end
M.KNOWN_EVENTS = KNOWN_EVENTS

function Frame:RegisterEvent(event)
    if type(event) ~= "string" then typeErr("RegisterEvent", 1, "string", event, 2) end
    if not KNOWN_EVENTS[event] then
        error(("Frame:RegisterEvent(): Attempt to register unknown event \"%s\""):format(event), 2)
    end
    -- Midnight-era clients forbid the combat log to addons: Blizzard's "blocked" popup
    if event == "COMBAT_LOG_EVENT_UNFILTERED" and addonWhere(2) and not M.ProtectedCall("RegisterEvent(COMBAT_LOG_EVENT_UNFILTERED)", "forbidden", "Frame") then
        return false
    end
    self._events = self._events or {}
    if self._events[event] then return true end
    self._events[event] = true
    eventFrames[event] = eventFrames[event] or {}
    table.insert(eventFrames[event], self)
    return true
end
function Frame:RegisterUnitEvent(event) return self:RegisterEvent(event) end
function Frame:UnregisterEvent(event)
    if self._events then self._events[event] = nil end
    local list = eventFrames[event]
    for i, f in ipairs(list or {}) do if f == self then table.remove(list, i) break end end
end
function Frame:UnregisterAllEvents()
    for e in pairs(self._events or {}) do self:UnregisterEvent(e) end
end
function Frame:IsEventRegistered(e) return self._events and self._events[e] or false end

function M.FireEvent(event, ...)
    local list = {}
    for i, f in ipairs(eventFrames[event] or {}) do list[i] = f end
    for _, f in ipairs(list) do
        if f._events and f._events[event] then
            local args, n = { ... }, select("#", ...)
            M.Dispatch(function() M.FireScript(f, "OnEvent", event, unpack(args, 1, n)) end)
        end
    end
end

-- hierarchy & strata --------------------------------------------------------

function Frame:GetChildren() return unpack(self._children or {}) end
function Frame:GetNumChildren() return #(self._children or {}) end
function Frame:GetRegions() return unpack(self._regions or {}) end
function Frame:GetNumRegions() return #(self._regions or {}) end
function Frame:SetFrameLevel(l)
    checkNum("SetFrameLevel", 1, l)
    if l < 0 or l > 10000 then error("SetFrameLevel(): level must be 0..10000", 2) end
    self._level = math.floor(l)
end
function Frame:GetFrameLevel()
    if self._level then return self._level end
    return self._parent and self._parent.GetFrameLevel and (self._parent:GetFrameLevel() + 1) or 0
end
function Frame:SetFrameStrata(s)
    if not STRATA[s] then error(("SetFrameStrata(): invalid strata '%s'"):format(tostring(s)), 2) end
    self._strata = s
end
function Frame:GetFrameStrata()
    if self._strata then return self._strata end
    return self._parent and self._parent.GetFrameStrata and self._parent:GetFrameStrata() or "MEDIUM"
end
function Frame:Raise() self._raised = (self._raised or 0) + 1 end
function Frame:Lower() end
function Frame:EnableMouse(v) self._mouse = v and true or false end
function Frame:IsMouseEnabled() return self._mouse or false end
function Frame:SetMouseClickEnabled(v) self._mouseClick = v and true or false end
function Frame:IsMouseClickEnabled()
    if self._mouseClick ~= nil then return self._mouseClick end
    return self._mouse or false
end
function Frame:SetMouseMotionEnabled(v) self._mouseMotion = v and true or false end
function Frame:IsMouseMotionEnabled()
    if self._mouseMotion ~= nil then return self._mouseMotion end
    return self._mouse or false
end
function Frame:EnableMouseWheel(v) self._wheel = v and true or false end
function Frame:IsMouseWheelEnabled() return self._wheel or false end
function Frame:SetMovable(v) self._movable = v end
function Frame:IsMovable() return self._movable or false end
function Frame:SetID(id) self._id = id end
function Frame:GetID() return self._id or 0 end
function Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function Frame:GetAttribute(k) return self._attr and self._attr[k] end
-- protected in combat for everyone, forbidden on this client for insecure code (configurable)
function Frame:SetPassThroughButtons(...)
    M.ProtectedCall("SetPassThroughButtons", CFG.passThroughForbidden and "forbidden" or "nocombat", self._name or self._type)
end
function Frame:SetPropagateMouseClicks(...)
    M.ProtectedCall("SetPropagateMouseClicks", CFG.passThroughForbidden and "forbidden" or "nocombat", self._name or self._type)
end
function Frame:_protectedCheck(what)
    if self._protected then M.ProtectedCall(self._name .. ":" .. what, "nocombat", self._name) end
end
Frame._protectedCheck = nil -- only set on protected frames (see MakeProtected)
function M.MakeProtected(f)
    f._protected = true
    f._protectedCheck = function(self, what) M.ProtectedCall((self._name or "?") .. ":" .. what, "nocombat", self._name) end
end

-- Button --------------------------------------------------------------------

local Button = defType("Button", "Frame")
local function setStateTexture(self, key, tex, blend)
    if tex == nil then self[key] = nil return end
    if isWidget(tex) then self[key] = tex; return end
    texArg("Set" .. key, tex)
    local t = self[key] or self:CreateTexture(nil, key == "_highlight" and "HIGHLIGHT" or "ARTWORK")
    t:SetTexture(tex)
    t:SetAllPoints(self)
    if blend then t._blend = blend end
    self[key] = t
end
function Button:SetNormalTexture(t) setStateTexture(self, "_normal", t) end
function Button:GetNormalTexture() return self._normal end
function Button:SetPushedTexture(t) setStateTexture(self, "_pushed", t) end
function Button:GetPushedTexture() return self._pushed end
function Button:SetDisabledTexture(t) setStateTexture(self, "_disabled", t) end
function Button:GetDisabledTexture() return self._disabled end
function Button:SetHighlightTexture(t, blend)
    if blend ~= nil and blend ~= "ADD" and blend ~= "BLEND" and blend ~= "MOD" and blend ~= "ALPHAKEY" and blend ~= "DISABLE" then
        error("SetHighlightTexture(): invalid blend mode", 2)
    end
    setStateTexture(self, "_highlight", t, blend)
end
function Button:GetHighlightTexture() return self._highlight end
function Button:LockHighlight() self._highlightLocked = true end
function Button:UnlockHighlight() self._highlightLocked = false end
function Button:Enable() self._enabled = true end
function Button:Disable() self._enabled = false end
function Button:SetEnabled(v) self._enabled = v and true or false end
function Button:IsEnabled() return self._enabled ~= false end
function Button:RegisterForClicks(...) self._clicks = { ... } end
function Button:GetFontString() return self._fontString end
function Button:SetFontString(fs) self._fontString = fs end
function Button:SetText(t)
    if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then typeErr("SetText", 1, "string", t, 2) end
    if not self._fontString then
        self._fontString = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        self._fontString:SetPoint("CENTER")
    end
    self._fontString:SetText(t)
end
function Button:GetText() return self._fontString and self._fontString:GetText() end
function Button:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
function Button:GetTextWidth() return self._fontString and self._fontString:GetStringWidth() or 0 end
function Button:Click(button)
    if self._enabled == false then return end
    M.FireScript(self, "OnClick", button or "LeftButton", false)
end

defType("CheckButton", "Button")
function Types.CheckButton.methods:SetChecked(v) self._checked = v and true or false end
function Types.CheckButton.methods:GetChecked() return self._checked or false end

-- ScrollFrame -----------------------------------------------------------------

local ScrollFrame = defType("ScrollFrame", "Frame")
function ScrollFrame:SetScrollChild(child)
    if not isWidget(child) then error("SetScrollChild(): argument must be a frame", 2) end
    if self._scrollChild then self._scrollChild._scrollParent = nil end
    self._scrollChild = child
    child._scrollParent = self
    if child._parent ~= self then child:SetParent(self) end
end
function ScrollFrame:GetScrollChild() return self._scrollChild end
function ScrollFrame:SetVerticalScroll(v) checkNum("SetVerticalScroll", 1, v); self._vscroll = v end
function ScrollFrame:GetVerticalScroll() return self._vscroll or 0 end
function ScrollFrame:SetHorizontalScroll(v) checkNum("SetHorizontalScroll", 1, v); self._hscroll = v end
function ScrollFrame:GetHorizontalScroll() return self._hscroll or 0 end
function ScrollFrame:GetVerticalScrollRange()
    local c = self._scrollChild
    if not c then return 0 end
    return math.max(0, c:GetHeight() - self:GetHeight())
end
function ScrollFrame:GetHorizontalScrollRange() return 0 end

-- EditBox ---------------------------------------------------------------------

local EditBox = defType("EditBox", "Frame")
function EditBox:SetText(t)
    if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then typeErr("SetText", 1, "string", t, 2) end
    self._text = tostring(t or "")
    M.FireScript(self, "OnTextChanged", false)
end
function EditBox:GetText() return self._text or "" end
function EditBox:Insert(t) self:SetText((self._text or "") .. t) end
function EditBox:HasFocus() return false end
function EditBox:GetNumLetters() return #(self._text or "") end
-- simulate the user typing
function M.TypeText(eb, text)
    eb._text = text
    M.Dispatch(function() M.FireScript(eb, "OnTextChanged", true) end)
end

-- Slider / StatusBar / misc ---------------------------------------------------
local Slider = defType("Slider", "Frame")
function Slider:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Slider:GetMinMaxValues() return self._min or 0, self._max or 0 end
function Slider:SetValue(v) self._value = v; M.FireScript(self, "OnValueChanged", v, false) end
function Slider:GetValue() return self._value or 0 end
defType("StatusBar", "Slider")
defType("Cooldown", "Frame")
defType("Model", "Frame")
defType("PlayerModel", "Model")
defType("GameTooltip", "Frame")
defType("Minimap", "Frame")
defType("SimpleHTML", "Frame")
defType("MessageFrame", "Frame")

---------------------------------------------------------------------------
-- templates
---------------------------------------------------------------------------

local templates = {}
M.templates = templates

-- BackdropTemplateMixin-like
BackdropTemplateMixin = {}
function BackdropTemplateMixin:SetBackdrop(info)
    if info ~= nil and type(info) ~= "table" then error("SetBackdrop(): table expected", 2) end
    self._backdrop = info
    if info then
        self._bdColor = self._bdColor or { 1, 1, 1, 1 }
        if not rawget(self, "Center") then
            self.Center = self:CreateTexture(nil, "BACKGROUND", nil, -8)
            self.Center:SetAllPoints()
        end
        if info.edgeFile and not rawget(self, "TopEdge") then
            for _, k in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
                self[k] = self:CreateTexture(nil, "BORDER", nil, -8)
            end
        end
    end
end
function BackdropTemplateMixin:GetBackdrop() return self._backdrop end
function BackdropTemplateMixin:ApplyBackdrop() end
function BackdropTemplateMixin:ClearBackdrop() self._backdrop = nil end
function BackdropTemplateMixin:SetBackdropColor(r, g, b, a)
    checkNum("SetBackdropColor", 1, r); checkNum("SetBackdropColor", 2, g); checkNum("SetBackdropColor", 3, b)
    if not self._backdrop then M.Log("SetBackdropColor before SetBackdrop at %s", addonWhere(3) or "?") end
    self._bdColor = { r, g, b, a or 1 }
end
function BackdropTemplateMixin:GetBackdropColor() return unpack(self._bdColor or { 1, 1, 1, 1 }) end
function BackdropTemplateMixin:SetBackdropBorderColor(r, g, b, a)
    checkNum("SetBackdropBorderColor", 1, r); checkNum("SetBackdropBorderColor", 2, g); checkNum("SetBackdropBorderColor", 3, b)
    self._bdBorder = { r, g, b, a or 1 }
end
function BackdropTemplateMixin:GetBackdropBorderColor() return unpack(self._bdBorder or { 1, 1, 1, 1 }) end
function BackdropTemplateMixin:OnBackdropLoaded() end
function BackdropTemplateMixin:OnBackdropSizeChanged() end

function Mixin(obj, ...)
    for i = 1, select("#", ...) do
        local m = select(i, ...)
        if type(m) ~= "table" then error("Mixin(): mixin must be a table", 2) end
        for k, v in pairs(m) do obj[k] = v end
    end
    return obj
end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateAndInitFromMixin(mixin, ...)
    local o = CreateFromMixins(mixin)
    if o.Init then o:Init(...) end
    return o
end

local function fs(parent, font, key)
    local f = parent:CreateFontString(nil, "OVERLAY", font)
    if key then parent[key] = f end
    return f
end

templates.BackdropTemplate = { apply = function(f)
    Mixin(f, BackdropTemplateMixin)
end }

templates.UIPanelButtonTemplate = { type = "Button", apply = function(b)
    b.Left = b:CreateTexture(nil, "BACKGROUND"); b.Middle = b:CreateTexture(nil, "BACKGROUND"); b.Right = b:CreateTexture(nil, "BACKGROUND")
    b.Text = fs(b, "GameFontNormal")
    b.Text:SetPoint("CENTER")
    b._fontString = b.Text
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    b:SetSize(40, 22)
end }

templates.UIPanelCloseButton = { type = "Button", apply = function(b)
    b:SetSize(32, 32)
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    b:SetScript("OnClick", function(self) local p = self:GetParent(); if p then p:Hide() end end)
end }
templates.UIPanelCloseButtonNoScripts = { type = "Button", apply = function(b) b:SetSize(32, 32) end }

templates.UIPanelScrollFrameTemplate = { type = "ScrollFrame", apply = function(sf)
    local bar = M.CreateFrameRaw("Slider", sf._name and (sf._name .. "ScrollBar") or nil, sf)
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, -16)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 16)
    bar:SetWidth(16)
    sf.ScrollBar = bar
    bar.ScrollUpButton = M.CreateFrameRaw("Button", bar._name and (bar._name .. "ScrollUpButton") or nil, bar)
    bar.ScrollDownButton = M.CreateFrameRaw("Button", bar._name and (bar._name .. "ScrollDownButton") or nil, bar)
    sf:EnableMouseWheel(true)
end }
templates.ScrollFrameTemplate = templates.UIPanelScrollFrameTemplate

templates.SearchBoxTemplate = { type = "EditBox", apply = function(eb)
    eb.Instructions = fs(eb, "GameFontDisableSmall")
    eb.Instructions:SetPoint("TOPLEFT", 16, 0); eb.Instructions:SetPoint("BOTTOMRIGHT", -20, 0)
    eb.searchIcon = eb:CreateTexture(nil, "OVERLAY")
    eb.clearButton = M.CreateFrameRaw("Button", nil, eb)
    eb:SetFontObject("ChatFontSmall")
end }
templates.InputBoxTemplate = { type = "EditBox", apply = function(eb) end }

templates.BasicFrameTemplate = { apply = function(f)
    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.TitleBg = f:CreateTexture(nil, "BACKGROUND")
    f.TitleText = fs(f, "GameFontNormal")
    f.TitleText:SetPoint("TOP", 0, -5)
    f.CloseButton = M.CreateFrameRaw("Button", f._name and (f._name .. "CloseButton") or nil, f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", 2, 1)
end }
templates.BasicFrameTemplateWithInset = { apply = function(f)
    templates.BasicFrameTemplate.apply(f)
    f.Inset = M.CreateFrameRaw("Frame", nil, f)
    f.Inset:SetPoint("TOPLEFT", 4, -24); f.Inset:SetPoint("BOTTOMRIGHT", -6, 4)
end }
templates.ButtonFrameTemplate = templates.BasicFrameTemplateWithInset
templates.PortraitFrameTemplate = templates.BasicFrameTemplate
templates.TooltipBackdropTemplate = templates.BackdropTemplate
templates.SecureActionButtonTemplate = { type = "Button", apply = function(b) M.MakeProtected(b) end }

function M.ApplyTextureTemplate(t, template) end

-- frame creation -------------------------------------------------------------

local FRAME_TYPES = { Frame = true, Button = true, CheckButton = true, ScrollFrame = true, EditBox = true,
    Slider = true, StatusBar = true, Cooldown = true, Model = true, PlayerModel = true, GameTooltip = true,
    SimpleHTML = true, MessageFrame = true, Minimap = true }

local function applyTemplates(f, templateList)
    if templateList == nil then return end
    if type(templateList) ~= "string" then error("CreateFrame(): template must be a string", 3) end
    for tname in templateList:gmatch("[^,%s]+") do
        local t = templates[tname]
        if not t then error(("CreateFrame(): Couldn't find inherited node \"%s\""):format(tname), 3) end
        if t.apply then t.apply(f) end
        if t.xml then M.ApplyXmlTemplate(f, t.xml) end
    end
end

function M.CreateFrameRaw(ftype, name, parent, template, id)
    if type(name) == "string" and parent and parent._name then name = name:gsub("%$parent", parent._name) end
    local f = newObject(ftype, name, nil)
    if parent then f:SetParent(parent) end
    if name then _G[name] = f end
    if template then applyTemplates(f, template) end
    return f
end

function CreateFrame(ftype, name, parent, template, id)
    if type(ftype) ~= "string" or not FRAME_TYPES[ftype] then
        error(("CreateFrame(): Unknown frame type '%s'"):format(tostring(ftype)), 2)
    end
    if name ~= nil and type(name) ~= "string" then typeErr("CreateFrame", 2, "string", name, 1) end
    if type(parent) == "string" then parent = _G[parent] end
    if parent ~= nil and not isWidget(parent) then error("CreateFrame(): bad parent", 2) end
    if template ~= nil then
        for tname in tostring(template):gmatch("[^,%s]+") do
            if not templates[tname] then
                error(("CreateFrame(): Couldn't find inherited node \"%s\""):format(tname), 2)
            end
            local tt = templates[tname].type
            if tt and tt ~= ftype and not (tt == "Button" and ftype == "CheckButton") and not (tt == "Frame") then
                M.Log("CreateFrame(%s) with template %s made for %s at %s", ftype, tname, tt, addonWhere(3) or "?")
            end
        end
    end
    local f = M.CreateFrameRaw(ftype, name, parent, template, id)
    if f._scripts and f._scripts.OnLoad then M.FireScript(f, "OnLoad") end
    return f
end

-- XML templates registered by run.py from <Frame virtual="true"> definitions
-- def = { name, type, mixin, size = {x,y}, enableMouse, layers = { {level, textures = {...}} }, scripts = { OnLoad = {method=...} } }
function M.RegisterXmlTemplate(def)
    templates[def.name] = { type = def.type, xml = def }
end

function M.ApplyXmlTemplate(f, def)
    if def.inherits then applyTemplates(f, def.inherits) end
    if def.mixin then
        for mname in def.mixin:gmatch("[^,%s]+") do
            local m = _G[mname]
            if type(m) ~= "table" then error(("CreateFrame(): mixin '%s' is not defined"):format(mname), 4) end
            Mixin(f, m)
        end
    end
    if def.size then f:SetSize(def.size.x or 0, def.size.y or 0) end
    if def.enableMouse then f:EnableMouse(true) end
    for _, region in ipairs(def.regions or {}) do
        local r
        if region.kind == "Texture" then
            r = f:CreateTexture(region.name, region.layer, nil, region.sublevel)
            if region.file then r:SetTexture(region.file) end
            if region.atlas then r:SetAtlas(region.atlas) end
            if region.color then r:SetVertexColor(region.color.r or 1, region.color.g or 1, region.color.b or 1, region.color.a or 1) end
            if region.alphaMode then r._blend = region.alphaMode end
        else
            r = f:CreateFontString(region.name, region.layer, region.inherits)
            if region.text then r:SetText(region.text) end
        end
        if region.hidden then r:Hide() end
        if region.size then r:SetSize(region.size.x or 0, region.size.y or 0) end
        if region.setAllPoints then r:SetAllPoints() end
        for _, a in ipairs(region.anchors or {}) do
            local rel = a.relativeKey and f or nil
            r:SetPoint(a.point, rel or f, a.relativePoint or a.point, a.x or 0, a.y or 0)
        end
        if region.parentKey then f[region.parentKey] = r end
    end
    for script, s in pairs(def.scripts or {}) do
        local fn
        if s.method then
            local method = s.method
            fn = function(self, ...)
                local m = self[method]
                if type(m) ~= "function" then error(("%s: method '%s' not found"):format(script, method)) end
                return m(self, ...)
            end
        elseif s.func then
            fn = _G[s.func]
        end
        if fn then
            f._scripts = f._scripts or {}
            if s.inherit == "prepend" or s.inherit == "append" then
                f:HookScript(script, fn)
            else
                f._scripts[script] = fn
            end
        end
    end
end

---------------------------------------------------------------------------
-- core UI objects
---------------------------------------------------------------------------

UIParent = M.CreateFrameRaw("Frame", "UIParent", nil)
UIParent._isRoot = true
UIParent._w, UIParent._h = M.SCREEN_W, M.SCREEN_H
UIParent._strata = "MEDIUM"
WorldFrame = M.CreateFrameRaw("Frame", "WorldFrame", nil)
WorldFrame._isRoot = true

UISpecialFrames = {}

-- GameTooltip
GameTooltip = M.CreateFrameRaw("GameTooltip", "GameTooltip", UIParent)
GameTooltip._shown = false
GameTooltip._lines = {}
do
    local T = Types.GameTooltip.methods
    function T:SetOwner(owner, anchor)
        if not isWidget(owner) then error("GameTooltip:SetOwner(): owner must be a frame", 2) end
        self._owner, self._lines = owner, {}
    end
    function T:GetOwner() return self._owner end
    function T:IsOwned(f) return self._owner == f end
    function T:ClearLines() self._lines = {} end
    function T:SetText(t, r, g, b, a, wrap)
        if type(t) ~= "string" and type(t) ~= "number" then typeErr("SetText", 1, "string", t, 2) end
        self._lines = { tostring(t) }
    end
    function T:AddLine(t, r, g, b, wrap)
        if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then typeErr("AddLine", 1, "string", t, 2) end
        table.insert(self._lines, tostring(t or ""))
    end
    function T:AddDoubleLine(l, r) table.insert(self._lines, tostring(l or "") .. "  " .. tostring(r or "")) end
    function T:NumLines() return #self._lines end
    function T:SetItemByID(id)
        checkNum("SetItemByID", 1, id)
        self._lines = {}
        local name = M.ItemCached(id) and M.ITEMS[id] and M.ITEMS[id][1]
        -- modern tooltips show a pending line and refresh themselves when the data arrives
        if name then self._lines = { name } else self._lines = { RETRIEVING_ITEM_INFO }; M.RequestItem(id) end
    end
    function T:SetHyperlink(link) self._lines = { tostring(link) } end
    function T:SetUnit() end
    function T:SetSpellByID() end
    function T:FadeOut() self:Hide() end
    function T:SetMinimumWidth() end
    function T:SetPadding() end
end

---------------------------------------------------------------------------
-- world map
---------------------------------------------------------------------------

MapCanvasDataProviderMixin = {}
function MapCanvasDataProviderMixin:OnAdded(owningMap) self.owningMap = owningMap end
function MapCanvasDataProviderMixin:OnRemoved(owningMap) self.owningMap = nil end
function MapCanvasDataProviderMixin:GetMap() return self.owningMap end
function MapCanvasDataProviderMixin:RemoveAllData() end
function MapCanvasDataProviderMixin:RefreshAllData(fromOnShow) end
function MapCanvasDataProviderMixin:OnShow() end
function MapCanvasDataProviderMixin:OnHide() end
function MapCanvasDataProviderMixin:OnMapChanged() self:RefreshAllData() end
function MapCanvasDataProviderMixin:OnCanvasScaleChanged() end
function MapCanvasDataProviderMixin:OnCanvasSizeChanged() end
function MapCanvasDataProviderMixin:OnEvent() end
function MapCanvasDataProviderMixin:SignalEvent() end
function MapCanvasDataProviderMixin:RegisterEvent() end
function MapCanvasDataProviderMixin:UnregisterEvent() end

MapCanvasPinMixin = {}
function MapCanvasPinMixin:OnLoad() end
function MapCanvasPinMixin:OnAcquired(...) end
function MapCanvasPinMixin:OnReleased() end
function MapCanvasPinMixin:OnClick() end
function MapCanvasPinMixin:OnMouseEnter() end
function MapCanvasPinMixin:OnMouseLeave() end
function MapCanvasPinMixin:OnMouseDown() end
function MapCanvasPinMixin:OnMouseUp() end
function MapCanvasPinMixin:GetMap() return self.owningMap end
function MapCanvasPinMixin:SetPosition(x, y)
    checkNum("SetPosition", 1, x); checkNum("SetPosition", 2, y)
    self.normalizedX, self.normalizedY = x, y
end
function MapCanvasPinMixin:GetPosition() return self.normalizedX, self.normalizedY end
function MapCanvasPinMixin:SetScalingLimits(f, min, max) self.scaleFactor = f end
function MapCanvasPinMixin:UseFrameLevelType() end
function MapCanvasPinMixin:GetFrameLevelType() return "PIN_FRAME_LEVEL_DEFAULT" end
function MapCanvasPinMixin:ApplyFrameLevel() end
function MapCanvasPinMixin:CheckMouseButtonPassthrough(...)
    -- Blizzard: decides which buttons pass through to the map and calls the protected API
    self:SetPassThroughButtons(...)
end
function MapCanvasPinMixin:SetIgnoreGlobalPinScale() end
function MapCanvasPinMixin:DisableInheritedMotionScriptsWarning() return false end
function MapCanvasPinMixin:IsIgnoringGlobalPinScale() return false end

local WMF = M.CreateFrameRaw("Frame", "WorldMapFrame", UIParent)
WorldMapFrame = WMF
WMF._shown = false
WMF:SetSize(1022, 766)
WMF:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
WMF._strata = "HIGH"
WMF.ScrollContainer = M.CreateFrameRaw("ScrollFrame", nil, WMF)
WMF.ScrollContainer:SetPoint("TOPLEFT", 10, -70)
WMF.ScrollContainer:SetPoint("BOTTOMRIGHT", -10, 28)
WMF.ScrollContainer.Child = M.CreateFrameRaw("Frame", nil, WMF.ScrollContainer)
WMF.ScrollContainer.Child:SetSize(1002, 668)
WMF.ScrollContainer.Child:SetPoint("TOPLEFT")
WMF.ScrollContainer:SetFrameLevel(WMF:GetFrameLevel() + 2)
-- a Blizzard layer with a high frame level (e.g. the player pin layer)
local blizzLayer = M.CreateFrameRaw("Frame", nil, WMF.ScrollContainer.Child)
blizzLayer:SetFrameLevel(2400)
WMF.BorderFrame = M.CreateFrameRaw("Frame", nil, WMF)
-- the nav bar with its crumbs (World > Kalimdor > The Barrens)
WMF.NavBar = M.CreateFrameRaw("Frame", nil, WMF)
WMF.NavBar:SetPoint("TOPLEFT", 60, -30)
WMF.NavBar:SetSize(600, 34)
WMF.NavBar.navList = {}
for i = 1, 3 do
    local crumb = M.CreateFrameRaw("Button", nil, WMF.NavBar)
    crumb:SetSize(90, 34)
    crumb:SetPoint("LEFT", (i - 1) * 90, 0)
    WMF.NavBar.navList[i] = crumb
end
WMF.mapID = 1413
WMF.dataProviders = {}
WMF.pinPools = {}
WMF.pinsByTemplate = {}
WMF.blizzProviders = {}
WMF._secureScripts = {}

local mapAPI = {}
function mapAPI:GetMapID() return self.mapID end
function mapAPI:GetCanvas() return self.ScrollContainer.Child end
function mapAPI:GetCanvasContainer() return self.ScrollContainer end
function mapAPI:OnMapChanged()
    for p in pairs(self.dataProviders) do
        if p.OnMapChanged then M.Isolated(p.OnMapChanged, p) end
    end
end
function mapAPI:SetMapID(mapID)
    checkNum("SetMapID", 1, mapID)
    if not C_Map.GetMapInfo(mapID) then error(("SetMapID(): invalid map %s"):format(mapID), 2) end
    if self.mapID == mapID then return end
    if M.taint then
        M.Log("WorldMapFrame:SetMapID(%d) from tainted execution (%s) -> map state tainted", mapID, addonWhere(3) or "?")
        M.mapStateTainted = (M.mapStateTainted or 0) + 1
        M.ProtectedCall("WorldMapFrame:SetMapID", "nocombat", "WorldMapFrame")
    end
    self.mapID = mapID
    self:OnMapChanged()
end
function mapAPI:NavigateToParentMap()
    local info = C_Map.GetMapInfo(self.mapID)
    if info and info.parentMapID and info.parentMapID > 0 then self:SetMapID(info.parentMapID) end
end
function mapAPI:AddDataProvider(p)
    if type(p) ~= "table" then error("AddDataProvider(): provider table expected", 2) end
    self.dataProviders[p] = true
    p:OnAdded(self)
    if self:IsShown() then M.Isolated(p.RefreshAllData, p, true) end
end
function mapAPI:RemoveDataProvider(p)
    self.dataProviders[p] = nil
    p:RemoveAllData(); p:OnRemoved(self)
end
function mapAPI:AcquirePin(template, ...)
    if not templates[template] then error(("AcquirePin(): unknown template '%s'"):format(tostring(template)), 2) end
    local pool = self.pinPools[template]
    if not pool then pool = { free = {}, active = {} }; self.pinPools[template] = pool end
    local pin = table.remove(pool.free)
    local new = false
    if not pin then
        pin = CreateFrame(templates[template].type or "Frame", nil, self.ScrollContainer.Child, template)
        new = true
    end
    table.insert(pool.active, pin) -- FramePool:Acquire marks it active before any setup (like the client)
    pin.pinTemplate = template
    pin.owningMap = self
    if new then
        -- Blizzard_MapCanvas.lua MapCanvasMixin:AcquirePin (retail/Midnight UI used by WoW Forever)
        local click, motion = pin:IsMouseClickEnabled(), pin:IsMouseMotionEnabled()
        if click then
            pin:SetScript("OnMouseUp", function(p, button) if p.OnMouseUp then p:OnMouseUp(button) end end)
            pin:SetScript("OnMouseDown", function(p, button) if p.OnMouseDown then p:OnMouseDown(button) end end)
            if pin:IsObjectType("Button") then pin:SetScript("OnClick", nil) end
        end
        if motion then
            if not (pin.DisableInheritedMotionScriptsWarning and pin:DisableInheritedMotionScriptsWarning()) then
                if pin:GetScript("OnEnter") ~= nil or pin:GetScript("OnLeave") ~= nil then
                    error("Blizzard_MapCanvas.lua:309: assertion failed! (pin template '" .. template ..
                        "' defines OnEnter/OnLeave; MapCanvas asserts GetScript('OnEnter') == nil)", 2)
                end
            end
            pin:SetScript("OnEnter", function(p) if p.OnMouseEnter then p:OnMouseEnter() end end)
            pin:SetScript("OnLeave", function(p) if p.OnMouseLeave then p:OnMouseLeave() end end)
        end
    end
    if new and pin.OnLoad and not (pin._scripts and pin._scripts.OnLoad) then pin:OnLoad() end
    pin:Show()
    if pin.OnAcquired then pin:OnAcquired(...) end
    if pin.CheckMouseButtonPassthrough then pin:CheckMouseButtonPassthrough("RightButton") end
    return pin
end
function mapAPI:RemoveAllPinsByTemplate(template)
    local pool = self.pinPools[template]
    if not pool then return end
    for _, pin in ipairs(pool.active) do
        pin:Hide()
        if pin.OnReleased then pin:OnReleased() end
        table.insert(pool.free, pin)
    end
    pool.active = {}
end
function mapAPI:RemovePin(pin)
    local pool = self.pinPools[pin.pinTemplate]
    for i, p in ipairs(pool and pool.active or {}) do
        if p == pin then table.remove(pool.active, i); pin:Hide(); table.insert(pool.free, pin) return end
    end
end
function mapAPI:EnumeratePinsByTemplate(template)
    local pool = self.pinPools[template]
    local i = 0
    return function() i = i + 1; return pool and pool.active[i] end
end
function mapAPI:GetNumActivePinsByTemplate(template)
    local pool = self.pinPools[template]
    return pool and #pool.active or 0
end
function mapAPI:RefreshAllDataProviders()
    for p in pairs(self.dataProviders) do M.Isolated(p.RefreshAllData, p) end
end
function mapAPI:HandleUserActionToggleSelf() if self:IsShown() then self:Hide() else self:Show() end end
function mapAPI:SetPinPosition() end
function mapAPI:GetGlobalPinScale() return 1 end
function mapAPI:IsMaximized() return false end
function mapAPI:SetPinTemplateType() end
for k, v in pairs(mapAPI) do WMF[k] = v end

-- Blizzard's own data provider: quest pins (exercise CheckMouseButtonPassthrough in the current taint state)
templates.BlizzQuestPinTemplate = { type = "Button", apply = function(f) Mixin(f, MapCanvasPinMixin) end }
local blizzProvider = CreateFromMixins(MapCanvasDataProviderMixin)
blizzProvider.isBlizzard = true
function blizzProvider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate("BlizzQuestPinTemplate") end
function blizzProvider:RefreshAllData()
    self:RemoveAllData()
    local n = (self:GetMap():GetMapID() % 3) + 2
    for i = 1, n do self:GetMap():AcquirePin("BlizzQuestPinTemplate", i) end
end
WMF:AddDataProvider(blizzProvider)

-- Blizzard OnShow: refresh providers (secure part of the show)
WMF._scripts = { OnShow = function(self)
    for p in pairs(self.dataProviders) do
        if p.OnShow then M.Isolated(p.OnShow, p) end
        M.Isolated(p.RefreshAllData, p, true)
    end
end, OnHide = function(self)
    for p in pairs(self.dataProviders) do if p.OnHide then M.Isolated(p.OnHide, p) end end
end }

function ToggleWorldMap()
    if M.taint and M.combat then M.ProtectedCall("ToggleWorldMap/ShowUIPanel(WorldMapFrame)", "nocombat", "WorldMapFrame") end
    WMF:HandleUserActionToggleSelf()
end
function ShowUIPanel(f) if f then f:Show() end end
function HideUIPanel(f) if f then f:Hide() end end
-- the user presses M (secure)
function M.UserToggleWorldMap() M.Dispatch(function() WMF:HandleUserActionToggleSelf() end) end

---------------------------------------------------------------------------
-- minimap
---------------------------------------------------------------------------

MinimapCluster = M.CreateFrameRaw("Frame", "MinimapCluster", UIParent)
MinimapCluster:SetSize(200, 220)
MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
Minimap = M.CreateFrameRaw("Minimap", "Minimap", MinimapCluster)
Minimap:SetSize(140, 140)
Minimap:SetPoint("CENTER", MinimapCluster, "TOP", 9, -92)
Minimap._zoom = 0
do
    local Mm = Types.Minimap.methods
    function Mm:GetZoom() return self._zoom end
    function Mm:SetZoom(z)
        checkNum("SetZoom", 1, z)
        if z < 0 or z >= 6 then error("Minimap:SetZoom(): zoom out of range", 2) end
        self._zoom = z
    end
    function Mm:GetZoomLevels() return 6 end
    function Mm:SetMaskTexture(t) self._mask = t end
    function Mm:SetBlipTexture() end
    function Mm:SetPlayerTexture() end
    function Mm:PingLocation() end
    function Mm:GetPingPosition() return 0, 0 end
    function Mm:UpdateBlips() end
end
MinimapBackdrop = M.CreateFrameRaw("Frame", "MinimapBackdrop", Minimap)
Minimap.ZoomIn = M.CreateFrameRaw("Button", nil, Minimap)
Minimap.ZoomOut = M.CreateFrameRaw("Button", nil, Minimap)
Minimap.ZoomHitArea = M.CreateFrameRaw("Frame", nil, Minimap)
M.CreateFrameRaw("Button", "LibDBIcon10_Details", Minimap)
M.CreateFrameRaw("Button", "QuestieFrame123", Minimap)
M.CreateFrameRaw("Frame", "TomTomMinimapArrow", Minimap)
Minimap:CreateTexture("MinimapBorder", "ARTWORK")
Minimap:CreateTexture(nil, "OVERLAY")

-- the Minimap and its cluster must not be moved / reparented / resized from addon code in combat
local function CombatGuard(f, methods)
    for _, name in ipairs(methods) do
        local orig = findMethod(f._type, name)
        rawset(f, name, function(self, ...)
            M.ProtectedCall(("%s:%s (in combat)"):format(self._name or "?", name), "nocombat", self._name)
            return orig(self, ...)
        end)
    end
end
CombatGuard(Minimap, { "SetParent", "SetPoint", "ClearAllPoints", "SetSize", "SetScale", "Hide", "Show", "SetFrameStrata", "SetFrameLevel" })
CombatGuard(MinimapCluster, { "Hide", "Show", "SetParent", "SetPoint", "ClearAllPoints" })

C_Minimap = { _ground = false }
function C_Minimap.GetDrawGroundTextures() return C_Minimap._ground end
function C_Minimap.SetDrawGroundTextures(v) C_Minimap._ground = v end

---------------------------------------------------------------------------
-- game data: maps, instance, player, quests, items
---------------------------------------------------------------------------

Enum = Enum or {}
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

M.MAPS = {
    [947] = { name = "Azeroth", mapType = 1, parentMapID = 946 },
    [1414] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [1413] = { name = "The Barrens", mapType = 3, parentMapID = 1414, rect = { 0.42, 0.62, 0.38, 0.80 } },
    [1411] = { name = "Durotar", mapType = 3, parentMapID = 1414, rect = { 0.56, 0.66, 0.38, 0.55 } },
    [1440] = { name = "Ashenvale", mapType = 3, parentMapID = 1414, rect = { 0.36, 0.55, 0.28, 0.40 } },
    [1441] = { name = "Thousand Needles", mapType = 3, parentMapID = 1414, rect = { 0.48, 0.62, 0.72, 0.84 } },
    [1443] = { name = "Desolace", mapType = 3, parentMapID = 1414, rect = { 0.32, 0.44, 0.50, 0.66 } },
    [1444] = { name = "Feralas", mapType = 3, parentMapID = 1414, rect = { 0.33, 0.48, 0.62, 0.80 } },
    [1446] = { name = "Tanaris", mapType = 3, parentMapID = 1414, rect = { 0.50, 0.66, 0.74, 0.92 } },
    [1412] = { name = "Mulgore", mapType = 3, parentMapID = 1414, rect = { 0.40, 0.48, 0.56, 0.72 } },
    [1420] = { name = "Tirisfal Glades", mapType = 3, parentMapID = 1415, rect = { 0.38, 0.56, 0.10, 0.25 } },
    [1421] = { name = "Silverpine Forest", mapType = 3, parentMapID = 1415, rect = { 0.36, 0.48, 0.20, 0.40 } },
    [1436] = { name = "Westfall", mapType = 3, parentMapID = 1415, rect = { 0.36, 0.46, 0.70, 0.85 } },
    [1453] = { name = "Stormwind City", mapType = 3, parentMapID = 1415, rect = { 0.41, 0.47, 0.64, 0.72 } },
    [1455] = { name = "Ironforge", mapType = 3, parentMapID = 1415, rect = { 0.46, 0.50, 0.52, 0.57 } },
    [1458] = { name = "Undercity", mapType = 3, parentMapID = 1415, rect = { 0.42, 0.46, 0.18, 0.22 } },
    [1430] = { name = "Deadwind Pass", mapType = 3, parentMapID = 1415 },
    [1431] = { name = "Duskwood", mapType = 3, parentMapID = 1415 },
    [1432] = { name = "Loch Modan", mapType = 3, parentMapID = 1415 },
    [1433] = { name = "Redridge Mountains", mapType = 3, parentMapID = 1415 },
    [1437] = { name = "Wetlands", mapType = 3, parentMapID = 1415 },
    [1438] = { name = "Teldrassil", mapType = 3, parentMapID = 1414 },
    [1456] = { name = "Thunder Bluff", mapType = 3, parentMapID = 1414 },
    [1454] = { name = "Orgrimmar", mapType = 3, parentMapID = 1414 },
    [1457] = { name = "Darnassus", mapType = 3, parentMapID = 1414 },
    [1427] = { name = "Searing Gorge", mapType = 3, parentMapID = 1415 },
    [1428] = { name = "Burning Steppes", mapType = 3, parentMapID = 1415 },
    [1435] = { name = "Swamp of Sorrows", mapType = 3, parentMapID = 1415 },
    [1418] = { name = "Badlands", mapType = 3, parentMapID = 1415 },
    [1423] = { name = "Eastern Plaguelands", mapType = 3, parentMapID = 1415 },
    [1422] = { name = "Western Plaguelands", mapType = 3, parentMapID = 1415 },
    [1424] = { name = "Hillsbrad Foothills", mapType = 3, parentMapID = 1415 },
    [1416] = { name = "Alterac Mountains", mapType = 3, parentMapID = 1415 },
    [1417] = { name = "Arathi Highlands", mapType = 3, parentMapID = 1415 },
    [1426] = { name = "Dun Morogh", mapType = 3, parentMapID = 1415 },
    [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
    [1434] = { name = "Stranglethorn Vale", mapType = 3, parentMapID = 1415 },
    [1439] = { name = "Darkshore", mapType = 3, parentMapID = 1414 },
    [1442] = { name = "Stonetalon Mountains", mapType = 3, parentMapID = 1414 },
    [1445] = { name = "Dustwallow Marsh", mapType = 3, parentMapID = 1414 },
    [1447] = { name = "Azshara", mapType = 3, parentMapID = 1414 },
    [1448] = { name = "Felwood", mapType = 3, parentMapID = 1414 },
    [1449] = { name = "Un'Goro Crater", mapType = 3, parentMapID = 1414 },
    [1450] = { name = "Moonglade", mapType = 3, parentMapID = 1414 },
    [1451] = { name = "Silithus", mapType = 3, parentMapID = 1414 },
    [1452] = { name = "Winterspring", mapType = 3, parentMapID = 1414 },
    [1425] = { name = "The Hinterlands", mapType = 3, parentMapID = 1415 },
    [1419] = { name = "Blasted Lands", mapType = 3, parentMapID = 1415 },
    [279] = { name = "Wailing Caverns", mapType = 4, parentMapID = 1413 },
}

C_Map = {}
function C_Map.GetMapInfo(id)
    if type(id) ~= "number" then error("Usage: C_Map.GetMapInfo(uiMapID)", 2) end
    local m = M.MAPS[id]
    if not m then return nil end
    return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID or 0, flags = 0 }
end
function C_Map.GetMapInfoAtPosition(id, x, y)
    for zid, m in pairs(M.MAPS) do
        if m.parentMapID == id and m.rect and x >= m.rect[1] and x <= m.rect[2] and y >= m.rect[3] and y <= m.rect[4] then
            return C_Map.GetMapInfo(zid)
        end
    end
    return C_Map.GetMapInfo(id)
end
function C_Map.GetMapRectOnMap(id, top)
    local m = M.MAPS[id]
    if m and m.rect and m.parentMapID == top then return m.rect[1], m.rect[2], m.rect[3], m.rect[4] end
    return nil
end
function C_Map.GetBestMapForUnit() return nil end
function C_Map.GetPlayerMapPosition() return nil end
function C_Map.GetMapArtLayers() return nil end
function C_Map.GetMapGroupID() return nil end
function C_Map.GetMapChildrenInfo() return {} end
-- fires WORLD_MAP_OPEN; Blizzard's handler opens the map and sets it (secure execution)
function C_Map.OpenWorldMap(id)
    if id ~= nil and type(id) ~= "number" then error("Usage: C_Map.OpenWorldMap([uiMapID])", 2) end
    if not M.ProtectedCall("C_Map.OpenWorldMap", "nocombat", "WorldMapFrame") then return end
    M.openWorldMapCalls = (M.openWorldMapCalls or 0) + 1
    M.Dispatch(function()
        if not WMF:IsShown() then WMF:Show() end
        if id then WMF:SetMapID(id) end
    end)
end
function C_Map.CanSetUserWaypointOnMap(id) return C_Map.GetMapInfo(id) ~= nil end
-- the last user waypoint and whether it is super-tracked (the navigation arrow)
M.waypoint = nil
function C_Map.SetUserWaypoint(point)
    if type(point) ~= "table" or type(point.uiMapID) ~= "number" then error("Usage: C_Map.SetUserWaypoint(uiMapPoint)", 2) end
    M.waypoint = { map = point.uiMapID, x = point.position.x, y = point.position.y }
end
function C_Map.ClearUserWaypoint() M.waypoint = nil end
UiMapPoint = {}
function UiMapPoint.CreateFromCoordinates(id, x, y)
    return { uiMapID = id, position = { x = x, y = y } }
end
C_SuperTrack = {}
function C_SuperTrack.SetSuperTrackedUserWaypoint(on)
    if M.waypoint then M.waypoint.tracked = on and true or false end
end

C_Texture = {}
local ATLASES = { Dungeon = true, Raid = true, ["QuestNormal"] = true, ["Waypoint-MapPin-ChatIcon"] = true,
    ["nameplates-icon-elite-gold"] = true, ["nameplates-icon-elite-silver"] = true }
function C_Texture.GetAtlasInfo(a)
    if CFG.noDungeonAtlas and a == "Dungeon" then return nil end
    return ATLASES[a] and { width = 32, height = 32, file = 1 } or nil
end

-- instance & player
M.player = { name = "Testplayer", faction = "Horde", class = "WARRIOR", level = 20, inInstance = true,
    instanceID = 43, instanceName = "Wailing Caverns", instanceType = "party" }
function IsInInstance()
    local p = M.player
    if not p.inInstance then return false, "none" end
    return true, p.instanceType
end
-- the area inside the zone (M.player.subZone), "" when none
function GetSubZoneText() return M.player.subZone or "" end
function GetInstanceInfo()
    local p = M.player
    if not p.inInstance then return "Kalimdor", "none", 0, "", 5, 0, false, 1, 0, nil end
    return p.instanceName, p.instanceType, 1, "Normal", 5, 0, false, p.instanceID, 5, nil
end
function UnitFactionGroup(u) return M.player.faction, M.player.faction end
function UnitLevel(u) return M.player.level end
local CLASS_NAMES = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest", ROGUE = "Rogue", WARLOCK = "Warlock",
    HUNTER = "Hunter", DRUID = "Druid", SHAMAN = "Shaman", PALADIN = "Paladin" }
M.party = {} -- { {name=, class=} }
function UnitClass(u)
    if u == "player" then return CLASS_NAMES[M.player.class], M.player.class, 1 end
    local i = tonumber(tostring(u):match("party(%d)") or tostring(u):match("raid(%d+)") or "")
    local p = i and M.party[i]
    if p then return CLASS_NAMES[p.class], p.class, 1 end
    return nil
end
function UnitName(u)
    if u == "player" then return M.player.name end
    local i = tonumber(tostring(u):match("party(%d)") or tostring(u):match("raid(%d+)") or "")
    return i and M.party[i] and M.party[i].name or nil
end
-- M.target = { name, guid, dead } stands for the player's target
function UnitGUID(u)
    if u == "target" then return M.target and M.target.guid end
    return "Player-1-00000001"
end
function UnitIsDead(u) return u == "target" and M.target ~= nil and M.target.dead == true end
function UnitIsUnit(a, b) return a == b end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost() return false end
function UnitExists(u) return u == "player" or (u == "target" and M.target ~= nil) or UnitName(u) ~= nil end
function IsInRaid() return false end
function IsInGroup() return #M.party > 0 end
function GetNumGroupMembers() return #M.party > 0 and #M.party + 1 or 0 end
function GetNumSubgroupMembers() return #M.party end
function InCombatLockdown() return M.combat end
function UnitAffectingCombat() return M.combat end
function GetCursorPosition() return M.cursorX or 960, M.cursorY or 540 end
function IsMouseButtonDown() return false end
M.mod = { shift = false, ctrl = false, alt = false }
function IsModifiedClick(action)
    if action == "CHATLINK" or action == "COMPAREITEMS" then return M.mod.shift end
    if action == "DRESSUP" then return M.mod.ctrl end
    return false
end
function IsShiftKeyDown() return M.mod.shift end
function IsControlKeyDown() return M.mod.ctrl end
function GameTooltip_ShowCompareItem() M.compareShown = true end
function IsAltKeyDown() return false end
function GetLocale() return M.config.locale or "enUS" end
function GetBuildInfo() return "1.60.1", "70938", "Nov 1 2026", 16001 end
function GetMouseFoci() return { M.mouseFocus } end
function GetScreenWidth() return M.SCREEN_W end
function GetScreenHeight() return M.SCREEN_H end
function PlaySound() end
function StopSound() end
M.combatLogEvent = nil
function CombatLogGetCurrentEventInfo()
    local e = M.combatLogEvent or {}
    return unpack(e, 1, 21)
end

CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 } }
RAID_CLASS_COLORS = {}
for class in pairs(CLASS_NAMES) do
    RAID_CLASS_COLORS[class] = { r = 1, g = 0.8, b = 0.5, colorStr = "ffffcc80" }
end

-- quests
M.questsDone, M.questsInLog = {}, {}
C_QuestLog = {}
function C_QuestLog.IsQuestFlaggedCompleted(id) return M.questsDone[id] == true end
function C_QuestLog.GetLogIndexForQuestID(id) return M.questsInLog[id] end
function C_QuestLog.IsOnQuest(id) return M.questsInLog[id] ~= nil end
function C_QuestLog.GetTitleForQuestID(id) return nil end
M.questsReady = {}
M.questsWatched = {}
M.pushedQuests = {}
-- quest reward APIs: values the scenario sets in M.rewardXP / M.rewardMoney (by quest ID)
M.rewardXP, M.rewardMoney = {}, {}
function GetQuestLogRewardXP(questID) return M.rewardXP[questID] or 0 end
function GetQuestLogRewardMoney(questID) return M.rewardMoney[questID] or 0 end
function GetRewardXP() return 0 end
function GetRewardMoney() return 0 end
function GetQuestID() return M.openQuestID or 0 end
function C_QuestLog.GetQuestWatchType(id) return M.questsWatched[id] and 0 or nil end
function C_QuestLog.AddQuestWatch(id) M.questsWatched[id] = true; M.FireEvent("QUEST_WATCH_LIST_CHANGED", id, true) return true end
function C_QuestLog.RemoveQuestWatch(id) M.questsWatched[id] = nil; M.FireEvent("QUEST_WATCH_LIST_CHANGED", id, false) return true end
M.objectives = {}
function C_QuestLog.GetQuestObjectives(id) return M.objectives[id] or {} end
function C_QuestLog.IsPushableQuest(id) return M.questsInLog[id] ~= nil end
function C_QuestLog.SetSelectedQuest(id) M.selectedQuest = id end
function QuestLogPushQuest()
    if M.combat then M.ProtectedCall("QuestLogPushQuest", "nocombat") end
    table.insert(M.pushedQuests, M.selectedQuest)
end
function BreakUpLargeNumbers(n) local s = tostring(math.floor(n)) local r repeat s, r = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until r == 0 return s end
function GetCoinTextureString(copper) return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100) end
function C_QuestLog.ReadyForTurnIn(id) return M.questsReady[id] == true end
function C_QuestLog.IsComplete(id) return M.questsReady[id] == true end
if CFG.legacy then
    function IsQuestFlaggedCompleted(id) return M.questsDone[id] == true end
    function GetQuestLogIndexByID(id) return M.questsInLog[id] or 0 end
end

-- items: name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon
M.ITEMS = {
    [6630] = { "Seedcutter", 3, "Weapon", "One-Handed Axes", "INVTYPE_WEAPON", 135421 },
    [6631] = { "Living Root", 3, "Weapon", "Staves", "INVTYPE_2HWEAPON", 135146 },
    [6629] = { "Sporid Cape", 3, "Armor", "Cloth", "INVTYPE_CLOAK", 133762 },
    [10412] = { "Belt of the Fang", 3, "Armor", "Leather", "INVTYPE_WAIST", 132493 },
    [5404] = { "Serpent's Shoulders", 3, "Armor", "Leather", "INVTYPE_SHOULDER", 135039 },
    [6446] = { "Snakeskin Bag", 2, "Container", "Bag", "INVTYPE_BAG", 133643 },
    [6465] = { "Robe of the Moccasin", 3, "Armor", "Cloth", "INVTYPE_ROBE", 132650 },
    [6460] = { "Cobrahn's Grasp", 3, "Armor", "Mail", "INVTYPE_WAIST", 132517 },
    [10410] = { "Leggings of the Fang", 3, "Armor", "Leather", "INVTYPE_LEGS", 134586 },
    [13245] = { "Kresh's Back", 3, "Armor", "Shields", "INVTYPE_SHIELD", 134955 },
    [6447] = { "Worn Turtle Shell Shield", 3, "Armor", "Shields", "INVTYPE_SHIELD", 134955 },
    [5970] = { "Serpent Gloves", 3, "Armor", "Cloth", "INVTYPE_HAND", 132939 },
    [6459] = { "Savage Trodders", 3, "Armor", "Mail", "INVTYPE_FEET", 132535 },
    [6469] = { "Venomstrike", 3, "Weapon", "Bows", "INVTYPE_RANGED", 135490 },
    [10441] = { "Glowing Shard", 1, "Quest", "Quest", "", 134071 },
    [6461] = { "Slime-encrusted Pads", 3, "Armor", "Leather", "INVTYPE_SHOULDER", 135039 },
    [6463] = { "Deep Fathom Ring", 3, "Armor", "Miscellaneous", "INVTYPE_FINGER", 133345 },
    [6627] = { "Mutant Scale Breastplate", 3, "Armor", "Mail", "INVTYPE_CHEST", 132629 },
    [6473] = { "Armor of the Fang", 3, "Armor", "Leather", "INVTYPE_CHEST", 132719 },
    [6472] = { "Stinging Viper", 3, "Weapon", "One-Handed Maces", "INVTYPE_WEAPON", 133476 },
    [6448] = { "Tail Spike", 3, "Weapon", "Daggers", "INVTYPE_WEAPON", 135641 },
    [6449] = { "Glowing Lizardscale Cloak", 3, "Armor", "Cloth", "INVTYPE_CLOAK", 133762 },
    [5243] = { "Firebelcher", 3, "Weapon", "Wands", "INVTYPE_RANGEDRIGHT", 135139 },
    [6632] = { "Feyscale Cloak", 3, "Armor", "Cloth", "INVTYPE_CLOAK", 133762 },
}
M.itemCache = {}            -- id -> true when the client has it cached
M.pendingItems = {}
-- items cached from the start (others load asynchronously after a request)
for _, id in ipairs({ 6630, 6629, 10412, 6465 }) do M.itemCache[id] = true end
function M.ItemExists(id) return M.ITEMS[id] ~= nil or (id < 200000) end
function M.ItemCached(id) return M.itemCache[id] == true end
function M.RequestItem(id)
    if M.itemCache[id] or not M.ItemExists(id) or M.pendingItems[id] then return end
    M.pendingItems[id] = true
    M.AddTimer(0.25, function()
        M.pendingItems[id] = nil
        M.itemCache[id] = true
        M.FireEvent("GET_ITEM_INFO_RECEIVED", id, true)
        M.FireEvent("ITEM_DATA_LOAD_RESULT", id, true)
    end)
end
local function itemData(id)
    local d = M.ITEMS[id]
    if d then return d end
    if id < 200000 then return { "Item #" .. id, 2, "Armor", "Miscellaneous", "INVTYPE_TRINKET", 134400 } end
    return nil
end
local function getItemInfo(item)
    if type(item) == "string" then item = tonumber(item:match("item:(%d+)")) or tonumber(item) end
    if type(item) ~= "number" then error("Usage: GetItemInfo(itemID|\"name\"|\"itemlink\")", 2) end
    local d = itemData(item)
    if not d or not M.ItemCached(item) then M.RequestItem(item); return nil end
    local link = ("|cff1eff00|Hitem:%d::::::::20:::::::::|h[%s]|h|r"):format(item, d[1])
    return d[1], link, d[2], 25, 18, d[3], d[4], 1, d[5], d[6], 1000, 2, 0, 1, 0, nil, false
end
local function getItemInfoInstant(item)
    if type(item) == "string" then item = tonumber(item:match("item:(%d+)")) or tonumber(item) end
    if type(item) ~= "number" then error("Usage: GetItemInfoInstant(itemID)", 2) end
    local d = itemData(item)
    if not d then return nil end
    local classID = ({ Weapon = 2, Armor = 4 })[d[3]] or 12
    local subClassID = ({ ["One-Handed Axes"] = 0, ["Staves"] = 10, ["Bows"] = 2, ["One-Handed Maces"] = 4,
        ["Daggers"] = 15, ["Wands"] = 19, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Shields = 6, Miscellaneous = 0 })[d[4]] or 0
    return item, d[3], d[4], d[5], d[6], classID, subClassID
end
local QUALITY = { [0] = { 0.62, 0.62, 0.62, "ff9d9d9d" }, { 1, 1, 1, "ffffffff" }, { 0.12, 1, 0, "ff1eff00" },
    { 0, 0.44, 0.87, "ff0070dd" }, { 0.64, 0.21, 0.93, "ffa335ee" }, { 1, 0.5, 0, "ffff8000" } }
local function getItemQualityColor(q)
    local c = QUALITY[q] or QUALITY[1]
    return c[1], c[2], c[3], c[4]
end
ITEM_QUALITY_COLORS = {}
for q, c in pairs(QUALITY) do ITEM_QUALITY_COLORS[q] = { r = c[1], g = c[2], b = c[3], hex = "|c" .. c[4] } end

C_Item = {
    GetItemInfo = getItemInfo, GetItemInfoInstant = getItemInfoInstant, GetItemQualityColor = getItemQualityColor,
    RequestLoadItemDataByID = function(id) M.RequestItem(id) end,
    IsItemDataCachedByID = function(id) return M.ItemCached(id) end,
    DoesItemExistByID = function(id) return M.ItemExists(id) end,
    GetItemIconByID = function(id) local d = itemData(id) return d and d[6] end,
    GetItemQualityByID = function(id) local d = itemData(id) return d and d[2] end,
    GetItemNameByID = function(id) local d = M.ItemCached(id) and itemData(id) return d and d[1] end,
}
if CFG.legacy then
    GetItemInfo = getItemInfo
    GetItemInfoInstant = getItemInfoInstant
    GetItemQualityColor = getItemQualityColor
end

-- ItemMixin (ObjectAPI/Item.lua)
Item = {}
local ItemMT = { __index = {} }
local ItemM = ItemMT.__index
function Item:CreateFromItemID(id)
    if type(id) ~= "number" then error("Usage: Item:CreateFromItemID(number)", 2) end
    return setmetatable({ itemID = id }, ItemMT)
end
function ItemM:GetItemID() return self.itemID end
function ItemM:IsItemEmpty() return not M.ItemExists(self.itemID) end
function ItemM:IsItemDataCached() return M.ItemCached(self.itemID) end
function ItemM:GetItemName() local d = itemData(self.itemID) return M.ItemCached(self.itemID) and d and d[1] end
function ItemM:GetItemIcon() local d = itemData(self.itemID) return d and d[6] end
function ItemM:GetItemQuality() local d = itemData(self.itemID) return d and d[2] end
function ItemM:GetItemLink() return select(2, getItemInfo(self.itemID)) end
function ItemM:ContinueOnItemLoad(cb)
    if type(cb) ~= "function" then error("Usage: ContinueOnItemLoad(callbackFunction)", 2) end
    local id = self.itemID
    if not M.ItemExists(id) then return end -- never fires for items that do not exist
    if M.ItemCached(id) then cb() return end
    M.RequestItem(id)
    M.AddTimer(0.26, function() if M.ItemCached(id) then cb() end end)
end
function ItemM:ContinueWithCancelOnItemLoad(cb) self:ContinueOnItemLoad(cb); return function() end end

-- strings used by the addon
RETRIEVING_ITEM_INFO = "Retrieving item information"
for k, v in pairs({ INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_BODY = "Shirt",
    INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet",
    INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket",
    INVTYPE_CLOAK = "Back", INVTYPE_WEAPON = "One-Hand", INVTYPE_SHIELD = "Off Hand", INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand", INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_HOLDABLE = "Held In Off-hand",
    INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Thrown", INVTYPE_BAG = "Bag",
    INVTYPE_AMMO = "Ammo", INVTYPE_RELIC = "Relic", INVTYPE_TABARD = "Tabard" }) do _G[k] = v end

-- misc Blizzard UI functions
function SetPortraitTextureFromCreatureDisplayID(tex, displayID)
    if not isWidget(tex) or tex._type ~= "Texture" then error("SetPortraitTextureFromCreatureDisplayID(): texture expected", 2) end
    checkNum("SetPortraitTextureFromCreatureDisplayID", 2, displayID)
    tex._texture = "portrait:" .. displayID
end
function SetPortraitTexture(tex, unit) tex._texture = "portrait:" .. tostring(unit) end
function SetPortraitToTexture(tex, path) tex._texture = path end
function ChatEdit_InsertLink(link) M.lastChatLink = link return true end
function DressUpItemLink(link) M.lastDressUp = link return true end
function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1, GetRGB = function(s) return s.r, s.g, s.b end,
        GetRGBA = function(s) return s.r, s.g, s.b, s.a end }
end
-- scenario may set M.FileExists(path) -> bool; default: every file exists
if not CFG.noGetFileIDFromPath then
    function GetFileIDFromPath(path)
        if type(path) ~= "string" then error("Usage: GetFileIDFromPath(path)", 2) end
        if M.FileExists and not M.FileExists(path) then return nil end
        return 100000 + #path
    end
end

-- hooks ----------------------------------------------------------------------
function hooksecurefunc(a, b, c)
    local tbl, name, fn
    if type(a) == "string" then tbl, name, fn = _G, a, b else tbl, name, fn = a, b, c end
    local orig = tbl[name]
    if type(orig) ~= "function" then error(("hooksecurefunc(): %s is not a function"):format(tostring(name)), 2) end
    if type(fn) ~= "function" then error("hooksecurefunc(): hook must be a function", 2) end
    tbl[name] = function(...)
        local r = { orig(...) }
        local args, n = { ... }, select("#", ...)
        local saved = M.taint
        M.SafeCall(function() fn(unpack(args, 1, n)) end)
        M.taint = saved -- secure hooks do not taint the caller
        return unpack(r)
    end
end

-- error handler -----------------------------------------------------------------
local errorHandler = function(err) M.RecordError(err, debug.traceback("", 2)) end
function geterrorhandler() return errorHandler end
function seterrorhandler(f) errorHandler = f end

function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    R.prints[#R.prints + 1] = table.concat(t, " ")
end

-- WoW Lua extras ------------------------------------------------------------------
function strsplit(sep, str, limit)
    if type(str) ~= "string" then error("bad argument #2 to 'strsplit' (string expected)", 2) end
    local out, pos, n = {}, 1, 0
    while true do
        if limit and n >= limit - 1 then break end
        local s, e = str:find(sep, pos, true)
        if not s then break end
        out[#out + 1] = str:sub(pos, s - 1); n = n + 1
        pos = e + 1
    end
    out[#out + 1] = str:sub(pos)
    return unpack(out)
end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function tInvert(t) local o = {} for k, v in pairs(t) do o[v] = k end return o end
function CopyTable(t, shallow)
    local o = {}
    for k, v in pairs(t) do o[k] = (type(v) == "table" and not shallow) and CopyTable(v) or v end
    return o
end
function tostringall(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return unpack(t) end
tinsert, tremove, sort, getn = table.insert, table.remove, table.sort, table.getn
strfind, strmatch, strsub, strlen, strlower, strupper, strrep, gsub, format, strbyte, strchar =
    string.find, string.match, string.sub, string.len, string.lower, string.upper, string.rep, string.gsub,
    string.format, string.byte, string.char
floor, ceil, abs, max, min, sqrt, mod = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.fmod
string.split = function(s, sep) return strsplit(sep, s) end
string.trim = strtrim
date, time = os.date, os.time
debugprofilestop = function() return M.now * 1000 end
SlashCmdList = {}
hash_SlashCmdList = {}

-- addon compartment / settings stubs that exist on modern clients
AddonCompartmentFrame = M.CreateFrameRaw("Frame", "AddonCompartmentFrame", UIParent)
function AddonCompartmentFrame:RegisterAddon() end
C_AddOns = { IsAddOnLoaded = function(n) return n == "ForeverDungeonMap" end, GetAddOnMetadata = function() return nil end,
    LoadAddOn = function() return true end }

---------------------------------------------------------------------------
-- sandbox: remove what WoW does not have; log undefined global reads
---------------------------------------------------------------------------

function M.Sandbox()
    io, require, dofile, loadfile, module, package = nil, nil, nil, nil, nil, nil
    os = { date = os.date, time = os.time, clock = os.clock }
    local G = _G
    setmetatable(G, {
        __index = function(_, k)
            local where = addonWhere(3)
            if where then
                R.missingGlobals[k] = R.missingGlobals[k] or {}
                R.missingGlobals[k][where] = (R.missingGlobals[k][where] or 0) + 1
            end
            return nil
        end,
        __newindex = function(t, k, v)
            local where = addonWhere(3)
            if where and not R.globalsWritten[k] then R.globalsWritten[k] = where end
            rawset(t, k, v)
        end,
    })
end

---------------------------------------------------------------------------
-- helpers for scenarios
---------------------------------------------------------------------------

-- simulate the mouse entering / leaving / clicking a widget (secure dispatch)
function M.Enter(f) M.mouseFocus = f; M.Dispatch(function() M.FireScript(f, "OnEnter", true) end) end
function M.Leave(f) if M.mouseFocus == f then M.mouseFocus = nil end M.Dispatch(function() M.FireScript(f, "OnLeave", true) end) end
function M.Click(f, button)
    M.Dispatch(function()
        if f:IsObjectType("Button") then
            if f._enabled == false then return end
            M.FireScript(f, "OnClick", button or "LeftButton", false)
        else
            M.FireScript(f, "OnMouseUp", button or "LeftButton")
        end
    end)
end

-- shown descendant widgets with their rects relative to `root`'s top-left
function M.Descendants(root, filter, out)
    out = out or {}
    for _, c in ipairs(root._children or {}) do
        if not filter or filter(c) then out[#out + 1] = c end
        M.Descendants(c, filter, out)
    end
    return out
end

-- top offset (pixels below root's top) and height of region r
function M.RelTop(root, r)
    local rb, rh = vspan(root)
    local b, h = vspan(r)
    if not rb or not b then return nil end
    return (rb + rh) - (b + h), h
end
function M.RelLeft(root, r)
    local rl = hspan(root)
    local l, w = hspan(r)
    if not rl or not l then return nil end
    return l - rl, w
end
