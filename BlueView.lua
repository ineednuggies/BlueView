--!strict
-- BlueView.lua (SpareStackUI) - Full updated package build
-- Features:
-- ✅ Autoscaling + mobile support
-- ✅ Sidebar categories + tabs w/ optional icons
-- ✅ Inactive tabs grey, active bright
-- ✅ Selected tab bar correct on first layout + switches
-- ✅ Dragging doesn't snap back to center
-- ✅ Main search starts empty (placeholder only)
-- ✅ Dropdown + MultiDropdown: inline under control, searchable, checkbox multi-select
-- ✅ ColorPicker: color wheel (HSV) + presets (incl. white)
-- ✅ Popup manager: only ONE popup open at a time; switching tabs closes popups
-- ✅ Theme binding hooks: ThemeManager can live-update all bound UI
-- ✅ Config flags: ConfigManager can save/load toggles, sliders, dropdowns, multi dropdowns, colors

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
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
-- Icons (Lucide-ready)
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
	MinimizeKey: Enum.KeyCode?,
	UnlockMouseOnOpen: boolean?,
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
-- Theme binding
--////////////////////////////////////////////////////////////
type ThemeBinding = {inst: Instance, prop: string, key: string}
local function setProp(inst: Instance, prop: string, value: any)
	(inst :: any)[prop] = value
end

--////////////////////////////////////////////////////////////
-- Popup manager (one at a time)
--////////////////////////////////////////////////////////////
type PopupCloser = () -> ()
local function isDescendantOf(inst: Instance, ancestor: Instance): boolean
	local cur: Instance? = inst
	while cur do
		if cur == ancestor then return true end
		cur = cur.Parent
	end
	return false
end

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

	
	-- Popup layer (dropdowns/color pickers). Parent to ScreenGui to avoid clipping by scrolling frames.
	local popupLayer = mk("Frame", {
		Name = "PopupLayer",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 900,
		ClipsDescendants = false,
		Parent = gui,
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

	-- Autoscale
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
		-- IMPORTANT: don't re-center root (fix snap-back after dragging)
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
		Size = UDim2.new(0, 320, 1, 0),
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



		local keyHint = mk("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(14 + 94 + 12), 0.5, 0), -- left of btnWrap (no overlap)
			Size = UDim2.fromOffset(140, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "Minimize: " .. (options.MinimizeKey or Enum.KeyCode.RightControl).Name,
			TextSize = 12,
			Font = Enum.Font.Gotham,
			TextColor3 = theme.Muted,
			ZIndex = 13,
			Parent = topbar, -- or btnWrap; topbar gives you more room
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

	local tabLayout = mk("UIListLayout", {
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
		Text = "", -- empty by default
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
	self._killOnClose = options.KillOnClose == true
	self._onKill = options.OnKill
	self._toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	self._minimizeKey = options.MinimizeKey or Enum.KeyCode.RightControl
	self._unlockMouse = options.UnlockMouseOnOpen == true
	self._visible = true
	self._minToken = 0
		local prevMouseBehavior = UserInputService.MouseBehavior
		local prevMouseIcon = UserInputService.MouseIconEnabled
		
		function self:_ApplyMouseState()
			if not self._unlockMouse then return end
		
			if self._visible then
				prevMouseBehavior = UserInputService.MouseBehavior
				prevMouseIcon = UserInputService.MouseIconEnabled
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			else
				UserInputService.MouseBehavior = prevMouseBehavior
				UserInputService.MouseIconEnabled = prevMouseIcon
			end
		end


	self._themeBindings = {} :: {ThemeBinding}
	self._themeWatchers = {} :: { (Theme) -> () }
	self._flags = {} :: {[string]: {get: () -> any, set: (any) -> ()}}
	self._categories = {} :: {[string]: boolean}

	self._activePopup = nil :: Frame?
	self._activePopupClose = nil :: PopupCloser?

	self._ui = {
		keyHint = keyHint,
		gui = gui,
		popupLayer = popupLayer,
		root = root,
		topbar = topbar,
		contentWrap = contentWrap,
		sidebar = sidebar,
		tabList = tabList,
		tabButtons = tabButtons,
		tabLayout = tabLayout,
		selectedBar = selectedBar,
		tabsContainer = tabsContainer,
		searchInput = searchInput,
		sizeConstraint = sizeConstraint,
		origMinSize = origMinSize,
		titleLabel = titleLabel,
		canvasBg = canvasBg,
		searchBox = searchBox,
		searchIcon = searchIcon,
	}
		

	--////////////////////////////////////////////////////////////
	-- Theme binding helpers
	--////////////////////////////////////////////////////////////
	function self:_BindTheme(inst: Instance, prop: string, key: string)
		if inst == nil then return end
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

	-- core binds
	self:_BindTheme(keyHint, "TextColor3", "Muted")
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

	--////////////////////////////////////////////////////////////
	-- Popup manager
	--////////////////////////////////////////////////////////////
	function self:_CloseActivePopup()
		if self._activePopupClose then
			pcall(self._activePopupClose)
		end
		self._activePopup = nil
		self._activePopupClose = nil
	end

	function self:_SetActivePopup(popup: Frame, closer: PopupCloser)
		if self._activePopup and self._activePopup ~= popup then
			self:_CloseActivePopup()
		end
		self._activePopup = popup
		self._activePopupClose = closer
		self._activePopupOpenedAt = os.clock()
	end

-- Position a popup directly under an anchor control (centered), clamped to popup layer bounds
function self:_PositionPopupUnder(anchor: GuiObject, popup: GuiObject, yPad: number?)
	if not anchor or not popup then return end
	local layer: Frame = self._ui.popupLayer
	if not layer or not layer.Parent then return end
	-- ensure we have valid Absolute* (defer 1 frame if needed)
	if layer.AbsoluteSize.X <= 0 or popup.AbsoluteSize.X <= 0 then
		task.defer(function()
			self:_PositionPopupUnder(anchor, popup, yPad)
		end)
		return
	end
	yPad = yPad or 6
	popup.AnchorPoint = Vector2.new(0, 0)

	local aPos = anchor.AbsolutePosition
	local aSize = anchor.AbsoluteSize
	local lPos = layer.AbsolutePosition
	local lSize = layer.AbsoluteSize
	local pSize = popup.AbsoluteSize

	local desiredX = (aPos.X - lPos.X) + math.floor((aSize.X - pSize.X) / 2)
	local desiredY = (aPos.Y - lPos.Y) + aSize.Y + yPad

	-- clamp inside layer
	local maxX = math.max(0, lSize.X - pSize.X)
	local maxY = math.max(0, lSize.Y - pSize.Y)
	local x = math.clamp(desiredX, 0, maxX)
	local y = math.clamp(desiredY, 0, maxY)

	popup.Position = UDim2.new(0, x, 0, y)
end

	-- close popup on outside click + global keybinds
	-- - ToggleKey: shows/hides the whole UI
	-- - MinimizeKey: shows/hides the whole UI (same behavior, just a separate bind)
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end

		-- keybinds
		if input.KeyCode == self._toggleKey or input.KeyCode == self._minimizeKey then
			self:Toggle()
			return
		end

		-- outside click closes active popup
		if not self._activePopup then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local pos = UserInputService:GetMouseLocation()
		local objs = gui:GetGuiObjectsAtPosition(pos.X, pos.Y)
		for _, o in ipairs(objs) do
			if self._activePopup and isDescendantOf(o, self._activePopup) then
				return
			end
		end

		self:_CloseActivePopup()
	end))


	--////////////////////////////////////////////////////////////
	-- Selected bar updater
	--////////////////////////////////////////////////////////////
				function self:_UpdateSelectedBar(instant: boolean?)
			local tab = self.SelectedTab
			if not tab or not tab._btn or not tab._btn.Parent then return end

			local sb: Frame = self._ui.selectedBar
			local container: GuiObject = self._ui.tabButtons

			-- Robust, UIScale-safe positioning:
			-- Use AbsolutePosition deltas instead of summing offsets/padding.
			local y = (tab._btn.AbsolutePosition.Y - container.AbsolutePosition.Y)
			y += math.floor((tab._btn.AbsoluteSize.Y - sb.AbsoluteSize.Y) / 2)
			if y < 0 then y = 0 end

			local pos = UDim2.new(0, -6, 0, y)
			if instant then
				sb.Position = pos
			else
				tween(sb, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = pos })
			end
		end

	function self:_UpdateSelectedBarDeferred(instant: boolean?)
		task.spawn(function()
			RunService.RenderStepped:Wait()
			RunService.RenderStepped:Wait()
			self:_UpdateSelectedBar(instant)
		end)
	end

	-- when layout changes, refresh
	tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_UpdateSelectedBarDeferred(true)
	end)

	--////////////////////////////////////////////////////////////
	-- Dragging
	--////////////////////////////////////////////////////////////
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

	--////////////////////////////////////////////////////////////
	-- Minimize / Shrink
	--////////////////////////////////////////////////////////////
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
	minimizeBtn.MouseButton1Click:Connect(function() applyMinimize(not self._minimized) end)

	-- Close
	local function doKill()
		if self.IsKilled then return end
		self.IsKilled = true
		if self._killOnClose and self._onKill then pcall(self._onKill) end
		self:Destroy()
	end
	closeBtn.MouseButton1Click:Connect(doKill)


	-- Search filter (groupbox title match)
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
	
function WindowMT:SetMinimizeKey(key: Enum.KeyCode)
	self._minimizeKey = key
	if self._ui.keyHint then
		self._ui.keyHint.Text = "Minimize: " .. key.Name
	end
end

function WindowMT:Toggle(state: boolean?)
	if state == nil then self._visible = not self._visible else self._visible = state end
	self.Gui.Enabled = self._visible
	self:_ApplyMouseState()
	if not self._visible then
		self:_CloseActivePopup()
	end
end
function WindowMT:Destroy()
	for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
	if self.Gui then self.Gui:Destroy() end
end

function WindowMT:SetTheme(newTheme: Theme)
	self:_ApplyTheme(newTheme)
	for _, fn in ipairs(self._themeWatchers) do
		pcall(function() fn(self.Theme) end)
	end
	-- refresh tab colors instantly
	for _, tab in ipairs(self._tabOrder) do
		if self.SelectedTab == tab then
			tab._btnLabel.TextColor3 = self.Theme.Text
			if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.05 end
		else
			tab._btnLabel.TextColor3 = self.Theme.Muted
			if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.45 end
		end
	end
end
function WindowMT:GetTheme(): Theme
	return self.Theme
end

function WindowMT:OnThemeChanged(fn: (Theme) -> ())
	table.insert(self._themeWatchers, fn)
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
			self:_UpdateSelectedBarDeferred(true)
		end)
	end

	return tab
end

function WindowMT:SelectTab(name: string, instant: boolean?)
	local tab = self.Tabs[name]
	if not tab then return end

	-- close any open popup when switching tabs
	self:_CloseActivePopup()

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

	-- update bar after layout settles
	self:_UpdateSelectedBarDeferred(instant == true)
end

--////////////////////////////////////////////////////////////
-- Groupbox
--////////////////////////////////////////////////////////////
local function makeGroupbox(theme: Theme, iconProvider: IconProvider?, title: string, window: any)
	local frame = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 60),
		ClipsDescendants = true,
	})
	withUICorner(frame, 12)
	withUIStroke(frame, theme.Stroke, 0.35, 1)

	if window then
		window:_BindTheme(frame, "BackgroundColor3", "Panel")
		window:_BindTheme((frame:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
	end

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
	if window then window:_BindTheme(titleLabel, "TextColor3", "Text") end

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
	if window then window:_BindTheme(fallback, "TextColor3", "SubText") end

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

	return frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP
end

function TabMT:AddGroupbox(title: string, opts: {Side: ("Left"|"Right")?, InitialCollapsed: boolean?}?)
	opts = opts or {}
	local side = opts.Side or "Left"

	local window: any = self._window
	local theme: Theme = window.Theme
	local frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP =
		makeGroupbox(theme, window.IconProvider, title, window)

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

	local HEADER_H = 26
	local function setIconCollapsed(state: boolean)
		if chevronDown then
			icon.Image = state and (chevronRight or chevronDown) or chevronDown
		else
			fallback.Text = state and ">" or "v"
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

	local function setCollapsed(state: boolean)
		gb._collapsed = state
		setIconCollapsed(state)
		applyHeight(false)
	end

	collapseBtn.MouseButton1Click:Connect(function()
		setCollapsed(not gb._collapsed)
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
-- Toggle (no giant glow; subtle)
--////////////////////////////////////////////////////////////
local GLOW_IMG = "rbxassetid://93208570840427" -- set to your radial glow png

local function addRadialGlowSimple(host: GuiObject, color: Color3, pad: number, alpha: number)
	local disabled = (GLOW_IMG == "" or GLOW_IMG == "rbxassetid://0")
	local parent = host.Parent
	if not parent or not parent:IsA("GuiObject") then
		local function noop(_: number) end
		return noop
	end

	local layer = mk("Frame", {
		Name = "RadialGlow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = math.max(1, host.ZIndex - 1),
		ClipsDescendants = false,
		Parent = parent,
	}) :: Frame

	local img = mk("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, pad, 1, pad),
		Image = GLOW_IMG,
		ImageColor3 = color,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = layer.ZIndex,
		Parent = layer,
	}) :: ImageLabel

	local dead = false
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

	local function setIntensity(intensity: number)
		intensity = math.clamp(intensity, 0, 1)
		if disabled then img.ImageTransparency = 1 return end
		img.ImageTransparency = 1 - ((1 - alpha) * intensity)
	end

	local function setColor(newColor: Color3)
		img.ImageColor3 = newColor
	end

	host:GetPropertyChangedSignal("Position"):Connect(sync)
	host:GetPropertyChangedSignal("Size"):Connect(sync)
	host:GetPropertyChangedSignal("AnchorPoint"):Connect(sync)
	host:GetPropertyChangedSignal("Rotation"):Connect(sync)
	host:GetPropertyChangedSignal("ZIndex"):Connect(sync)
	host.AncestryChanged:Connect(function(_, np)
		if np == nil then dead = true; pcall(function() layer:Destroy() end) end
	end)

	sync()
	return setIntensity, setColor
end

function GroupMT:AddToggle(text: string, default: boolean?, callback: ((boolean) -> ())?, flag: string?)
	local theme: Theme = self._tab._window.Theme
	local window: any = self._tab._window
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

	local setGlow, setGlowColor = addRadialGlowSimple(track, theme.Accent, 14, 0.86)
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

	local function set(state: boolean, fire: boolean?)
		on = state
		tween(track, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = on and theme.Accent or theme.Stroke
		})
		tween(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -24, 0.5, -10) or UDim2.new(0, 4, 0.5, -10),
		})
		setGlow(on and 1 or 0)
		if fire ~= false and callback then task.spawn(callback, on) end
	end

	btn.MouseButton1Click:Connect(function() set(not on, true) end)

	-- keep toggle visuals correct when theme/accent changes
	window:OnThemeChanged(function(newTheme)
		theme = newTheme
		knob.BackgroundColor3 = theme.Text
		if on then
			track.BackgroundColor3 = theme.Accent
			setGlow(1)
		else
			track.BackgroundColor3 = theme.Stroke
			setGlow(0)
		end
		if setGlowColor then setGlowColor(theme.Accent) end
	end)


	if flag and flag ~= "" then
		window:RegisterFlag(flag, function() return on end, function(v)
			set(v == true, false)
		end)
	end

	return {Set = function(v: boolean) set(v, true) end, Get = function() return on end}
end

--////////////////////////////////////////////////////////////
-- Slider (no glow)
--////////////////////////////////////////////////////////////
function GroupMT:AddSlider(text: string, min: number, max: number, default: number?, step: number?, callback: ((number) -> ())?, flag: string?)
	local theme: Theme = self._tab._window.Theme
	local window: any = self._tab._window
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
		window:RegisterFlag(flag, function() return value end, function(v)
			apply(tonumber(v) or value, false)
		end)
	end

	return {Set = function(v: number) apply(v, true) end, Get = function() return value end}
end

--////////////////////////////////////////////////////////////
-- Button (no glow) + slightly narrower X padding
--////////////////////////////////////////////////////////////
function GroupMT:AddButton(text: string, callback: (() -> ())?)
	local theme: Theme = self._tab._window.Theme
	local window: any = self._tab._window

	local row = makeRow(42)
	row.Parent = self._content

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -6, 1, 0), -- slightly less wide
		Position = UDim2.new(0, 3, 0, 0),
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
-- Dropdowns (inline under control, centered to button)
--////////////////////////////////////////////////////////////
local function makeDropdownBase(window: any, theme: Theme, row: Frame, anchorBtn: GuiObject)
	row.ClipsDescendants = false

	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(0, 0),
		ClipsDescendants = true,
		ZIndex = 200,
		Visible = false,
		Parent = window._ui.popupLayer,
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
		ZIndex = 201,
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
		ZIndex = 201,
		Parent = panel,
	})
	mk("UIPadding", {PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,10),Parent=listFrame})
	local layout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=listFrame})

	return panel, search, listFrame, layout
end

function GroupMT:AddDropdown(text: string, items: {string}, default: string?, callback: ((string) -> ())?, flag: string?)
	local theme: Theme = self._tab._window.Theme
	local window: any = self._tab._window
	local selected = default or (items[1] or "")

	local row = makeRow(46)
	row.Parent = self._content
	row.ClipsDescendants = false

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
		Position = UDim2.new(0, 3, 0, 22),
		Size = UDim2.new(1, -6, 0, 24),
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

	local panel, search, listFrame, layout = makeDropdownBase(window, theme, row, btn)
	local open = false
	local PANEL_MAX = 230

	local function closeNow()
		open = false
		tween(panel, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, 0)})
		task.delay(0.12, function()
			if not open then panel.Visible = false end
		end)
	end

	local function rebuild(filter: string?)
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		local q = string.lower(filter or "")
		for _, it in ipairs(items) do
			if q == "" or string.find(string.lower(it), q, 1, true) then
				local itemBtn = mk("TextButton", {
					BackgroundColor3 = theme.Panel2,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 30),
					Text = it,
					TextSize = 13,
					Font = Enum.Font.Gotham,
					TextColor3 = theme.Text,
					AutoButtonColor = false,
					ZIndex = 202,
					Parent = listFrame,
				})
				withUICorner(itemBtn, 10)
				withUIStroke(itemBtn, theme.Stroke, 0.65, 1)
				window:_BindTheme(itemBtn, "BackgroundColor3", "Panel2")
				window:_BindTheme(itemBtn, "TextColor3", "Text")
				window:_BindTheme((itemBtn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

				itemBtn.MouseButton1Click:Connect(function()
					selected = it
					btn.Text = it
					if callback then task.spawn(callback, it) end
					closeNow()
				end)
			end
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		rebuild(search.Text)
	end)

	local function openNow()
		panel.Visible = true
		panel.Size = UDim2.fromOffset(btn.AbsoluteSize.X, 0)
		-- position using absolute coords so it lines up under the button
		window:_PositionPopupUnder(btn, panel, 6)

		rebuild(search.Text)
		local targetH = math.min(PANEL_MAX, 52 + layout.AbsoluteContentSize.Y + 16)
		tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(btn.AbsoluteSize.X, targetH),
		})
		-- re-position after size anim starts (clamp uses popup height)
		task.defer(function()
			if panel.Visible then
				window:_PositionPopupUnder(btn, panel, 6)
			end
		end)

		window:_SetActivePopup(panel, closeNow)
		open = true
	end

	btn.MouseButton1Click:Connect(function()
		if open then
			closeNow()
			window:_CloseActivePopup()
		else
			openNow()
		end
	end)

	if flag and flag ~= "" then
		window:RegisterFlag(flag,
			function() return selected end,
			function(v)
				local s = tostring(v)
				selected = s
				btn.Text = s
			end
		)
	end

	return {Get=function() return selected end, Set=function(v: string) selected=v; btn.Text=v; if callback then task.spawn(callback, v) end end}
end

function GroupMT:AddMultiDropdown(text: string, items: {string}, default: {string}?, callback: (({string}) -> ())?, flag: string?)
	local theme: Theme = self._tab._window.Theme
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

	local row = makeRow(46)
	row.Parent = self._content
	row.ClipsDescendants = false

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
		Position = UDim2.new(0, 3, 0, 22),
		Size = UDim2.new(1, -6, 0, 24),
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

	local panel, search, listFrame, layout = makeDropdownBase(window, theme, row, btn)
	local open = false
	local PANEL_MAX = 260

	local function closeNow()
		open = false
		tween(panel, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(btn.AbsoluteSize.X, 0)})
		task.delay(0.12, function()
			if not open then panel.Visible = false end
		end)
	end

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
					ZIndex = 202,
					Parent = listFrame,
				})

				local box = mk("Frame", {
					BackgroundColor3 = theme.Panel2,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(18, 18),
					Position = UDim2.fromOffset(6, 6),
					ZIndex = 203,
					Parent = itemRow,
				})
				withUICorner(box, 6)
				withUIStroke(box, theme.Stroke, 0.55, 1)
				window:_BindTheme(box, "BackgroundColor3", "Panel2")
				window:_BindTheme((box:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

				local check = mk("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Text = chosen[it] and "✓" or "",
					TextSize = 14,
					Font = Enum.Font.GothamBold,
					TextColor3 = theme.Accent,
					ZIndex = 204,
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
					ZIndex = 203,
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

	local function openNow()
		panel.Visible = true
		panel.Size = UDim2.fromOffset(btn.AbsoluteSize.X, 0)
		window:_PositionPopupUnder(btn, panel, 6)

		rebuild(search.Text)
		local targetH = math.min(PANEL_MAX, 52 + layout.AbsoluteContentSize.Y + 16)
		tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(btn.AbsoluteSize.X, targetH),
		})
		task.defer(function()
			if panel.Visible then
				window:_PositionPopupUnder(btn, panel, 6)
			end
		end)

		window:_SetActivePopup(panel, closeNow)
		open = true
	end

	btn.MouseButton1Click:Connect(function()
		if open then
			closeNow()
			window:_CloseActivePopup()
		else
			openNow()
		end
	end)

	if flag and flag ~= "" then
		window:RegisterFlag(flag,
			function() return currentList() end,
			function(v)
				chosen = {}
				if typeof(v) == "table" then
					for _, s in ipairs(v :: {any}) do
						chosen[tostring(s)] = true
					end
				end
				refreshBtnText()
			end
		)
	end

	return {Get=function() return currentList() end, Set=function(list: {string}) chosen={}; for _, s in ipairs(list) do chosen[s]=true end; refreshBtnText(); if callback then task.spawn(callback, currentList()) end end}
end

--////////////////////////////////////////////////////////////
-- Color Picker (color wheel HSV)
--////////////////////////////////////////////////////////////
-- NOTE: This uses math-based wheel picking (no texture required).
-- If you want a pretty wheel image, set WHEEL_IMG to an uploaded wheel PNG and it will render behind the picker.
local WHEEL_IMG = "rbxassetid://78013985921887" -- e.g. "rbxassetid://<your_color_wheel_png>"

local function hsvToColor(h: number, s: number, v: number): Color3
	return Color3.fromHSV(h, s, v)
end
local function colorToHSV(c: Color3): (number, number, number)
	return c:ToHSV()
end

function GroupMT:AddColorPicker(text: string, default: Color3?, callback: ((Color3) -> ())?, flag: string?)
	local theme: Theme = self._tab._window.Theme
	local window: any = self._tab._window

	local current = default or theme.Accent
	local h, s, v = colorToHSV(current)

	local row = makeRow(46)
	row.Parent = self._content
	row.ClipsDescendants = false

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

	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(268, 0),
		ClipsDescendants = true,
		ZIndex = 220,
		Visible = false,
		Parent = window._ui.popupLayer,
	})
	withUICorner(panel, 12)
	withUIStroke(panel, theme.Stroke, 0.45, 1)
	window:_BindTheme(panel, "BackgroundColor3", "Panel")
	window:_BindTheme((panel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local PANEL_H = 178

	-- wheel area
	local wheel = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(25, 23, 40),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(120, 120),
		ZIndex = 221,
		Parent = panel,
	})
	withUICorner(wheel, 999)
	withUIStroke(wheel, theme.Stroke, 0.65, 1)
	window:_BindTheme((wheel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	-- optional wheel image
	if WHEEL_IMG ~= "" then
		mk("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = WHEEL_IMG,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 221,
			Parent = wheel,
			Rotation = 360,
		})
	end

	-- wheel cursor
	local wheelCursor = mk("Frame", {
		BackgroundColor3 = Color3.new(1,1,1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 223,
		Parent = wheel,
	})
	withUICorner(wheelCursor, 999)
	withUIStroke(wheelCursor, Color3.new(0,0,0), 0.35, 1)

	-- Value slider
	local valBar = mk("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(140, 10),
		Size = UDim2.fromOffset(22, 120),
		ZIndex = 221,
		Parent = panel,
	})
	withUICorner(valBar, 10)
	withUIStroke(valBar, theme.Stroke, 0.65, 1)
	window:_BindTheme((valBar:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local valFill = mk("Frame", {
		BackgroundColor3 = Color3.new(1,1,1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 221,
		Parent = valBar,
	})
	withUICorner(valFill, 10)

	local valGrad = mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(1,1,1)),
		Parent = valFill,
	})

	local valCursor = mk("Frame", {
		BackgroundColor3 = Color3.new(1,1,1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = 223,
		Parent = valBar,
	})
	withUICorner(valCursor, 999)
	withUIStroke(valCursor, Color3.new(0,0,0), 0.35, 1)

	-- presets
	local presets = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 138),
		Size = UDim2.new(1, -20, 0, 30),
		ZIndex = 221,
		Parent = panel,
	})
	local pl = mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = presets,
	})

	local function updateUIFromHSV()
		current = hsvToColor(h, s, v)
		swatchBtn.BackgroundColor3 = current
		-- cursor positions
		local r = math.clamp(s, 0, 1)
		local ang = h * math.pi * 2
		local cx = math.cos(ang) * r
		local cy = math.sin(ang) * r
		wheelCursor.Position = UDim2.fromScale(0.5 + cx * 0.5, 0.5 + cy * 0.5)
		valCursor.Position = UDim2.new(0, 0, 1 - v, -1)

		-- adjust value gradient based on hue/sat
		valGrad.Color = ColorSequence.new(Color3.new(0,0,0), hsvToColor(h, s, 1))
	end

	local function applyColor(fire: boolean)
		updateUIFromHSV()
		if callback and fire then task.spawn(callback, current) end
	end

	local function presetBtn(c: Color3)
		local b = mk("TextButton", {
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(28, 28),
			Text = "",
			AutoButtonColor = false,
			ZIndex = 222,
			Parent = presets,
		})
		withUICorner(b, 8)
		withUIStroke(b, theme.Stroke, 0.35, 1)
		window:_BindTheme((b:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
		b.MouseButton1Click:Connect(function()
			h, s, v = colorToHSV(c)
			applyColor(true)
		end)
	end

	presetBtn(Color3.new(1,1,1))
	presetBtn(Color3.new(0,0,0))
	presetBtn(theme.Accent)
	presetBtn(Color3.fromRGB(255, 90, 90))
	presetBtn(Color3.fromRGB(90, 255, 170))
	presetBtn(Color3.fromRGB(90, 180, 255))

	updateUIFromHSV()

	local draggingWheel = false
	local draggingVal = false

	local function setWheelFromPos(px: number, py: number)
		local p = wheel.AbsolutePosition
		local sz = wheel.AbsoluteSize
		local cx = (px - (p.X + sz.X/2)) / (sz.X/2)
		local cy = (py - (p.Y + sz.Y/2)) / (sz.Y/2)
		local r = math.sqrt(cx*cx + cy*cy)
		if r > 1 then
			cx /= r
			cy /= r
			r = 1
		end
		local ang = math.atan2(cy, cx)
		if ang < 0 then ang += math.pi*2 end
		h = ang / (math.pi*2)
		s = r
		applyColor(true)
	end

	local function setValFromPos(py: number)
		local p = valBar.AbsolutePosition
		local sz = valBar.AbsoluteSize
		v = 1 - clamp01((py - p.Y) / sz.Y)
		applyColor(true)
	end

	wheel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingWheel = true
			setWheelFromPos(input.Position.X, input.Position.Y)
		end
	end)
	wheel.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingWheel = false
		end
	end)
	valBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingVal = true
			setValFromPos(input.Position.Y)
		end
	end)
	valBar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingVal = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			if draggingWheel then setWheelFromPos(input.Position.X, input.Position.Y) end
			if draggingVal then setValFromPos(input.Position.Y) end
		end
	end)

	local open = false
	local function closeNow()
		open = false
		tween(panel, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(268, 0)})
		task.delay(0.12, function()
			if not open then panel.Visible = false end
		end)
	end
	local function openNow()
		panel.Visible = true
		window:_PositionPopupUnder(swatchBtn, panel, 6)
		panel.Size = UDim2.fromOffset(268, 0)
		tween(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(268, PANEL_H)})
		window:_SetActivePopup(panel, closeNow)
		open = true
	end

	swatchBtn.MouseButton1Click:Connect(function()
		if open then
			closeNow()
			window:_CloseActivePopup()
		else
			openNow()
		end
	end)

	if flag and flag ~= "" then
		window:RegisterFlag(flag, function() return current end, function(vAny)
			if typeof(vAny) == "Color3" then
				current = vAny
				h, s, v = colorToHSV(current)
				applyColor(false)
			end
		end)
	end

	return {Get=function() return current end, Set=function(c: Color3) current=c; h,s,v = colorToHSV(c); applyColor(true) end}
end

return UILib
