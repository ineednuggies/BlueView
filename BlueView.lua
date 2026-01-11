--!strict
-- BlueView.lua
-- SpareStackUI / BlueView – Full updated library
--
-- ✅ Autoscale (UIScale + viewport loop) + Mobile support (TouchEnabled sidebar tweak)
-- ✅ Theme binding system: changing Theme.Text updates ALL bound text (tabs + controls + dropdown items)
-- ✅ Toggle glow changed: 4-sided edge glow (top/left/right/bottom) using texture (no center-only glow)
-- ✅ Slider + Button glow removed
-- ✅ Selected tab bar fixed on first run (deferred + layout settle)
-- ✅ Dropdown + MultiDropdown are INLINE (drop down under the control), with Search bars
-- ✅ Textboxes start EMPTY (no "textbox" prefill)
-- ✅ ColorPicker control added (Hue + SV) for scripts + ThemeManager
-- ✅ Config capture supported via window:GetConfig() / window:LoadConfig()

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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

--////////////////////////////////////////////////////////////
-- Glow texture
-- IMPORTANT: set this to YOUR soft glow texture
--////////////////////////////////////////////////////////////
local GLOW_IMG = "rbxassetid://93208570840427" -- set to your glow texture

-- 4-sided edge glow around a host (top/left/right/bottom). Returns setIntensity(0..1), destroy()
local function addEdgeGlow(host: GuiObject, color: Color3, thicknessPx: number, alpha: number)
	local disabled = (GLOW_IMG == "" or GLOW_IMG == "rbxassetid://0")
	local parent = host.Parent
	if not parent or not parent:IsA("GuiObject") then
		local function noop(_: number) end
		return noop, function() end
	end

	local layer = mk("Frame", {
		Name = "EdgeGlow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = math.max(1, host.ZIndex - 1),
		ClipsDescendants = false,
		Parent = parent,
	}) :: Frame

	local function edge(z: number)
		return mk("ImageLabel", {
			BackgroundTransparency = 1,
			Image = GLOW_IMG,
			ImageColor3 = color,
			ImageTransparency = alpha,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = z,
			Parent = layer,
		}) :: ImageLabel
	end

	local top = edge(layer.ZIndex)
	local bottom = edge(layer.ZIndex)
	local left = edge(layer.ZIndex)
	local right = edge(layer.ZIndex)

	local dead = false
	local conns: {RBXScriptConnection} = {}

	local function sync()
		if dead then return end
		if not host.Parent or host.Parent ~= parent then return end

		layer.AnchorPoint = host.AnchorPoint
		layer.Rotation = host.Rotation

		local hs = host.Size
		layer.Size = hs

		local hp = host.Position
		layer.Position = hp

		layer.ZIndex = math.max(1, host.ZIndex - 1)
		top.ZIndex = layer.ZIndex
		bottom.ZIndex = layer.ZIndex
		left.ZIndex = layer.ZIndex
		right.ZIndex = layer.ZIndex

		-- 4 sides (slightly outside)
		local t = thicknessPx
		top.AnchorPoint = Vector2.new(0.5, 1)
		top.Position = UDim2.new(0.5, 0, 0, 0)
		top.Size = UDim2.new(1, t * 2, 0, t * 2)

		bottom.AnchorPoint = Vector2.new(0.5, 0)
		bottom.Position = UDim2.new(0.5, 0, 1, 0)
		bottom.Size = UDim2.new(1, t * 2, 0, t * 2)
		bottom.Rotation = 180

		left.AnchorPoint = Vector2.new(1, 0.5)
		left.Position = UDim2.new(0, 0, 0.5, 0)
		left.Size = UDim2.new(0, t * 2, 1, t * 2)
		left.Rotation = -90

		right.AnchorPoint = Vector2.new(0, 0.5)
		right.Position = UDim2.new(1, 0, 0.5, 0)
		right.Size = UDim2.new(0, t * 2, 1, t * 2)
		right.Rotation = 90
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
		local it = 1 - ((1 - alpha) * intensity)
		top.ImageTransparency = it
		bottom.ImageTransparency = it
		left.ImageTransparency = it
		right.ImageTransparency = it
	end

	local function destroy()
		if dead then return end
		dead = true
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		conns = {}
		pcall(function() layer:Destroy() end)
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

local function themeClone(t: Theme): Theme
	local out: {[string]: any} = {}
	for k, v in pairs(t :: any) do
		out[k] = v
	end
	return out :: any
end

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
	AddTab: (self: Window, name: string, icon: string?) -> any,
	SelectTab: (self: Window, name: string) -> (),
	GetTheme: (self: Window) -> Theme,
	SetTheme: (self: Window, partial: {[string]: any}) -> (),
	GetConfig: (self: Window) -> {[string]: any},
	LoadConfig: (self: Window, cfg: {[string]: any}) -> (),
	IsKilled: boolean,
	Tabs: {[string]: any},
}

local WindowMT = {}
WindowMT.__index = WindowMT

local TabMT = {}
TabMT.__index = TabMT

local GroupMT = {}
GroupMT.__index = GroupMT

--////////////////////////////////////////////////////////////
-- Theme bindings + Config registry
--////////////////////////////////////////////////////////////
type ThemeBinding =
	{ kind: "prop", inst: Instance, prop: string, key: string }
	| { kind: "fn", apply: (theme: Theme) -> () }

type ControlEntry = {
	get: () -> any,
	set: (any) -> (),
}

function WindowMT:GetTheme(): Theme
	return self.Theme
end

function WindowMT:_BindThemeProp(inst: Instance, prop: string, key: string)
	self._themeBindings = self._themeBindings or {}
	table.insert(self._themeBindings, { kind = "prop", inst = inst, prop = prop, key = key } :: any)
	;(inst :: any)[prop] = (self.Theme :: any)[key]
end

function WindowMT:_BindThemeFn(apply: (theme: Theme) -> ())
	self._themeBindings = self._themeBindings or {}
	table.insert(self._themeBindings, { kind = "fn", apply = apply } :: any)
	apply(self.Theme)
end

function WindowMT:SetTheme(partial: {[string]: any})
	for k, v in pairs(partial) do
		(self.Theme :: any)[k] = v
	end

	local binds: {ThemeBinding} = self._themeBindings or {}
	for _, b in ipairs(binds) do
		if (b :: any).kind == "prop" then
			local bb = b :: any
			if bb.inst and bb.inst.Parent then
				(bb.inst :: any)[bb.prop] = (self.Theme :: any)[bb.key]
			end
		else
			local bf = b :: any
			pcall(function() bf.apply(self.Theme) end)
		end
	end
end

function WindowMT:_RegisterControl(id: string, get: () -> any, set: (any) -> ())
	self._controls = self._controls or {}
	self._controls[id] = { get = get, set = set }
end

function WindowMT:GetConfig(): {[string]: any}
	local out: {[string]: any} = {}
	local ctrls: {[string]: ControlEntry} = self._controls or {}
	for id, e in pairs(ctrls) do
		local ok, v = pcall(e.get)
		if ok then out[id] = v end
	end
	return out
end

function WindowMT:LoadConfig(cfg: {[string]: any})
	local ctrls: {[string]: ControlEntry} = self._controls or {}
	for id, v in pairs(cfg) do
		local e = ctrls[id]
		if e then
			pcall(function() e.set(v) end)
		end
	end
end

--////////////////////////////////////////////////////////////
-- Window
--////////////////////////////////////////////////////////////
function UILib.new(options: WindowOptions): Window
	options = options or {}
	local theme = themeClone(options.Theme or DefaultTheme)
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

	local bgGrad = mk("UIGradient", {
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

	-- Window state table
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

	self._themeBindings = {}
	self._controls = {}

	-- Theme-bind root/background/strokes
	self:_BindThemeProp(root, "BackgroundColor3", "BG")
	self:_BindThemeProp((root:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")
	self:_BindThemeFn(function(t: Theme)
		bgGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, t.BG2),
			ColorSequenceKeypoint.new(1, t.BG),
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
	withUIStroke(topbar, theme.Stroke, 0.25, 1)

	self:_BindThemeProp(topbar, "BackgroundColor3", "Panel2")
	self:_BindThemeProp((topbar:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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

	self:_BindThemeProp(appIcon, "BackgroundColor3", "Panel")
	self:_BindThemeProp((appIcon:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local appIconText = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "B",
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextColor3 = theme.Accent,
		ZIndex = 13,
		Parent = appIcon,
	})
	self:_BindThemeProp(appIconText, "TextColor3", "Accent")

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
	self:_BindThemeProp(titleLabel, "TextColor3", "Text")

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

		self:_BindThemeProp(b, "BackgroundColor3", "Panel2")
		self:_BindThemeProp((b:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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
		self:_BindThemeProp(t, "TextColor3", "SubText")

		b.MouseEnter:Connect(function()
			tween(t, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.Text})
		end)
		b.MouseLeave:Connect(function()
			tween(t, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextColor3 = self.Theme.SubText})
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
	self:_BindThemeProp(sidebar, "BackgroundColor3", "Panel2")
	self:_BindThemeProp((sidebar:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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
	self:_BindThemeProp(selectedBar, "BackgroundColor3", "Accent")

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
	self:_BindThemeProp(searchBox, "BackgroundColor3", "Panel2")
	self:_BindThemeProp((searchBox:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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
	self:_BindThemeProp(searchInput, "TextColor3", "Text")
	self:_BindThemeProp(searchInput, "PlaceholderColor3", "Muted")

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

	self:_BindThemeProp(canvasBg, "BackgroundColor3", "BG2")
	self:_BindThemeProp((canvasBg:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local canvasGrad = mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.BG2),
			ColorSequenceKeypoint.new(1, theme.BG),
		}),
		Parent = canvasBg,
	})
	self:_BindThemeFn(function(t: Theme)
		canvasGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, t.BG2),
			ColorSequenceKeypoint.new(1, t.BG),
		})
	end)

	self._ui = {
		gui = gui,
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

	-- Minimize / Shrink (works)
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

	-- Search filter (groupboxes by title)
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
local function makeSidebarTab(window: any, name: string, icon: string?)
	local theme: Theme = window.Theme
	local iconProvider: IconProvider? = window.IconProvider

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
	window:_BindThemeProp(bg, "BackgroundColor3", "Panel")

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
	window:_BindThemeProp(label, "TextColor3", "SubText")

	return btn, bg, label, iconImg
end

function WindowMT:AddTab(name: string, icon: string?)
	local theme: Theme = self.Theme
	local btn, bg, label, iconImg = makeSidebarTab(self, name, icon)

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

	-- ✅ First-run selection after layout settles (fix bar offset / missing)
	if not self.SelectedTab then
		task.defer(function()
			task.wait(0.05)
			self:SelectTab(name)
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

	-- ✅ bar uses absolute positions, but wait for layout + render
	task.defer(function()
		task.wait(0.05)
		local sb: Frame = self._ui.selectedBar
		local holder: Frame = self._ui.tabButtons

		local barH = 34
		local btnAbs = tab._btn.AbsolutePosition
		local holderAbs = holder.AbsolutePosition
		local btnH = tab._btn.AbsoluteSize.Y

		local y = (btnAbs.Y - holderAbs.Y) + math.floor((btnH - barH) / 2)
		tween(sb, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, -6, 0, y),
			Size = UDim2.new(0, 3, 0, barH),
		})
	end)
end

--////////////////////////////////////////////////////////////
-- Groupbox
--////////////////////////////////////////////////////////////
local function makeGroupbox(window: any, title: string)
	local theme: Theme = window.Theme
	local iconProvider = window.IconProvider

	local frame = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 60),
		ClipsDescendants = true,
	})
	withUICorner(frame, 12)
	withUIStroke(frame, theme.Stroke, 0.35, 1)

	window:_BindThemeProp(frame, "BackgroundColor3", "Panel")
	window:_BindThemeProp((frame:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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
	window:_BindThemeProp(titleLabel, "TextColor3", "Text")

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
	window:_BindThemeProp(fallback, "TextColor3", "SubText")

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

	return frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP
end

function TabMT:AddGroupbox(title: string, opts: {Side: ("Left"|"Right")?, InitialCollapsed: boolean?}?)
	opts = opts or {}
	local side = opts.Side or "Left"

	local window = self._window
	local frame, contentMask, content, list, collapseBtn, icon, fallback, chevronDown, chevronRight, PAD, GAP =
		makeGroupbox(window, title)

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

local function makeControlId(group: any, labelText: string): string
	local tabName = group._tab.Name
	local gbTitle = group.Title or "Group"
	return tabName .. "/" .. gbTitle .. "/" .. labelText
end

--////////////////////////////////////////////////////////////
-- Toggle (4-edge glow)
--////////////////////////////////////////////////////////////
function GroupMT:AddToggle(text: string, default: boolean?, callback: ((boolean) -> ())?)
	local window = self._tab._window
	local theme: Theme = window.Theme
	local on = default == true

	local row = makeRow(40)
	row.Parent = self._content
	row.LayoutOrder = (row.LayoutOrder == 0 and 0) or row.LayoutOrder

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
	window:_BindThemeProp(label, "TextColor3", "Text")

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
	window:_BindThemeFn(function(t: Theme)
		if on then track.BackgroundColor3 = t.Accent else track.BackgroundColor3 = t.Stroke end
	end)

	-- ✅ 4-sided edge glow (no center glow)
	local setGlow = addEdgeGlow(track, theme.Accent, 10, 0.85)
	setGlow(on and 1 or 0)
	window:_BindThemeFn(function(t: Theme)
		-- recolor glow by destroying and recreating would be heavy; simplest: update ImageColor3
		for _, child in ipairs(track.Parent:GetChildren()) do
			if child:IsA("Frame") and child.Name == "EdgeGlow" then
				for _, img in ipairs(child:GetChildren()) do
					if img:IsA("ImageLabel") then img.ImageColor3 = t.Accent end
				end
			end
		end
	end)

	local knob = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(20, 20),
		Position = on and UDim2.new(1, -24, 0.5, -10) or UDim2.new(0, 4, 0.5, -10),
		ZIndex = 21,
		Parent = track,
	})
	withUICorner(knob, 999)

	local function set(state: boolean)
		on = state
		tween(track, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = on and window.Theme.Accent or window.Theme.Stroke
		})
		tween(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -24, 0.5, -10) or UDim2.new(0, 4, 0.5, -10),
		})
		setGlow(on and 1 or 0)
		if callback then task.spawn(callback, on) end
	end

	btn.MouseButton1Click:Connect(function() set(not on) end)

	local id = makeControlId(self, text)
	window:_RegisterControl(id, function() return on end, function(v: any) set(v == true) end)

	return {Set = set, Get = function() return on end}
end

--////////////////////////////////////////////////////////////
-- Slider (NO glow)
--////////////////////////////////////////////////////////////
function GroupMT:AddSlider(text: string, min: number, max: number, default: number?, step: number?, callback: ((number) -> ())?)
	local window = self._tab._window
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
	window:_BindThemeProp(label, "TextColor3", "Text")

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
	window:_BindThemeProp(valLabel, "TextColor3", "SubText")

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
	window:_BindThemeProp(bar, "BackgroundColor3", "Panel2")
	window:_BindThemeProp((bar:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local fill = mk("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 21,
		Parent = bar,
	})
	withUICorner(fill, 999)
	window:_BindThemeProp(fill, "BackgroundColor3", "Accent")

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

	local id = makeControlId(self, text)
	window:_RegisterControl(id, function() return value end, function(v: any) apply(tonumber(v) or value, true) end)

	return {Set = function(v: number) apply(v, true) end, Get = function() return value end}
end

--////////////////////////////////////////////////////////////
-- Button (NO glow)
--////////////////////////////////////////////////////////////
function GroupMT:AddButton(text: string, callback: (() -> ())?)
	local window = self._tab._window
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

	window:_BindThemeProp(btn, "BackgroundColor3", "Panel2")
	window:_BindThemeProp(btn, "TextColor3", "Text")
	window:_BindThemeProp((btn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

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
-- Textbox (starts EMPTY)
--////////////////////////////////////////////////////////////
function GroupMT:AddTextbox(labelText: string, placeholder: string?, callback: ((string) -> ())?)
	local window = self._tab._window
	local theme: Theme = window.Theme

	local row = makeRow(52)
	row.Parent = self._content

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})
	window:_BindThemeProp(label, "TextColor3", "Text")

	local box = mk("TextBox", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "", -- ✅ empty
		PlaceholderText = placeholder or "",
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	withUICorner(box, 10)
	withUIStroke(box, theme.Stroke, 0.45, 1)
	mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = box})

	window:_BindThemeProp(box, "BackgroundColor3", "Panel2")
	window:_BindThemeProp(box, "TextColor3", "Text")
	window:_BindThemeProp(box, "PlaceholderColor3", "Muted")
	window:_BindThemeProp((box:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if callback then task.spawn(callback, box.Text) end
	end)

	local id = makeControlId(self, labelText)
	window:_RegisterControl(id, function() return box.Text end, function(v: any) box.Text = tostring(v or "") end)

	return {Set = function(v: string) box.Text = v end, Get = function() return box.Text end, Box = box}
end

--////////////////////////////////////////////////////////////
-- Dropdowns (INLINE drop-down panel under the control) + Search
-- MultiDropdown uses checkboxes (no "Done" button).
--////////////////////////////////////////////////////////////
local function makeCheck(theme: Theme, iconProvider: IconProvider?, window: any)
	local box = mk("Frame", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 18),
	})
	withUICorner(box, 5)
	withUIStroke(box, theme.Stroke, 0.35, 1)

	window:_BindThemeProp(box, "BackgroundColor3", "Panel2")
	window:_BindThemeProp((box:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local checkId = resolveIcon(iconProvider, "lucide:check")
	local img = mk("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = checkId or "",
		ImageTransparency = 0.05,
		Visible = (checkId ~= nil),
		Parent = box,
	})

	local fallback = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "✓",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextColor3 = theme.Text,
		Visible = (checkId == nil),
		Parent = box,
	})
	window:_BindThemeProp(fallback, "TextColor3", "Text")

	return box, img, fallback
end

function GroupMT:AddDropdown(labelText: string, options: {string}, default: string?, callback: ((string) -> ())?)
	local window = self._tab._window
	local theme: Theme = window.Theme
	local iconProvider = window.IconProvider

	local opts: {string} = table.clone(options)
	local value = default or opts[1] or ""

	local row = makeRow(52)
	row.Parent = self._content

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})
	window:_BindThemeProp(label, "TextColor3", "Text")

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(btn, 10)
	withUIStroke(btn, theme.Stroke, 0.45, 1)
	window:_BindThemeProp(btn, "BackgroundColor3", "Panel2")
	window:_BindThemeProp((btn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local selected = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -36, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = value,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = btn,
	})
	window:_BindThemeProp(selected, "TextColor3", "Text")

	local chevId = resolveIcon(iconProvider, "lucide:chevron-down")
	local chev = mk("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Image = chevId or "",
		ImageTransparency = 0.15,
		Parent = btn,
	})
	local chevFallback = mk("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Text = "v",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextColor3 = theme.SubText,
		Visible = (chevId == nil),
		Parent = btn,
	})
	window:_BindThemeProp(chevFallback, "TextColor3", "SubText")

	-- inline panel (pushes layout)
	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		Parent = self._content,
	})
	panel.LayoutOrder = row.LayoutOrder + 1
	withUICorner(panel, 10)
	withUIStroke(panel, theme.Stroke, 0.45, 1)
	window:_BindThemeProp(panel, "BackgroundColor3", "Panel")
	window:_BindThemeProp((panel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	mk("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = panel,
	})

	local search = mk("TextBox", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 26),
		Text = "", -- ✅ empty
		PlaceholderText = "Search...",
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	withUICorner(search, 10)
	withUIStroke(search, theme.Stroke, 0.45, 1)
	mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = search})
	window:_BindThemeProp(search, "BackgroundColor3", "Panel2")
	window:_BindThemeProp(search, "TextColor3", "Text")
	window:_BindThemeProp(search, "PlaceholderColor3", "Muted")
	window:_BindThemeProp((search:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local listFrame = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 140),
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		Parent = panel,
	})

	local ll = mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = listFrame,
	})

	local open = false

	local function computeHeight()
		local itemsH = math.min(180, ll.AbsoluteContentSize.Y)
		return 8 + 26 + 8 + itemsH + 8
	end

	local function setOpen(state: boolean)
		open = state
		tween(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 0, open and computeHeight() or 0)
		})
	end

	local function rebuild(filter: string)
		filter = string.lower(filter)
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end

		for i, opt in ipairs(opts) do
			if filter == "" or string.find(string.lower(opt), filter, 1, true) then
				local item = mk("TextButton", {
					BackgroundColor3 = theme.Panel2,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 28),
					Text = "",
					AutoButtonColor = false,
					LayoutOrder = i,
					Parent = listFrame,
				})
				withUICorner(item, 10)
				withUIStroke(item, theme.Stroke, 0.5, 1)
				window:_BindThemeProp(item, "BackgroundColor3", "Panel2")
				window:_BindThemeProp((item:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

				local txt = mk("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 10, 0, 0),
					Size = UDim2.new(1, -10, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = opt,
					TextSize = 14,
					Font = Enum.Font.Gotham,
					TextColor3 = theme.Text,
					Parent = item,
				})
				window:_BindThemeProp(txt, "TextColor3", "Text")

				item.MouseButton1Click:Connect(function()
					value = opt
					selected.Text = value
					setOpen(false)
					if callback then task.spawn(callback, value) end
				end)
			end
		end

		if open then setOpen(true) end
	end

	rebuild("")
	search:GetPropertyChangedSignal("Text"):Connect(function()
		rebuild(search.Text or "")
	end)

	btn.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	local function set(v: string)
		value = v
		selected.Text = value
		if callback then task.spawn(callback, value) end
	end

	local control = {} :: any
	function control.Set(v: string) set(v) end
	function control.Get(): string return value end
	function control.SetOptions(newOptions: {string})
		opts = table.clone(newOptions)
		if table.find(opts, value) == nil then
			value = opts[1] or ""
			selected.Text = value
		end
		rebuild(search.Text or "")
	end

	local id = makeControlId(self, labelText)
	window:_RegisterControl(id, function() return value end, function(v: any) set(tostring(v or "")) end)

	return control
end

function GroupMT:AddMultiDropdown(labelText: string, options: {string}, default: {string}?, callback: (({string}) -> ())?)
	local window = self._tab._window
	local theme: Theme = window.Theme
	local iconProvider = window.IconProvider

	local opts: {string} = table.clone(options)
	local selectedSet: {[string]: boolean} = {}
	for _, v in ipairs(default or {}) do selectedSet[v] = true end

	local function getSelectedList(): {string}
		local out = {}
		for _, opt in ipairs(opts) do
			if selectedSet[opt] then table.insert(out, opt) end
		end
		return out
	end

	local function summary(): string
		local list = getSelectedList()
		if #list == 0 then return "None" end
		if #list <= 3 then return table.concat(list, ", ") end
		return tostring(#list) .. " selected"
	end

	local row = makeRow(52)
	row.Parent = self._content

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})
	window:_BindThemeProp(label, "TextColor3", "Text")

	local btn = mk("TextButton", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(btn, 10)
	withUIStroke(btn, theme.Stroke, 0.45, 1)
	window:_BindThemeProp(btn, "BackgroundColor3", "Panel2")
	window:_BindThemeProp((btn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local selectedLabel = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -10, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = summary(),
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = btn,
	})
	window:_BindThemeProp(selectedLabel, "TextColor3", "Text")

	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		Parent = self._content,
	})
	panel.LayoutOrder = row.LayoutOrder + 1
	withUICorner(panel, 10)
	withUIStroke(panel, theme.Stroke, 0.45, 1)
	window:_BindThemeProp(panel, "BackgroundColor3", "Panel")
	window:_BindThemeProp((panel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	mk("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = panel,
	})

	local search = mk("TextBox", {
		BackgroundColor3 = theme.Panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 26),
		Text = "", -- ✅ empty
		PlaceholderText = "Search...",
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	withUICorner(search, 10)
	withUIStroke(search, theme.Stroke, 0.45, 1)
	mk("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = search})
	window:_BindThemeProp(search, "BackgroundColor3", "Panel2")
	window:_BindThemeProp(search, "TextColor3", "Text")
	window:_BindThemeProp(search, "PlaceholderColor3", "Muted")
	window:_BindThemeProp((search:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local listFrame = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 160),
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		Parent = panel,
	})

	local ll = mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = listFrame,
	})

	local open = false
	local function computeHeight()
		local itemsH = math.min(200, ll.AbsoluteContentSize.Y)
		return 8 + 26 + 8 + itemsH + 8
	end

	local function setOpen(state: boolean)
		open = state
		tween(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 0, open and computeHeight() or 0)
		})
	end

	local function fire()
		selectedLabel.Text = summary()
		if callback then task.spawn(callback, getSelectedList()) end
	end

	local function rebuild(filter: string)
		filter = string.lower(filter)
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end

		for i, opt in ipairs(opts) do
			if filter == "" or string.find(string.lower(opt), filter, 1, true) then
				local item = mk("TextButton", {
					BackgroundColor3 = theme.Panel2,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 30),
					Text = "",
					AutoButtonColor = false,
					LayoutOrder = i,
					Parent = listFrame,
				})
				withUICorner(item, 10)
				withUIStroke(item, theme.Stroke, 0.5, 1)
				window:_BindThemeProp(item, "BackgroundColor3", "Panel2")
				window:_BindThemeProp((item:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

				local txt = mk("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 10, 0, 0),
					Size = UDim2.new(1, -38, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = opt,
					TextSize = 14,
					Font = Enum.Font.Gotham,
					TextColor3 = theme.Text,
					Parent = item,
				})
				window:_BindThemeProp(txt, "TextColor3", "Text")

				local cb, img, fb = makeCheck(theme, iconProvider, window)
				cb.AnchorPoint = Vector2.new(1, 0.5)
				cb.Position = UDim2.new(1, -10, 0.5, 0)
				cb.Parent = item

				local function setChecked(on: boolean)
					selectedSet[opt] = on
					if img then img.Visible = on end
					if fb then fb.Visible = on end
					fire()
				end

				setChecked(selectedSet[opt] == true)

				item.MouseButton1Click:Connect(function()
					setChecked(not (selectedSet[opt] == true))
				end)
			end
		end

		if open then setOpen(true) end
	end

	rebuild("")
	search:GetPropertyChangedSignal("Text"):Connect(function()
		rebuild(search.Text or "")
	end)

	btn.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	local function set(list: {string})
		selectedSet = {}
		for _, v in ipairs(list) do selectedSet[v] = true end
		rebuild(search.Text or "")
		fire()
	end

	local control = {} :: any
	function control.Set(list: {string}) set(list) end
	function control.Get(): {string} return getSelectedList() end
	function control.SetOptions(newOptions: {string})
		opts = table.clone(newOptions)
		-- remove invalid selections
		local valid: {[string]: boolean} = {}
		for _, o in ipairs(opts) do valid[o] = true end
		for k in pairs(selectedSet) do
			if not valid[k] then selectedSet[k] = nil end
		end
		rebuild(search.Text or "")
		fire()
	end

	local id = makeControlId(self, labelText)
	window:_RegisterControl(id, function() return getSelectedList() end, function(v: any)
		if typeof(v) == "table" then
			set(v :: any)
		end
	end)

	return control
end

--////////////////////////////////////////////////////////////
-- ColorPicker (Hue + SV) INLINE
--////////////////////////////////////////////////////////////
local function hsvToColor(h: number, s: number, v: number): Color3
	return Color3.fromHSV(math.clamp(h, 0, 1), math.clamp(s, 0, 1), math.clamp(v, 0, 1))
end

local function colorToHSV(c: Color3): (number, number, number)
	local h, s, v = c:ToHSV()
	return h, s, v
end

function GroupMT:AddColorPicker(labelText: string, default: Color3?, callback: ((Color3) -> ())?)
	local window = self._tab._window
	local theme: Theme = window.Theme

	local h, s, v = colorToHSV(default or theme.Accent)
	local current = hsvToColor(h, s, v)

	local row = makeRow(52)
	row.Parent = self._content

	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = theme.Text,
		Parent = row,
	})
	window:_BindThemeProp(label, "TextColor3", "Text")

	local swatchBtn = mk("TextButton", {
		BackgroundColor3 = current,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(44, 18),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	withUICorner(swatchBtn, 8)
	withUIStroke(swatchBtn, theme.Stroke, 0.35, 1)
	window:_BindThemeProp((swatchBtn:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	local panel = mk("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		Parent = self._content,
	})
	panel.LayoutOrder = row.LayoutOrder + 1
	withUICorner(panel, 10)
	withUIStroke(panel, theme.Stroke, 0.45, 1)
	window:_BindThemeProp(panel, "BackgroundColor3", "Panel")
	window:_BindThemeProp((panel:FindFirstChildOfClass("UIStroke") :: UIStroke), "Color", "Stroke")

	mk("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = panel,
	})

	local open = false
	local PANEL_H = 150

	local sv = mk("Frame", {
		BackgroundColor3 = hsvToColor(h, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(190, 120),
		Parent = panel,
	})
	withUICorner(sv, 10)

	local svGrad = mk("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), hsvToColor(h, 1, 1)),
		Rotation = 0,
		Parent = sv,
	})

	local vOverlay = mk("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = sv,
	})
	withUICorner(vOverlay, 10)
	mk("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Rotation = 90,
		Parent = vOverlay,
	})

	local svCursor = mk("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(10, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = sv,
	})
	withUICorner(svCursor, 999)
	withUIStroke(svCursor, Color3.new(0, 0, 0), 0.25, 2)

	local hue = mk("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 200, 0, 0),
		Size = UDim2.fromOffset(18, 120),
		Parent = panel,
	})
	withUICorner(hue, 10)

	mk("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,   0,   0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255,   0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(  0, 255,   0)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(  0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(  0,   0, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255,   0, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255,   0,   0)),
		}),
		Parent = hue,
	})

	local hueCursor = mk("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = hue,
	})
	withUICorner(hueCursor, 999)
	withUIStroke(hueCursor, Color3.new(0, 0, 0), 0.35, 2)

	local function applyColor(fire: boolean)
		current = hsvToColor(h, s, v)
		swatchBtn.BackgroundColor3 = current
		if fire and callback then task.spawn(callback, current) end
	end

	local function setSVFromMouse(x: number, y: number)
		local ap = sv.AbsolutePosition
		local as = sv.AbsoluteSize
		local rx = math.clamp((x - ap.X) / as.X, 0, 1)
		local ry = math.clamp((y - ap.Y) / as.Y, 0, 1)
		s = rx
		v = 1 - ry
		svCursor.Position = UDim2.new(rx, 0, ry, 0)
		applyColor(true)
	end

	local function setHFromMouse(y: number)
		local ap = hue.AbsolutePosition
		local as = hue.AbsoluteSize
		local ry = math.clamp((y - ap.Y) / as.Y, 0, 1)
		h = ry
		hueCursor.Position = UDim2.new(0, 0, ry, 0)
		sv.BackgroundColor3 = hsvToColor(h, 1, 1)
		svGrad.Color = ColorSequence.new(Color3.new(1,1,1), hsvToColor(h, 1, 1))
		applyColor(true)
	end

	svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
	hueCursor.Position = UDim2.new(0, 0, h, 0)

	local draggingSV = false
	local draggingH = false

	sv.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSV = true
			setSVFromMouse(input.Position.X, input.Position.Y)
		end
	end)
	sv.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSV = false
		end
	end)

	hue.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingH = true
			setHFromMouse(input.Position.Y)
		end
	end)
	hue.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingH = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			if draggingSV then setSVFromMouse(input.Position.X, input.Position.Y) end
			if draggingH then setHFromMouse(input.Position.Y) end
		end
	end)

	local function setOpen(state: boolean)
		open = state
		tween(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 0, open and PANEL_H or 0)
		})
	end

	swatchBtn.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	local id = makeControlId(self, labelText)
	window:_RegisterControl(id, function()
		return { current.R, current.G, current.B }
	end, function(vAny: any)
		if typeof(vAny) == "table" and #vAny >= 3 then
			local c = Color3.new(vAny[1], vAny[2], vAny[3])
			h, s, v = colorToHSV(c)
			sv.BackgroundColor3 = hsvToColor(h, 1, 1)
			svGrad.Color = ColorSequence.new(Color3.new(1,1,1), hsvToColor(h, 1, 1))
			svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
			hueCursor.Position = UDim2.new(0, 0, h, 0)
			applyColor(true)
		end
	end)

	return {
		Set = function(c: Color3)
			h, s, v = colorToHSV(c)
			sv.BackgroundColor3 = hsvToColor(h, 1, 1)
			svGrad.Color = ColorSequence.new(Color3.new(1,1,1), hsvToColor(h, 1, 1))
			svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
			hueCursor.Position = UDim2.new(0, 0, h, 0)
			applyColor(true)
		end,
		Get = function(): Color3
			return current
		end
	}
end

return UILib
