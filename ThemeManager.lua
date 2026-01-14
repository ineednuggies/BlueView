-- ThemeManager.lua
-- Minimal ThemeManager compatible with BlueView.lua
-- Usage:
--   ThemeManager.Init(Library)
--   ThemeManager.SetLibraryTheme("DarkPurple") or ThemeManager.SetTheme({...})
--   ThemeManager.GetTheme()
local ThemeManager = {}

ThemeManager.Library = nil
ThemeManager.Themes = {}
ThemeManager.Current = nil

ThemeManager.Themes["DarkPurple"] = {
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

ThemeManager.Themes["MidnightBlue"] = {
	Accent = Color3.fromRGB(96, 165, 250),
	BG     = Color3.fromRGB(6, 10, 18),
	BG2    = Color3.fromRGB(9, 16, 30),
	Panel  = Color3.fromRGB(10, 18, 34),
	Panel2 = Color3.fromRGB(8, 14, 26),
	Stroke = Color3.fromRGB(28, 46, 72),
	Text   = Color3.fromRGB(238, 244, 255),
	SubText= Color3.fromRGB(170, 190, 220),
	Muted  = Color3.fromRGB(120, 140, 170),
}

function ThemeManager.Init(library)
	ThemeManager.Library = library
	ThemeManager.Current = ThemeManager.Themes["DarkPurple"]
end

function ThemeManager.GetTheme()
	return ThemeManager.Current
end

function ThemeManager.SetTheme(themeTable)
	ThemeManager.Current = themeTable
	if ThemeManager.Library and ThemeManager.Library.SetTheme then
		ThemeManager.Library:SetTheme(themeTable)
	end
end

function ThemeManager.SetLibraryTheme(name)
	local t = ThemeManager.Themes[name]
	if not t then return end
	ThemeManager.SetTheme(t)
end

function ThemeManager.AddTheme(name, themeTable)
	ThemeManager.Themes[name] = themeTable
end

return ThemeManager
