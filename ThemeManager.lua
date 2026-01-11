--!strict
-- ThemeManager.lua
-- Adds a "Theme" UI into a chosen tab, for END-USERS (players) to edit theme
-- Requires BlueView.lua supports window:SetTheme + AddColorPicker

local ThemeManager = {}

export type SetupOpts = {
	TabName: string?,
	GroupTitle: string?,
	Side: ("Left"|"Right")?,
}

function ThemeManager.Setup(window: any, opts: SetupOpts?)
	opts = opts or {}
	local tabName = opts.TabName or "Settings"
	local groupTitle = opts.GroupTitle or "Theme"
	local side = opts.Side or "Right"

	local tab = window.Tabs and window.Tabs[tabName]
	if not tab then
		tab = window:AddTab(tabName, "lucide:palette")
	end

	local gb = tab:AddGroupbox(groupTitle, {Side = side})
	local t = window:GetTheme()

	gb:AddColorPicker("Accent Color", t.Accent, function(c)
		window:SetTheme({ Accent = c })
	end)

	gb:AddColorPicker("Text Color", t.Text, function(c)
		window:SetTheme({ Text = c })
	end)

	gb:AddColorPicker("SubText Color", t.SubText, function(c)
		window:SetTheme({ SubText = c })
	end)

	gb:AddColorPicker("Muted Color", t.Muted, function(c)
		window:SetTheme({ Muted = c })
	end)

	gb:AddColorPicker("Background Color", t.BG, function(c)
		window:SetTheme({ BG = c })
	end)

	gb:AddColorPicker("Background 2", t.BG2, function(c)
		window:SetTheme({ BG2 = c })
	end)

	gb:AddColorPicker("Panel Color", t.Panel, function(c)
		window:SetTheme({ Panel = c })
	end)

	gb:AddColorPicker("Panel 2", t.Panel2, function(c)
		window:SetTheme({ Panel2 = c })
	end)

	gb:AddColorPicker("Stroke Color", t.Stroke, function(c)
		window:SetTheme({ Stroke = c })
	end)
end

return ThemeManager
