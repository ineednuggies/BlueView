--!strict
-- ThemeManager.lua (UPDATED)
-- Provides UI to edit Accent + Text + Background colors + Presets

local ThemeManager = {}

local PRESETS = {
	["BlueView Purple"] = function()
		return {
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
	end,
	["Midnight"] = function()
		return {
			Accent = Color3.fromRGB(90, 180, 255),
			BG     = Color3.fromRGB(6, 8, 12),
			BG2    = Color3.fromRGB(10, 12, 18),
			Panel  = Color3.fromRGB(14, 16, 24),
			Panel2 = Color3.fromRGB(10, 12, 18),
			Stroke = Color3.fromRGB(36, 46, 70),
			Text   = Color3.fromRGB(240, 247, 255),
			SubText= Color3.fromRGB(170, 190, 210),
			Muted  = Color3.fromRGB(110, 130, 150),
		}
	end,
	["Light"] = function()
		return {
			Accent = Color3.fromRGB(120, 90, 255),
			BG     = Color3.fromRGB(235, 238, 245),
			BG2    = Color3.fromRGB(245, 247, 252),
			Panel  = Color3.fromRGB(255, 255, 255),
			Panel2 = Color3.fromRGB(248, 250, 255),
			Stroke = Color3.fromRGB(190, 195, 210),
			Text   = Color3.fromRGB(20, 22, 28),
			SubText= Color3.fromRGB(70, 75, 90),
			Muted  = Color3.fromRGB(110, 115, 135),
		}
	end,
}

local PRESET_NAMES = {"BlueView Purple", "Midnight", "Light"}

function ThemeManager.Setup(window: any, tab: any)
	-- Put Theme UI inside chosen tab
	local gb = tab:AddGroupbox("Theme", {Side = "Right"})

	gb:AddDropdown("Preset Theme", PRESET_NAMES, "BlueView Purple", function(name: string)
		local maker = PRESETS[name]
		if maker then
			window:SetTheme(maker())
		end
	end, "theme_preset")

	-- compact spacing comes from BlueView groupbox padding changes
	gb:AddColorPicker("Accent", window:GetTheme().Accent, function(c: Color3)
		local t = window:GetTheme()
		t.Accent = c
		window:SetTheme(t)
	end, "theme_accent")

	gb:AddColorPicker("Text", window:GetTheme().Text, function(c: Color3)
		local t = window:GetTheme()
		t.Text = c
		-- derive SubText/Muted as “grey versions” if you want:
		-- keep your existing if you prefer, but here’s a simple blend:
		t.SubText = t.Text:Lerp(Color3.new(1,1,1), 0.25)
		t.Muted = t.Text:Lerp(Color3.new(0,0,0), 0.55)
		window:SetTheme(t)
	end, "theme_text")

	gb:AddColorPicker("Background", window:GetTheme().BG, function(c: Color3)
		local t = window:GetTheme()
		t.BG = c
		window:SetTheme(t)
	end, "theme_bg")

	gb:AddColorPicker("Panel", window:GetTheme().Panel, function(c: Color3)
		local t = window:GetTheme()
		t.Panel = c
		window:SetTheme(t)
	end, "theme_panel")
end

return ThemeManager
