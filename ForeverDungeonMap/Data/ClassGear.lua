-- ForeverDungeonMap - which armour and weapon types each class can use (classic rules).
-- Hand-written game facts. Item class / subclass IDs as returned by C_Item.GetItemInfoInstant:
-- armour (class 4): 0 miscellaneous, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem;
-- weapons (class 2): 0 one-handed axe, 1 two-handed axe, 2 bow, 3 gun, 4 one-handed mace, 5 two-handed mace,
-- 6 polearm, 7 one-handed sword, 8 two-handed sword, 10 staff, 13 fist weapon, 14 miscellaneous,
-- 15 dagger, 16 thrown, 18 crossbow, 19 wand, 20 fishing pole.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

ns.ITEM_CLASS_WEAPON, ns.ITEM_CLASS_ARMOR = 2, 4

-- [class] = { armor = { [subclass] = true }, weapon = { [subclass] = true } }
local function Set(list)
    local set = {}
    for _, value in ipairs(list) do set[value] = true end
    return set
end

ns.CLASS_GEAR = {
    WARRIOR = { armor = Set({ 0, 1, 2, 3, 4, 6 }), weapon = Set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 18, 20 }) },
    PALADIN = { armor = Set({ 0, 1, 2, 3, 4, 6, 7 }), weapon = Set({ 0, 1, 4, 5, 6, 7, 8, 14, 20 }) },
    HUNTER = { armor = Set({ 0, 1, 2, 3 }), weapon = Set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 14, 15, 16, 18, 20 }) },
    ROGUE = { armor = Set({ 0, 1, 2 }), weapon = Set({ 2, 3, 4, 7, 13, 14, 15, 16, 18, 20 }) },
    PRIEST = { armor = Set({ 0, 1 }), weapon = Set({ 4, 10, 14, 15, 19, 20 }) },
    SHAMAN = { armor = Set({ 0, 1, 2, 3, 6, 9 }), weapon = Set({ 0, 1, 4, 5, 10, 13, 14, 15, 20 }) },
    MAGE = { armor = Set({ 0, 1 }), weapon = Set({ 7, 10, 14, 15, 19, 20 }) },
    WARLOCK = { armor = Set({ 0, 1 }), weapon = Set({ 7, 10, 14, 15, 19, 20 }) },
    DRUID = { armor = Set({ 0, 1, 2, 8 }), weapon = Set({ 4, 5, 10, 13, 14, 15, 20 }) },
}
