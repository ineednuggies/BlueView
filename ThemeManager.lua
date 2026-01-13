--!strict
-- ThemeManager.lua - simple theme presets + apply to BlueView window

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

local themes: {[string]: Theme} = {
	Purple = {
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
	Midnight = {
		Accent = Color3.fromRGB(90, 180, 255),
		BG     = Color3.fromRGB(7, 9, 14),
		BG2    = Color3.fromRGB(10, 12, 20),
		Panel  = Color3.fromRGB(13, 16, 26),
		Panel2 = Color3.fromRGB(10, 12, 20),
		Stroke = Color3.fromRGB(32, 45, 70),
		Text   = Color3.fromRGB(235, 245, 255),
		SubText= Color3.fromRGB(170, 185, 205),
		Muted  = Color3.fromRGB(110, 125, 150),
	},
	Crimson = {
		Accent = Color3.fromRGB(255, 90, 90),
		BG     = Color3.fromRGB(14, 8, 10),
		BG2    = Color3.fromRGB(20, 10, 14),
		Panel  = Color3.fromRGB(24, 12, 16),
		Panel2 = Color3.fromRGB(18, 10, 13),
		Stroke = Color3.fromRGB(75, 36, 45),
		Text   = Color3.fromRGB(245, 235, 240),
		SubText= Color3.fromRGB(205, 170, 182),
		Muted  = Color3.fromRGB(155, 120, 130),
	},
}

function ThemeManager.GetThemes()
	return themes
end

function ThemeManager.AddTheme(name: string, theme: Theme)
	themes[name] = theme
end

function ThemeManager.Apply(window: any, nameOrTheme: any)
	if typeof(nameOrTheme) == "string" then
		local t = themes[nameOrTheme]
		if t and window and window.SetTheme then
			window:SetTheme(t)
		end
	elseif typeof(nameOrTheme) == "table" then
		if window and window.SetTheme then
			window:SetTheme(nameOrTheme)
		end
	end
end

return ThemeManager
