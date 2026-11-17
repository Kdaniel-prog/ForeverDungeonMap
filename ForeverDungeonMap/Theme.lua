-- ForeverDungeonMap - "Gilded Codex" skin: one palette, fonts and textures for every dungeon
-- (docs/ui-spec.md section 0). Dungeons get their character from their art, not from colours.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L

-- Palette (spec 0.2): the only place colours are written down.
local C = {
    INK         = { 0.06, 0.05, 0.04, 0.94 },
    ROW         = { 0.11, 0.09, 0.07, 0.96 },
    ROW_HOVER   = { 0.16, 0.13, 0.09, 0.98 },
    ROW_SEL     = { 0.24, 0.18, 0.08, 0.98 },
    ROW_PRESS   = { 0.08, 0.06, 0.05, 1 },
    EDGE        = { 0.36, 0.29, 0.17, 1 },
    EDGE_PANEL  = { 0.55, 0.43, 0.22, 1 },
    GOLD        = { 1.00, 0.82, 0.00, 1 },
    GOLD_SOFT   = { 1.00, 0.78, 0.30, 1 },
    TEXT        = { 0.93, 0.91, 0.86, 1 },
    MUTED       = { 0.64, 0.60, 0.52, 1 },
    PARCH_BG    = { 0.80, 0.70, 0.50, 1 },
    PARCH_TEXT  = { 0.20, 0.12, 0.04, 1 },
    PARCH_HEAD  = { 0.42, 0.11, 0.02, 1 },
    PARCH_MUTED = { 0.38, 0.29, 0.18, 1 },
    PARCH_ROW   = { 0.16, 0.12, 0.07, 0.92 },
    PARCH_ROW_HOVER = { 0.22, 0.17, 0.10, 0.95 },
    PARCH_ROW_SEL = { 0.30, 0.22, 0.10, 0.95 },
    PARCH_EDGE  = { 0.45, 0.33, 0.18, 1 },
    PARCH_LINK  = { 0.10, 0.28, 0.55, 1 },
    PARCH_RULE  = { 0.42, 0.11, 0.02, 0.35 },
    DONE        = { 0.25, 1.00, 0.25, 1 },
    DONE_PARCH  = { 0.10, 0.45, 0.08, 1 },
    DEFEATED    = { 1.00, 0.32, 0.25, 1 },
    FOREVER     = { 0.40, 0.80, 1.00, 1 },
    RARE        = { 0.75, 0.75, 1.00, 1 },
    RED         = { 1.00, 0.30, 0.30, 1 },
    HINT        = { 0.60, 0.80, 1.00, 1 },
    WHITE       = { 1, 1, 1, 1 },
    CLEAR       = { 0, 0, 0, 0 },
    PRESS_SHADE = { 0, 0, 0, 0.25 },
    LINE_HOVER  = { 1, 0.82, 0, 0.10 },
    LINE_SEL    = { 1, 0.82, 0, 0.18 },
    LINE_PRESS  = { 1, 0.82, 0, 0.14 },
    CHAIN_BG    = { 0, 0, 0, 0.35 },
    BADGE_BG    = { 0.06, 0.05, 0.04, 1 },
    ORDER_BG    = { 0.08, 0.06, 0.05, 1 },
    MAP_BG      = { 0.03, 0.025, 0.02, 1 },
    SHADE_DARK  = { 0, 0, 0, 0.92 },
    SHADE_LIGHT = { 0, 0, 0, 0.25 },
    SHADE_FLAT  = { 0, 0, 0, 0.6 },
    ROCK_TINT   = { 0.32, 0.30, 0.28, 1 },
    TOOLTIP_BG  = { 0.03, 0.03, 0.04, 1 },
    SUBTLE      = { 0.80, 0.80, 0.80, 1 },
    TOOLTIP_TEXT = { 0.75, 0.75, 0.75, 1 },
    BLACK       = { 0, 0, 0, 1 },
    PILL_EDGE   = { 1.00, 0.78, 0.30, 1 },
}
ns.C = C

-- Alpha values of the skin.
ns.ALPHA = {
    rowGlow = 0.30, cardGlow = 0.15, parchmentGlow = 0.18, headerArt = 0.75, lore = 0.18,
    mapLore = 0.12, disabled = 0.5, divider = 0.8, cardArt = 0.85, hiddenArt = 0.3,
}

-- "|cffRRGGBB" for a palette colour.
function ns.Hex(color)
    local function byte(value) return math.floor(value * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(byte(color[1]), byte(color[2]), byte(color[3]))
end

-- Inline texture for a FontString ("|T<file>:<size>|t").
function ns.IconString(texture, size)
    return ("|T%s:%d|t"):format(tostring(texture), size or 14)
end

-- Textures (spec 0.1), by FileDataID where the spec confirmed them.
ns.TEX = {
    WHITE = "Interface\\Buttons\\WHITE8X8",
    -- Interface\FrameGeneral\UI-Background-Rock
    ROCK = 374155,
    -- Interface\DialogFrame\UI-DialogBox-Background-Dark
    DIALOG_BG = 312922,
    -- Interface\DialogFrame\UI-DialogBox-Gold-Border
    GOLD_BORDER = 131076,
    -- Interface\DialogFrame\UI-DialogBox-Header
    RIBBON = 131080,
    -- Interface\Tooltips\UI-Tooltip-Border
    TOOLTIP_EDGE = 137057,
    -- Interface\Common\UI-TooltipDivider
    DIVIDER = 609615,
    -- Interface\QuestFrame\QuestBG
    PARCHMENT = 530420,
    -- Interface\QuestFrame\UI-HorizontalBreak
    HORIZONTAL_BREAK = 136783,
    -- Interface\QuestFrame\UI-Quest-BulletPoint
    BULLET = 136788,
    -- Interface\QuestFrame\UI-QuestTitleHighlight
    ROW_GLOW = 136810,
    -- Interface\Common\WhiteIconFrame
    QUALITY_FRAME = 651080,
    -- Interface\Buttons\ButtonHilight-Square
    SQUARE_HIGHLIGHT = 130718,
    -- Interface\Common\portrait-ring-withbg-highlight
    RING_HOVER = 652157,
    -- Interface\Common\GoldRing
    GOLD_RING = 519888,
    -- Interface\CharacterFrame\TempPortraitAlphaMask
    CIRCLE_MASK = 130924,
    -- Interface\GossipFrame\AvailableQuestIcon
    QUEST_AVAILABLE = 132049,
    -- Interface\GossipFrame\ActiveQuestIcon (gold "?")
    QUEST_ACTIVE = 132048,
    -- Interface\GossipFrame\IncompleteQuestIcon (grey "?")
    QUEST_INCOMPLETE = 365195,
    -- Interface\RaidFrame\ReadyCheck-Ready
    TICK = 136814,
    -- Interface\RaidFrame\ReadyCheck-NotReady
    CROSS = 136813,
    -- Interface\Common\icon-alliance
    ALLIANCE = 652155,
    -- Interface\Common\icon-horde
    HORDE = 652156,
    -- Interface\TargetingFrame\UI-TargetingFrame-Skull
    SKULL = 137025,
    -- Interface\Icons\INV_Misc_Map_01
    MAP = 134269,
    -- Interface\Icons\INV_Misc_QuestionMark
    QUESTION = 134400,
    -- Interface\Buttons\UI-Common-MouseHilight
    ROUND_HIGHLIGHT = 130757,
    -- Interface\EncounterJournal\UI-EJ-BOSS-Default
    BOSS_DEFAULT = 521744,
    -- Interface\Common\FavoritesIcon
    FAVOURITE = 922035,
    -- Interface\Icons\XP_Icon
    EXPERIENCE = 894556,
    -- Interface\MoneyFrame\UI-GoldIcon / UI-SilverIcon / UI-CopperIcon
    COIN_GOLD = 237618,
    COIN_SILVER = 237620,
    COIN_COPPER = 237617,
    MINIMAP_ROUND_MASK = "Interface\\Masks\\CircleMaskScalable",
    CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
    SLOT_FILTER = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    DROPDOWN_ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow",
    TRACK = "Interface\\Icons\\INV_Misc_Spyglass_03",
    SHARE = "Interface\\Icons\\INV_Letter_15",
    -- the game's own blue "report a bug" beetle; the note icon if this client lacks it
    BUG_REPORT = "Interface\\HelpFrame\\HelpIcon-Bug",
    BUG_REPORT_FALLBACK = "Interface\\Icons\\INV_Misc_Note_01",
    MINUS = "Interface\\Buttons\\UI-MinusButton-Up",
    PLUS = "Interface\\Buttons\\UI-PlusButton-Up",
    -- Interface\Buttons\UI-DialogBox-Button-Gold-Up / -Down / UI-DialogBox-Button-Disabled
    ACTION_UP = 949700,
    ACTION_DOWN = 949699,
    ACTION_DISABLED = 130760,
    PREVIOUS_UP = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    -- icon of the map's level dropdown
    FLOOR_ICON = "Interface\\Icons\\INV_Misc_Map02",
    LFG_DUNGEON = "Interface\\LFGFrame\\LFGIcon-Dungeon",
    LFG_PREFIX = "Interface\\LFGFrame\\LFGIcon-",
    -- journal home: "Hide dungeons" and "Recap"; recap pills: time and deaths
    HIDE = "Interface\\Icons\\Ability_Stealth",
    RECAP = "Interface\\Icons\\INV_Scroll_03",
    CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    DEATH = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    CHAIN = ns.MEDIA .. "Chain",
}
ns.TEX.ACTION_COORDS = { 0, 0.625, 0, 0.6875 }
ns.TEX.BOSS_DEFAULT_COORDS = { 0.25, 0.75, 0, 1 }
ns.TEX.FULL_COORDS = { 0, 1, 0, 1 }
-- QuestBG's parchment fills only 300x336 of its 512x512 file
ns.TEX.PARCHMENT_COORDS = { 0, 0.5859375, 0, 0.65625 }
ns.TEX.SQUARE_CROP_COORDS = { 0.25, 0.75, 0, 1 }
ns.TEX.DUNGEON_ATLAS = "Dungeon"
-- elite dragon of a boss pin without a portrait: rare elites silver, others gold
ns.TEX.ELITE_ATLAS = { gold = "nameplates-icon-elite-gold", silver = "nameplates-icon-elite-silver" }
ns.TEX.EXPERIENCE_COORDS = { 0.08, 0.92, 0.08, 0.92 }
-- Class icon crops of UI-CharacterCreate-Classes, used when CLASS_ICON_TCOORDS is missing.
ns.TEX.CLASS_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
}

-- Fonts (spec 0.3): role -> first font object that exists on this client.
local FONTS = {
    title = { "QuestTitleFontBlackShadow", "GameFontNormalHuge" },
    panelTitle = { "GameFontNormalLarge" },
    questTitle = { "QuestTitleFont", "GameFontNormalLarge" },
    questHeading = { "QuestTitleFont", "GameFontNormal" },
    questBody = { "QuestFont", "GameFontHighlight" },
    questSmall = { "QuestFontNormalSmall", "GameFontNormalSmall" },
    number = { "NumberFontNormal", "GameFontHighlightSmall" },
    numberSmall = { "NumberFontNormalSmall", "GameFontHighlightSmall" },
    disable = { "GameFontDisable" },
    disableLarge = { "GameFontDisableLarge" },
}
local resolvedFonts = {}

-- Font object name for a role (falls back when the client lacks the preferred one).
function ns.Font(role)
    if resolvedFonts[role] then return resolvedFonts[role] end
    for _, name in ipairs(FONTS[role] or { role }) do
        if _G[name] then
            resolvedFonts[role] = name
            return name
        end
    end
    resolvedFonts[role] = "GameFontNormal"
    return "GameFontNormal"
end

-- Backdrops of panels, rows, thin insets and the window.
ns.BACKDROP = {
    bgFile = ns.TEX.WHITE, edgeFile = ns.TEX.TOOLTIP_EDGE, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
ns.BACKDROP_THIN = {
    bgFile = ns.TEX.WHITE, edgeFile = ns.TEX.TOOLTIP_EDGE, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
ns.BACKDROP_LINE = { bgFile = ns.TEX.WHITE, edgeFile = ns.TEX.WHITE, edgeSize = 1 }
ns.BACKDROP_WINDOW = {
    bgFile = ns.TEX.DIALOG_BG, tile = true, tileSize = 32,
    edgeFile = ns.TEX.GOLD_BORDER, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
}

-- Paint a BackdropTemplate frame: fill colour, optional border colour and backdrop.
function ns.Paint(frame, fill, edge, backdrop)
    if not frame.SetBackdrop then return end
    backdrop = backdrop or ns.BACKDROP
    if frame.appliedBackdrop ~= backdrop then
        frame:SetBackdrop(backdrop)
        frame.appliedBackdrop = backdrop
    end
    frame:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
    if edge then frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1) end
end

-- Quest difficulty colour of a level against the player's level: r, g, b.
function ns.LevelColor(level)
    if not level then return C.TEXT[1], C.TEXT[2], C.TEXT[3] end
    if type(GetQuestDifficultyColor) == "function" then
        local ok, color = pcall(GetQuestDifficultyColor, level)
        if ok and type(color) == "table" and color.r then return color.r, color.g, color.b end
    end
    local difference = level - (UnitLevel("player") or 1)
    if difference >= 5 then return 1, 0.1, 0.1 end
    if difference >= 3 then return 1, 0.5, 0.25 end
    if difference >= -2 then return 1, 0.82, 0 end
    if difference >= -8 then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

-- Colour of a dungeon level range for the player: r, g, b.
function ns.RangeColor(minimum, maximum)
    if not minimum then return C.TEXT[1], C.TEXT[2], C.TEXT[3] end
    local playerLevel = UnitLevel("player") or 1
    if playerLevel < minimum - 2 then return 1, 0.1, 0.1 end
    if playerLevel < minimum then return 1, 0.5, 0.25 end
    if playerLevel > maximum then return 0.5, 0.5, 0.5 end
    return ns.LevelColor(playerLevel)
end

-- "Level 15-24" in the range colour.
function ns.RangeText(dungeon)
    if not dungeon.min then return nil end
    local red, green, blue = ns.RangeColor(dungeon.min, dungeon.max)
    return ns.Hex({ red, green, blue }) .. L["Level %d-%d"]:format(dungeon.min, dungeon.max) .. "|r"
end
