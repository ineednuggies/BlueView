--!strict
-- ConfigManager.lua - save/load BlueView flags
-- Uses writefile/readfile if present (executors), otherwise in-memory fallback.

local HttpService = game:GetService("HttpService")

local ConfigManager = {}
ConfigManager.__index = ConfigManager

local folder = "BlueViewConfigs"
local libraryWindow: any = nil
local memoryStore: {[string]: string} = {}

function ConfigManager.SetFolder(name: string)
	folder = name
end

function ConfigManager.SetLibrary(window: any)
	libraryWindow = window
end

local function canFile()
	return (typeof(writefile) == "function") and (typeof(readfile) == "function") and (typeof(isfile) == "function") and (typeof(makefolder) == "function")
end

local function ensureFolder()
	if not canFile() then return end
	if not isfolder(folder) then
		makefolder(folder)
	end
end

function ConfigManager.Save(name: string)
	if not libraryWindow or not libraryWindow.CollectConfig then return false end
	local data = libraryWindow:CollectConfig()
	local json = HttpService:JSONEncode(data)

	if canFile() then
		ensureFolder()
		writefile(folder .. "/" .. name .. ".json", json)
	else
		memoryStore[name] = json
	end
	return true
end

function ConfigManager.Load(name: string)
	if not libraryWindow or not libraryWindow.ApplyConfig then return false end
	local json: string? = nil

	if canFile() then
		ensureFolder()
		local path = folder .. "/" .. name .. ".json"
		if isfile(path) then
			json = readfile(path)
		end
	else
		json = memoryStore[name]
	end

	if not json then return false end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(json :: string)
	end)
	if not ok then return false end

	libraryWindow:ApplyConfig(decoded)
	return true
end

return ConfigManager
