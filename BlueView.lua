--!strict
-- BlueView.lua (All features restored + fixes)
-- Features:
--  ✅ Categories in sidebar
--  ✅ Active tab bright, inactive tab muted
--  ✅ Selected tab bar position stable (no drift)
--  ✅ Dragging does NOT snap back to center (autoscale won't overwrite position)
--  ✅ Search textbox starts empty
--  ✅ Dropdown + MultiDropdown inline under control, centered, overlays correctly
--  ✅ MultiDropdown uses checkbox checkmarks (no Done)
--  ✅ Single-popup manager: only one dropdown/color wheel open at a time; closes on tab switch
--  ✅ Color picker uses wheel image (with fallback) + brightness bar fixed (top=bright)
--  ✅ Theme bindings update all text/content colors; toggles retain on/off colors after theme change
--  ✅ Lucide icons supported via IconProvider callback (works with latte-soft/lucide-roblox)

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

--////////////////////////////////////////////////////////////
-- Icons (Lucide-ready via IconProvider callback)
--////////////////////////////////////////////////////////////
export type IconProvider = (name: string) -> string?

local function resolveIcon(iconProvider: IconProvider?, icon: string?): string?
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
	SetKillCallback: (self: Window, killOnClose: boolean, onKill: (() -> ())?) -> (),
	SetToggleKey: (self: Window, key: Enum.KeyCode) -> (),

	AddCategory: (self: Window, name: string) -> (),
	AddTab: (self: Window, name: string, icon: string?, category: string?) -> any,
	SelectTab: (self: Window, name: string, instant: boolean?) -> (),

	SetTheme: (self: Window, theme: Theme) -> (),
	GetTheme: (self: Window) -> Theme,

	RegisterFlag: (self: Window, flag: string, getter: () -> any, setter: (any) -> ()) -> (),
	CollectConfig: (self: Window) -> {[string]: any},
	ApplyConfig: (self: Window, data: {[string]: any}) -> (),
}

local WindowMT = {}
WindowMT.__index = WindowMT

local TabMT = {}
TabMT.__index = TabMT

local GroupMT = {}
GroupMT.__index = GroupMT

--////////////////////////////////////////////////////////////
-- Theme bindings
--////////////////////////////////////////////////////////////
type ThemeBinding = { inst: Instance, prop: string, key: string }
local function setProp(inst: Instance, prop: string, value: any)
	(inst :: any)[prop] = value
end

--////////////////////////////////////////////////////////////
-- Popup manager (single popup at a time)
--////////////////////////////////////////////////////////////
type PopupHandle = {
	Close: (instant: boolean?) -> (),
	IsOpen: () -> boolean,
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

	local sizeConstraint = mk("UISizeConstraint", {
		MinSize = options.MinSize or Vector2.new(560, 360),
		MaxSize = options.MaxSize or Vector2.new(1400, 900),
		Parent = root,
	}) :: UISizeConstraint
	local origMinSize = sizeConstraint.MinSize

	-- Autoscale (does not touch Position)
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
	task.spawn(function()
		while gui.Parent do
			task.wait(0.25)
			updateScale()
		end
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

	-- Sidebar
	local sidebar = mk("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 200, 1, 0),
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

	local tabListLayout = mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = tabButtons,
	}) :: UIListLayout

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

	-- Overlay holder for popups (ensures they overlay and don't collide)
	local overlay = mk("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 500,
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
	self._tabCount = 0
	self._layoutCounter = 0

	self.SelectedTab = nil
	self._connections = {}
	self._minimized = false
	self._origSize = root.Size
	self._killOnClose = options.KillOnClose == true
	self._onKill = options.OnKill
	self._toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	self._visible = true
	self._minToken = 0

	self._themeBindings = {} :: {ThemeBinding}
	self._flags = {} :: {[string]: {get: () -> any, set: (any) -> ()}}

	self._categories = {} :: {[string]: boolean}

	self._ui = {
		gui = gui,
		root = root,
		topbar = topbar,
		contentWrap = contentWrap,
		sidebar = sidebar,
		tabList = tabList,
		tabButtons = tabButtons,
		tabListLayout = tabListLayout,
		selectedBar = selectedBar,
		tabsContainer = tabsContainer,
		searchInput = searchInput,
		sizeConstraint = sizeConstraint,
		origMinSize = origMinSize,
		titleLabel = titleLabel,
		canvasBg = canvasBg,
		searchBox = searchBox,
		searchIcon = searchIcon,
		overlay = overlay,
	}

	-- Popup manager
	self._activePopup = nil :: PopupHandle?

	function self:_SetActivePopup(p: PopupHandle?)
		-- close previous (if different)
		if self._activePopup and (not p or self._activePopup ~= p) then
			pcall(function() self._activePopup:Close(false) end)
		end
		self._activePopup = p
	end
	function self:_ClosePopup()
		if self._activePopup then
			pcall(function() self._activePopup:Close(false) end)
		end
		self._activePopup = nil
	end

	-- Theme binding system
	function self:_BindTheme(inst: Instance, prop: string, key: string)
		table.insert(self._themeBindings, {inst = inst, prop = prop, key = key})
	end
	function self:_ApplyTheme(newTheme: Theme)
		self.Theme = newTheme
		for _, b in ipairs(self._themeBindings) do
			local v = (newTheme :: any)[b.key]
			if v ~= nil then
				pcall(function() setProp(b.inst, b.prop, v) end)
			end
		end
	end

	-- Core theme binds
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

	-- Selected bar updater (stable, no drift)
	self._barToken = 0
	function self:_UpdateSelectedBar(instant: boolean?)
		local tab = self.SelectedTab
		if not tab then return end
		local sb: Frame = self._ui.selectedBar
		if not sb then return end
		if not tab._btn then return end

		local ref = self._ui.tabList
		local btn = tab._btn :: GuiObject
		if not (ref and ref:IsA("GuiObject")) then return end

		local barH = sb.AbsoluteSize.Y
		if barH <= 0 then barH = 34 end

		local y = (btn.AbsolutePosition.Y - ref.AbsolutePosition.Y) + math.floor((btn.AbsoluteSize.Y - barH)/2)

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
			-- let layouts settle across a few frames
			for _ = 1, 3 do
				RunService.RenderStepped:Wait()
			end
			if token ~= self._barToken then return end
			self:_UpdateSelectedBar(instant)
		end)
	end

	-- keep bar correct if list layout changes height
	tabListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_UpdateSelectedBarDeferred(true)
	end)

	-- Dragging
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

	-- Minimize / Shrink
	local function applyMinimize(state: boolean)
		self._minToken += 1
		local token = self._minToken

		self._minimized = state
		local sc: UISizeConstraint = self._ui.sizeConstraint
		local origMin: Vector2 = self._ui.origMinSize

		if state then
			sc.MinSize = Vector2.new(origMin.X, 56)
			contentWrap.Visible = true
			local targetSize = UDim2.new(self._origSize.X.Scale, self._origSize.X.Offset, 0, 56)
			tween(root, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = targetSize})

			task.delay(0.18, function()
				if self._minimized and self._minToken == token then
					contentWrap.Visible = false
				end
			end)
		else
			sc.MinSize = origMin
			contentWrap.Visible = true
			tween(root, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = self._origSize})
		end
	end
	minimizeBtn.MouseButton1Click:Connect(function()
		self:_ClosePopup()
		applyMinimize(not self._minimized)
	end)

	-- Close
	local function doKill()
		if self.IsKilled then return end
		self.IsKilled = true
		if self._killOnClose and self._onKill then pcall(self._onKill) end
		self:Destroy()
	end
	closeBtn.MouseButton1Click:Connect(doKill)

	-- Toggle key
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == self._toggleKey then
			self:_ClosePopup()
			self:Toggle()
		end
	end))

	-- Search filter
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

	-- Click outside closes popup
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			-- if there's an active popup, and click isn't inside it => close
			local p = self._activePopup
			if p and p.IsOpen() then
				-- popup implementations will set a flag on their root Frame
				-- we do a simple check: if mouse is inside overlay children bounds, keep open
				local mouse = UserInputService:GetMouseLocation()
				local keep = false
				for _, child in ipairs(overlay:GetChildren()) do
					if child:IsA("GuiObject") and child.Visible then
						local ap = child.AbsolutePosition
						local asz = child.AbsoluteSize
						if mouse.X >= ap.X and mouse.X <= ap.X + asz.X and mouse.Y >= ap.Y and mouse.Y <= ap.Y + asz.Y then
							keep = true
							break
						end
					end
				end
				if not keep then
					self:_ClosePopup()
				end
			end
		end
	end))

	-- Mobile tweak
	if UserInputService.TouchEnabled then
		sidebar.Size = UDim2.new(0, 170, 1, 0)
		mainPanel.Position = UDim2.new(0, 170, 0, 0)
		mainPanel.Size = UDim2.new(1, -170, 1, 0)
	end

	return (self :: any) :: Window
end

function WindowMT:SetToggleKey(key: Enum.KeyCode) self._toggleKey = key end
function WindowMT:SetKillCallback(killOnClose: boolean, onKill: (() -> ())?)
	self._killOnClose = killOnClose
	self._onKill = onKill
end
function WindowMT:Toggle(state: boolean?)
	if state == nil then self._visible = not self._visible else self._visible = state end
	self.Gui.Enabled = self._visible
end
function WindowMT:Destroy()
	for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
	if self.Gui then self.Gui:Destroy() end
end

function WindowMT:SetTheme(newTheme: Theme)
	self:_ApplyTheme(newTheme)

	-- refresh tab visuals immediately
	for _, tab in ipairs(self._tabOrder) do
		tab:_RefreshVisuals(true)
	end

	-- keep selected bar color
	self._ui.selectedBar.BackgroundColor3 = self.Theme.Accent
end
function WindowMT:GetTheme(): Theme
	return self.Theme
end

function WindowMT:RegisterFlag(flag: string, getter: () -> any, setter: (any) -> ())
	self._flags[flag] = {get = getter, set = setter}
end
function WindowMT:CollectConfig(): {[string]: any}
	local out: {[string]: any} = {}
	for k, v in pairs(self._flags) do
		local ok, value = pcall(v.get)
		if ok then out[k] = value end
	end
	return out
end
function WindowMT:ApplyConfig(data: {[string]: any})
	for k, v in pairs(data) do
		local entry = self._flags[k]
		if entry then
			pcall(entry.set, v)
		end
	end
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
	tab.Left = colLeft
	tab.Right = colRight
	tab._cols = {Left = colLeft, Right = colRight}
	tab._groupboxes = {}

	function tab:_RefreshVisuals(instant: boolean?)
		local w = self._window
		local th = w.Theme
		local selected = (w.SelectedTab == self)
		if selected then
			if instant then
				self._btnBg.BackgroundTransparency = 0.40
				self._btnLabel.TextColor3 = th.Text
				if self._btnIcon then self._btnIcon.ImageTransparency = 0.05 end
			else
				tween(self._btnBg, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.40})
				tween(self._btnLabel, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = th.Text})
				if self._btnIcon then self._btnIcon.ImageTransparency = 0.05 end
			end
		else
			if instant then
				self._btnBg.BackgroundTransparency = 1
				self._btnLabel.TextColor3 = th.Muted
				if self._btnIcon then self._btnIcon.ImageTransparency = 0.45 end
			else
				tween(self._btnBg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
				tween(self._btnLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = th.Muted})
				if self._btnIcon then self._btnIcon.ImageTransparency = 0.45 end
			end
		end
	end

	self.Tabs[name] = tab
	table.insert(self._tabOrder, tab)

	-- theme binds for tab base colors
	self:_BindTheme(label, "TextColor3", "Muted") -- default inactive; selected overrides
	self:_BindTheme(bg, "BackgroundColor3", "Panel")

	btn.MouseButton1Click:Connect(function()
		self:SelectTab(name, false)
	end)

	btn.MouseEnter:Connect(function()
		if self.SelectedTab ~= tab then
			tween(bg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.55})
			tween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.Text})
			if iconImg then iconImg.ImageTransparency = 0.25 end
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.SelectedTab ~= tab then
			tween(bg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
			tween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.Muted})
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

function WindowMT:SelectTab(name: string, instant: boolean?)
	local tab = self.Tabs[name]
	if not tab then return end

	-- close any open popup when switching tabs
	self:_ClosePopup()

	for _, t in ipairs(self._tabOrder) do
		t._page.Visible = false
	end

	tab._page.Visible = true
	self.SelectedTab = tab

	-- refresh visuals
	for _, t in ipairs(self._tabOrder) do
		t:_RefreshVisuals(instant)
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

	return frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, titleLabel, PAD, GAP
end

function TabMT:AddGroupbox(title: string, opts: {Side: ("Left"|"Right")?, InitialCollapsed: boolean?}?)
	opts = opts or {}
	local side = opts.Side or "Left"

	local theme: Theme = self._window.Theme
	local frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, titleLabel, PAD, GAP =
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
	table.insert(self._groupboxes, gb)

	-- theme binds
	self._window:_BindTheme(frame, "BackgroundColor3", "Panel")
	self._window:_BindTheme((frame:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
	self._window:_BindTheme(titleLabel, "TextColor3", "Text")
	self._window:_BindTheme(fallback, "TextColor3", "SubText")

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
-- Controls helpers
--////////////////////////////////////////////////////////////
local function makeRow(height: number)
	return mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height)})
end

--////////////////////////////////////////////////////////////
-- Toggle
--////////////////////////////////////////////////////////////
function GroupMT:AddToggle(text: string, default: boolean?, callback: ((boolean) -> ())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme
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
		Size = UDim2.fromOffset(52, 26), -- slightly smaller X per request
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
	window:_BindTheme(track, "BackgroundColor3", "Stroke") -- base bind; we override on refresh

	local knob = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 18),
		Position = on and UDim2.new(1, -22, 0.5, -9) or UDim2.new(0, 4, 0.5, -9),
		ZIndex = 21,
		Parent = track,
	})
	withUICorner(knob, 999)

	-- keep toggle correct after theme changes
	local function refreshColors()
		theme = window.Theme
		track.BackgroundColor3 = on and theme.Accent or theme.Stroke
	end

	local function set(state: boolean, fire: boolean?)
		on = state
		refreshColors()
		tween(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -22, 0.5, -9) or UDim2.new(0, 4, 0.5, -9),
		})
		if fire ~= false and callback then task.spawn(callback, on) end
	end

	btn.MouseButton1Click:Connect(function() set(not on, true) end)

	-- bind theme changes
	window:_BindTheme(track, "BackgroundColor3", "Stroke")
	table.insert(window._connections, RunService.Heartbeat:Connect(function()
		-- lightweight: only adjust on theme object change
		-- (theme table reference changes when SetTheme called)
		if theme ~= window.Theme then
			theme = window.Theme
			refreshColors()
		end
	end))

	if flag and flag ~= "" then
		window:RegisterFlag(flag, function() return on end, function(v) set(v == true, false) end)
	end

	return {Set = function(v: boolean) set(v, true) end, Get = function() return on end}
end

--////////////////////////////////////////////////////////////
-- Slider
--////////////////////////////////////////////////////////////
function GroupMT:AddSlider(text: string, min: number, max: number, default: number?, step: number?, callback: ((number) -> ())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme
	step = step or 1
	local value = math.clamp(default or min, min, max)

	local row = makeRow(52)
	row.Parent = self._content

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

	if flag and flag ~= "" then
		window:RegisterFlag(flag, function() return value end, function(v) apply(tonumber(v) or value, false) end)
	end

	return {Set = function(v: number) apply(v, true) end, Get = function() return value end}
end

--////////////////////////////////////////////////////////////
-- Button
--////////////////////////////////////////////////////////////
function GroupMT:AddButton(text: string, callback: (() -> ())?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme

	local row = makeRow(42)
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
	window:_BindTheme((btn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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
-- Dropdown + MultiDropdown (overlay to root overlay, positioned under the button)
--////////////////////////////////////////////////////////////
local function makeDropdownPanel(window: any, anchor: GuiObject)
	local theme: Theme = window.Theme
	local overlay: Frame = window._ui.overlay
	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(anchor.AbsoluteSize.X, 0),
		Position = UDim2.fromOffset(anchor.AbsolutePosition.X - overlay.AbsolutePosition.X, anchor.AbsolutePosition.Y - overlay.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 6),
		ClipsDescendants = true,
		ZIndex = 600,
		Visible = false,
		Parent = overlay,
	})
	withUICorner(panel, 10)
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
		ZIndex = 601,
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
		ZIndex = 601,
		Parent = panel,
	})
	mk("UIPadding", {PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,10),Parent=listFrame})
	local layout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=listFrame})

	-- keep panel following anchor if UI moves/scrolls
	local function syncPos()
		if not anchor.Parent then return end
		panel.Size = UDim2.fromOffset(anchor.AbsoluteSize.X, panel.Size.Y.Offset)
		panel.Position = UDim2.fromOffset(anchor.AbsolutePosition.X - overlay.AbsolutePosition.X, anchor.AbsolutePosition.Y - overlay.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 6)
	end

	local hb = RunService.RenderStepped:Connect(function()
		if panel.Parent then
			syncPos()
		end
	end)

	local handle: PopupHandle = nil :: any
	handle = {
		Close = function(_: any, instant: boolean?)
			if not panel.Parent then return end
			if instant then
				panel.Size = UDim2.fromOffset(panel.Size.X.Offset, 0)
				panel.Visible = false
			else
				tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(panel.Size.X.Offset, 0)})
				task.delay(0.14, function()
					if panel then panel.Visible = false end
				end)
			end
			if hb.Connected then hb:Disconnect() end
		end,
		IsOpen = function()
			return panel.Visible and panel.Size.Y.Offset > 0
		end,
	}
	return panel, search, listFrame, layout, handle
end

function GroupMT:AddDropdown(text: string, items: {string}, default: string?, callback: ((string) -> ())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme
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
		Size = UDim2.new(1, 0, 0, 22),
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

	local panel: Frame? = nil
	local search: TextBox? = nil
	local listFrame: ScrollingFrame? = nil
	local layout: UIListLayout? = nil
	local popup: PopupHandle? = nil
	local open = false
	local PANEL_MAX = 220

	local function rebuild(filter: string?)
		if not listFrame or not layout then return end
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		local q = string.lower(filter or "")
		for _, it in ipairs(items) do
			if q == "" or string.find(string.lower(it), q, 1, true) then
				local itemBtn = mk("TextButton", {
					BackgroundColor3 = window.Theme.Panel2,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 30),
					Text = it,
					TextSize = 13,
					Font = Enum.Font.Gotham,
					TextColor3 = window.Theme.Text,
					AutoButtonColor = false,
					ZIndex = 602,
					Parent = listFrame,
				})
				withUICorner(itemBtn, 10)
				withUIStroke(itemBtn, window.Theme.Stroke, 0.65, 1)
				window:_BindTheme(itemBtn, "BackgroundColor3", "Panel2")
				window:_BindTheme(itemBtn, "TextColor3", "Text")
				window:_BindTheme((itemBtn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

				itemBtn.MouseButton1Click:Connect(function()
					selected = it
					btn.Text = it
					if callback then task.spawn(callback, it) end
					setOpen(false)
				end)
			end
		end
	end

	function setOpen(state: boolean)
		open = state
		if open then
			window:_ClosePopup()
			panel, search, listFrame, layout, popup = makeDropdownPanel(window, btn)
			panel.Visible = true
			rebuild((search :: TextBox).Text)
			(search :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
				rebuild((search :: TextBox).Text)
			end)
			local targetH = math.min(PANEL_MAX, 52 + (layout :: UIListLayout).AbsoluteContentSize.Y + 16)
			panel.Size = UDim2.fromOffset(panel.Size.X.Offset, 0)
			tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(panel.Size.X.Offset, targetH)})
			window:_SetActivePopup(popup)
		else
			if popup then
				popup:Close(false)
			end
			window:_SetActivePopup(nil)
		end
	end

	btn.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	if flag and flag ~= "" then
		window:RegisterFlag(flag, function() return selected end, function(v)
			local s = tostring(v)
			selected = s
			btn.Text = s
		end)
	end

	return {
		Get = function() return selected end,
		Set = function(v: string)
			selected = v
			btn.Text = v
			if callback then task.spawn(callback, v) end
		end
	}
end

function GroupMT:AddMultiDropdown(text: string, items: {string}, default: {string}?, callback: (({string}) -> ())?, flag: string?)
	local window: any = self._tab._window

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

	local row = makeRow(44)
	row.Parent = self._content

	local title = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = window.Theme.SubText,
		Parent = row,
	})
	window:_BindTheme(title, "TextColor3", "SubText")

	local btn = mk("TextButton", {
		BackgroundColor3 = window.Theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Select...",
		TextSize = 13,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = window.Theme.Text,
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(btn, 10)
	withUIStroke(btn, window.Theme.Stroke, 0.5, 1)
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

	local panel: Frame? = nil
	local search: TextBox? = nil
	local listFrame: ScrollingFrame? = nil
	local layout: UIListLayout? = nil
	local popup: PopupHandle? = nil
	local open = false
	local PANEL_MAX = 240

	local function rebuild(filter: string?)
		if not listFrame then return end
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local q = string.lower(filter or "")
		for _, it in ipairs(items) do
			if q == "" or string.find(string.lower(it), q, 1, true) then
				local itemRow = mk("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 30),
					ZIndex = 602,
					Parent = listFrame,
				})

				local box = mk("Frame", {
					BackgroundColor3 = window.Theme.Panel2,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(18, 18),
					Position = UDim2.fromOffset(6, 6),
					ZIndex = 603,
					Parent = itemRow,
				})
				withUICorner(box, 6)
				withUIStroke(box, window.Theme.Stroke, 0.55, 1)
				window:_BindTheme(box, "BackgroundColor3", "Panel2")
				window:_BindTheme((box:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

				local check = mk("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Text = chosen[it] and "✓" or "",
					TextSize = 14,
					Font = Enum.Font.GothamBold,
					TextColor3 = window.Theme.Accent,
					ZIndex = 604,
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
					TextColor3 = window.Theme.Text,
					AutoButtonColor = false,
					ZIndex = 603,
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

	function setOpen(state: boolean)
		open = state
		if open then
			window:_ClosePopup()
			panel, search, listFrame, layout, popup = makeDropdownPanel(window, btn)
			panel.Visible = true
			rebuild((search :: TextBox).Text)
			(search :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
				rebuild((search :: TextBox).Text)
			end)
			local targetH = math.min(PANEL_MAX, 52 + (layout :: UIListLayout).AbsoluteContentSize.Y + 16)
			panel.Size = UDim2.fromOffset(panel.Size.X.Offset, 0)
			tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(panel.Size.X.Offset, targetH)})
			window:_SetActivePopup(popup)
		else
			if popup then popup:Close(false) end
			window:_SetActivePopup(nil)
		end
	end

	btn.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	if flag and flag ~= "" then
		window:RegisterFlag(flag, function() return currentList() end, function(v)
			chosen = {}
			if typeof(v) == "table" then
				for _, s in ipairs(v :: {any}) do chosen[tostring(s)] = true end
			end
			refreshBtnText()
		end)
	end

	return {
		Get = function() return currentList() end,
		Set = function(list: {string})
			chosen = {}
			for _, s in ipairs(list) do chosen[s] = true end
			refreshBtnText()
			if callback then task.spawn(callback, currentList()) end
		end
	}
end

--////////////////////////////////////////////////////////////
-- Color Picker (wheel image + brightness bar)
--////////////////////////////////////////////////////////////
local WHEEL_IMG = "rbxassetid://1003599924" -- <-- set your wheel asset id here (must be a color wheel texture)
local function hsvToColor(h: number, s: number, v: number): Color3 return Color3.fromHSV(h, s, v) end
local function colorToHSV(c: Color3): (number, number, number) return c:ToHSV() end

-- Map point in wheel to HSV hue/sat (radius based)
local function wheelPointToHS(px: number, py: number): (number, number)
	local angle = math.atan2(py, px) -- -pi..pi
	local hue = (angle / (2 * math.pi)) % 1
	local sat = math.clamp(math.sqrt(px*px + py*py), 0, 1)
	return hue, sat
end

function GroupMT:AddColorPicker(text: string, default: Color3?, callback: ((Color3) -> ())?, flag: string?)
	local window: any = self._tab._window
	local theme: Theme = window.Theme

	local current = default or theme.Accent
	local h, s, v = colorToHSV(current)

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
		Position = UDim2.new(1, 0, 0.5, 0),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(swatchBtn, 10)
	withUIStroke(swatchBtn, theme.Stroke, 0.45, 1)
	window:_BindTheme((swatchBtn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local panel: Frame? = nil
	local popup: PopupHandle? = nil
	local open = false

	local function applyColor(fire: boolean)
		current = hsvToColor(h, s, v)
		swatchBtn.BackgroundColor3 = current
		if callback and fire then task.spawn(callback, current) end
	end

	local function buildPanel()
		local overlay: Frame = window._ui.overlay
		panel = mk("Frame", {
			BackgroundColor3 = window.Theme.Panel,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(260, 180),
			Position = UDim2.fromOffset(swatchBtn.AbsolutePosition.X - overlay.AbsolutePosition.X - 260 + swatchBtn.AbsoluteSize.X, swatchBtn.AbsolutePosition.Y - overlay.AbsolutePosition.Y + swatchBtn.AbsoluteSize.Y + 6),
			ClipsDescendants = true,
			ZIndex = 650,
			Visible = false,
			Parent = overlay,
		})
		withUICorner(panel, 12)
		withUIStroke(panel, window.Theme.Stroke, 0.45, 1)
		window:_BindTheme(panel, "BackgroundColor3", "Panel")
		window:_BindTheme((panel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

		-- wheel
		local wheel = mk("ImageButton", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(140, 140),
			Position = UDim2.fromOffset(12, 12),
			Image = WHEEL_IMG,
			ImageColor3 = Color3.new(1,1,1),
			ImageTransparency = (WHEEL_IMG == "rbxassetid://0" or WHEEL_IMG == "") and 1 or 0,
			AutoButtonColor = false,
			ZIndex = 651,
			Parent = panel,
		})

		-- fallback if no wheel image
		local fallback = mk("Frame", {
			BackgroundColor3 = hsvToColor(h, 1, 1),
			BorderSizePixel = 0,
			Size = wheel.Size,
			Position = wheel.Position,
			Visible = wheel.ImageTransparency >= 1,
			ZIndex = 651,
			Parent = panel,
		})
		withUICorner(fallback, 12)
		withUIStroke(fallback, window.Theme.Stroke, 0.6, 1)
		window:_BindTheme((fallback:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
		mk("UIGradient", {
			Color = ColorSequence.new(Color3.new(1,1,1), hsvToColor(h, 1, 1)),
			Rotation = 0,
			Parent = fallback,
		})
		mk("UIGradient", {
			Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(0,0,0)),
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)}),
			Rotation = 90,
			Parent = fallback,
		})

		local cursor = mk("Frame", {
			BackgroundColor3 = Color3.new(1,1,1),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(10, 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5 + (math.cos(h*2*math.pi)*s)/2, 0, 0.5 + (math.sin(h*2*math.pi)*s)/2, 0),
			ZIndex = 652,
			Parent = panel,
		})
		withUICorner(cursor, 999)
		withUIStroke(cursor, Color3.new(0,0,0), 0.35, 1)

		-- brightness bar (top = 1, bottom = 0)
		local bright = mk("Frame", {
			BackgroundColor3 = Color3.fromRGB(255,255,255),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(18, 140),
			Position = UDim2.fromOffset(160, 12),
			ZIndex = 651,
			Parent = panel,
		})
		withUICorner(bright, 10)
		withUIStroke(bright, window.Theme.Stroke, 0.6, 1)
		window:_BindTheme((bright:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

		mk("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, hsvToColor(h, s, 1)),
				ColorSequenceKeypoint.new(1, Color3.new(0,0,0)),
			}),
			Parent = bright,
		})

		local bCursor = mk("Frame", {
			BackgroundColor3 = Color3.new(1,1,1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 4),
			Position = UDim2.new(0, 0, 1 - v, -2),
			ZIndex = 652,
			Parent = bright,
		})
		withUICorner(bCursor, 999)
		withUIStroke(bCursor, Color3.new(0,0,0), 0.35, 1)

		-- presets row
		local presets = mk("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 156),
			Size = UDim2.new(1, -24, 0, 20),
			ZIndex = 651,
			Parent = panel,
		})
		mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = presets})

		local function presetBtn(c: Color3)
			local b = mk("TextButton", {
				BackgroundColor3 = c,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(20, 20),
				Text = "",
				AutoButtonColor = false,
				ZIndex = 652,
				Parent = presets,
			})
			withUICorner(b, 7)
			withUIStroke(b, window.Theme.Stroke, 0.35, 1)
			window:_BindTheme((b:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
			b.MouseButton1Click:Connect(function()
				h, s, v = colorToHSV(c)
				cursor.Position = UDim2.new(0.5 + (math.cos(h*2*math.pi)*s)/2, 0, 0.5 + (math.sin(h*2*math.pi)*s)/2, 0)
				bCursor.Position = UDim2.new(0, 0, 1 - v, -2)
				applyColor(true)
			end)
		end

		presetBtn(Color3.new(1,1,1))
		presetBtn(Color3.new(0,0,0))
		presetBtn(window.Theme.Accent)
		presetBtn(Color3.fromRGB(255, 90, 90))
		presetBtn(Color3.fromRGB(90, 255, 170))
		presetBtn(Color3.fromRGB(90, 180, 255))

		local draggingWheel = false
		local draggingBright = false

		local function setHSFromPos(px: number, py: number)
			local base = wheel.ImageTransparency < 1 and wheel or fallback
			local ap = base.AbsolutePosition
			local asz = base.AbsoluteSize
			local cx = ap.X + asz.X/2
			local cy = ap.Y + asz.Y/2
			local dx = (px - cx) / (asz.X/2)
			local dy = (py - cy) / (asz.Y/2)
			local nh, ns = wheelPointToHS(dx, dy)
			h, s = nh, ns
			cursor.Position = UDim2.new(0.5 + (math.cos(h*2*math.pi)*s)/2, 0, 0.5 + (math.sin(h*2*math.pi)*s)/2, 0)
			applyColor(true)
		end

		local function setVFromPos(py: number)
			local ap = bright.AbsolutePosition
			local asz = bright.AbsoluteSize
			v = 1 - clamp01((py - ap.Y) / asz.Y) -- top bright
			bCursor.Position = UDim2.new(0, 0, 1 - v, -2)
			applyColor(true)
		end

		wheel.MouseButton1Down:Connect(function()
			draggingWheel = true
			local mp = UserInputService:GetMouseLocation()
			setHSFromPos(mp.X, mp.Y)
		end)
		wheel.MouseButton1Up:Connect(function() draggingWheel = false end)
		fallback.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				draggingWheel = true
				setHSFromPos(i.Position.X, i.Position.Y)
			end
		end)
		fallback.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				draggingWheel = false
			end
		end)

		bright.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				draggingBright = true
				setVFromPos(i.Position.Y)
			end
		end)
		bright.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				draggingBright = false
			end
		end)

		local conn = UserInputService.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
				if draggingWheel then
					setHSFromPos(i.Position.X, i.Position.Y)
				end
				if draggingBright then
					setVFromPos(i.Position.Y)
				end
			end
		end)

		-- popup handle
		popup = {
			Close = function(_: any, instant: boolean?)
				if conn.Connected then conn:Disconnect() end
				if not panel then return end
				if instant then
					panel.Visible = false
				else
					tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(panel.Size.X.Offset, 0)})
					task.delay(0.14, function() if panel then panel.Visible = false end end)
				end
				task.delay(0.2, function()
					if panel then panel:Destroy() end
					panel = nil
				end)
			end,
			IsOpen = function()
				return panel ~= nil and (panel :: any).Visible == true
			end
		} :: any

		return popup
	end

	local function setOpen(state: boolean)
		open = state
		if open then
			window:_ClosePopup()
			popup = buildPanel()
			if panel then
				panel.Visible = true
				panel.Size = UDim2.fromOffset(panel.Size.X.Offset, 0)
				tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(panel.Size.X.Offset, 180)})
			end
			window:_SetActivePopup(popup)
		else
			if popup then popup:Close(false) end
			window:_SetActivePopup(nil)
		end
	end

	swatchBtn.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	if flag and flag ~= "" then
		window:RegisterFlag(flag, function() return current end, function(vv)
			if typeof(vv) == "Color3" then
				current = vv
				h, s, v = colorToHSV(current)
				applyColor(false)
			end
		end)
	end

	return {
		Get = function() return current end,
		Set = function(c: Color3)
			current = c
			h, s, v = colorToHSV(current)
			applyColor(true)
		end
	}
end

return UILib
