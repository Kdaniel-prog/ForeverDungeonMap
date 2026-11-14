-- checks.lua - reusable scenario helpers for the ForeverDungeonMap harness
local Mock = MOCK
Mock.report.checks = Mock.report.checks or {}

-- Record a check result.
function Mock.Check(name, passed, detail)
    table.insert(Mock.report.checks, { name = name, ok = passed and true or false,
        detail = detail and tostring(detail) or nil, context = Mock.context })
    return passed
end

-- Run a step as a new execution path (like a user click or an event), with a label.
function Mock.Step(name, work, ...)
    local previous = Mock.context
    Mock.context = name
    local ok = Mock.Dispatch(work, ...)
    Mock.context = previous
    return ok
end

function Mock.Shown(widgets)
    local shown = {}
    for _, widget in ipairs(widgets) do
        if widget:IsShown() then shown[#shown + 1] = widget end
    end
    return shown
end

-- Shown direct children of `content`, sorted by top offset, with their geometry.
function Mock.Rows(content)
    local rows = {}
    for _, child in ipairs(content._children or {}) do
        if child._shown then
            local top, height = Mock.RelTop(content, child)
            local left, width = Mock.RelLeft(content, child)
            rows[#rows + 1] = { w = child, top = top, height = height, left = left, width = width }
        end
    end
    table.sort(rows, function(first, second) return (first.top or 1e9) < (second.top or 1e9) end)
    return rows
end

local function Overlaps(first, second)
    local firstRight, secondRight = (first.left or 0) + (first.width or 0), (second.left or 0) + (second.width or 0)
    if (first.left or 0) >= secondRight - 0.5 or (second.left or 0) >= firstRight - 0.5 then return false end
    return second.top < first.top + first.height - 0.5
end

local function RowProblems(rows, options, problems)
    for i, row in ipairs(rows) do
        if not row.top then problems[#problems + 1] = ("row %d (%s) has no position"):format(i, tostring(row.w)) end
        if row.height and row.height <= 0 then problems[#problems + 1] = ("row %d (%s) height %s"):format(i, tostring(row.w), row.height) end
        if options.width and row.left and row.width and row.left + row.width > options.width + 0.5 then
            problems[#problems + 1] = ("row %d (%s) ends at x=%.1f beyond width %.1f"):format(i, tostring(row.w), row.left + row.width, options.width)
        end
    end
end

local function OverlapProblems(rows, problems)
    for i = 1, #rows do
        for j = i + 1, #rows do
            local first, second = rows[i], rows[j]
            if first.top and second.top and Overlaps(first, second) then
                problems[#problems + 1] = ("rows %d and %d overlap (%.1f+%.1f > %.1f)"):format(i, j, first.top, first.height, second.top)
            end
        end
    end
end

-- Wrapped text must fit the row that holds it.
local function TextProblems(rows, problems)
    for i, row in ipairs(rows) do
        for _, region in ipairs(row.w._regions or {}) do
            if region._type == "FontString" and region._shown and region._wrap ~= false and region._text and region._text ~= ""
                and #region._points <= 1 and region:GetStringHeight() > (row.height or 0) + 0.5 then
                problems[#problems + 1] = ("row %d text '%s' needs %.0fpx but row is %.0fpx"):format(i,
                    Mock.PlainText(region._text):sub(1, 30), region:GetStringHeight(), row.height or 0)
            end
        end
    end
end

-- Rows in a canvas need a rect and a positive height, must not overlap and must fit the content.
function Mock.CheckRows(label, content, options)
    options = options or {}
    local rows, problems = Mock.Rows(content), {}
    RowProblems(rows, options, problems)
    OverlapProblems(rows, problems)
    local last = rows[#rows]
    if last and last.top and content:GetHeight() + 0.5 < last.top + last.height then
        problems[#problems + 1] = ("content height %.1f < last row bottom %.1f"):format(content:GetHeight(), last.top + last.height)
    end
    TextProblems(rows, problems)
    Mock.Check(label .. ": rows laid out (" .. #rows .. " rows)", #problems == 0, table.concat(problems, "; "))
    return rows
end

-- All visible text below a widget, joined with " | ".
function Mock.TextOf(widget)
    local parts = {}
    local function Scan(frame)
        for _, region in ipairs(frame._regions or {}) do
            if region._type == "FontString" and region._shown and region._text then parts[#parts + 1] = Mock.PlainText(region._text) end
        end
        for _, child in ipairs(frame._children or {}) do
            if child._shown then Scan(child) end
        end
    end
    Scan(widget)
    return table.concat(parts, " | ")
end

function Mock.FindChild(root, predicate)
    for _, child in ipairs(Mock.Descendants(root)) do
        if predicate(child) then return child end
    end
end

-- Count how often a frame gets hidden (detects repaint flicker under the mouse).
function Mock.WatchHide(frame)
    frame._hideCount = 0
    local originalHide = frame.Hide
    frame.Hide = function(self, ...)
        if self._shown then self._hideCount = self._hideCount + 1 end
        return originalHide(self, ...)
    end
end
