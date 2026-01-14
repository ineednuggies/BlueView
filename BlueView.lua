--!strict
-- BlueView.lua (All features, No ConfigManager)
-- Features:
-- ✅ Categories in sidebar (headers)
-- ✅ Active tab bright, inactive tab muted
-- ✅ Selected tab bar stable (no drift, supports scrolling + categories)
-- ✅ Dragging does not snap back
-- ✅ Search textbox starts empty
-- ✅ Dropdowns + multi-dropdown: single popup at a time, closes on tab switch
-- ✅ Dropdown popup anchored under the clicked button, centered
-- ✅ Multi-dropdown uses checkbox checkmarks (no Done button)
-- ✅ ColorPicker remade: color wheel + value/brightness bar (correct orientation)
-- ✅ Theme bindings: Text/SubText/Muted apply everywhere (toggles keep state on theme change)
-- ✅ Lucide-ready icons via IconProvider or global Lucide module (latte-soft/lucide-roblox compatible)

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local UILib = {}
UILib.__index = UILib

--////////////////////////////////////////////////////////////
-- Utils
--////////////////////////////////////////////////////////////
local function tween(inst: Instance, ti: TweenInfo, props: {[string]: any})
	local t = TweenService:Create(inst, ti, props)
	t:Play()
	return t
end

local function mk(className: string, props: {[string]: any}?, children: {Instance}?)
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	return inst
end

local function withUICorner(parent: Instance, radius: number)
	return mk("UICorner", {CornerRadius = UDim.new(0, radius), Parent = parent})
end

local function withUIStroke(parent: Instance, color: Color3, transparency: number, thickness: number)
	return mk("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function clamp01(x: number): number
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end

local function safeDisconnect(c: RBXScriptConnection?)
	if c then pcall(function() c:Disconnect() end) end
end

--////////////////////////////////////////////////////////////
-- Icons (Lucide-ready)
--////////////////////////////////////////////////////////////
export type IconProvider = (name: string) -> string?

local function tryGlobalLucide(): any
	-- latte-soft/lucide-roblox returns a table with icons or a getIcon function depending on build.
	local g = (getgenv and getgenv()) or (_G :: any)
	if type(g) == "table" then
		return g.Lucide or g.lucide or g.LUCIDE
	end
	return nil
end

local function resolveIcon(iconProvider: IconProvider?, icon: string?): string?
	if not icon or icon == "" then return nil end
	if string.find(icon, "rbxassetid://") == 1 then
		return icon
	end
	local prefix = "lucide:"
	if string.find(icon, prefix) == 1 then
		local key = string.sub(icon, #prefix + 1)
		if iconProvider then
			return iconProvider(key)
		end
		local L = tryGlobalLucide()
		if L then
			if type(L.getIcon) == "function" then
				local ok, res = pcall(L.getIcon, key)
				if ok and type(res) == "string" then return res end
			end
			if type(L.icons) == "table" and type(L.icons[key]) == "string" then
				return L.icons[key]
			end
			if type(L[key]) == "string" then
				return L[key]
			end
		end
		return nil
	end
	-- plain name: try provider or global lucide table
	if iconProvider then
		local res = iconProvider(icon)
		if res then return res end
	end
	local L = tryGlobalLucide()
	if L and type(L.icons) == "table" and type(L.icons[icon]) == "string" then
		return L.icons[icon]
	end
	return nil
end

local function makeIcon(imageId: string?, size: number, transparency: number?)
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

local DefaultTheme: Theme = {
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
-- Types
--////////////////////////////////////////////////////////////
export type WindowOptions = {
	Title: string?,
	Width: number?,
	Height: number?,
	Parent: Instance?,
	ToggleKey: Enum.KeyCode?,
	Theme: Theme?,
	IconProvider: IconProvider?,
	KillOnClose: boolean?,
	OnKill: (() -> ())?,

	AutoScale: boolean?,
	MinScale: number?,
	MaxScale: number?,
	MinSize: Vector2?,
	MaxSize: Vector2?,
}

export type Window = {
	Gui: ScreenGui,
	Root: Frame,
	IsKilled: boolean,

	Destroy: (self: Window) -> (),
	Toggle: (self: Window, state: boolean?) -> (),
	SetToggleKey: (self: Window, key: Enum.KeyCode) -> (),
	SetTheme: (self: Window, theme: Theme) -> (),
	GetTheme: (self: Window) -> Theme,

	AddCategory: (self: Window, name: string) -> (),
	AddTab: (self: Window, name: string, icon: string?, category: string?) -> any,
	SelectTab: (self: Window, name: string, instant: boolean?) -> (),
}

local WindowMT = {}
WindowMT.__index = WindowMT

local TabMT = {}
TabMT.__index = TabMT

local GroupMT = {}
GroupMT.__index = GroupMT

type ThemeBinding = { inst: Instance, prop: string, key: string }

--////////////////////////////////////////////////////////////
-- Popup Manager (single popup at a time)
--////////////////////////////////////////////////////////////
type PopupHandle = {
	kind: string,
	root: GuiObject,
	close: () -> (),
}

--////////////////////////////////////////////////////////////
-- Window
--////////////////////////////////////////////////////////////
function UILib.new(options: WindowOptions): Window
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
		ClipsDescendants = false, -- important for popup layer
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

	local sizeConstraint = mk("UISizeConstraint", {
		MinSize = options.MinSize or Vector2.new(560, 360),
		MaxSize = options.MaxSize or Vector2.new(1400, 900),
		Parent = root,
	}) :: UISizeConstraint

	-- Autoscale (does NOT re-center after dragging)
	local autoScale = if options.AutoScale == nil then true else options.AutoScale
	local uiScale = mk("UIScale", {Scale = 1, Parent = root})
	local minScale = options.MinScale or 0.68
	local maxScale = options.MaxScale or 1.0

	local function updateScale()
		if not autoScale then uiScale.Scale = 1; return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local s = math.min(vp.X / baseW, vp.Y / baseH, 1)
		s = math.clamp(s * 0.94, minScale, maxScale)
		uiScale.Scale = s
	end
	updateScale()

	local scalerConn: RBXScriptConnection? = nil
	scalerConn = RunService.Heartbeat:Connect(function()
		if not gui.Parent then safeDisconnect(scalerConn); return end
		updateScale()
	end)

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
	-- straighten bottom corners
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
		Size = UDim2.new(0, 360, 1, 0),
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

	local function makeTopButton(label: string)
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

	-- Sidebar (scrolling)
	local sidebar = mk("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 200, 1, 0),
		ZIndex = 6,
		Parent = contentWrap,
	})
	withUIStroke(sidebar, theme.Stroke, 0.25, 1)

	local sidebarScroll = mk("ScrollingFrame", {
		Name = "SidebarScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.35,
		ZIndex = 7,
		Parent = sidebar,
	})
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = sidebarScroll,
	})

	local tabButtons = mk("Frame", {
		Name = "TabButtons",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
		Parent = sidebarScroll,
	})

	local tabLayout = mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = tabButtons,
	})

	-- Selected bar (must be inside scrolling content)
	local selectedBar = mk("Frame", {
		Name = "SelectedBar",
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 0, 34),
		Position = UDim2.new(0, -6, 0, 0),
		ZIndex = 50,
		Parent = sidebarScroll,
	})
	withUICorner(selectedBar, 999)

	-- Main panel
	local mainPanel = mk("Frame", {
		Name = "MainPanel",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 200, 0, 0),
		Size = UDim2.new(1, -200, 1, 0),
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
		Text = "", -- starts empty
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

	-- Popup layer (one place to render dropdowns + color pickers)
	local popupLayer = mk("Frame", {
		Name = "PopupLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1000,
		ClipsDescendants = false,
		Parent = root,
	})

	-- Window state
	local self: any = setmetatable({}, WindowMT)
	self.Gui = gui
	self.Root = root
	self.Theme = theme
	self.IconProvider = iconProvider
	self.IsKilled = false

	self.Tabs = {}
	self._tabOrder = {}
	self._layoutCounter = 0
	self.SelectedTab = nil
	self._connections = {}
	self._minimized = false
	self._origSize = root.Size
	self._toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	self._visible = true

	self._themeBindings = {} :: {ThemeBinding}
	self._categories = {} :: {[string]: boolean}
	self._popupLayer = popupLayer :: Frame
	self._activePopup = nil :: PopupHandle?

	-- theme bind helpers
	function self:_BindTheme(inst: Instance, prop: string, key: string)
		table.insert(self._themeBindings, {inst = inst, prop = prop, key = key})
	end
	function self:_ApplyTheme(newTheme: Theme)
		self.Theme = newTheme
		for _, b in ipairs(self._themeBindings) do
			local v = (newTheme :: any)[b.key]
			if v ~= nil then
				pcall(function() (b.inst :: any)[b.prop] = v end)
			end
		end
		-- refresh tab visuals (keep selected)
		for _, tab in ipairs(self._tabOrder) do
			if self.SelectedTab == tab then
				tab._btnBg.BackgroundTransparency = 0.40
				tab._btnLabel.TextColor3 = self.Theme.Text
				if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.05 end
			else
				tab._btnBg.BackgroundTransparency = 1
				tab._btnLabel.TextColor3 = self.Theme.Muted
				if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.45 end
			end
		end
		-- ensure toggles that are ON keep accent color
		for _, tab in ipairs(self._tabOrder) do
			for _, gb in ipairs(tab._groupboxes) do
				for _, updater in ipairs(gb._themeUpdaters) do
					pcall(updater)
				end
			end
		end
		-- update selected bar color
		selectedBar.BackgroundColor3 = self.Theme.Accent
	end

	-- Popup API
	function self:_ClosePopup()
		local p = self._activePopup
		if p then
			self._activePopup = nil
			pcall(p.close)
		end
	end

	function self:_OpenPopup(kind: string, popupRoot: GuiObject, closeFn: () -> ())
		-- close any other popup first
		self:_ClosePopup()
		self._activePopup = {kind = kind, root = popupRoot, close = closeFn}
	end

	-- Selected bar updater (stable, supports scrolling)
	self._barToken = 0
	function self:_UpdateSelectedBar(instant: boolean?)
		local tab = self.SelectedTab
		if not tab or not tab._btn then return end

		local sb: Frame = selectedBar
		local scroll: ScrollingFrame = sidebarScroll
		local barH = sb.AbsoluteSize.Y > 0 and sb.AbsoluteSize.Y or 34

		-- y within scroll canvas:
		local btnAbsY = tab._btn.AbsolutePosition.Y
		local scrollAbsY = scroll.AbsolutePosition.Y
		local canvasY = scroll.CanvasPosition.Y
		local btnH = tab._btn.AbsoluteSize.Y

		local y = (btnAbsY - scrollAbsY) + canvasY + math.floor((btnH - barH) / 2)

		if instant then
			sb.Position = UDim2.new(0, -6, 0, y)
		else
			tween(sb, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, -6, 0, y),
			})
		end
	end

	function self:_UpdateSelectedBarDeferred(instant: boolean?)
		self._barToken += 1
		local token = self._barToken
		task.spawn(function()
			RunService.RenderStepped:Wait()
			RunService.RenderStepped:Wait()
			if token ~= self._barToken then return end
			self:_UpdateSelectedBar(instant)
		end)
	end

	-- Update bar when sidebar scroll moves
	table.insert(self._connections, sidebarScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_UpdateSelectedBar(true)
	end))

	-- Theme binds core
	self:_BindTheme(root, "BackgroundColor3", "BG")
	self:_BindTheme((root:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
	self:_BindTheme(topbar, "BackgroundColor3", "Panel2")
	self:_BindTheme(sidebar, "BackgroundColor3", "Panel2")
	self:_BindTheme(selectedBar, "BackgroundColor3", "Accent")
	self:_BindTheme(canvasBg, "BackgroundColor3", "BG2")
	self:_BindTheme(searchBox, "BackgroundColor3", "Panel2")
	self:_BindTheme((searchBox:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
	self:_BindTheme(titleLabel, "TextColor3", "Text")
	self:_BindTheme(searchInput, "TextColor3", "Text")
	self:_BindTheme(searchInput, "PlaceholderColor3", "Muted")

	-- Dragging (topbar)
	do
		local dragging = false
		local dragStart: Vector2? = nil
		local startPos: UDim2? = nil

		local function overButtons(): boolean
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
				if dragStart and startPos then
					local delta = input.Position - dragStart
					root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
				end
			end
		end))
	end

	-- Minimize
	local function applyMinimize(state: boolean)
		self._minimized = state
		if state then
			local targetSize = UDim2.new(self._origSize.X.Scale, self._origSize.X.Offset, 0, 56)
			tween(root, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = targetSize})
			task.delay(0.18, function()
				if self._minimized then
					contentWrap.Visible = false
				end
			end)
		else
			contentWrap.Visible = true
			tween(root, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = self._origSize})
		end
	end
	minimizeBtn.MouseButton1Click:Connect(function() applyMinimize(not self._minimized) end)

	-- Close
	closeBtn.MouseButton1Click:Connect(function()
		if self.IsKilled then return end
		self.IsKilled = true
		self:_ClosePopup()
		if options.KillOnClose and options.OnKill then pcall(options.OnKill) end
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
		for _, gb in ipairs(tab._groupboxes) do
			if q == "" then
				gb._frame.Visible = true
			else
				local n = string.lower(gb.Title or "")
				gb._frame.Visible = (string.find(n, q, 1, true) ~= nil)
			end
		end
	end)

	-- Mobile tweak
	if UserInputService.TouchEnabled then
		sidebar.Size = UDim2.new(0, 170, 1, 0)
		mainPanel.Position = UDim2.new(0, 170, 0, 0)
		mainPanel.Size = UDim2.new(1, -170, 1, 0)
	end

	-- store ui refs
	self._ui = {
		sidebarScroll = sidebarScroll,
		tabButtons = tabButtons,
		tabLayout = tabLayout,
		tabsContainer = tabsContainer,
		popupLayer = popupLayer,
	}

	-- keep bar stable when layout changes
	tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_UpdateSelectedBarDeferred(true)
	end)

	return (self :: any) :: Window
end

function WindowMT:SetToggleKey(key: Enum.KeyCode) self._toggleKey = key end

function WindowMT:Toggle(state: boolean?)
	if state == nil then self._visible = not self._visible else self._visible = state end
	self.Gui.Enabled = self._visible
end

function WindowMT:Destroy()
	self:_ClosePopup()
	for _, c in ipairs(self._connections) do safeDisconnect(c) end
	if self.Gui then self.Gui:Destroy() end
end

function WindowMT:SetTheme(newTheme: Theme)
	self:_ApplyTheme(newTheme)
end

function WindowMT:GetTheme(): Theme
	return self.Theme
end

--////////////////////////////////////////////////////////////
-- Sidebar Categories + Tabs
--////////////////////////////////////////////////////////////
function WindowMT:AddCategory(name: string)
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

local function makeSidebarTab(theme: Theme, iconProvider: IconProvider?, name: string, icon: string?)
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

function WindowMT:AddTab(name: string, icon: string?, category: string?)
	if category and category ~= "" then
		self:AddCategory(category)
	end

	local theme: Theme = self.Theme
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

	local tab: any = setmetatable({}, TabMT)
	tab.Name = name
	tab._window = self
	tab._btn = btn
	tab._btnBg = bg
	tab._btnLabel = label
	tab._btnIcon = iconImg
	tab._page = page
	tab._cols = {Left = colLeft, Right = colRight}
	tab._groupboxes = {}

	self.Tabs[name] = tab
	table.insert(self._tabOrder, tab)

	-- theme binds for tab
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
		end)
	end

	return tab
end

function WindowMT:SelectTab(name: string, instant: boolean?)
	local tab = self.Tabs[name]
	if not tab then return end

	-- close any open popup when switching tabs
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
local function makeGroupbox(theme: Theme, iconProvider: IconProvider?, title: string)
	local frame = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 60),
		ClipsDescendants = true,
	})
	withUICorner(frame, 12)
	withUIStroke(frame, theme.Stroke, 0.35, 1)

	local inner = mk("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	local PAD = 10
	mk("UIPadding", {PaddingTop=UDim.new(0,PAD),PaddingBottom=UDim.new(0,PAD),PaddingLeft=UDim.new(0,PAD),PaddingRight=UDim.new(0,PAD),Parent=inner})

	local header = mk("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = inner,
	})

	local titleLbl = mk("TextLabel", {
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
		Name = "ContentMask",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 26 + GAP),
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		Parent = inner,
	})

	local content = mk("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = contentMask,
	})

	local list = mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = content,
	})

	mk("Frame", {
		Name = "BottomSpacer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 999999,
		Parent = content,
	})

	return frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, titleLbl, PAD, GAP
end

function TabMT:AddGroupbox(title: string, opts: {Side: ("Left"|"Right")?, InitialCollapsed: boolean?}? )
	opts = opts or {}
	local side = opts.Side or "Left"

	local theme: Theme = self._window.Theme
	local frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, titleLbl, PAD, GAP =
		makeGroupbox(theme, self._window.IconProvider, title)

	frame.Parent = self._cols[side]
	frame.LayoutOrder = #self._groupboxes + 1

	local gb: any = setmetatable({}, GroupMT)
	gb.Title = title
	gb._tab = self
	gb._frame = frame
	gb._mask = contentMask
	gb._content = content
	gb._list = list
	gb._collapsed = false
	gb._themeUpdaters = {}
	table.insert(self._groupboxes, gb)

	-- theme binds
	self._window:_BindTheme(frame, "BackgroundColor3", "Panel")
	self._window:_BindTheme((frame:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
	self._window:_BindTheme(titleLbl, "TextColor3", "Text")

	local HEADER_H = 26
	local function setIconCollapsed(state: boolean)
		if chevronDown then
			(icon :: ImageLabel).Image = state and (chevronRight or chevronDown) or chevronDown
		else
			(fallback :: TextLabel).Text = state and ">" or "v"
		end
	end

	local function applyHeight(instant: boolean?)
		local h = list.AbsoluteContentSize.Y
		local contentH = if gb._collapsed then 0 else (h + 2)
		local maskH = contentH
		local target = (PAD * 2) + HEADER_H + GAP + maskH

		if instant then
			gb._mask.Size = UDim2.new(1, 0, 0, maskH)
			gb._content.Size = UDim2.new(1, 0, 0, maskH)
			gb._frame.Size = UDim2.new(1, 0, 0, target)
		else
			tween(gb._mask, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, maskH)})
			tween(gb._content, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, maskH)})
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
-- Control helpers
--////////////////////////////////////////////////////////////
local function makeRow(height: number)
	return mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height)})
end

--////////////////////////////////////////////////////////////
-- Toggle
--////////////////////////////////////////////////////////////
function GroupMT:AddToggle(text: string, default: boolean?, callback: ((boolean)->())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme
	local on = default == true

	local row = makeRow(40); row.Parent = self._content
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
		Size = UDim2.fromOffset(52, 26),
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
	withUIStroke(track, theme.Stroke, 0.75, 1)
	window:_BindTheme((track:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local knob = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 18),
		Position = on and UDim2.new(1, -22, 0.5, -9) or UDim2.new(0, 4, 0.5, -9),
		ZIndex = 21,
		Parent = track,
	})
	withUICorner(knob, 999)

	local function applyThemeForToggle()
		-- keep state while swapping theme
		theme = window.Theme
		track.BackgroundColor3 = on and theme.Accent or theme.Stroke
	end
	table.insert(self._themeUpdaters, applyThemeForToggle)
	window:_BindTheme(label, "TextColor3", "Text")

	local function set(state: boolean, fire: boolean?)
		on = state
		local tTheme: Theme = window.Theme
		tween(track, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = on and tTheme.Accent or tTheme.Stroke
		})
		tween(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -22, 0.5, -9) or UDim2.new(0, 4, 0.5, -9),
		})
		if fire ~= false and callback then task.spawn(callback, on) end
	end

	btn.MouseButton1Click:Connect(function() set(not on, true) end)

	return {Set = function(v: boolean) set(v, true) end, Get = function() return on end}
end

--////////////////////////////////////////////////////////////
-- Slider
--////////////////////////////////////////////////////////////
function GroupMT:AddSlider(text: string, min: number, max: number, default: number?, step: number?, callback: ((number)->())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme
	step = step or 1
	local value = math.clamp(default or min, min, max)

	local row = makeRow(52); row.Parent = self._content

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -80, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})
	window:_BindTheme(label, "TextColor3", "Text")

	local valLabel = mk("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 70, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = string.format("%.3f", value),
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.SubText,
		Parent = row,
	})
	window:_BindTheme(valLabel, "TextColor3", "SubText")

	local bar = mk("Frame", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 8),
		ZIndex = 20,
		Parent = row,
	})
	withUICorner(bar, 999)
	withUIStroke(bar, theme.Stroke, 0.5, 1)
	window:_BindTheme(bar, "BackgroundColor3", "Panel2")
	window:_BindTheme((bar:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local fill = mk("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 21,
		Parent = bar,
	})
	withUICorner(fill, 999)
	window:_BindTheme(fill, "BackgroundColor3", "Accent")

	local thumb = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 22,
		Parent = bar,
	})
	withUICorner(thumb, 999)

	local function apply(v: number, fire: boolean)
		v = math.clamp(v, min, max)
		local steps = math.floor((v - min) / step + 0.5)
		v = math.clamp(min + steps * step, min, max)
		value = v
		valLabel.Text = string.format("%.3f", value)
		local a = clamp01((value - min) / (max - min))
		fill.Size = UDim2.new(a, 0, 1, 0)
		thumb.Position = UDim2.new(a, 0, 0.5, 0)
		if fire and callback then task.spawn(callback, value) end
	end
	apply(value, false)

	local dragging = false
	local function setFromX(x: number)
		local absPos = bar.AbsolutePosition.X
		local absSize = bar.AbsoluteSize.X
		local a = clamp01((x - absPos) / absSize)
		apply(min + (max - min) * a, true)
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	bar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)

	return {Set = function(v: number) apply(v, true) end, Get = function() return value end}
end

--////////////////////////////////////////////////////////////
-- Button (slightly narrower padding via inset)
--////////////////////////////////////////////////////////////
function GroupMT:AddButton(text: string, callback: (() -> ())?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme

	local row = makeRow(42); row.Parent = self._content
	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -10, 1, 0), -- ✅ slightly less x size
		Position = UDim2.new(0, 5, 0, 0),
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
	window:_BindTheme((btn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	btn.MouseEnter:Connect(function()
		tween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = theme.Panel})
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = theme.Panel2})
	end)
	btn.MouseButton1Click:Connect(function()
		if callback then task.spawn(callback) end
	end)
	return btn
end

--////////////////////////////////////////////////////////////
-- Popup positioning helper (center under anchor)
--////////////////////////////////////////////////////////////
local function popupUnder(window: any, anchor: GuiObject, popup: GuiObject, width: number, height: number, yPad: number)
	local root: Frame = window.Root
	local layer: Frame = window._popupLayer

	-- convert absolute to root-space offset
	local aPos = anchor.AbsolutePosition
	local aSize = anchor.AbsoluteSize
	local rPos = root.AbsolutePosition

	local x = (aPos.X - rPos.X) + math.floor(aSize.X/2 - width/2)
	local y = (aPos.Y - rPos.Y) + aSize.Y + yPad

	-- clamp inside root
	x = math.clamp(x, 10, math.max(10, root.AbsoluteSize.X - width - 10))
	y = math.clamp(y, 10, math.max(10, root.AbsoluteSize.Y - height - 10))

	popup.Size = UDim2.fromOffset(width, height)
	popup.Position = UDim2.fromOffset(x, y)
	popup.Parent = layer
end

--////////////////////////////////////////////////////////////
-- Dropdown + MultiDropdown (single popup, centered)
--////////////////////////////////////////////////////////////
local function makePopupBase(window: any, theme: Theme, width: number, height: number)
	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, 0),
		ClipsDescendants = true,
		ZIndex = 1500,
	})
	withUICorner(panel, 12)
	withUIStroke(panel, theme.Stroke, 0.45, 1)
	window:_BindTheme(panel, "BackgroundColor3", "Panel")
	window:_BindTheme((panel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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
		ZIndex = 1501,
		Parent = panel,
	})
	withUICorner(search, 10)
	withUIStroke(search, theme.Stroke, 0.5, 1)
	window:_BindTheme(search, "BackgroundColor3", "Panel2")
	window:_BindTheme(search, "TextColor3", "Text")
	window:_BindTheme(search, "PlaceholderColor3", "Muted")
	window:_BindTheme((search:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local listFrame = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.2,
		ZIndex = 1501,
		Parent = panel,
	})
	mk("UIPadding", {PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,10),Parent=listFrame})
	local layout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=listFrame})

	return panel, search, listFrame, layout
end

function GroupMT:AddDropdown(text: string, items: {string}, default: string?, callback: ((string)->())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme
	local selected = default or (items[1] or "")

	local row = makeRow(44); row.Parent = self._content
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
		Position = UDim2.new(0, 5, 0, 22),
		Size = UDim2.new(1, -10, 0, 22),
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
	window:_BindTheme((btn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local open = false
	local PANEL_W = math.max(240, btn.AbsoluteSize.X)
	local PANEL_H = 240

	local function closePopup()
		open = false
		-- animate height to zero then destroy
		local p = window._activePopup
		if p and p.root then
			local rootObj = p.root
			tween(rootObj, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(rootObj.Size.X.Scale, rootObj.Size.X.Offset, 0, 0)})
			task.delay(0.14, function()
				if rootObj and rootObj.Parent then rootObj:Destroy() end
			end)
		end
	end

	local function openPopup()
		open = true
		local tTheme: Theme = window.Theme
		local panel, search, listFrame, layout = makePopupBase(window, tTheme, PANEL_W, PANEL_H)

		-- build items
		local function rebuild(filter: string?)
			for _, c in ipairs(listFrame:GetChildren()) do
				if c:IsA("TextButton") then c:Destroy() end
			end
			local q = string.lower(filter or "")
			for _, it in ipairs(items) do
				if q == "" or string.find(string.lower(it), q, 1, true) then
					local itemBtn = mk("TextButton", {
						BackgroundColor3 = tTheme.Panel2,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 30),
						Text = it,
						TextSize = 13,
						Font = Enum.Font.Gotham,
						TextColor3 = tTheme.Text,
						AutoButtonColor = false,
						ZIndex = 1502,
						Parent = listFrame,
					})
					withUICorner(itemBtn, 10)
					withUIStroke(itemBtn, tTheme.Stroke, 0.65, 1)
					window:_BindTheme(itemBtn, "BackgroundColor3", "Panel2")
					window:_BindTheme(itemBtn, "TextColor3", "Text")
					window:_BindTheme((itemBtn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

					itemBtn.MouseButton1Click:Connect(function()
						selected = it
						btn.Text = it
						if callback then task.spawn(callback, it) end
						window:_ClosePopup()
					end)
				end
			end
		end

		search:GetPropertyChangedSignal("Text"):Connect(function()
			rebuild(search.Text)
		end)

		rebuild("")

		-- position + animate open
		local desiredW = math.max(240, btn.AbsoluteSize.X)
		local desiredH = math.min(PANEL_H, 52 + layout.AbsoluteContentSize.Y + 16)
		popupUnder(window, btn, panel, desiredW, desiredH, 6)
		panel.Size = UDim2.fromOffset(desiredW, 0)
		tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(desiredW, desiredH)})

		-- register as active popup
		window:_OpenPopup("dropdown", panel, function() closePopup() end)
	end

	btn.MouseButton1Click:Connect(function()
		if window._activePopup and open then
			window:_ClosePopup()
			return
		end
		openPopup()
	end)

	return {Get = function() return selected end, Set = function(v: string) selected = v; btn.Text = v end}
end

function GroupMT:AddMultiDropdown(text: string, items: {string}, default: {string}?, callback: (({string})->())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme

	local chosen: {[string]: boolean} = {}
	if default then
		for _, v in ipairs(default) do chosen[v] = true end
	end

	local function currentList(): {string}
		local out: {string} = {}
		for _, it in ipairs(items) do
			if chosen[it] then table.insert(out, it) end
		end
		return out
	end

	local row = makeRow(44); row.Parent = self._content
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
		Position = UDim2.new(0, 5, 0, 22),
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
	window:_BindTheme((btn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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

	local open = false
	local PANEL_H = 260

	local function closePopup(panel: GuiObject?)
		open = false
		if panel then
			tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, 0)})
			task.delay(0.14, function()
				if panel and panel.Parent then panel:Destroy() end
			end)
		end
	end

	local function openPopup()
		open = true
		local tTheme: Theme = window.Theme
		local panel, search, listFrame, layout = makePopupBase(window, tTheme, math.max(240, btn.AbsoluteSize.X), PANEL_H)

		local function rebuild(filter: string?)
			for _, c in ipairs(listFrame:GetChildren()) do
				if c:IsA("Frame") then c:Destroy() end
			end
			local q = string.lower(filter or "")
			for _, it in ipairs(items) do
				if q == "" or string.find(string.lower(it), q, 1, true) then
					local itemRow = mk("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 30),
						ZIndex = 1502,
						Parent = listFrame,
					})

					local box = mk("Frame", {
						BackgroundColor3 = tTheme.Panel2,
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(18, 18),
						Position = UDim2.fromOffset(6, 6),
						ZIndex = 1503,
						Parent = itemRow,
					})
					withUICorner(box, 6)
					withUIStroke(box, tTheme.Stroke, 0.55, 1)
					window:_BindTheme(box, "BackgroundColor3", "Panel2")
					window:_BindTheme((box:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

					local check = mk("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Text = chosen[it] and "✓" or "",
						TextSize = 14,
						Font = Enum.Font.GothamBold,
						TextColor3 = tTheme.Accent,
						ZIndex = 1504,
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
						TextColor3 = tTheme.Text,
						AutoButtonColor = false,
						ZIndex = 1503,
						Parent = itemRow,
					})
					window:_BindTheme(label, "TextColor3", "Text")

					local function toggleIt()
						chosen[it] = not chosen[it]
						check.Text = chosen[it] and "✓" or ""
						refreshBtnText()
						if callback then task.spawn(callback, currentList()) end
					end
					label.MouseButton1Click:Connect(toggleIt)
					box.InputBegan:Connect(function(inp)
						if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
							toggleIt()
						end
					end)
				end
			end
		end

		search:GetPropertyChangedSignal("Text"):Connect(function()
			rebuild(search.Text)
		end)

		rebuild("")

		local desiredW = math.max(240, btn.AbsoluteSize.X)
		local desiredH = math.min(PANEL_H, 52 + layout.AbsoluteContentSize.Y + 16)
		popupUnder(window, btn, panel, desiredW, desiredH, 6)
		panel.Size = UDim2.fromOffset(desiredW, 0)
		tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(desiredW, desiredH)})

		window:_OpenPopup("multidropdown", panel, function() closePopup(panel) end)
	end

	btn.MouseButton1Click:Connect(function()
		if window._activePopup and open then
			window:_ClosePopup()
			return
		end
		openPopup()
	end)

	return {Get = function() return currentList() end, Set = function(list: {string})
		table.clear(chosen)
		for _, s in ipairs(list) do chosen[s] = true end
		refreshBtnText()
	end}
end

--////////////////////////////////////////////////////////////
-- Color Wheel Picker (popup, single-open)
--////////////////////////////////////////////////////////////
local WHEEL_IMG = "rbxassetid://0" -- <- put YOUR wheel image id here (must be a colored wheel image)
local function hsvToColor(h: number, s: number, v: number): Color3
	return Color3.fromHSV(h, s, v)
end

local function colorToHSV(c: Color3): (number, number, number)
	return c:ToHSV()
end

local function angleToHue(dx: number, dy: number): number
	local ang = math.atan2(dy, dx) -- -pi..pi
	local h = (ang / (2*math.pi)) + 0.5
	return (h % 1)
end

function GroupMT:AddColorPicker(text: string, default: Color3?, callback: ((Color3)->())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme

	local current = default or theme.Accent
	local h, s, v = colorToHSV(current)

	local row = makeRow(44); row.Parent = self._content
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
		Position = UDim2.new(1, -5, 0.5, 0),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(swatchBtn, 10)
	withUIStroke(swatchBtn, theme.Stroke, 0.45, 1)
	window:_BindTheme((swatchBtn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local open = false

	local function applyColor(fire: boolean)
		current = hsvToColor(h, s, v)
		swatchBtn.BackgroundColor3 = current
		if callback and fire then task.spawn(callback, current) end
	end

	local function closePopup(panel: GuiObject?)
		open = false
		if panel then
			tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, 0)})
			task.delay(0.14, function()
				if panel and panel.Parent then panel:Destroy() end
			end)
		end
	end

	local function openPopup()
		open = true
		local tTheme: Theme = window.Theme

		local PANEL_W = 300
		local PANEL_H = 190

		local panel = mk("Frame", {
			BackgroundColor3 = tTheme.Panel,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 1500,
		})
		withUICorner(panel, 12)
		withUIStroke(panel, tTheme.Stroke, 0.45, 1)
		window:_BindTheme(panel, "BackgroundColor3", "Panel")
		window:_BindTheme((panel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

		-- Color wheel (requires a colored wheel image)
		local wheel = mk("ImageButton", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(140, 140),
			Position = UDim2.fromOffset(12, 12),
			Image = WHEEL_IMG,
			ImageColor3 = Color3.new(1,1,1), -- ensure image not tinted
			AutoButtonColor = false,
			ZIndex = 1501,
			Parent = panel,
		})

		-- If wheel image id isn't set, show a helpful fallback label
		local wheelFallback = mk("TextLabel", {
			BackgroundTransparency = 1,
			Size = wheel.Size,
			Position = wheel.Position,
			Text = (WHEEL_IMG == "rbxassetid://0" or WHEEL_IMG == "") and "Set WHEEL_IMG\nin BlueView.lua" or "",
			TextSize = 12,
			Font = Enum.Font.Gotham,
			TextColor3 = tTheme.Muted,
			TextWrapped = true,
			ZIndex = 1502,
			Parent = panel,
		})
		window:_BindTheme(wheelFallback, "TextColor3", "Muted")

		-- Wheel cursor
		local cursor = mk("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(10, 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 1503,
			Parent = wheel,
		})
		withUICorner(cursor, 999)
		withUIStroke(cursor, Color3.new(1,1,1), 0.0, 2)
		withUIStroke(cursor, Color3.new(0,0,0), 0.4, 1)

		-- Brightness bar (top = bright, bottom = dark)
		local vBar = mk("Frame", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.new(1,1,1),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(16, 140),
			Position = UDim2.fromOffset(164, 12),
			ZIndex = 1501,
			Parent = panel,
		})
		withUICorner(vBar, 999)
		withUIStroke(vBar, tTheme.Stroke, 0.5, 1)
		window:_BindTheme((vBar:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
		local vGrad = mk("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(0,0,0)),
			Parent = vBar,
		})

		local vCursor = mk("Frame", {
			BackgroundColor3 = Color3.new(1,1,1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 4),
			ZIndex = 1502,
			Parent = vBar,
		})
		withUICorner(vCursor, 999)
		withUIStroke(vCursor, Color3.new(0,0,0), 0.4, 1)

		-- Presets row
		local presets = mk("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 0, 26),
			Position = UDim2.fromOffset(12, 154),
			ZIndex = 1501,
			Parent = panel,
		})
		local pl = mk("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = presets,
		})

		local function setHSVFromColor(c: Color3, fire: boolean)
			h, s, v = colorToHSV(c)
			applyColor(fire)
		end

		local function presetBtn(c: Color3)
			local b = mk("TextButton", {
				BackgroundColor3 = c,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(26, 26),
				Text = "",
				AutoButtonColor = false,
				ZIndex = 1502,
				Parent = presets,
			})
			withUICorner(b, 8)
			withUIStroke(b, tTheme.Stroke, 0.35, 1)
			window:_BindTheme((b:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
			b.MouseButton1Click:Connect(function()
				setHSVFromColor(c, true)
			end)
		end

		presetBtn(Color3.new(1,1,1))
		presetBtn(Color3.new(0,0,0))
		presetBtn(window.Theme.Accent)
		presetBtn(Color3.fromRGB(255, 90, 90))
		presetBtn(Color3.fromRGB(90, 255, 170))
		presetBtn(Color3.fromRGB(90, 180, 255))

		-- helpers to update cursor positions
		local function updateCursors()
			-- wheel cursor position from h,s
			local radius = 0.5 * wheel.AbsoluteSize.X
			local cx = radius
			local cy = radius
			local ang = (h - 0.5) * 2 * math.pi
			local r = s * (radius - 6)
			local x = cx + math.cos(ang) * r
			local y = cy + math.sin(ang) * r
			cursor.Position = UDim2.fromOffset(x, y)
			-- v cursor (top=1, bottom=0)
			vCursor.Position = UDim2.new(0, 0, 0, math.floor((1 - v) * (vBar.AbsoluteSize.Y - 4)))
			-- update bar gradient to match hue+sat at full value
			local topColor = hsvToColor(h, s, 1)
			vGrad.Color = ColorSequence.new(topColor, Color3.new(0,0,0))
		end

		updateCursors()

		local draggingWheel = false
		local draggingV = false

		local function setFromWheel(px: number, py: number)
			local wp = wheel.AbsolutePosition
			local ws = wheel.AbsoluteSize
			local cx = wp.X + ws.X/2
			local cy = wp.Y + ws.Y/2
			local dx = (px - cx)
			local dy = (py - cy)
			local dist = math.sqrt(dx*dx + dy*dy)
			local radius = ws.X/2
			local rr = math.clamp(dist / radius, 0, 1)
			h = angleToHue(dx, dy)
			s = rr
			applyColor(true)
			updateCursors()
		end

		local function setFromV(py: number)
			local vp = vBar.AbsolutePosition
			local vs = vBar.AbsoluteSize
			local a = clamp01((py - vp.Y) / vs.Y)
			v = 1 - a -- top=1, bottom=0
			applyColor(true)
			updateCursors()
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

		vBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				draggingV = true
				setFromV(input.Position.Y)
			end
		end)
		vBar.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				draggingV = false
			end
		end)

		local moveConn = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				if draggingWheel then setFromWheel(input.Position.X, input.Position.Y) end
				if draggingV then setFromV(input.Position.Y) end
			end
		end)

		-- position + animate open
		popupUnder(window, swatchBtn, panel, PANEL_W, PANEL_H, 6)
		panel.Size = UDim2.fromOffset(PANEL_W, 0)
		tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(PANEL_W, PANEL_H)})

		window:_OpenPopup("colorpicker", panel, function()
			safeDisconnect(moveConn)
			closePopup(panel)
		end)
	end

	swatchBtn.MouseButton1Click:Connect(function()
		-- if another popup open, close it first (handled by _OpenPopup)
		openPopup()
	end)

	applyColor(false)

	return {Get = function() return current end, Set = function(c: Color3) current = c; h,s,v = colorToHSV(c); applyColor(true) end}
end

return UILib
