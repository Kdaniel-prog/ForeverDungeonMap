-- ForeverDungeonMap - translations. The English text is the key: ns.L["Boss icon size on maps"]
-- returns the client language's text, or the key itself when there is no translation.
-- Language files call ns.AddTranslations(locales, { [english] = translated, ... }).
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...

local translations = {}
ns.L = setmetatable({}, {
    __index = function(_, english) return translations[english] or english end,
    -- translations come only through ns.AddTranslations
    __newindex = function() error("ns.L is read-only; use ns.AddTranslations", 2) end,
})

local function ClientLocale()
    return type(GetLocale) == "function" and GetLocale() or "enUS"
end

-- Use `strings` when the client runs one of `locales` ("deDE" or { "esES", "esMX" }).
function ns.AddTranslations(locales, strings)
    if type(locales) == "string" then locales = { locales } end
    local clientLocale = ClientLocale()
    for _, locale in ipairs(locales) do
        if locale == clientLocale then
            for english, translated in pairs(strings) do translations[english] = translated end
            return true
        end
    end
    return false
end
