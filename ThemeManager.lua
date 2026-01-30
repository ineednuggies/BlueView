-- ThemeManager.lua (Lua 5.1 / executor friendly)
-- ThemeManager compatible with BlueView.
-- Adds: full color editor (BG/BG2/Panel/Panel2/Stroke/Text/SubText/Muted/Accent) + legacy key aliases (BG1/TextColor/etc).

local ThemeManager = {}
ThemeManager.__index = ThemeManager

local function clone(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = v
	end
	return o
end

-- Normalize keys so older naming still works
local function normalizeThemeKeys(t)
	if not t then return {} end
	local out = clone(t)

	-- Legacy aliases
	if out.BG1 and not out.BG then out.BG = out.BG1 end
	if out.Background and not out.BG then out.BG = out.Background end

	if out.TextColor and not out.Text then out.Text = out.TextColor end
	if out.SubTextColor and not out.SubText then out.SubText = out.SubTextColor end
	if out.AccentColor and not out.Accent then out.Accent = out.AccentColor end
	if out.Outline and not out.Stroke then out.Stroke = out.Outline end

	-- Also expose common names for convenience
	out.BG1 = out.BG1 or out.BG
	out.TextColor = out.TextColor or out.Text
	out.AccentColor = out.AccentColor or out.Accent

	return out
end

local DEFAULT_PRESETS = {
	["Purple Night"] = normalizeThemeKeys({
		Accent = Color3.fromRGB(154, 108, 255),
		BG     = Color3.fromRGB(10, 9, 16),
		BG2    = Color3.fromRGB(16, 13, 26),
		Panel  = Color3.fromRGB(18, 15, 30),
		Panel2 = Color3.fromRGB(13, 11, 22),
		Stroke = Color3.fromRGB(44, 36, 70),
		Text   = Color3.fromRGB(238, 240, 255),
		SubText= Color3.fromRGB(170, 175, 200),
		Muted  = Color3.fromRGB(115, 120, 150),
	}),
	["Midnight"] = normalizeThemeKeys({
		Accent = Color3.fromRGB(90, 180, 255),
		BG     = Color3.fromRGB(8, 10, 14),
		BG2    = Color3.fromRGB(12, 16, 22),
		Panel  = Color3.fromRGB(16, 20, 28),
		Panel2 = Color3.fromRGB(12, 14, 20),
		Stroke = Color3.fromRGB(36, 46, 64),
		Text   = Color3.fromRGB(235, 244, 255),
		SubText= Color3.fromRGB(160, 180, 205),
		Muted  = Color3.fromRGB(110, 125, 150),
	}),
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
		window:SetTheme(normalizeThemeKeys(clone(t)))
	end
end

local function addColor(gb, window, key, label)
	local cur = normalizeThemeKeys(window:GetTheme())
	gb:AddColorPicker(label, cur[key], function(c)
		local t = normalizeThemeKeys(window:GetTheme())
		t[key] = c
		-- maintain legacy aliases too
		if key == "BG" then t.BG1 = c end
		if key == "Text" then t.TextColor = c end
		if key == "Accent" then t.AccentColor = c end
		window:SetTheme(t)
	end)
end

function ThemeManager:BuildThemeMenu(window, tab, side)
	if not window or not tab or not tab.AddGroupbox then
		return
	end

	side = side or "Left"
	local gb = tab:AddGroupbox("Theme", { Side = side })

	-- Presets
	local names = presetNames(self._presets)
	local default = names[1] or ""
	gb:AddDropdown("Preset", names, default, function(name)
		self:ApplyPreset(window, name)
	end)

	-- Full editor (BG1/BG2/TextColor/etc)
	addColor(gb, window, "Accent", "Accent")
	addColor(gb, window, "BG", "BG1")
	addColor(gb, window, "BG2", "BG2")
	addColor(gb, window, "Panel", "Panel")
	addColor(gb, window, "Panel2", "Panel2")
	addColor(gb, window, "Stroke", "Stroke")
	addColor(gb, window, "Text", "TextColor")
	addColor(gb, window, "SubText", "SubText")
	addColor(gb, window, "Muted", "Muted")

	-- Apply default preset immediately
	if default ~= "" then
		self:ApplyPreset(window, default)
	end
end

return ThemeManager
