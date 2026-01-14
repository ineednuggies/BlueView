--!strict
-- ConfigManager.lua
-- Saves/loads BlueView flags to the executor workspace folder when available.
-- Supports: toggles, sliders, dropdowns, multi dropdowns, color pickers, plus theme flags if you include them.
-- Requires:
--   window:RegisterFlag(flag, getter, setter) in BlueView
--   window:CollectConfig() and window:ApplyConfig(table)

local HttpService = game:GetService("HttpService")

local ConfigManager = {}
ConfigManager.__index = ConfigManager

type Window = any
type Tab = any

local function hasFileIO(): boolean
	return (typeof(writefile) == "function") and (typeof(readfile) == "function") and (typeof(isfile) == "function") and (typeof(makefolder) == "function")
end

local function safeFolder(path: string)
	if hasFileIO() then
		if not isfolder(path) then
			makefolder(path)
		end
	end
end

local function jsonEncode(t: any): string
	return HttpService:JSONEncode(t)
end
local function jsonDecode(s: string): any
	return HttpService:JSONDecode(s)
end

function ConfigManager.new()
	local self = setmetatable({}, ConfigManager)
	self.Folder = "BlueView"
	self.SubFolder = "configs"
	self.Window = nil :: Window?
	return self
end

function ConfigManager:SetFolder(folder: string)
	self.Folder = folder
end

function ConfigManager:SetWindow(window: Window)
	self.Window = window
end

function ConfigManager:_basePath(): string
	return self.Folder .. "/" .. self.SubFolder
end

function ConfigManager:_filePath(name: string): string
	return self:_basePath() .. "/" .. name .. ".json"
end

function ConfigManager:List(): {string}
	local out = {}
	if not hasFileIO() then
		return out
	end
	safeFolder(self.Folder)
	safeFolder(self:_basePath())
	local files = listfiles(self:_basePath())
	for _, f in ipairs(files) do
		local n = string.match(f, "([^/\\]+)%.json$")
		if n then table.insert(out, n) end
	end
	table.sort(out)
	return out
end

function ConfigManager:Save(name: string): boolean
	if not self.Window then return false end
	if not hasFileIO() then return false end
	if name == nil or name == "" then return false end

	safeFolder(self.Folder)
	safeFolder(self:_basePath())

	local data = self.Window:CollectConfig()
	local ok, encoded = pcall(jsonEncode, data)
	if not ok then return false end

	writefile(self:_filePath(name), encoded)
	return true
end

function ConfigManager:Load(name: string): boolean
	if not self.Window then return false end
	if not hasFileIO() then return false end
	local path = self:_filePath(name)
	if not isfile(path) then return false end

	local raw = readfile(path)
	local ok, decoded = pcall(jsonDecode, raw)
	if not ok then return false end

	self.Window:ApplyConfig(decoded)
	return true
end

function ConfigManager:Delete(name: string): boolean
	if not hasFileIO() then return false end
	local path = self:_filePath(name)
	if isfile(path) then
		delfile(path)
		return true
	end
	return false
end

function ConfigManager:Rename(oldName: string, newName: string): boolean
	if not hasFileIO() then return false end
	local oldPath = self:_filePath(oldName)
	local newPath = self:_filePath(newName)
	if not isfile(oldPath) then return false end
	if isfile(newPath) then return false end
	writefile(newPath, readfile(oldPath))
	delfile(oldPath)
	return true
end

-- Builds a UI in a tab for end-users to manage configs
function ConfigManager:BuildConfigMenu(window: Window, tab: Tab, side: string?)
	side = side or "Right"
	self:SetWindow(window)

	local gb = tab:AddGroupbox("Config", {Side = side})
	local configs = self:List()
	local current = configs[1] or ""

	local function refreshDropdown()
		configs = self:List()
	end

	local nameBoxVal = current

	gb:AddDropdown("Config", configs, current, function(sel)
		current = sel
	end)

	-- "Name" as dropdown-like: reusing dropdown items isn't ideal; so just provide quick actions
	gb:AddButton("Refresh List", function()
		refreshDropdown()
	end)

	gb:AddButton("Save Current to '" .. (current ~= "" and current or "new") .. "'", function()
		if current == "" then current = "default" end
		self:Save(current)
	end)

	gb:AddButton("Load '" .. (current ~= "" and current or "default") .. "'", function()
		if current == "" then return end
		self:Load(current)
	end)

	gb:AddButton("Delete '" .. (current ~= "" and current or "default") .. "'", function()
		if current == "" then return end
		self:Delete(current)
		current = ""
		refreshDropdown()
	end)

	return gb
end

return ConfigManager
