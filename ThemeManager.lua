--!strict
-- ThemeManager.lua
-- Requires SpareStackUI.lua update (window:ApplyTheme + theme hooks)

local ThemeManager = {}

export type SetupOptions = {
	TabName: string,
	GroupTitle: string?,
	Side: ("Left"|"Right")?,
}

local function clamp255(n: number): number
	return math.clamp(math.floor(n + 0.5), 0, 255)
end

local function colorToRGB(c: Color3)
	return clamp255(c.R * 255), clamp255(c.G * 255), clamp255(c.B * 255)
end

local function rgbToColor(r: number, g: number, b: number): Color3
	return Color3.fromRGB(clamp255(r), clamp255(g), clamp255(b))
end

function ThemeManager.Setup(window: any, opts: SetupOptions)
	local tab = window.Tabs[opts.TabName]
	if not tab then
		error(("ThemeManager.Setup: Tab '%s' not found"):format(opts.TabName))
	end

	local side = opts.Side or "Right"
	local gb = tab:AddGroupbox(opts.GroupTitle or "Theme", {Side = side})

	local theme = window:GetTheme()

	local function addColorEditor(label: string, getColor: ()->Color3, applyColor: (Color3)->())
		local c = getColor()
		local r, g, b = colorToRGB(c)

		gb:AddSlider(label .. " - R", 0, 255, r, 1, function(v)
			r = v
			applyColor(rgbToColor(r, g, b))
		end)
		gb:AddSlider(label .. " - G", 0, 255, g, 1, function(v)
			g = v
			applyColor(rgbToColor(r, g, b))
		end)
		gb:AddSlider(label .. " - B", 0, 255, b, 1, function(v)
			b = v
			applyColor(rgbToColor(r, g, b))
		end)
	end

	-- Text color editor
	addColorEditor("Text", function()
		return window:GetTheme().Text
	end, function(c: Color3)
		-- keep SubText/Muted reasonably derived
		window:ApplyTheme({
			Text = c,
			SubText = c:Lerp(Color3.new(1,1,1), 0.0):Lerp(Color3.new(0,0,0), 0.35),
			Muted = c:Lerp(Color3.new(0,0,0), 0.55),
		})
	end)

	-- Main color editor
	addColorEditor("Main", function()
		return window:GetTheme().BG
	end, function(c: Color3)
		window:ApplyTheme({
			BG = c,
			BG2 = c:Lerp(Color3.new(1,1,1), 0.08),
			Panel = c:Lerp(Color3.new(1,1,1), 0.10),
			Panel2 = c:Lerp(Color3.new(0,0,0), 0.12),
		})
	end)

	-- Accent color editor
	addColorEditor("Accent", function()
		return window:GetTheme().Accent
	end, function(c: Color3)
		window:ApplyTheme({Accent = c})
	end)

	gb:AddButton("Reset Theme", function()
		-- you can replace these with your own defaults if you want
		window:ApplyTheme({
			Accent = Color3.fromRGB(154, 108, 255),
			BG     = Color3.fromRGB(10, 9, 16),
			BG2    = Color3.fromRGB(16, 13, 26),
			Panel  = Color3.fromRGB(18, 15, 30),
			Panel2 = Color3.fromRGB(13, 11, 22),
			Stroke = Color3.fromRGB(44, 36, 70),
			Text   = Color3.fromRGB(238, 240, 255),
			SubText= Color3.fromRGB(170, 175, 200),
			Muted  = Color3.fromRGB(105, 110, 140),
		})
	end)

	return gb
end

return ThemeManager
