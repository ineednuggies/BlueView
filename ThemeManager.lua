-- ThemeManager.lua (executor-friendly)
-- Fixes:
-- 1) Default preset no longer starts as Crimson (uses Purple Night if available)
-- 2) Full theme editing restored (all theme keys are editable)

local ThemeManager = {}
ThemeManager.__index = ThemeManager

local function clone(t)
	local o = {}
	for k, v in pairs(t or {}) do
		o[k] = v
	end
	return o
end

local DEFAULT_PRESETS = {
	["Purple Night"] = {
		Accent = Color3.fromRGB(154, 108, 255),
		BG     = Color3.fromRGB(10, 9, 16),
		BG2    = Color3.fromRGB(16, 13, 26),
		Panel  = Color3.fromRGB(18, 15, 30),
		Panel2 = Color3.fromRGB(13, 11, 22),
		Stroke = Color3.fromRGB(44, 36, 70),
		Text   = Color3.fromRGB(238, 240, 255),
		SubText= Color3.fromRGB(170, 175, 200),
		Muted  = Color3.fromRGB(115, 120, 150),
	},
	["Midnight"] = {
		Accent = Color3.fromRGB(90, 180, 255),
		BG     = Color3.fromRGB(8, 10, 14),
		BG2    = Color3.fromRGB(12, 16, 22),
		Panel  = Color3.fromRGB(16, 20, 28),
		Panel2 = Color3.fromRGB(12, 14, 20),
		Stroke = Color3.fromRGB(36, 46, 64),
		Text   = Color3.fromRGB(235, 244, 255),
		SubText= Color3.fromRGB(160, 180, 205),
		Muted  = Color3.fromRGB(110, 125, 150),
	},
	["Crimson"] = {
		Accent = Color3.fromRGB(255, 90, 90),
		BG     = Color3.fromRGB(14, 8, 10),
		BG2    = Color3.fromRGB(22, 12, 14),
		Panel  = Color3.fromRGB(26, 16, 18),
		Panel2 = Color3.fromRGB(18, 10, 12),
		Stroke = Color3.fromRGB(70, 36, 42),
		Text   = Color3.fromRGB(255, 238, 240),
		SubText= Color3.fromRGB(215, 170, 175),
		Muted  = Color3.fromRGB(160, 115, 120),
	},
}

function ThemeManager.GetDefaultPresets()
	local out = {}
	for name, theme in pairs(DEFAULT_PRESETS) do
		out[name] = clone(theme)
	end
	return out
end

function ThemeManager.new()
	return setmetatable({
		_presets = ThemeManager.GetDefaultPresets(),
		_currentName = nil,
	}, ThemeManager)
end

function ThemeManager:SetPresets(presets)
	if type(presets) == "table" then
		self._presets = presets
	else
		self._presets = ThemeManager.GetDefaultPresets()
	end
end

local function presetNames(presets)
	local names = {}
	for name in pairs(presets or {}) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function chooseDefaultPreset(presets)
	if presets and presets["Purple Night"] then
		return "Purple Night"
	end
	local names = presetNames(presets)
	return names[1] or ""
end

function ThemeManager:ApplyPreset(window, name)
	local t = self._presets and self._presets[name]
	if window and t then
		self._currentName = name
		window:SetTheme(clone(t))
	end
end

-- helper to safely set a theme key
local function setThemeKey(window, key, value)
	if not window then return end
	local t = clone(window:GetTheme())
	t[key] = value
	window:SetTheme(t)
end

function ThemeManager:BuildThemeMenu(window, tab, side)
	-- Requires BlueView tab object with AddGroupbox, groupbox AddDropdown/AddColorPicker/AddButton.
	if not window or not tab or not tab.AddGroupbox then
		return
	end

	side = side or "Left"
	local gb = tab:AddGroupbox("Theme", { Side = side })

	local names = presetNames(self._presets)
	local defaultPreset = chooseDefaultPreset(self._presets)

	-- Preset selector (does NOT force Crimson as default anymore)
	gb:AddDropdown("Preset", names, defaultPreset ~= "" and defaultPreset or (names[1] or ""), function(name)
		self:ApplyPreset(window, name)
	end)

	-- Apply a sane default once so the UI starts consistent
	if defaultPreset ~= "" then
		self:ApplyPreset(window, defaultPreset)
	end

	-- Full editor (restored)
	gb:AddColorPicker("Accent", window:GetTheme().Accent, function(c)
		setThemeKey(window, "Accent", c)
	end)
	gb:AddColorPicker("BG", window:GetTheme().BG, function(c)
		setThemeKey(window, "BG", c)
	end)
	gb:AddColorPicker("BG2", window:GetTheme().BG2, function(c)
		setThemeKey(window, "BG2", c)
	end)
	gb:AddColorPicker("Panel", window:GetTheme().Panel, function(c)
		setThemeKey(window, "Panel", c)
	end)
	gb:AddColorPicker("Panel2", window:GetTheme().Panel2, function(c)
		setThemeKey(window, "Panel2", c)
	end)
	gb:AddColorPicker("Stroke", window:GetTheme().Stroke, function(c)
		setThemeKey(window, "Stroke", c)
	end)
	gb:AddColorPicker("Text", window:GetTheme().Text, function(c)
		setThemeKey(window, "Text", c)
	end)
	gb:AddColorPicker("SubText", window:GetTheme().SubText, function(c)
		setThemeKey(window, "SubText", c)
	end)
	gb:AddColorPicker("Muted", window:GetTheme().Muted, function(c)
		setThemeKey(window, "Muted", c)
	end)

	-- quick reset button (optional but handy)
	if gb.AddButton then
		gb:AddButton("Reset to preset", function()
			local name = self._currentName or defaultPreset
			if name and name ~= "" then
				self:ApplyPreset(window, name)
			end
		end)
	end
end

return ThemeManager
