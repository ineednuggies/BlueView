--!strict
-- ConfigManager.lua (UPDATED)
-- Saves/loads config values using executor filesystem APIs.

local HttpService = game:GetService("HttpService")

local ConfigManager = {}
ConfigManager.__index = ConfigManager

local function hasFS()
	return (type(writefile) == "function")
		and (type(readfile) == "function")
		and (type(isfile) == "function")
end

local function ensureFolder(path: string)
	if type(isfolder) == "function" and type(makefolder) == "function" then
		if not isfolder(path) then
			makefolder(path)
		end
	end
end

local function safeEncode(t: any): string
	return HttpService:JSONEncode(t)
end

local function safeDecode(s: string): any
	return HttpService:JSONDecode(s)
end

function ConfigManager.new(rootFolder: string)
	local self = setmetatable({}, ConfigManager)
	self.RootFolder = rootFolder
	return self
end

function ConfigManager:GetFolder(): string
	return self.RootFolder
end

function ConfigManager:Save(window: any, name: string): (boolean, string)
	if not hasFS() then return false, "Filesystem not available in this environment." end
	if name == "" then return false, "Config name is empty." end

	ensureFolder(self.RootFolder)
	local path = self.RootFolder .. "/" .. name .. ".json"

	local data = window:CollectConfig()
	local ok, err = pcall(function()
		writefile(path, safeEncode(data))
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, "Saved: " .. name
end

function ConfigManager:Load(window: any, name: string): (boolean, string)
	if not hasFS() then return false, "Filesystem not available in this environment." end
	local path = self.RootFolder .. "/" .. name .. ".json"
	if type(isfile) == "function" and not isfile(path) then
		return false, "Config not found: " .. name
	end

	local ok, err = pcall(function()
		local raw = readfile(path)
		local data = safeDecode(raw)
		if typeof(data) == "table" then
			window:ApplyConfig(data)
		end
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, "Loaded: " .. name
end

function ConfigManager:Delete(name: string): (boolean, string)
	if not hasFS() then return false, "Filesystem not available in this environment." end
	if type(delfile) ~= "function" then return false, "Delete not supported." end

	local path = self.RootFolder .. "/" .. name .. ".json"
	local ok, err = pcall(function()
		if type(isfile) == "function" and isfile(path) then
			delfile(path)
		end
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, "Deleted: " .. name
end

function ConfigManager:Rename(oldName: string, newName: string): (boolean, string)
	if not hasFS() then return false, "Filesystem not available in this environment." end
	if type(delfile) ~= "function" then return false, "Rename not supported." end

	local oldPath = self.RootFolder .. "/" .. oldName .. ".json"
	local newPath = self.RootFolder .. "/" .. newName .. ".json"

	local ok, err = pcall(function()
		local raw = readfile(oldPath)
		writefile(newPath, raw)
		delfile(oldPath)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, "Renamed: " .. oldName .. " -> " .. newName
end

function ConfigManager:List(): {string}
	local out: {string} = {}
	if not hasFS() then return out end
	if type(listfiles) ~= "function" then return out end
	ensureFolder(self.RootFolder)

	local ok, files = pcall(function()
		return listfiles(self.RootFolder)
	end)
	if not ok or typeof(files) ~= "table" then return out end

	for _, p in ipairs(files :: {any}) do
		local s = tostring(p)
		local name = string.match(s, "([^/\\]+)%.json$")
		if name then table.insert(out, name) end
	end
	table.sort(out)
	return out
end

return ConfigManager

