-- locale_scenario.lua - translations (Locales/Locale.lua): English keys, client-locale tables,
-- read-only ns.L. The mock client is enUS. Run with and without --combat.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step

Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
M.Advance(1)

local L = ns.L
Check("ns.L and ns.AddTranslations exist", type(L) == "table" and type(ns.AddTranslations) == "function")
Check("missing key returns the English key", L["Boss icon size on maps"] == "Boss icon size on maps")
Check("enUS client ignores other languages", L["Quest giver"] == "Quest giver" and L["%s XP"]:format(5) == "5 XP")
Check("other locale not applied", ns.AddTranslations("deDE", { ["Scenario key"] = "Szenario" }) == false
    and L["Scenario key"] == "Scenario key")
Check("client locale applied", ns.AddTranslations({ "enGB", "enUS" }, { ["Scenario key"] = "Scenario text" }) == true
    and L["Scenario key"] == "Scenario text")
Check("ns.L is read-only", not pcall(function() L["Scenario key"] = "changed" end) and L["Scenario key"] == "Scenario text")
Check("quest pin tooltip text goes through ns.L", ns.Rewards.FormatExperience(90, false) == "90 XP")
