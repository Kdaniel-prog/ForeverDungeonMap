-- ForeverDungeonMap - the options panel (Game Menu > Options > AddOns > ForeverDungeonMap)
-- and the settings API other files read: ns.Settings.Get(key), ns.Settings.OnChanged(key, listener).
-- Uses the modern Settings API; older clients get a plain Interface Options panel.
-- Copyright (C) 2026 kiszeldaniel. Licensed under the GNU GPL v3 (see LICENSE).

local addonName, ns = ...
local L = ns.L

local Options = {}
ns.Settings = Options

local CATEGORY_NAME = "ForeverDungeonMap"
-- unique variable names in the Settings API
local VARIABLE_PREFIX = "ForeverDungeonMap_"
-- legacy panel layout
local LEGACY_LEFT, LEGACY_TOP, LEGACY_ROW_HEIGHT, LEGACY_SLIDER_ROW_HEIGHT, LEGACY_SLIDER_WIDTH = 16, -16, 32, 48, 220

-- Every setting, in panel order. slider = { min, max, step }.
local DEFINITIONS = {
    { key = "questPins", default = true, label = L["Quest pins on the world map"],
        tooltip = L["Show where dungeon quests start (!) and are turned in (?) on zone and continent maps."] },
    { key = "liveView", default = true, label = L["Live view next to the map"],
        tooltip = L["Show your minimap enlarged next to the world map while the map is open."] },
    { key = "liveViewOnlyInDungeons", default = false, label = L["Live view only inside dungeons"],
        tooltip = L["Open the live view only while you are inside a dungeon or raid."] },
    { key = "autoDungeonMap", default = true, label = L["Dungeon map on M inside dungeons"],
        tooltip = L["Opening the world map inside a dungeon also opens the dungeon's own map."] },
    { key = "recapPopup", default = true, label = L["Recap after a dungeon"],
        tooltip = L["Show what happened (time, experience, loot) when you leave a dungeon."] },
    { key = "bossIconScale", default = 1.0, label = L["Boss icon size on maps"],
        tooltip = L["Size of the boss portraits on the dungeon maps."], slider = { min = 0.6, max = 1.6, step = 0.1 } },
}
local DEFINITION_OF = {}
for _, definition in ipairs(DEFINITIONS) do DEFINITION_OF[definition.key] = definition end

local listeners = {}
-- Settings API objects by key (modern panel only)
local settingObjects = {}
local modernCategory, legacyPanel

local function SavedSettings()
    return ns.db or ForeverDungeonMapDB
end

-- Current value of a setting (its default until one is saved).
function Options.Get(key)
    local savedSettings = SavedSettings()
    local value
    if type(savedSettings) == "table" then value = savedSettings[key] end
    if value == nil and DEFINITION_OF[key] then return DEFINITION_OF[key].default end
    return value
end

-- Run listener(value, key) whenever setting `key` changes.
function Options.OnChanged(key, listener)
    listeners[key] = listeners[key] or {}
    table.insert(listeners[key], listener)
end

local function Notify(key)
    local value = Options.Get(key)
    for _, listener in ipairs(listeners[key] or {}) do
        local ok, problem = pcall(listener, value, key)
        if not ok then geterrorhandler()(problem) end
    end
end

-- Change a setting from code (the panel shows the new value too).
function Options.Set(key, value)
    local setting = settingObjects[key]
    if setting and setting.SetValue then
        setting:SetValue(value)
        return
    end
    local savedSettings = SavedSettings()
    if type(savedSettings) ~= "table" then return end
    savedSettings[key] = value
    Notify(key)
end

local function ApplyDefaults()
    local savedSettings = SavedSettings()
    if type(savedSettings) ~= "table" then return end
    for _, definition in ipairs(DEFINITIONS) do
        if savedSettings[definition.key] == nil then savedSettings[definition.key] = definition.default end
    end
end

local function FormatPercent(value)
    return ("%d%%"):format(math.floor(value * ns.PERCENT + 0.5))
end

-- Snap a slider value to its step (sliders report fractions in between).
local function SnapToStep(value, slider)
    local steps = math.floor((value - slider.min) / slider.step + 0.5)
    return math.max(slider.min, math.min(slider.max, slider.min + steps * slider.step))
end


local function WatchModernSetting(setting, key)
    if setting.SetValueChangedCallback then
        setting:SetValueChangedCallback(function() Notify(key) end)
    elseif Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback(VARIABLE_PREFIX .. key, function() Notify(key) end)
    end
end

local function CreateModernSlider(category, setting, definition)
    local slider = definition.slider
    local sliderOptions = Settings.CreateSliderOptions(slider.min, slider.max, slider.step)
    local labelSide = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
    if labelSide and sliderOptions.SetLabelFormatter then sliderOptions:SetLabelFormatter(labelSide.Right, FormatPercent) end
    Settings.CreateSlider(category, setting, sliderOptions, definition.tooltip)
end

local function AddModernSetting(category, definition)
    local setting = Settings.RegisterAddOnSetting(category, VARIABLE_PREFIX .. definition.key, definition.key,
        SavedSettings(), type(definition.default), definition.label, definition.default)
    settingObjects[definition.key] = setting
    WatchModernSetting(setting, definition.key)
    if definition.slider then
        CreateModernSlider(category, setting, definition)
    else
        local createCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
        createCheckbox(category, setting, definition.tooltip)
    end
end

local function HasModernSettings()
    return type(Settings) == "table" and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.RegisterAddOnCategory and (Settings.CreateCheckbox or Settings.CreateCheckBox) and Settings.CreateSlider
end

local function RegisterModernPanel()
    local category = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
    for _, definition in ipairs(DEFINITIONS) do AddModernSetting(category, definition) end
    Settings.RegisterAddOnCategory(category)
    modernCategory = category
end


local function CreateLegacyCheckbox(panel, definition, top)
    local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", LEGACY_LEFT, top)
    checkbox.Label = panel:CreateFontString(nil, "ARTWORK", ns.Font("GameFontHighlight"))
    checkbox.Label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox.Label:SetText(definition.label)
    checkbox:SetScript("OnClick", function(self) Options.Set(definition.key, self:GetChecked() and true or false) end)
    checkbox.Refresh = function(self) self:SetChecked(Options.Get(definition.key) and true or false) end
    return checkbox, LEGACY_ROW_HEIGHT
end

local function CreateLegacySlider(panel, definition, top)
    local range = definition.slider
    local label = panel:CreateFontString(nil, "ARTWORK", ns.Font("GameFontHighlight"))
    label:SetPoint("TOPLEFT", LEGACY_LEFT + 4, top)
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    slider:SetWidth(LEGACY_SLIDER_WIDTH)
    slider:SetMinMaxValues(range.min, range.max)
    slider:SetValueStep(range.step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local function ShowValue() label:SetText(definition.label .. ": " .. FormatPercent(Options.Get(definition.key))) end
    slider:SetScript("OnValueChanged", function(_, value)
        if slider.refreshing then return end
        Options.Set(definition.key, SnapToStep(value, range))
        ShowValue()
    end)
    slider.Refresh = function(self)
        self.refreshing = true
        self:SetValue(Options.Get(definition.key))
        self.refreshing = false
        ShowValue()
    end
    return slider, LEGACY_SLIDER_ROW_HEIGHT
end

local function RegisterLegacyPanel()
    local panel = CreateFrame("Frame")
    panel.name = CATEGORY_NAME
    local title = panel:CreateFontString(nil, "ARTWORK", ns.Font("GameFontNormalLarge"))
    title:SetPoint("TOPLEFT", LEGACY_LEFT, LEGACY_TOP)
    title:SetText(CATEGORY_NAME)
    local controls, top = {}, LEGACY_TOP - LEGACY_ROW_HEIGHT
    for _, definition in ipairs(DEFINITIONS) do
        local create = definition.slider and CreateLegacySlider or CreateLegacyCheckbox
        local control, height = create(panel, definition, top)
        controls[#controls + 1] = control
        top = top - height
    end
    panel.refresh = function() for _, control in ipairs(controls) do control:Refresh() end end
    panel:SetScript("OnShow", panel.refresh)
    InterfaceOptions_AddCategory(panel)
    legacyPanel = panel
end


local function OpenPanel()
    if modernCategory and Settings.OpenToCategory then
        local categoryID = modernCategory.GetID and modernCategory:GetID() or modernCategory.ID
        Settings.OpenToCategory(categoryID)
    elseif legacyPanel and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(legacyPanel)
    end
end

-- Open the options panel (after combat when called in combat).
function Options.Open()
    ns.AfterCombat("settingsPanel", OpenPanel)
end

local function RegisterPanel()
    if HasModernSettings() then
        local ok, problem = pcall(RegisterModernPanel)
        if ok then return end
        geterrorhandler()(problem)
        settingObjects, modernCategory = {}, nil
    end
    if type(InterfaceOptions_AddCategory) == "function" then RegisterLegacyPanel() end
end

ns.OnLoad(function()
    ApplyDefaults()
    RegisterPanel()
end)
