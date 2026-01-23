-- ThemeManager.lua (Lua 5.1 / executor friendly)
-- Minimal ThemeManager compatible with BlueView.

local ThemeManager = {}
ThemeManager.__index = ThemeManager

local function clone(t)
	local o = {}
	for k, v in pairs(t) do
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
	-- presets: table<string, themeTable>
	if type(presets) == "table" then
		self._presets = presets
	else
		self._presets = ThemeManager.GetDefaultPresets()
	end
end

local function presetNames(presets)
	local names = {}
	for name in pairs(presets) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function ThemeManager:ApplyPreset(window, name)
	local t = self._presets and self._presets[name]
	if window and t then
		self._currentName = name
		window:SetTheme(clone(t))
	end
end

function ThemeManager:BuildThemeMenu(window, tab, side)
	-- Requires BlueView tab object with AddGroupbox, and groupbox AddDropdown/AddColorPicker.
	if not window or not tab or not tab.AddGroupbox then
		return
	end

	side = side or "Left"
	local gb = tab:AddGroupbox("Theme", { Side = side })

	local names = presetNames(self._presets)
	local default = names[1] or ""

	gb:AddDropdown("Preset", names, default, function(name)
		self:ApplyPreset(window, name)
	end)

	-- Nice extra: Accent picker to override preset accent.
	gb:AddColorPicker("Accent", window:GetTheme().Accent, function(c)
		local t = window:GetTheme()
		t.Accent = c
		window:SetTheme(t)
	end)

	-- Apply default preset immediately so menu matches current theme.
	if default ~= "" then
		self:ApplyPreset(window, default)
	end
end

return ThemeManager
