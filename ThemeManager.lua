--!strict
-- ThemeManager.lua

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

local function deepCopy(t: any): any
	local out = {}
	for k, v in pairs(t) do
		if typeof(v) == "table" then
			out[k] = deepCopy(v)
		else
			out[k] = v
		end
	end
	return out
end

local PRESETS: {[string]: Theme} = {
	["Purple Glass"] = {
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
	["Deep Space"] = {
		Accent = Color3.fromRGB(90, 180, 255),
		BG     = Color3.fromRGB(6, 8, 14),
		BG2    = Color3.fromRGB(10, 12, 22),
		Panel  = Color3.fromRGB(14, 16, 28),
		Panel2 = Color3.fromRGB(10, 12, 22),
		Stroke = Color3.fromRGB(30, 40, 70),
		Text   = Color3.fromRGB(236, 242, 255),
		SubText= Color3.fromRGB(160, 175, 205),
		Muted  = Color3.fromRGB(110, 125, 155),
	},
	["Rose Night"] = {
		Accent = Color3.fromRGB(255, 110, 170),
		BG     = Color3.fromRGB(14, 8, 12),
		BG2    = Color3.fromRGB(22, 12, 18),
		Panel  = Color3.fromRGB(26, 14, 22),
		Panel2 = Color3.fromRGB(18, 10, 16),
		Stroke = Color3.fromRGB(70, 35, 55),
		Text   = Color3.fromRGB(250, 240, 248),
		SubText= Color3.fromRGB(210, 170, 195),
		Muted  = Color3.fromRGB(150, 115, 140),
	},
	["Mono"] = {
		Accent = Color3.fromRGB(255, 255, 255),
		BG     = Color3.fromRGB(10, 10, 10),
		BG2    = Color3.fromRGB(14, 14, 14),
		Panel  = Color3.fromRGB(18, 18, 18),
		Panel2 = Color3.fromRGB(14, 14, 14),
		Stroke = Color3.fromRGB(55, 55, 55),
		Text   = Color3.fromRGB(245, 245, 245),
		SubText= Color3.fromRGB(180, 180, 180),
		Muted  = Color3.fromRGB(120, 120, 120),
	},
}

ThemeManager._themes = deepCopy(PRESETS)
ThemeManager._window = nil
ThemeManager._current = "Purple Glass"

function ThemeManager:SetLibrary(window: any)
	self._window = window
end

function ThemeManager:GetThemeNames(): {string}
	local names = {}
	for k in pairs(self._themes) do table.insert(names, k) end
	table.sort(names)
	return names
end

function ThemeManager:AddTheme(name: string, theme: Theme)
	self._themes[name] = deepCopy(theme)
end

function ThemeManager:GetTheme(name: string): Theme?
	local t = self._themes[name]
	if not t then return nil end
	return deepCopy(t)
end

function ThemeManager:ApplyTheme(name: string)
	if not self._window then return end
	local theme = self._themes[name]
	if not theme then return end
	self._current = name
	self._window:SetTheme(deepCopy(theme))
end

function ThemeManager:GetCurrentThemeName(): string
	return self._current
end

return ThemeManager
