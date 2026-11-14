-- settings_legacy_scenario.lua - the options panel on a client without the modern Settings API:
-- Settings.lua falls back to InterfaceOptions_AddCategory. Run with and without --combat.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step
local COMBAT = M.combat

-- Stand-ins for the old Interface Options API and the two Blizzard templates the panel uses.
local panels, opened = {}, nil
function InterfaceOptions_AddCategory(panel) panels[#panels + 1] = panel end
function InterfaceOptionsFrame_OpenToCategory(panel) opened = panel end
M.RegisterXmlTemplate({ name = "UICheckButtonTemplate", type = "CheckButton", regions = {}, scripts = {} })
M.RegisterXmlTemplate({ name = "OptionsSliderTemplate", type = "Slider", regions = {}, scripts = {} })

Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
M.Advance(6)

local panel = panels[1]
Check("legacy panel registered", #panels == 1 and panel.name == "ForeverDungeonMap")
local checkboxes, sliders = {}, {}
for _, child in ipairs(panel and panel._children or {}) do
    if child:IsObjectType("CheckButton") then checkboxes[#checkboxes + 1] = child end
    if child:IsObjectType("Slider") then sliders[#sliders + 1] = child end
end
Check("three checkboxes and one slider", #checkboxes == 3 and #sliders == 1, #checkboxes .. " / " .. #sliders)

Step("show panel", function() panel:Show(); M.FireScript(panel, "OnShow") end)
Check("controls show the saved values", checkboxes[1]:GetChecked() == true and math.abs(sliders[1]:GetValue() - ns.Settings.Get("bossIconScale")) < 0.001)

local changed = {}
ns.Settings.OnChanged("questPins", function(value) changed[#changed + 1] = value end)
checkboxes[1]:SetChecked(false)
Step("click quest pins checkbox", function() M.Click(checkboxes[1]) end)
Check("checkbox saves and notifies", ns.Settings.Get("questPins") == false and changed[1] == false)

Step("drag slider to 1.23", function() sliders[1]:SetValue(1.23) end)
Check("slider snaps to the 10 % step", math.abs(ns.Settings.Get("bossIconScale") - 1.2) < 0.001, ns.Settings.Get("bossIconScale"))

Step("ns.Settings.Open", function() ns.Settings.Open() end)
if COMBAT then
    Check("in combat: panel waits for the end of combat", opened == nil)
    M.combat = false
    Step("PLAYER_REGEN_ENABLED", function() M.FireEvent("PLAYER_REGEN_ENABLED") end)
    M.combat = true
end
Check("legacy panel opened", opened == panel)
