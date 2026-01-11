--!strict
-- SpareStackUI.lua
-- Update:
-- ✅ Autoscale + mobile support confirmed (already included)
-- ✅ Toggle glow changed to 4-sided edge glow (Top/Bottom/Left/Right) using glow texture
-- ✅ Removed slider + button glow
-- ✅ Selected tab bar fixed on initial tab (startup) + correct reference frame
-- ✅ Added Dropdown + MultiDropdown (with search, overlays, not clipped)
-- ✅ Added theme hooks + control registry (for ThemeManager + ConfigManager)

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
	}) :: UIStroke
end

local function clamp01(x: number): number
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end

--////////////////////////////////////////////////////////////
-- Glow texture
-- NOTE: you can keep using your uploaded glow image
--////////////////////////////////////////////////////////////
local RADIAL_GLOW_IMG = "rbxassetid://93208570840427"

--////////////////////////////////////////////////////////////
-- Edge glow (4-sided glow strips) for toggles
-- Uses your texture, but masked into 4 strips.
--////////////////////////////////////////////////////////////
local function makeGlowStrip(parent: Instance, color: Color3, alpha: number, z: number)
	local img = mk("ImageLabel", {
		BackgroundTransparency = 1,
		Image = RADIAL_GLOW_IMG,
		ImageColor3 = color,
		ImageTransparency = alpha,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = z,
		Parent = parent,
	}) :: ImageLabel
	return img
end

-- returns setIntensity(0..1), destroy()
local function addEdgeGlowOutside(
	host: GuiObject,
	color: Color3,
	thickness: number, -- strip thickness in px
	alpha: number      -- base alpha (higher = more transparent)
)
	local disabled = (RADIAL_GLOW_IMG == "rbxassetid://0" or RADIAL_GLOW_IMG == "")
	local parent = host.Parent
	if not parent or not parent:IsA("GuiObject") then
		local function noop(_: number) end
		return noop, function() end
	end

	local glowZ = math.max(1, host.ZIndex - 1)

	local layer = mk("Frame", {
		Name = "EdgeGlow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = glowZ,
		ClipsDescendants = true,
		Parent = parent,
	}) :: Frame
	-- keep same rounding feel as host by matching corners with a big radius
	withUICorner(layer, 999)

	-- 4 strips (top/bottom/left/right)
	local top = makeGlowStrip(layer, color, 1, glowZ)
	local bottom = makeGlowStrip(layer, color, 1, glowZ)
	local left = makeGlowStrip(layer, color, 1, glowZ)
	local right = makeGlowStrip(layer, color, 1, glowZ)

	local baseAlpha = math.clamp(alpha, 0, 1)

	local dead = false
	local conns: {RBXScriptConnection} = {}

	local function sync()
		if dead then return end
		if not host.Parent or host.Parent ~= parent then return end

		layer.AnchorPoint = host.AnchorPoint
		layer.Rotation = host.Rotation

		local hs = host.Size
		layer.Size = UDim2.new(
			hs.X.Scale, hs.X.Offset + thickness * 2,
			hs.Y.Scale, hs.Y.Offset + thickness * 2
		)

		-- anchor compensation so padding stays centered
		local ap = host.AnchorPoint
		local shiftX = (ap.X - 0.5) * (thickness * 2)
		local shiftY = (ap.Y - 0.5) * (thickness * 2)

		local hp = host.Position
		layer.Position = UDim2.new(
			hp.X.Scale, hp.X.Offset + shiftX,
			hp.Y.Scale, hp.Y.Offset + shiftY
		)

		layer.ZIndex = math.max(1, host.ZIndex - 1)
		local z = layer.ZIndex

		-- layout strips inside padded layer
		top.ZIndex = z
		bottom.ZIndex = z
		left.ZIndex = z
		right.ZIndex = z

		top.AnchorPoint = Vector2.new(0.5, 0)
		top.Position = UDim2.new(0.5, 0, 0, 0)
		top.Size = UDim2.new(1, 0, 0, thickness)

		bottom.AnchorPoint = Vector2.new(0.5, 1)
		bottom.Position = UDim2.new(0.5, 0, 1, 0)
		bottom.Size = UDim2.new(1, 0, 0, thickness)

		left.AnchorPoint = Vector2.new(0, 0.5)
		left.Position = UDim2.new(0, 0, 0.5, 0)
		left.Size = UDim2.new(0, thickness, 1, 0)

		right.AnchorPoint = Vector2.new(1, 0.5)
		right.Position = UDim2.new(1, 0, 0.5, 0)
		right.Size = UDim2.new(0, thickness, 1, 0)
	end

	local function setIntensity(intensity: number)
		intensity = math.clamp(intensity, 0, 1)
		if disabled then
			top.ImageTransparency = 1
			bottom.ImageTransparency = 1
			left.ImageTransparency = 1
			right.ImageTransparency = 1
			return
		end
		-- intensity -> lower transparency (more visible)
		local t = 1 - ((1 - baseAlpha) * intensity)
		top.ImageTransparency = t
		bottom.ImageTransparency = t
		left.ImageTransparency = t
		right.ImageTransparency = t
	end

	local function destroy()
		if dead then return end
		dead = true
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		conns = {}
		pcall(function() if layer then layer:Destroy() end end)
	end

	table.insert(conns, host:GetPropertyChangedSignal("Position"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("Size"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("AnchorPoint"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("Rotation"):Connect(sync))
	table.insert(conns, host:GetPropertyChangedSignal("ZIndex"):Connect(sync))
	table.insert(conns, host.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil then destroy() end
	end))

	sync()
	setIntensity(0)
	return setIntensity, destroy
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
	Muted  = Color3.fromRGB(105, 110, 140),
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
	Destroy: (self: Window) -> (),
	Toggle: (self: Window, state: boolean?) -> (),
	SetKillCallback: (self: Window, killOnClose: boolean, onKill: (() -> ())?) -> (),
	SetToggleKey: (self: Window, key: Enum.KeyCode) -> (),

	ApplyTheme: (self: Window, partial: {[string]: any}) -> (),
	GetTheme: (self: Window) -> Theme,
	GetConfig: (self: Window) -> {[string]: any},
	LoadConfig: (self: Window, cfg: {[string]: any}) -> (),

	AddTab: (self: Window, name: string, icon: string?) -> any,
	SelectTab: (self: Window, name: string) -> (),
	IsKilled: boolean,
}

local WindowMT = {}
WindowMT.__index = WindowMT

local TabMT = {}
TabMT.__index = TabMT

local GroupMT = {}
GroupMT.__index = GroupMT

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
		Name = "SpareStackUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})

	-- Overlay lives at ScreenGui level so dropdowns never get clipped by Root (Root clips descendants)
	local overlay = mk("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2000,
		Parent = gui,
	}) :: Frame

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
	local rootStroke = withUIStroke(root, theme.Stroke, 0.35, 1)

	local rootGrad = mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.BG2),
			ColorSequenceKeypoint.new(1, theme.BG),
		}),
		Parent = root,
	}) :: UIGradient

	local sizeConstraint = mk("UISizeConstraint", {
		MinSize = options.MinSize or Vector2.new(560, 360),
		MaxSize = options.MaxSize or Vector2.new(1400, 900),
		Parent = root,
	}) :: UISizeConstraint
	local origMinSize = sizeConstraint.MinSize

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

	self.SelectedTab = nil
	self._connections = {}
	self._minimized = false
	self._origSize = root.Size
	self._killOnClose = options.KillOnClose == true
	self._onKill = options.OnKill
	self._toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	self._visible = true
	self._minToken = 0

	-- Theme hooks + control registry
	self._themeHooks = {} :: { (Theme) -> () }
	self._controls = {} :: { [string]: {type: string, get: ()->any, set: (any)->()} }

	local function hook(fn: (Theme)->())
		table.insert(self._themeHooks, fn)
	end
	self._hook = hook

	local function runThemeHooks()
		for _, fn in ipairs(self._themeHooks) do
			pcall(fn, self.Theme)
		end
	end

	function self:_registerControl(key: string, typ: string, getFn: ()->any, setFn: (any)->())
		self._controls[key] = { type = typ, get = getFn, set = setFn }
	end

	-- Public theme API
	function WindowMT:GetTheme(): Theme
		return self.Theme
	end
	function WindowMT:ApplyTheme(partial: {[string]: any})
		for k, v in pairs(partial) do
			(self.Theme :: any)[k] = v
		end
		runThemeHooks()
	end

	function WindowMT:GetConfig()
		local out: {[string]: any} = {}
		for k, c in pairs(self._controls) do
			out[k] = c.get()
		end
		return out
	end

	function WindowMT:LoadConfig(cfg: {[string]: any})
		for k, v in pairs(cfg) do
			local c = self._controls[k]
			if c then
				pcall(function() c.set(v) end)
			end
		end
	end

	-- Bind initial theme hooks for main window pieces
	hook(function(th: Theme)
		root.BackgroundColor3 = th.BG
		rootStroke.Color = th.Stroke
		rootGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, th.BG2),
			ColorSequenceKeypoint.new(1, th.BG),
		})
	end)

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
		root.Position = UDim2.fromScale(0.5, 0.5)
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
	local topbarStroke = withUIStroke(topbar, theme.Stroke, 0.25, 1)

	local topbarBottom = mk("Frame", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -14),
		ZIndex = 10,
		Parent = topbar,
	})

	hook(function(th: Theme)
		topbar.BackgroundColor3 = th.Panel2
		topbarBottom.BackgroundColor3 = th.Panel2
		topbarStroke.Color = th.Stroke
	end)

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
	local appIconStroke = withUIStroke(appIcon, theme.Stroke, 0.35, 1)

	local appIconText = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "S",
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextColor3 = theme.Accent,
		ZIndex = 13,
		Parent = appIcon,
	})

	local titleText = mk("TextLabel", {
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

	hook(function(th: Theme)
		appIcon.BackgroundColor3 = th.Panel
		appIconStroke.Color = th.Stroke
		appIconText.TextColor3 = th.Accent
		titleText.TextColor3 = th.Text
	end)

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
		local s = withUIStroke(b, theme.Stroke, 0.35, 1)

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

		hook(function(th: Theme)
			s.Color = th.Stroke
			-- keep base color consistent
			if b.BackgroundColor3 ~= th.Panel then
				b.BackgroundColor3 = th.Panel2
			end
			t.TextColor3 = t.TextColor3 -- hover handles this
		end)

		b.MouseEnter:Connect(function()
			tween(b, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = theme.Panel})
			tween(t, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = theme.Text})
		end)
		b.MouseLeave:Connect(function()
			tween(b, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = theme.Panel2})
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
	local sidebarStroke = withUIStroke(sidebar, theme.Stroke, 0.25, 1)

	hook(function(th: Theme)
		sidebar.BackgroundColor3 = th.Panel2
		sidebarStroke.Color = th.Stroke
	end)

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

	mk("UIListLayout", {
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

	hook(function(th: Theme)
		selectedBar.BackgroundColor3 = th.Accent
	end)

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
	local searchStroke = withUIStroke(searchBox, theme.Stroke, 0.35, 1)
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
		TextSize = 14,
		TextColor3 = theme.Text,
		PlaceholderText = "Search element",
		PlaceholderColor3 = theme.Muted,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
		Parent = searchBox,
	})

	hook(function(th: Theme)
		searchBox.BackgroundColor3 = th.Panel2
		searchStroke.Color = th.Stroke
		searchInput.TextColor3 = th.Text
		searchInput.PlaceholderColor3 = th.Muted
	end)

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
	local canvasStroke = withUIStroke(canvasBg, theme.Stroke, 0.55, 1)
	local canvasGrad = mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.BG2),
			ColorSequenceKeypoint.new(1, theme.BG),
		}),
		Parent = canvasBg,
	}) :: UIGradient

	hook(function(th: Theme)
		canvasBg.BackgroundColor3 = th.BG2
		canvasStroke.Color = th.Stroke
		canvasGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, th.BG2),
			ColorSequenceKeypoint.new(1, th.BG),
		})
	end)

	self._ui = {
		gui = gui,
		overlay = overlay,
		root = root,
		topbar = topbar,
		contentWrap = contentWrap,
		sidebar = sidebar,
		tabList = tabList,
		tabButtons = tabButtons,
		selectedBar = selectedBar,
		tabsContainer = tabsContainer,
		searchInput = searchInput,
		sizeConstraint = sizeConstraint,
		origMinSize = origMinSize,
	}

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
	minimizeBtn.MouseButton1Click:Connect(function() applyMinimize(not self._minimized) end)

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
		if input.KeyCode == self._toggleKey then self:Toggle() end
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

	-- Mobile tweak (already exists)
	if UserInputService.TouchEnabled then
		sidebar.Size = UDim2.new(0, 170, 1, 0)
		mainPanel.Position = UDim2.new(0, 170, 0, 0)
		mainPanel.Size = UDim2.new(1, -170, 1, 0)
	end

	-- Selected bar helper (fixes startup offset too)
	function self:_UpdateSelectedBar(tabObj: any, instant: boolean?)
		local sb: Frame = self._ui.selectedBar
		local tabListAbs = self._ui.tabList.AbsolutePosition

		local barH = 34
		local btnAbs = tabObj._btn.AbsolutePosition
		local btnH = tabObj._btn.AbsoluteSize.Y

		local y = (btnAbs.Y - tabListAbs.Y) + math.floor((btnH - barH) / 2)
		if instant then
			sb.Position = UDim2.new(0, -6, 0, y)
			sb.Size = UDim2.new(0, 3, 0, barH)
		else
			tween(sb, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, -6, 0, y),
				Size = UDim2.new(0, 3, 0, barH),
			})
		end
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

--////////////////////////////////////////////////////////////
-- Tabs
--////////////////////////////////////////////////////////////
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
	local iconImg = makeIcon(iconId, 18, 0.18)
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
		TextColor3 = theme.SubText,
		ZIndex = 3,
		Parent = btn,
	})

	return btn, bg, label, iconImg
end

function WindowMT:AddTab(name: string, icon: string?)
	local theme: Theme = self.Theme
	local btn, bg, label, iconImg = makeSidebarTab(theme, self.IconProvider, name, icon)

	-- theme hooks
	self:_hook(function(th: Theme)
		-- keep inactive look unless selected/hovered
		label.TextColor3 = label.TextColor3
		bg.BackgroundColor3 = th.Panel
	end)

	self._tabCount += 1
	btn.LayoutOrder = self._tabCount
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

	btn.MouseButton1Click:Connect(function() self:SelectTab(name) end)

	btn.MouseEnter:Connect(function()
		if self.SelectedTab ~= tab then
			tween(bg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.55})
			tween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.Text})
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.SelectedTab ~= tab then
			tween(bg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
			tween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.SubText})
		end
	end)

	-- Select first tab + fix initial selected bar position (wait for layout)
	if not self.SelectedTab then
		self:SelectTab(name)
		task.spawn(function()
			RunService.RenderStepped:Wait()
			RunService.RenderStepped:Wait()
			if self.SelectedTab == tab then
				self:_UpdateSelectedBar(tab, true)
			end
		end)
	end

	return tab
end

function WindowMT:SelectTab(name: string)
	local tab = self.Tabs[name]
	if not tab then return end

	for _, t in ipairs(self._tabOrder) do
		t._page.Visible = false
		tween(t._btnBg, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
		tween(t._btnLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.SubText})
		if t._btnIcon then t._btnIcon.ImageTransparency = 0.18 end
	end

	tab._page.Visible = true
	self.SelectedTab = tab

	tween(tab._btnBg, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.40})
	tween(tab._btnLabel, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.Text})
	if tab._btnIcon then tab._btnIcon.ImageTransparency = 0.05 end

	task.spawn(function()
		-- wait for layout to settle, then move bar
		RunService.RenderStepped:Wait()
		self:_UpdateSelectedBar(tab, false)
	end)
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
	local stroke = withUIStroke(frame, theme.Stroke, 0.35, 1)

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
		Padding = UDim.new(0, 8),
		Parent = content,
	})

	mk("Frame", {
		Name = "BottomSpacer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 999999,
		Parent = content,
	})

	return frame, stroke, titleLbl, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP
end

function TabMT:AddGroupbox(title: string, opts: {Side: ("Left"|"Right")?, InitialCollapsed: boolean?}?)
	opts = opts or {}
	local side = opts.Side or "Left"

	local theme: Theme = self._window.Theme
	local frame, stroke, titleLbl, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP =
		makeGroupbox(theme, self._window.IconProvider, title)

	-- theme hooks
	self._window:_hook(function(th: Theme)
		frame.BackgroundColor3 = th.Panel
		stroke.Color = th.Stroke
		titleLbl.TextColor3 = th.Text
		if fallback then fallback.TextColor3 = th.SubText end
	end)

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
-- Controls shared
--////////////////////////////////////////////////////////////
local function makeRow(height: number)
	return mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height)})
end

local function makeControlKey(gbTitle: string, text: string)
	return gbTitle .. " / " .. text
end

--////////////////////////////////////////////////////////////
-- Toggle (4-sided glow only)
--////////////////////////////////////////////////////////////
function GroupMT:AddToggle(text: string, default: boolean?, callback: ((boolean) -> ())?)
	local theme: Theme = self._tab._window.Theme
	local on = default == true

	local row = makeRow(40)
	row.Parent = self._content

	local lbl = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -90, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})

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

	-- 4-sided edge glow (no center glow)
	local setEdgeGlow = addEdgeGlowOutside(track, theme.Accent, 16, 0.90)
	setEdgeGlow(on and 1 or 0)

	local knob = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(20, 20),
		Position = on and UDim2.new(1, -24, 0.5, -10) or UDim2.new(0, 4, 0.5, -10),
		ZIndex = 21,
		Parent = track,
	})
	withUICorner(knob, 999)

	-- theme hooks
	self._tab._window:_hook(function(th: Theme)
		lbl.TextColor3 = th.Text
		if on then
			track.BackgroundColor3 = th.Accent
		else
			track.BackgroundColor3 = th.Stroke
		end
	end)

	local function set(state: boolean)
		on = state
		tween(track, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = on and theme.Accent or theme.Stroke
		})
		tween(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -24, 0.5, -10) or UDim2.new(0, 4, 0.5, -10),
		})
		setEdgeGlow(on and 1 or 0)
		if callback then task.spawn(callback, on) end
	end

	btn.MouseButton1Click:Connect(function() set(not on) end)

	-- register for configs
	local key = makeControlKey(self.Title, text)
	self._tab._window:_registerControl(key, "toggle", function() return on end, function(v: any) set(v == true) end)

	return {Set = set, Get = function() return on end, Key = key}
end

--////////////////////////////////////////////////////////////
-- Slider (NO glow)
--////////////////////////////////////////////////////////////
function GroupMT:AddSlider(text: string, min: number, max: number, default: number?, step: number?, callback: ((number) -> ())?)
	local theme: Theme = self._tab._window.Theme
	step = step or 1
	local value = math.clamp(default or min, min, max)

	local row = makeRow(52)
	row.Parent = self._content

	local lbl = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -80, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})

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

	local bar = mk("Frame", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 8),
		ZIndex = 20,
		Parent = row,
	})
	withUICorner(bar, 999)
	local barStroke = withUIStroke(bar, theme.Stroke, 0.5, 1)

	local fill = mk("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 21,
		Parent = bar,
	})
	withUICorner(fill, 999)

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

	self._tab._window:_hook(function(th: Theme)
		lbl.TextColor3 = th.Text
		valLabel.TextColor3 = th.SubText
		bar.BackgroundColor3 = th.Panel2
		barStroke.Color = th.Stroke
		fill.BackgroundColor3 = th.Accent
	end)

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

	local key = makeControlKey(self.Title, text)
	self._tab._window:_registerControl(key, "slider", function() return value end, function(v: any)
		if typeof(v) == "number" then apply(v, true) end
	end)

	return {Set = function(v: number) apply(v, true) end, Get = function() return value end, Key = key}
end

--////////////////////////////////////////////////////////////
-- Button (NO glow)
--////////////////////////////////////////////////////////////
function GroupMT:AddButton(text: string, callback: (() -> ())?)
	local theme: Theme = self._tab._window.Theme

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
	local stroke = withUIStroke(btn, theme.Stroke, 0.35, 1)

	self._tab._window:_hook(function(th: Theme)
		btn.TextColor3 = th.Text
		btn.BackgroundColor3 = th.Panel2
		stroke.Color = th.Stroke
	end)

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
-- Dropdown helpers (overlay, search, not clipped)
--////////////////////////////////////////////////////////////
local function buildDropdownOverlay(
	window: any,
	anchor: GuiObject,
	title: string,
	options: {string},
	multi: boolean,
	initial: any,
	onChange: (any)->()
)
	local theme: Theme = window.Theme
	local overlay: Frame = window._ui.overlay

	-- click-catcher (close on outside click)
	local catcher = mk("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2000,
		Parent = overlay,
	}) :: TextButton

	local box = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 2001,
		Parent = overlay,
	}) :: Frame
	withUICorner(box, 12)
	local boxStroke = withUIStroke(box, theme.Stroke, 0.25, 1)

	-- position near anchor (screen space)
	local aPos = anchor.AbsolutePosition
	local aSize = anchor.AbsoluteSize
	local w = math.max(260, aSize.X)
	local maxVisible = 7
	local rowH = 32
	local baseH = 42 + 10 + (math.min(#options, maxVisible) * rowH) + (multi and 44 or 0)

	box.Size = UDim2.fromOffset(w, baseH)
	box.Position = UDim2.fromOffset(aPos.X, aPos.Y + aSize.Y + 6)

	-- keep on screen
	do
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			local bx = box.Position.X.Offset
			local by = box.Position.Y.Offset
			if bx + w > vp.X - 10 then
				bx = math.max(10, vp.X - w - 10)
			end
			if by + baseH > vp.Y - 10 then
				by = math.max(10, aPos.Y - baseH - 6)
			end
			box.Position = UDim2.fromOffset(bx, by)
		end
	end

	local header = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		TextSize = 14,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = theme.Text,
		ZIndex = 2002,
		Parent = box,
	})

	local search = mk("TextBox", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 30),
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = theme.Text,
		PlaceholderText = "Search...",
		PlaceholderColor3 = theme.Muted,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2002,
		Parent = box,
	})
	withUICorner(search, 10)
	local searchStroke = withUIStroke(search, theme.Stroke, 0.4, 1)
	mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = search})

	local listFrame = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 70),
		Size = UDim2.new(1, -16, 1, multi and -118 or -78),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.2,
		ZIndex = 2002,
		Parent = box,
	}) :: ScrollingFrame

	local layout = mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = listFrame,
	})

	local function makeOptRow(txt: string)
		local b = mk("TextButton", {
			BackgroundColor3 = theme.Panel2,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, rowH),
			Text = "",
			AutoButtonColor = false,
			ZIndex = 2003,
		})
		withUICorner(b, 10)
		local s = withUIStroke(b, theme.Stroke, 0.45, 1)

		local t = mk("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = txt,
			TextSize = 13,
			Font = Enum.Font.Gotham,
			TextColor3 = theme.Text,
			ZIndex = 2004,
			Parent = b,
		})

		return b, s, t
	end

	local selectedSet: {[string]: boolean} = {}
	local selectedOne: string? = nil

	if multi then
		if typeof(initial) == "table" then
			for _, v in ipairs(initial :: {string}) do
				selectedSet[v] = true
			end
		end
	else
		if typeof(initial) == "string" then
			selectedOne = initial
		end
	end

	local rendered: {TextButton} = {}

	local function close()
		for _, b in ipairs(rendered) do pcall(function() b:Destroy() end) end
		pcall(function() box:Destroy() end)
		pcall(function() catcher:Destroy() end)
	end

	catcher.MouseButton1Click:Connect(close)

	local function commit()
		if multi then
			local out: {string} = {}
			for k, v in pairs(selectedSet) do
				if v then table.insert(out, k) end
			end
			table.sort(out)
			onChange(out)
		else
			onChange(selectedOne)
		end
	end

	local doneBtn: TextButton? = nil
	if multi then
		doneBtn = mk("TextButton", {
			BackgroundColor3 = theme.Panel2,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -24, 0, 34),
			Position = UDim2.new(0, 12, 1, -44),
			Text = "Done",
			TextSize = 14,
			Font = Enum.Font.GothamSemibold,
			TextColor3 = theme.Text,
			AutoButtonColor = false,
			ZIndex = 2002,
			Parent = box,
		})
		withUICorner(doneBtn, 10)
		withUIStroke(doneBtn, theme.Stroke, 0.4, 1)
		doneBtn.MouseButton1Click:Connect(function()
			commit()
			close()
		end)
	end

	local function render()
		for _, b in ipairs(rendered) do pcall(function() b:Destroy() end) end
		rendered = {}

		local q = string.lower(search.Text or "")
		local idx = 0
		for _, opt in ipairs(options) do
			if q == "" or string.find(string.lower(opt), q, 1, true) ~= nil then
				idx += 1
				local b, _, _ = makeOptRow(opt)
				b.LayoutOrder = idx
				b.Parent = listFrame
				table.insert(rendered, b)

				local function refreshRow()
					if multi then
						b.BackgroundTransparency = selectedSet[opt] and 0.15 or 0
					else
						b.BackgroundTransparency = (selectedOne == opt) and 0.15 or 0
					end
				end
				refreshRow()

				b.MouseButton1Click:Connect(function()
					if multi then
						selectedSet[opt] = not selectedSet[opt]
						refreshRow()
					else
						selectedOne = opt
						commit()
						close()
					end
				end)
			end
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(render)

	-- theme hooks (overlay reflects theme changes too)
	window:_hook(function(th: Theme)
		box.BackgroundColor3 = th.Panel
		boxStroke.Color = th.Stroke
		header.TextColor3 = th.Text
		search.BackgroundColor3 = th.Panel2
		search.TextColor3 = th.Text
		search.PlaceholderColor3 = th.Muted
		searchStroke.Color = th.Stroke
		if doneBtn then
			doneBtn.BackgroundColor3 = th.Panel2
			doneBtn.TextColor3 = th.Text
		end
	end)

	render()
end

--////////////////////////////////////////////////////////////
-- Dropdown
--////////////////////////////////////////////////////////////
function GroupMT:AddDropdown(text: string, options: {string}, default: string?, callback: ((string)->())?)
	local theme: Theme = self._tab._window.Theme
	local selected = default or (options[1] or "")

	local row = makeRow(44)
	row.Parent = self._content

	local lbl = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 22),
		Text = selected,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
		ZIndex = 20,
		Parent = row,
	})
	withUICorner(btn, 10)
	local stroke = withUIStroke(btn, theme.Stroke, 0.45, 1)
	mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = btn})

	local chev = resolveIcon(self._tab._window.IconProvider, "lucide:chevron-down")
	local icon = makeIcon(chev, 16, 0.15)
	icon.Parent = btn
	icon.ZIndex = 21
	icon.AnchorPoint = Vector2.new(1, 0.5)
	icon.Position = UDim2.new(1, -8, 0.5, 0)

	self._tab._window:_hook(function(th: Theme)
		lbl.TextColor3 = th.Text
		btn.BackgroundColor3 = th.Panel2
		btn.TextColor3 = th.SubText
		stroke.Color = th.Stroke
	end)

	local function set(v: string)
		selected = v
		btn.Text = v
		if callback then task.spawn(callback, v) end
	end

	btn.MouseButton1Click:Connect(function()
		buildDropdownOverlay(self._tab._window, btn, text, options, false, selected, function(v: any)
			if typeof(v) == "string" then
				set(v)
			end
		end)
	end)

	local key = makeControlKey(self.Title, text)
	self._tab._window:_registerControl(key, "dropdown", function() return selected end, function(v: any)
		if typeof(v) == "string" then set(v) end
	end)

	return {Set = set, Get = function() return selected end, Key = key}
end

--////////////////////////////////////////////////////////////
-- Multi-select Dropdown
--////////////////////////////////////////////////////////////
function GroupMT:AddMultiDropdown(text: string, options: {string}, default: {string}?, callback: (({string})->())?)
	local theme: Theme = self._tab._window.Theme
	local selected: {string} = default or {}

	local function toSet(list: {string})
		local s: {[string]: boolean} = {}
		for _, v in ipairs(list) do s[v] = true end
		return s
	end
	local selSet = toSet(selected)

	local function displayText()
		local out: {string} = {}
		for k, v in pairs(selSet) do if v then table.insert(out, k) end end
		table.sort(out)
		if #out == 0 then return "None" end
		if #out <= 2 then return table.concat(out, ", ") end
		return tostring(#out) .. " selected"
	end

	local row = makeRow(44)
	row.Parent = self._content

	local lbl = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 22),
		Text = displayText(),
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
		ZIndex = 20,
		Parent = row,
	})
	withUICorner(btn, 10)
	local stroke = withUIStroke(btn, theme.Stroke, 0.45, 1)
	mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = btn})

	local chev = resolveIcon(self._tab._window.IconProvider, "lucide:chevron-down")
	local icon = makeIcon(chev, 16, 0.15)
	icon.Parent = btn
	icon.ZIndex = 21
	icon.AnchorPoint = Vector2.new(1, 0.5)
	icon.Position = UDim2.new(1, -8, 0.5, 0)

	self._tab._window:_hook(function(th: Theme)
		lbl.TextColor3 = th.Text
		btn.BackgroundColor3 = th.Panel2
		btn.TextColor3 = th.SubText
		stroke.Color = th.Stroke
	end)

	local function set(list: {string})
		selSet = toSet(list)
		btn.Text = displayText()
		if callback then task.spawn(callback, list) end
	end

	btn.MouseButton1Click:Connect(function()
		-- pass current selection list
		local cur: {string} = {}
		for k, v in pairs(selSet) do if v then table.insert(cur, k) end end
		table.sort(cur)

		buildDropdownOverlay(self._tab._window, btn, text, options, true, cur, function(v: any)
			if typeof(v) == "table" then
				set(v :: {string})
			end
		end)
	end)

	local key = makeControlKey(self.Title, text)
	self._tab._window:_registerControl(key, "multi_dropdown", function()
		local out: {string} = {}
		for k, v in pairs(selSet) do if v then table.insert(out, k) end end
		table.sort(out)
		return out
	end, function(v: any)
		if typeof(v) == "table" then
			set(v :: {string})
		end
	end)

	return {Set = set, Get = function()
		local out: {string} = {}
		for k, v in pairs(selSet) do if v then table.insert(out, k) end end
		table.sort(out)
		return out
	end, Key = key}
end

return UILib
