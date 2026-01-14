--!nocheck
-- BlueView.lua (SpareStackUI style) - Updated Full Script
-- Fixes:
-- ✅ Color wheel image rendering (no tint) + brightness slider orientation
-- ✅ Selected tab bar drift fixed under UIScale (scale-correct positioning)
-- ✅ Popups (dropdowns/color pickers) are true overlays (no clipping) + centered under button
-- ✅ Only ONE popup open at a time; switching tabs closes popups automatically
-- ✅ Dropdown buttons no longer shift (popup not parented to row)
-- ✅ Toggle ON-state stays correct after accent/theme changes

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local UILib = {}
UILib.__index = UILib

--////////////////////////////////////////////////////////////
-- Assets (override via UILib.SetAssets)
--////////////////////////////////////////////////////////////
local ASSETS = {
	Glow = "rbxassetid://93208570840427",        -- radial glow png (optional)
	ColorWheel = "rbxassetid://0",              -- ⚠️ set to your color wheel image id (Image/Decal asset)
}

function UILib.SetAssets(t)
	if typeof(t) == "table" then
		if t.Glow then ASSETS.Glow = tostring(t.Glow) end
		if t.ColorWheel then ASSETS.ColorWheel = tostring(t.ColorWheel) end
	end
end

--////////////////////////////////////////////////////////////
-- Utils
--////////////////////////////////////////////////////////////
local function tween(inst, ti, props)
	local tw = TweenService:Create(inst, ti, props)
	tw:Play()
	return tw
end

local function mk(className, props, children)
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			inst[k] = v
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	return inst
end

local function withUICorner(parent, radius)
	return mk("UICorner", {CornerRadius = UDim.new(0, radius), Parent = parent})
end

local function withUIStroke(parent, color, transparency, thickness)
	return mk("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function clamp01(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end

--////////////////////////////////////////////////////////////
-- Radial glow (single subtle)
--////////////////////////////////////////////////////////////
local function addRadialGlowSimple(host, color, pad, alpha)
	local parent = host.Parent
	if not parent or not parent:IsA("GuiObject") then
		return function(_) end
	end

	local layer = mk("Frame", {
		Name = "RadialGlow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = math.max(1, host.ZIndex - 1),
		ClipsDescendants = false,
		Parent = parent,
	})

	local img = mk("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, pad, 1, pad),
		Image = ASSETS.Glow,
		ImageColor3 = color,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = layer.ZIndex,
		Parent = layer,
	})

	local dead = false
	local conns = {}

	local function sync()
		if dead then return end
		if not host.Parent or host.Parent ~= parent then return end
		layer.AnchorPoint = host.AnchorPoint
		layer.Position = host.Position
		layer.Size = host.Size
		layer.Rotation = host.Rotation
		layer.ZIndex = math.max(1, host.ZIndex - 1)
		img.ZIndex = layer.ZIndex
	end

	local function setIntensity(intensity)
		intensity = math.clamp(intensity, 0, 1)
		if not ASSETS.Glow or ASSETS.Glow == "" or ASSETS.Glow == "rbxassetid://0" then
			img.ImageTransparency = 1
			return
		end
		img.ImageTransparency = 1 - ((1 - alpha) * intensity)
	end

	local function destroy()
		if dead then return end
		dead = true
		for _, c in ipairs(conns) do
			pcall(function() c:Disconnect() end)
		end
		pcall(function() layer:Destroy() end)
	end

	table.insert(conns, host:GetPropertyChangedSignal("Position"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("Size"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("AnchorPoint"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("Rotation"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("ZIndex"):Connect(sync))
	table.insert(conns, host.AncestryChanged:Connect(function(_, np)
		if np == nil then destroy() end
	end))

	sync()
	return setIntensity
end

--////////////////////////////////////////////////////////////
-- Icons (Lucide-ready)
--////////////////////////////////////////////////////////////
local function resolveIcon(iconProvider, icon)
	if not icon then return nil end
	if string.find(icon, "rbxassetid://") == 1 then
		return icon
	end
	local prefix = "lucide:"
	if string.find(icon, prefix) == 1 then
		local key = string.sub(icon, #prefix + 1)
		return iconProvider and iconProvider(key) or nil
	end
	return iconProvider and iconProvider(icon) or nil
end

local function makeIcon(imageId, size, transparency)
	return mk("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Image = imageId or "",
		ImageTransparency = transparency or 0,
		ScaleType = Enum.ScaleType.Fit,
	})
end

--////////////////////////////////////////////////////////////
-- Theme
--////////////////////////////////////////////////////////////
local DefaultTheme = {
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

--////////////////////////////////////////////////////////////
-- Metatables
--////////////////////////////////////////////////////////////
local WindowMT = {}
WindowMT.__index = WindowMT

local TabMT = {}
TabMT.__index = TabMT

local GroupMT = {}
GroupMT.__index = GroupMT

--////////////////////////////////////////////////////////////
-- Theme binding
--////////////////////////////////////////////////////////////
local function setProp(inst, prop, value)
	pcall(function() inst[prop] = value end)
end

function WindowMT:_BindTheme(inst, prop, key)
	table.insert(self._themeBindings, {inst = inst, prop = prop, key = key})
end

function WindowMT:_ApplyTheme(newTheme)
	self.Theme = newTheme
	for _, b in ipairs(self._themeBindings) do
		local v = newTheme[b.key]
		if v ~= nil then
			setProp(b.inst, b.prop, v)
		end
	end
end

--////////////////////////////////////////////////////////////
-- UIScale helper
--////////////////////////////////////////////////////////////
local function getScale(self)
	local s = 1
	if self._ui and self._ui.uiScale and self._ui.uiScale.Scale and self._ui.uiScale.Scale > 0 then
		s = self._ui.uiScale.Scale
	end
	return s
end

--////////////////////////////////////////////////////////////
-- Popup manager (single popup at a time)
--////////////////////////////////////////////////////////////
function WindowMT:_ClosePopup()
	if self._activePopup then
		local p = self._activePopup
		self._activePopup = nil
		pcall(function() p.close(true) end)
	end
end

function WindowMT:_OpenPopup(popupObj)
	self:_ClosePopup()
	self._activePopup = popupObj
end

function WindowMT:_MakePopupFrame()
	local theme = self.Theme
	local layer = self._ui.popupLayer
	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 520,
		ClipsDescendants = true,
		Parent = layer,
	})
	withUICorner(panel, 12)
	withUIStroke(panel, theme.Stroke, 0.45, 1)
	self:_BindTheme(panel, "BackgroundColor3", "Panel")
	self:_BindTheme((panel:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")
	return panel
end

--////////////////////////////////////////////////////////////
-- Window
--////////////////////////////////////////////////////////////
function UILib.new(options)
	options = options or {}
	local theme = options.Theme or DefaultTheme
	local iconProvider = options.IconProvider

	local parent = options.Parent
	if not parent then
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		parent = pg or LocalPlayer:WaitForChild("PlayerGui")
	end

	local baseW = options.Width or 980
	local baseH = options.Height or 560

	local gui = mk("ScreenGui", {
		Name = "BlueView",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})

	local root = mk("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(baseW, baseH),
		BackgroundColor3 = theme.BG,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = gui,
	})
	withUICorner(root, 14)
	withUIStroke(root, theme.Stroke, 0.35, 1)

	mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.BG2),
			ColorSequenceKeypoint.new(1, theme.BG),
		}),
		Parent = root,
	})

	mk("UISizeConstraint", {
		MinSize = options.MinSize or Vector2.new(560, 360),
		MaxSize = options.MaxSize or Vector2.new(1400, 900),
		Parent = root,
	})

	local uiScale = mk("UIScale", {Scale = 1, Parent = root})

	-- Topbar
	local topbar = mk("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})
	withUICorner(topbar, 14)
	withUIStroke(topbar, theme.Stroke, 0.25, 1)
	mk("Frame", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -14),
		ZIndex = 10,
		Parent = topbar,
	})

	local titleWrap = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 260, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		ZIndex = 11,
		Parent = topbar,
	})

	local appIcon = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(0, 14),
		BorderSizePixel = 0,
		ZIndex = 12,
		Parent = titleWrap,
	})
	withUICorner(appIcon, 8)
	withUIStroke(appIcon, theme.Stroke, 0.35, 1)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "B",
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextColor3 = theme.Accent,
		ZIndex = 13,
		Parent = appIcon,
	})

	local titleLabel = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(40, 10),
		Size = UDim2.new(1, -40, 1, -20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = options.Title or "BLUE VIEW",
		TextSize = 18,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Text,
		ZIndex = 12,
		Parent = titleWrap,
	})

	local btnWrap = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(94, 36),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		ZIndex = 12,
		Parent = topbar,
	})

	local function makeTopButton(label)
		local b = mk("TextButton", {
			BackgroundColor3 = theme.Panel2,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(40, 36),
			Text = "",
			AutoButtonColor = false,
			ZIndex = 13,
		})
		withUICorner(b, 10)
		withUIStroke(b, theme.Stroke, 0.35, 1)

		local t = mk("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = label,
			TextSize = 18,
			Font = Enum.Font.GothamBold,
			TextColor3 = theme.SubText,
			ZIndex = 14,
			Parent = b,
		})

		b.MouseEnter:Connect(function()
			tween(t, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = theme.Text})
		end)
		b.MouseLeave:Connect(function()
			tween(t, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = theme.SubText})
		end)
		return b
	end

	local minimizeBtn = makeTopButton("–")
	minimizeBtn.Parent = btnWrap
	minimizeBtn.Position = UDim2.fromOffset(0, 0)

	local closeBtn = makeTopButton("×")
	closeBtn.Parent = btnWrap
	closeBtn.Position = UDim2.fromOffset(50, 0)

	-- Content wrap
	local contentWrap = mk("Frame", {
		Name = "ContentWrap",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		ZIndex = 5,
		Parent = root,
	})

	-- Sidebar
	local sidebar = mk("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 190, 1, 0),
		ZIndex = 6,
		Parent = contentWrap,
	})
	withUIStroke(sidebar, theme.Stroke, 0.25, 1)

	mk("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = sidebar,
	})

	local tabList = mk("Frame", {
		Name = "TabList",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 7,
		Parent = sidebar,
	})

	local tabButtons = mk("Frame", {
		Name = "TabButtons",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
		Parent = tabList,
	})

	local tabButtonsLayout = mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = tabButtons,
	})

	local selectedBar = mk("Frame", {
		Name = "SelectedBar",
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 0, 34),
		Position = UDim2.new(0, -6, 0, 0),
		ZIndex = 50,
		Parent = tabList,
	})
	withUICorner(selectedBar, 999)

	-- Main panel
	local mainPanel = mk("Frame", {
		Name = "MainPanel",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 190, 0, 0),
		Size = UDim2.new(1, -190, 1, 0),
		ZIndex = 6,
		Parent = contentWrap,
	})
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = mainPanel,
	})

	-- Search row
	local searchRow = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 7,
		Parent = mainPanel,
	})

	local searchBox = mk("Frame", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 7,
		Parent = searchRow,
	})
	withUICorner(searchBox, 12)
	withUIStroke(searchBox, theme.Stroke, 0.35, 1)
	mk("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = searchBox})

	local searchIconId = resolveIcon(iconProvider, "lucide:search")
	local searchIcon = makeIcon(searchIconId, 18, 0.12)
	searchIcon.ZIndex = 8
	searchIcon.Parent = searchBox
	searchIcon.Position = UDim2.new(0, 0, 0.5, -9)

	local searchInput = mk("TextBox", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 26, 0, 0),
		Size = UDim2.new(1, -26, 1, 0),
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 14,
		TextColor3 = theme.Text,
		PlaceholderText = "Search element",
		PlaceholderColor3 = theme.Muted,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
		Parent = searchBox,
	})

	local tabsContainer = mk("Frame", {
		Name = "TabsContainer",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		ZIndex = 6,
		Parent = mainPanel,
	})

	local canvasBg = mk("Frame", {
		Name = "CanvasBg",
		BackgroundColor3 = theme.BG2,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = tabsContainer,
	})
	withUICorner(canvasBg, 14)
	withUIStroke(canvasBg, theme.Stroke, 0.55, 1)
	mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.BG2),
			ColorSequenceKeypoint.new(1, theme.BG),
		}),
		Parent = canvasBg,
	})

	-- Popup layer (overlay, avoids scrollingframe clipping)
	local popupLayer = mk("Frame", {
		Name = "PopupLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 0),
		ZIndex = 490,
		ClipsDescendants = false,
		Parent = root,
	})

	-- Window state
	local self = setmetatable({}, WindowMT)
	self.Gui = gui
	self.Root = root
	self.Theme = theme
	self.IconProvider = iconProvider

	self.Tabs = {}
	self._tabOrder = {}
	self._layoutCounter = 0
	self.SelectedTab = nil
	self._connections = {}
	self._minimized = false
	self._origSize = root.Size

	self._toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	self._visible = true
	self._themeBindings = {}
	self._categories = {}
	self._activePopup = nil

	self._toggleRefreshers = {}

	self._ui = {
		gui = gui,
		root = root,
		uiScale = uiScale,
		topbar = topbar,
		contentWrap = contentWrap,
		sidebar = sidebar,
		tabList = tabList,
		tabButtons = tabButtons,
		tabButtonsLayout = tabButtonsLayout,
		selectedBar = selectedBar,
		tabsContainer = tabsContainer,
		searchInput = searchInput,
		titleLabel = titleLabel,
		canvasBg = canvasBg,
		searchBox = searchBox,
		searchIcon = searchIcon,
		btnWrap = btnWrap,
		popupLayer = popupLayer,
	}

	-- Theme binds for core
	self:_BindTheme(root, "BackgroundColor3", "BG")
	self:_BindTheme((root:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")
	self:_BindTheme(topbar, "BackgroundColor3", "Panel2")
	self:_BindTheme(sidebar, "BackgroundColor3", "Panel2")
	self:_BindTheme(selectedBar, "BackgroundColor3", "Accent")
	self:_BindTheme(canvasBg, "BackgroundColor3", "BG2")
	self:_BindTheme(searchBox, "BackgroundColor3", "Panel2")
	self:_BindTheme((searchBox:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")
	self:_BindTheme(titleLabel, "TextColor3", "Text")
	self:_BindTheme(searchInput, "TextColor3", "Text")
	self:_BindTheme(searchInput, "PlaceholderColor3", "Muted")

	-- Autoscale
	local autoScale = (options.AutoScale == nil) and true or options.AutoScale
	local minScale = options.MinScale or 0.68
	local maxScale = options.MaxScale or 1.0
	local function updateScale()
		if not autoScale then uiScale.Scale = 1 return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local s = math.min(vp.X / baseW, vp.Y / baseH, 1)
		s = math.clamp(s * 0.94, minScale, maxScale)
		uiScale.Scale = s
		self:_UpdateSelectedBar(true)
	end
	updateScale()
	task.spawn(function()
		while gui.Parent do
			task.wait(0.25)
			updateScale()
		end
	end)

	-- Dragging
	do
		local dragging = false
		local dragStart
		local startPos

		local function overButtons()
			local p = UserInputService:GetMouseLocation()
			local bwPos = btnWrap.AbsolutePosition
			local bwSize = btnWrap.AbsoluteSize
			return p.X >= bwPos.X and p.X <= bwPos.X + bwSize.X and p.Y >= bwPos.Y and p.Y <= bwPos.Y + bwSize.Y
		end

		topbar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if overButtons() then return end
				dragging = true
				dragStart = input.Position
				startPos = root.Position
			end
		end)

		topbar.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)

		table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end))
	end

	-- Click outside closes popup
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if self._activePopup and self._activePopup.frame and self._activePopup.frame.Visible then
				local f = self._activePopup.frame
				local p = UserInputService:GetMouseLocation()
				local ap = f.AbsolutePosition
				local as = f.AbsoluteSize
				local inside = (p.X >= ap.X and p.X <= ap.X + as.X and p.Y >= ap.Y and p.Y <= ap.Y + as.Y)
				if not inside then
					self:_ClosePopup()
				end
			end
		end
	end))

	-- Minimize
	local function applyMinimize(state)
		self._minimized = state
		if state then
			contentWrap.Visible = true
			tween(root, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(root.Size.X.Scale, root.Size.X.Offset, 0, 56)})
			task.delay(0.18, function()
				if self._minimized then contentWrap.Visible = false end
			end)
		else
			contentWrap.Visible = true
			tween(root, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = self._origSize})
		end
	end
	minimizeBtn.MouseButton1Click:Connect(function() applyMinimize(not self._minimized) end)

	-- Close
	closeBtn.MouseButton1Click:Connect(function()
		self:Destroy()
	end)

	-- Toggle key
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == self._toggleKey then self:Toggle() end
	end))

	-- Search filter (groupbox title)
	searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		local tab = self.SelectedTab
		if not tab then return end
		local q = string.lower(searchInput.Text or "")
		if q == "" then
			for _, gb in ipairs(tab._groupboxes) do gb._frame.Visible = true end
			return
		end
		for _, gb in ipairs(tab._groupboxes) do
			local n = string.lower(gb.Title or "")
			gb._frame.Visible = (string.find(n, q, 1, true) ~= nil)
		end
	end)

	-- Update selected bar when layout changes
	tabButtonsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_UpdateSelectedBar(true)
	end)

	return self
end

function WindowMT:SetTheme(newTheme)
	self:_ApplyTheme(newTheme)
	for _, tab in ipairs(self._tabOrder) do
		if self.SelectedTab == tab then
			tab._btnLabel.TextColor3 = self.Theme.Text
			if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.05 end
		else
			tab._btnLabel.TextColor3 = self.Theme.Muted
			if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.45 end
		end
	end
	for _, fn in ipairs(self._toggleRefreshers) do pcall(fn) end
end

function WindowMT:Toggle(state)
	if state == nil then self._visible = not self._visible else self._visible = state end
	self.Gui.Enabled = self._visible
	if not self._visible then
		self:_ClosePopup()
	end
end

function WindowMT:Destroy()
	self:_ClosePopup()
	for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
	if self.Gui then pcall(function() self.Gui:Destroy() end) end
end

--////////////////////////////////////////////////////////////
-- Selected bar (UIScale-correct + no drift)
--////////////////////////////////////////////////////////////
function WindowMT:_UpdateSelectedBar(instant)
	local tab = self.SelectedTab
	if not tab or not tab._btn or not tab._btn.Parent then return end

	local sb = self._ui.selectedBar
	local ref = self._ui.tabList
	if not sb or not ref then return end

	local scale = getScale(self)

	local btnAbsY = tab._btn.AbsolutePosition.Y
	local refAbsY = ref.AbsolutePosition.Y
	local btnH = tab._btn.AbsoluteSize.Y
	local barH = sb.AbsoluteSize.Y
	if barH <= 0 then barH = 34 end

	local y = ((btnAbsY - refAbsY) / scale) + math.floor(((btnH / scale) - barH) / 2)
	local target = UDim2.new(0, -6, 0, y)

	if instant then
		sb.Position = target
	else
		tween(sb, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = target})
	end
end

function WindowMT:_UpdateSelectedBarDeferred(instant)
	task.defer(function()
		RunService.RenderStepped:Wait()
		RunService.RenderStepped:Wait()
		self:_UpdateSelectedBar(instant)
	end)
end

--////////////////////////////////////////////////////////////
-- Sidebar Categories + Tabs
--////////////////////////////////////////////////////////////
function WindowMT:AddCategory(name)
	if self._categories[name] then return end
	self._categories[name] = true

	self._layoutCounter += 1
	local header = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
		TextSize = 12,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = self.Theme.Muted,
		LayoutOrder = self._layoutCounter,
		ZIndex = 8,
		Parent = self._ui.tabButtons,
	})
	self:_BindTheme(header, "TextColor3", "Muted")

	self._layoutCounter += 1
	mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 2),
		LayoutOrder = self._layoutCounter,
		ZIndex = 7,
		Parent = self._ui.tabButtons,
	})
	self:_UpdateSelectedBarDeferred(true)
end

local function makeSidebarTab(theme, iconProvider, name, icon)
	local btn = mk("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40),
		Text = "",
		AutoButtonColor = false,
	})

	local bg = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = btn,
	})
	withUICorner(bg, 10)

	mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = btn})

	local iconId = resolveIcon(iconProvider, icon)
	local iconImg = makeIcon(iconId, 18, 0.45)
	iconImg.ZIndex = 3
	iconImg.Parent = btn
	iconImg.Position = UDim2.new(0, 10, 0.5, -9)

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 36, 0, 0),
		Size = UDim2.new(1, -36, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
		TextSize = 14,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Muted,
		ZIndex = 3,
		Parent = btn,
	})

	return btn, bg, label, iconImg
end

function WindowMT:AddTab(name, icon, category)
	if category and category ~= "" then
		self:AddCategory(category)
	end

	local theme = self.Theme
	local btn, bg, label, iconImg = makeSidebarTab(theme, self.IconProvider, name, icon)

	self._layoutCounter += 1
	btn.LayoutOrder = self._layoutCounter
	btn.Parent = self._ui.tabButtons

	local page = mk("Frame", {
		Name = "Tab_" .. name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
		Parent = self._ui.tabsContainer,
	})

	local colLeft = mk("ScrollingFrame", {
		Name = "Left",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0.5, -7, 1, 0),
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		ZIndex = 8,
		Parent = page,
	})
	mk("UIPadding", {PaddingTop=UDim.new(0,10),PaddingBottom=UDim.new(0,10),PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),Parent=colLeft})
	mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,10),Parent=colLeft})

	local colRight = mk("ScrollingFrame", {
		Name = "Right",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 7, 0, 0),
		Size = UDim2.new(0.5, -7, 1, 0),
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		ZIndex = 8,
		Parent = page,
	})
	mk("UIPadding", {PaddingTop=UDim.new(0,10),PaddingBottom=UDim.new(0,10),PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),Parent=colRight})
	mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,10),Parent=colRight})

	local tab = setmetatable({}, TabMT)
	tab.Name = name
	tab._window = self
	tab._btn = btn
	tab._btnBg = bg
	tab._btnLabel = label
	tab._btnIcon = iconImg
	tab._page = page
	tab.Left = colLeft
	tab.Right = colRight
	tab._groupboxes = {}

	self.Tabs[name] = tab
	table.insert(self._tabOrder, tab)

	self:_BindTheme(label, "TextColor3", "Muted")
	self:_BindTheme(bg, "BackgroundColor3", "Panel")

	btn.MouseButton1Click:Connect(function()
		self:SelectTab(name, false)
	end)

	btn.MouseEnter:Connect(function()
		if self.SelectedTab ~= tab then
			tween(bg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.55})
			tween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = theme.Text})
			if iconImg then iconImg.ImageTransparency = 0.25 end
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.SelectedTab ~= tab then
			tween(bg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
			tween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = theme.Muted})
			if iconImg then iconImg.ImageTransparency = 0.45 end
		end
	end)

	if not self.SelectedTab then
		task.defer(function()
			self:SelectTab(name, true)
			self:_UpdateSelectedBarDeferred(true)
		end)
	end

	return tab
end

function WindowMT:SelectTab(name, instant)
	local tab = self.Tabs[name]
	if not tab then return end

	self:_ClosePopup()

	for _, t in ipairs(self._tabOrder) do
		t._page.Visible = false
		if instant then
			t._btnBg.BackgroundTransparency = 1
			t._btnLabel.TextColor3 = self.Theme.Muted
			if t._btnIcon then t._btnIcon.ImageTransparency = 0.45 end
		else
			tween(t._btnBg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
			tween(t._btnLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.Muted})
			if t._btnIcon then t._btnIcon.ImageTransparency = 0.45 end
		end
	end

	tab._page.Visible = true
	self.SelectedTab = tab

	if instant then
		tab._btnBg.BackgroundTransparency = 0.40
		tab._btnLabel.TextColor3 = self.Theme.Text
		if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.05 end
	else
		tween(tab._btnBg, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.40})
		tween(tab._btnLabel, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.Text})
		if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.05 end
	end

	self:_UpdateSelectedBarDeferred(instant == true)
end

--////////////////////////////////////////////////////////////
-- Groupbox
--////////////////////////////////////////////////////////////
local function makeGroupbox(theme, iconProvider, title)
	local frame = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 60),
		ClipsDescendants = true,
	})
	withUICorner(frame, 12)
	withUIStroke(frame, theme.Stroke, 0.35, 1)

	local inner = mk("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame})
	local PAD = 10
	mk("UIPadding", {PaddingTop=UDim.new(0,PAD),PaddingBottom=UDim.new(0,PAD),PaddingLeft=UDim.new(0,PAD),PaddingRight=UDim.new(0,PAD),Parent=inner})

	local header = mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Parent = inner})

	local titleLabel = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -34, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		TextSize = 14,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Text,
		Parent = header,
	})

	local collapseBtn = mk("ImageButton", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		AutoButtonColor = false,
		Parent = header,
	})

	local chevronDown = resolveIcon(iconProvider, "lucide:chevron-down")
	local chevronRight = resolveIcon(iconProvider, "lucide:chevron-right")

	local icon = mk("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = chevronDown or "",
		ImageTransparency = 0.15,
		Parent = collapseBtn,
	})

	local fallback = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = chevronDown and "" or "v",
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextColor3 = theme.SubText,
		Visible = (chevronDown == nil),
		Parent = collapseBtn,
	})

	local GAP = 8
	local contentMask = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 26 + GAP),
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		Parent = inner,
	})

	local content = mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), Parent = contentMask})
	local list = mk("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = content})
	mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 999999, Parent = content})

	return frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP, titleLabel
end

function TabMT:AddGroupbox(title, opts)
	opts = opts or {}
	local side = opts.Side or "Left"

	local window = self._window
	local theme = window.Theme
	local frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP, titleLabel =
		makeGroupbox(theme, window.IconProvider, title)

	frame.Parent = (side == "Right") and self.Right or self.Left
	frame.LayoutOrder = #self._groupboxes + 1

	local gb = setmetatable({}, GroupMT)
	gb.Title = title
	gb._tab = self
	gb._frame = frame
	gb._mask = contentMask
	gb._content = content
	gb._list = list
	gb._collapsed = false

	window:_BindTheme(frame, "BackgroundColor3", "Panel")
	window:_BindTheme((frame:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")
	window:_BindTheme(titleLabel, "TextColor3", "Text")

	table.insert(self._groupboxes, gb)

	local HEADER_H = 26
	local function setIconCollapsed(state)
		if chevronDown then
			icon.Image = state and (chevronRight or chevronDown) or chevronDown
		else
			fallback.Text = state and ">" or "v"
		end
	end

	local function applyHeight(instant)
		local h = list.AbsoluteContentSize.Y
		local contentH = gb._collapsed and 0 or (h + 2)
		local target = (PAD * 2) + HEADER_H + GAP + contentH

		if instant then
			gb._mask.Size = UDim2.new(1, 0, 0, contentH)
			gb._content.Size = UDim2.new(1, 0, 0, contentH)
			gb._frame.Size = UDim2.new(1, 0, 0, target)
		else
			tween(gb._mask, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, contentH)})
			tween(gb._content, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, contentH)})
			tween(gb._frame, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, target)})
		end
	end

	list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if not gb._collapsed then applyHeight(false) end
	end)

	collapseBtn.MouseButton1Click:Connect(function()
		gb._collapsed = not gb._collapsed
		setIconCollapsed(gb._collapsed)
		applyHeight(false)
	end)

	gb._collapsed = opts.InitialCollapsed == true
	setIconCollapsed(gb._collapsed)
	applyHeight(true)

	return gb
end

--////////////////////////////////////////////////////////////
-- Controls helpers
--////////////////////////////////////////////////////////////
local function makeRow(height)
	return mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height)})
end

--////////////////////////////////////////////////////////////
-- Toggle
--////////////////////////////////////////////////////////////
function GroupMT:AddToggle(text, default, callback)
	local window = self._tab._window
	local theme = window.Theme
	local on = default == true

	local row = makeRow(40)
	row.Parent = self._content

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -90, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})
	window:_BindTheme(label, "TextColor3", "Text")

	local btn = mk("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(56, 28),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})

	local track = mk("Frame", {
		BackgroundColor3 = on and theme.Accent or theme.Stroke,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = btn,
	})
	withUICorner(track, 999)

	local setGlow = addRadialGlowSimple(track, theme.Accent, 18, 0.86)
	setGlow(on and 1 or 0)

	local knob = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(20, 20),
		Position = on and UDim2.new(1, -24, 0.5, -10) or UDim2.new(0, 4, 0.5, -10),
		ZIndex = 21,
		Parent = track,
	})
	withUICorner(knob, 999)

	local function refreshTheme()
		local t = window.Theme
		track.BackgroundColor3 = on and t.Accent or t.Stroke
		setGlow(on and 1 or 0)
	end
	table.insert(window._toggleRefreshers, refreshTheme)

	local function set(state, fire)
		on = state
		refreshTheme()
		tween(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -24, 0.5, -10) or UDim2.new(0, 4, 0.5, -10),
		})
		if fire ~= false and callback then task.spawn(callback, on) end
	end

	btn.MouseButton1Click:Connect(function() set(not on, true) end)

	return {Set = function(v) set(v == true, true) end, Get = function() return on end}
end

--////////////////////////////////////////////////////////////
-- Button
--////////////////////////////////////////////////////////////
function GroupMT:AddButton(text, callback)
	local window = self._tab._window
	local theme = window.Theme

	local row = makeRow(40)
	row.Parent = self._content

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Text = text,
		TextSize = 14,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Text,
		AutoButtonColor = false,
		ZIndex = 20,
		Parent = row,
	})
	withUICorner(btn, 12)
	withUIStroke(btn, theme.Stroke, 0.35, 1)

	window:_BindTheme(btn, "BackgroundColor3", "Panel2")
	window:_BindTheme(btn, "TextColor3", "Text")
	window:_BindTheme((btn:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

	btn.MouseEnter:Connect(function()
		tween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = window.Theme.Panel})
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = window.Theme.Panel2})
	end)
	btn.MouseButton1Click:Connect(function()
		if callback then task.spawn(callback) end
	end)

	return btn
end

--////////////////////////////////////////////////////////////
-- Dropdown popup builder (overlay)
--////////////////////////////////////////////////////////////
local function buildDropdownPopup(window, anchorBtn, items, onPick, multi, chosenMap)
	local theme = window.Theme
	local panel = window:_MakePopupFrame()
	panel.Visible = true

	-- search
	local search = mk("TextBox", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 34),
		Text = "",
		PlaceholderText = "Search...",
		PlaceholderColor3 = theme.Muted,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})
	withUICorner(search, 10)
	withUIStroke(search, theme.Stroke, 0.5, 1)
	window:_BindTheme(search, "BackgroundColor3", "Panel2")
	window:_BindTheme(search, "TextColor3", "Text")
	window:_BindTheme(search, "PlaceholderColor3", "Muted")
	window:_BindTheme((search:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

	-- list
	local listFrame = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.2,
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})
	mk("UIPadding", {PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,10),Parent=listFrame})
	local layout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=listFrame})

	local function rebuild(filter)
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
		end
		local q = string.lower(filter or "")
		for _, it in ipairs(items) do
			if q == "" or string.find(string.lower(it), q, 1, true) then
				if multi then
					local itemRow = mk("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 30),
						ZIndex = panel.ZIndex + 2,
						Parent = listFrame,
					})
					local box = mk("Frame", {
						BackgroundColor3 = theme.Panel2,
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(18, 18),
						Position = UDim2.fromOffset(6, 6),
						ZIndex = panel.ZIndex + 3,
						Parent = itemRow,
					})
					withUICorner(box, 6)
					withUIStroke(box, theme.Stroke, 0.55, 1)
					window:_BindTheme(box, "BackgroundColor3", "Panel2")
					window:_BindTheme((box:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

					local check = mk("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Text = (chosenMap[it] and "✓") or "",
						TextSize = 14,
						Font = Enum.Font.GothamBold,
						TextColor3 = theme.Accent,
						ZIndex = panel.ZIndex + 4,
						Parent = box,
					})
					window:_BindTheme(check, "TextColor3", "Accent")

					local label = mk("TextButton", {
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 30, 0, 0),
						Size = UDim2.new(1, -30, 1, 0),
						Text = it,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = 13,
						Font = Enum.Font.Gotham,
						TextColor3 = theme.Text,
						AutoButtonColor = false,
						ZIndex = panel.ZIndex + 3,
						Parent = itemRow,
					})
					window:_BindTheme(label, "TextColor3", "Text")

					local function toggleIt()
						chosenMap[it] = not chosenMap[it]
						check.Text = chosenMap[it] and "✓" or ""
						onPick()
					end
					label.MouseButton1Click:Connect(toggleIt)
					box.InputBegan:Connect(function(inp)
						if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
							toggleIt()
						end
					end)
				else
					local itemBtn = mk("TextButton", {
						BackgroundColor3 = theme.Panel2,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 30),
						Text = it,
						TextSize = 13,
						Font = Enum.Font.Gotham,
						TextColor3 = theme.Text,
						AutoButtonColor = false,
						ZIndex = panel.ZIndex + 2,
						Parent = listFrame,
					})
					withUICorner(itemBtn, 10)
					withUIStroke(itemBtn, theme.Stroke, 0.65, 1)
					window:_BindTheme(itemBtn, "BackgroundColor3", "Panel2")
					window:_BindTheme(itemBtn, "TextColor3", "Text")
					window:_BindTheme((itemBtn:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

					itemBtn.MouseButton1Click:Connect(function()
						onPick(it)
						window:_ClosePopup()
					end)
				end
			end
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		rebuild(search.Text)
	end)

	-- Position + size
	local function positionAndSize()
		local scale = getScale(window)
		local btnAbs = anchorBtn.AbsolutePosition
		local btnSize = anchorBtn.AbsoluteSize
		local rootAbs = window.Root.AbsolutePosition

		local x = (btnAbs.X - rootAbs.X) / scale
		local y = (btnAbs.Y - rootAbs.Y) / scale + (btnSize.Y / scale) + 6

		local w = (btnSize.X / scale)
		local maxH = 240
		local contentH = 52 + layout.AbsoluteContentSize.Y + 16
		local h = math.min(maxH, contentH)

		panel.Position = UDim2.new(0, x, 0, y)
		panel.Size = UDim2.new(0, w, 0, h)
	end

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(positionAndSize)

	rebuild("")
	positionAndSize()

	local function close(instant)
		if instant then
			panel.Visible = false
			panel:Destroy()
		else
			tween(panel, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, 0)})
			task.delay(0.15, function()
				if panel and panel.Parent then panel:Destroy() end
			end)
		end
	end

	return {frame = panel, close = close, reposition = positionAndSize}
end

function GroupMT:AddDropdown(text, items, default, callback)
	local window = self._tab._window
	local theme = window.Theme
	local selected = default or (items[1] or "")

	local row = makeRow(44)
	row.Parent = self._content

	local title = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.SubText,
		Parent = row,
	})
	window:_BindTheme(title, "TextColor3", "SubText")

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, -10, 0, 22), -- slightly less wide
		Text = selected,
		TextSize = 13,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Text,
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(btn, 10)
	withUIStroke(btn, theme.Stroke, 0.5, 1)
	window:_BindTheme(btn, "BackgroundColor3", "Panel2")
	window:_BindTheme(btn, "TextColor3", "Text")
	window:_BindTheme((btn:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

	btn.MouseButton1Click:Connect(function()
		local popup = buildDropdownPopup(window, btn, items, function(pick)
			selected = pick
			btn.Text = pick
			if callback then task.spawn(callback, pick) end
		end, false)
		window:_OpenPopup(popup)
	end)

	return {
		Get = function() return selected end,
		Set = function(v)
			selected = tostring(v)
			btn.Text = selected
			if callback then task.spawn(callback, selected) end
		end
	}
end

function GroupMT:AddMultiDropdown(text, items, default, callback)
	local window = self._tab._window
	local theme = window.Theme

	local chosen = {}
	if typeof(default) == "table" then
		for _, v in ipairs(default) do chosen[tostring(v)] = true end
	end

	local function currentList()
		local out = {}
		for _, it in ipairs(items) do
			if chosen[it] then table.insert(out, it) end
		end
		return out
	end

	local row = makeRow(44)
	row.Parent = self._content

	local title = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.SubText,
		Parent = row,
	})
	window:_BindTheme(title, "TextColor3", "SubText")

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, -10, 0, 22),
		Text = "Select...",
		TextSize = 13,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Text,
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(btn, 10)
	withUIStroke(btn, theme.Stroke, 0.5, 1)
	window:_BindTheme(btn, "BackgroundColor3", "Panel2")
	window:_BindTheme(btn, "TextColor3", "Text")
	window:_BindTheme((btn:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

	local function refreshBtnText()
		local list = currentList()
		if #list == 0 then
			btn.Text = "Select..."
		elseif #list <= 2 then
			btn.Text = table.concat(list, ", ")
		else
			btn.Text = tostring(#list) .. " selected"
		end
	end
	refreshBtnText()

	btn.MouseButton1Click:Connect(function()
		local popup
		popup = buildDropdownPopup(window, btn, items, function()
			refreshBtnText()
			if callback then task.spawn(callback, currentList()) end
			if popup and popup.reposition then popup.reposition() end
		end, true, chosen)
		window:_OpenPopup(popup)
	end)

	return {
		Get = function() return currentList() end,
		Set = function(list)
			chosen = {}
			for _, s in ipairs(list or {}) do chosen[tostring(s)] = true end
			refreshBtnText()
			if callback then task.spawn(callback, currentList()) end
		end
	}
end

--////////////////////////////////////////////////////////////
-- Color Wheel Picker (overlay, wheel image + brightness slider)
--////////////////////////////////////////////////////////////
local function hsvToColor(h,s,v) return Color3.fromHSV(h,s,v) end
local function colorToHSV(c) return c:ToHSV() end

local function buildColorWheelPopup(window, anchorBtn, startColor, onChanged)
	local theme = window.Theme
	local panel = window:_MakePopupFrame()
	panel.Visible = true
	panel.ZIndex = 560
	panel.ClipsDescendants = true

	local WHEEL_SIZE = 140
	local PAD = 10
	local BR_H = 16

	-- Wheel image
	local wheel = mk("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ASSETS.ColorWheel,
		ImageColor3 = Color3.new(1,1,1), -- IMPORTANT: do not tint
		ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE),
		Position = UDim2.fromOffset(PAD, PAD),
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})

	-- Fallback label if not set
	local wheelWarn = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = wheel.Size,
		Position = wheel.Position,
		Text = (ASSETS.ColorWheel == "rbxassetid://0" or ASSETS.ColorWheel == "" or not ASSETS.ColorWheel) and "Set ASSETS.ColorWheel" or "",
		TextSize = 14,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Muted,
		ZIndex = panel.ZIndex + 2,
		Parent = panel,
	})

	-- Preview
	local preview = mk("Frame", {
		BackgroundColor3 = startColor,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(PAD + WHEEL_SIZE + 10, PAD),
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})
	withUICorner(preview, 12)
	withUIStroke(preview, theme.Stroke, 0.45, 1)
	window:_BindTheme((preview:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

	-- Brightness bar (horizontal)
	local br = mk("Frame", {
		BackgroundColor3 = Color3.new(1,1,1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -(PAD*2), 0, BR_H),
		Position = UDim2.fromOffset(PAD, PAD + WHEEL_SIZE + 10),
		ZIndex = panel.ZIndex + 1,
		Parent = panel,
	})
	withUICorner(br, 10)
	withUIStroke(br, theme.Stroke, 0.55, 1)
	window:_BindTheme((br:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

	local brGrad = mk("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(1,1,1)),
		Parent = br,
	})

	local brCursor = mk("Frame", {
		BackgroundColor3 = Color3.new(1,1,1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, BR_H + 6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		ZIndex = panel.ZIndex + 2,
		Parent = br,
	})
	withUICorner(brCursor, 6)
	withUIStroke(brCursor, Color3.new(0,0,0), 0.35, 1)

	local function setBrightnessCursor(v)
		brCursor.Position = UDim2.new(v, 0, 0.5, 0)
	end

	-- Current HSV
	local h,s,v = colorToHSV(startColor)

	local function apply(fire)
		local c = hsvToColor(h,s,v)
		preview.BackgroundColor3 = c
		brGrad.Color = ColorSequence.new(Color3.new(0,0,0), hsvToColor(h,s,1))
		setBrightnessCursor(v)
		if fire and onChanged then onChanged(c) end
	end
	apply(false)

	-- Wheel interaction (polar)
	local draggingWheel = false
	local function setFromWheel(px, py)
		local p = wheel.AbsolutePosition
		local sz = wheel.AbsoluteSize
		local cx = p.X + sz.X/2
		local cy = p.Y + sz.Y/2
		local dx = px - cx
		local dy = py - cy
		local r = math.sqrt(dx*dx + dy*dy)
		local maxR = math.min(sz.X, sz.Y) / 2
		local nr = math.clamp(r / maxR, 0, 1)

		local ang = math.atan2(dy, dx) -- [-pi,pi]
		local hue = (ang / (2*math.pi)) + 0.5
		h = (hue % 1)
		s = nr
		apply(true)
	end

	wheel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingWheel = true
			setFromWheel(input.Position.X, input.Position.Y)
		end
	end)
	wheel.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingWheel = false
		end
	end)

	-- Brightness interaction
	local draggingBr = false
	local function setFromBrightness(px)
		local p = br.AbsolutePosition
		local sz = br.AbsoluteSize
		local a = clamp01((px - p.X) / sz.X)
		v = a
		apply(true)
	end

	br.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingBr = true
			setFromBrightness(input.Position.X)
		end
	end)
	br.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingBr = false
		end
	end)

	local moveConn = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			if draggingWheel then setFromWheel(input.Position.X, input.Position.Y) end
			if draggingBr then setFromBrightness(input.Position.X) end
		end
	end)

	-- Position + size
	local function positionAndSize()
		local scale = getScale(window)
		local btnAbs = anchorBtn.AbsolutePosition
		local btnSize = anchorBtn.AbsoluteSize
		local rootAbs = window.Root.AbsolutePosition

		local x = (btnAbs.X - rootAbs.X) / scale
		local y = (btnAbs.Y - rootAbs.Y) / scale + (btnSize.Y / scale) + 6

		local w = (WHEEL_SIZE + 44 + 10 + PAD*2)
		local hgt = (PAD + WHEEL_SIZE + 10 + BR_H + PAD)

		panel.Position = UDim2.new(0, x, 0, y)
		panel.Size = UDim2.new(0, w, 0, hgt)
	end
	positionAndSize()

	local function close(instant)
		if moveConn then pcall(function() moveConn:Disconnect() end) end
		if instant then
			panel.Visible = false
			panel:Destroy()
		else
			tween(panel, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, 0)})
			task.delay(0.15, function()
				if panel and panel.Parent then panel:Destroy() end
			end)
		end
	end

	return {frame = panel, close = close, reposition = positionAndSize}
end

function GroupMT:AddColorPicker(text, defaultColor, callback)
	local window = self._tab._window
	local theme = window.Theme
	local current = defaultColor or theme.Accent

	local row = makeRow(44)
	row.Parent = self._content

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -44, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})
	window:_BindTheme(label, "TextColor3", "Text")

	local swatchBtn = mk("TextButton", {
		BackgroundColor3 = current,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(34, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(swatchBtn, 10)
	withUIStroke(swatchBtn, theme.Stroke, 0.45, 1)
	window:_BindTheme((swatchBtn:FindFirstChildOfClass("UIStroke")), "Color", "Stroke")

	local function setColor(c, fire)
		current = c
		swatchBtn.BackgroundColor3 = c
		if fire and callback then task.spawn(callback, c) end
	end

	swatchBtn.MouseButton1Click:Connect(function()
		local popup = buildColorWheelPopup(window, swatchBtn, current, function(c)
			setColor(c, true)
		end)
		window:_OpenPopup(popup)
	end)

	return {
		Get = function() return current end,
		Set = function(c) setColor(c, true) end
	}
end

return UILib
