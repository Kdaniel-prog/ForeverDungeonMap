-- settings_scenario.lua - the options panel through the modern Settings API (Settings.lua).
-- The shared mock has no Settings API: a small stand-in is defined here. Run with and without --combat.
local addonName, ns = ...
local M = MOCK
local Check, Step = M.Check, M.Step
local COMBAT = M.combat

-- Stand-in for Blizzard's Settings API (Blizzard_Settings), only what Settings.lua uses.
local registered, opened = nil, nil
local function NewSetting(variable, key, savedTable, variableType, name, default)
    local setting = { variable = variable, key = key, variableType = variableType, name = name, default = default }
    function setting:GetValue() return savedTable[key] end
    function setting:SetValue(value)
        savedTable[key] = value
        if self.changed then M.Dispatch(self.changed, self, value) end
    end
    function setting:SetValueChangedCallback(fn) self.changed = fn end
    return setting
end
Settings = {
    RegisterVerticalLayoutCategory = function(name)
        local category = { name = name, settings = {}, controls = {} }
        function category:GetID() return 4242 end
        return category, {}
    end,
    RegisterAddOnSetting = function(category, variable, key, savedTable, variableType, name, default)
        assert(type(savedTable) == "table" and type(key) == "string" and variableType == type(default), "RegisterAddOnSetting usage")
        local setting = NewSetting(variable, key, savedTable, variableType, name, default)
        category.settings[key] = setting
        return setting
    end,
    CreateCheckbox = function(category, setting, tooltip)
        table.insert(category.controls, { kind = "checkbox", setting = setting, tooltip = tooltip })
    end,
    CreateSliderOptions = function(minimum, maximum, step)
        local sliderOptions = { minimum = minimum, maximum = maximum, step = step }
        function sliderOptions:SetLabelFormatter(side, formatter) self.formatter = formatter end
        return sliderOptions
    end,
    CreateSlider = function(category, setting, sliderOptions, tooltip)
        table.insert(category.controls, { kind = "slider", setting = setting, sliderOptions = sliderOptions, tooltip = tooltip })
    end,
    RegisterAddOnCategory = function(category) registered = category end,
    OpenToCategory = function(categoryID)
        if M.taint and M.combat then M.ProtectedCall("Settings.OpenToCategory", "nocombat", "SettingsPanel") end
        opened = categoryID
    end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }

ForeverDungeonMapDB = { questPins = false }
Step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", addonName) end)
Step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
Step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD", true, false) end)
M.Advance(6)

local KEYS = { "questPins", "liveView", "autoDungeonMap", "bossIconScale" }
Check("category registered as ForeverDungeonMap", registered and registered.name == "ForeverDungeonMap")
Check("four controls in order", registered and #registered.controls == 4 and (function()
    for i, key in ipairs(KEYS) do
        if registered.controls[i].setting.key ~= key then return false end
    end
    return true
end)())
Check("boss icon size is a 60-160 % slider", registered and registered.controls[4].kind == "slider"
    and registered.controls[4].sliderOptions.minimum == 0.6 and registered.controls[4].sliderOptions.maximum == 1.6
    and registered.controls[4].sliderOptions.formatter(1) == "100%")
Check("saved value kept, not overwritten by the default", ForeverDungeonMapDB.questPins == false and ns.Settings.Get("questPins") == false)
Check("defaults written when missing", ForeverDungeonMapDB.liveView == true and ForeverDungeonMapDB.autoDungeonMap == true)
Check("bossIconScale has a value", type(ns.Settings.Get("bossIconScale")) == "number")
Check("unknown key -> nil", ns.Settings.Get("noSuchSetting") == nil)

-- change through the panel: listeners run, QuestPins repaints
local seen = {}
ns.Settings.OnChanged("liveView", function(value, key) seen[#seen + 1] = key .. "=" .. tostring(value) end)
Step("user unticks live view", function() registered.settings.liveView:SetValue(false) end)
Check("OnChanged listener gets the new value", seen[1] == "liveView=false" and ns.Settings.Get("liveView") == false, table.concat(seen, ","))
Step("user ticks quest pins", function() registered.settings.questPins:SetValue(true) end)
Check("questPins change reaches the quest pins", ns.Settings.Get("questPins") == true)

-- change from code updates the panel's setting object too
Step("Settings.Set from code", function() ns.Settings.Set("liveView", true) end)
Check("Set from code notifies and saves", seen[2] == "liveView=true" and ForeverDungeonMapDB.liveView == true)

-- a listener error does not stop the others
ns.Settings.OnChanged("autoDungeonMap", function() error("listener failure (expected by the scenario)") end)
local after = false
ns.Settings.OnChanged("autoDungeonMap", function() after = true end)
local errorHandler = geterrorhandler()
local caught = 0
seterrorhandler(function() caught = caught + 1 end)
Step("change with a failing listener", function() ns.Settings.Set("autoDungeonMap", false) end)
seterrorhandler(errorHandler)
Check("failing listener reported, next listener still runs", caught == 1 and after == true)

-- open the panel
Step("ns.Settings.Open", function() ns.Settings.Open() end)
if COMBAT then
    Check("in combat: panel waits for the end of combat", opened == nil)
    M.combat = false
    Step("PLAYER_REGEN_ENABLED", function() M.FireEvent("PLAYER_REGEN_ENABLED") end)
    M.combat = true
end
Check("panel opened on our category", opened == 4242)
