--!strict
-- ThemeManager.lua
-- Minimal Theme Manager for BlueView
-- - Lets you register themes, set current theme, and generate a "Theme" menu inside a tab for end-users.
-- - Uses BlueView's Window:SetTheme() and Window:GetTheme()

local ThemeManager = {}
ThemeManager.__index = ThemeManager

export type Theme = {
	Accent: Color3,
	BG: Color3,
	BG2: Color3,
	Panel: Color3,
	Panel2: Color3,
	Stroke: Color3,
	Text: Color3,
	SubText: Color3,
	Muted: Color3,
}

type Window = any
type Tab = any

local defaultPresets: {[string]: Theme} = {}

local function cloneTheme(t: Theme): Theme
	return {
		Accent = t.Accent,
		BG = t.BG,
		BG2 = t.BG2,
		Panel = t.Panel,
		Panel2 = t.Panel2,
		Stroke = t.Stroke,
		Text = t.Text,
		SubText = t.SubText,
		Muted = t.Muted,
	}
end

function ThemeManager.new()
	local self = setmetatable({}, ThemeManager)
	self.Presets = {}
	self.CurrentName = "Default"
	return self
end

function ThemeManager:SetPresets(presets: {[string]: Theme})
	self.Presets = presets
end

function ThemeManager:AddPreset(name: string, theme: Theme)
	self.Presets[name] = theme
end

function ThemeManager:Apply(window: Window, name: string)
	local t = self.Presets[name]
	if not t then return end
	self.CurrentName = name
	window:SetTheme(cloneTheme(t))
end

-- Creates a theme editor section inside a tab (end-user UI)
-- side: "Left" | "Right"
function ThemeManager:BuildThemeMenu(window: Window, tab: Tab, side: string?)
	side = side or "Right"
	local gb = tab:AddGroupbox("Theme", {Side = side})
	local theme: Theme = window:GetTheme()

	-- Preset dropdown
	local presetNames = {}
	for k, _ in pairs(self.Presets) do table.insert(presetNames, k) end
	table.sort(presetNames)

	gb:AddDropdown("Preset", presetNames, self.CurrentName, function(name)
		self:Apply(window, name)
	end, "theme.preset")

	-- Color pickers
	gb:AddColorPicker("Accent", theme.Accent, function(c) theme.Accent = c; window:SetTheme(theme) end, "theme.accent")
	gb:AddColorPicker("Text", theme.Text, function(c) theme.Text = c; window:SetTheme(theme) end, "theme.text")
	gb:AddColorPicker("SubText", theme.SubText, function(c) theme.SubText = c; window:SetTheme(theme) end, "theme.subtext")
	gb:AddColorPicker("Muted", theme.Muted, function(c) theme.Muted = c; window:SetTheme(theme) end, "theme.muted")
	gb:AddColorPicker("Stroke", theme.Stroke, function(c) theme.Stroke = c; window:SetTheme(theme) end, "theme.stroke")
	gb:AddColorPicker("Panel", theme.Panel, function(c) theme.Panel = c; window:SetTheme(theme) end, "theme.panel")
	gb:AddColorPicker("Panel2", theme.Panel2, function(c) theme.Panel2 = c; window:SetTheme(theme) end, "theme.panel2")
	gb:AddColorPicker("BG", theme.BG, function(c) theme.BG = c; window:SetTheme(theme) end, "theme.bg")
	gb:AddColorPicker("BG2", theme.BG2, function(c) theme.BG2 = c; window:SetTheme(theme) end, "theme.bg2")

	return gb
end

-- Default presets you can use immediately
function ThemeManager.GetDefaultPresets(): {[string]: Theme}
	if next(defaultPresets) then
		local out = {}
		for k, v in pairs(defaultPresets) do out[k] = cloneTheme(v) end
		return out
	end

	defaultPresets["Default Purple"] = {
		Accent = Color3.fromRGB(154, 108, 255),
		BG     = Color3.fromRGB(10, 9, 16),
		BG2    = Color3.fromRGB(16, 13, 26),
		Panel  = Color3.fromRGB(18, 15, 30),
		Panel2 = Color3.fromRGB(13, 11, 22),
		Stroke = Color3.fromRGB(44, 36, 70),
		Text   = Color3.fromRGB(238, 240, 255),
		SubText= Color3.fromRGB(170, 175, 200),
		Muted  = Color3.fromRGB(115, 120, 150),
	}
	defaultPresets["Midnight Blue"] = {
		Accent = Color3.fromRGB(90, 180, 255),
		BG     = Color3.fromRGB(8, 10, 18),
		BG2    = Color3.fromRGB(12, 16, 28),
		Panel  = Color3.fromRGB(14, 18, 34),
		Panel2 = Color3.fromRGB(10, 14, 26),
		Stroke = Color3.fromRGB(36, 46, 80),
		Text   = Color3.fromRGB(238, 245, 255),
		SubText= Color3.fromRGB(165, 180, 210),
		Muted  = Color3.fromRGB(105, 120, 150),
	}
	defaultPresets["Rose Dark"] = {
		Accent = Color3.fromRGB(255, 90, 140),
		BG     = Color3.fromRGB(14, 8, 12),
		BG2    = Color3.fromRGB(22, 12, 18),
		Panel  = Color3.fromRGB(26, 14, 22),
		Panel2 = Color3.fromRGB(18, 10, 16),
		Stroke = Color3.fromRGB(80, 40, 60),
		Text   = Color3.fromRGB(255, 240, 248),
		SubText= Color3.fromRGB(215, 175, 195),
		Muted  = Color3.fromRGB(160, 120, 140),
	}

	local out = {}
	for k, v in pairs(defaultPresets) do out[k] = cloneTheme(v) end
	return out
end

return ThemeManager
