--!strict
-- ConfigManager.lua

local HttpService = game:GetService("HttpService")

local ConfigManager = {}
ConfigManager.__index = ConfigManager

ConfigManager._window = nil
ConfigManager._store = {} :: {[string]: string} -- in-memory JSON configs

local function canFS(): boolean
	return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end

local FOLDER = "BlueViewConfigs"

local function ensureFolder()
	if typeof(makefolder) == "function" then
		if typeof(isfolder) == "function" then
			if not isfolder(FOLDER) then makefolder(FOLDER) end
		else
			pcall(function() makefolder(FOLDER) end)
		end
	end
end

function ConfigManager:SetLibrary(window: any)
	self._window = window
end

function ConfigManager:Collect(): {[string]: any}
	if not self._window then return {} end
	return self._window:CollectConfig()
end

function ConfigManager:Apply(data: {[string]: any})
	if not self._window then return end
	self._window:ApplyConfig(data)
end

function ConfigManager:Save(name: string)
	if not self._window then return end
	local data = self._window:CollectConfig()
	local json = HttpService:JSONEncode(data)

	-- Always keep in-memory
	self._store[name] = json

	-- Optional filesystem
	if canFS() then
		ensureFolder()
		local path = FOLDER .. "/" .. name .. ".json"
		pcall(function() writefile(path, json) end)
	end
end

function ConfigManager:Load(name: string)
	if not self._window then return end

	local json: string? = self._store[name]

	if not json and canFS() then
		local path = FOLDER .. "/" .. name .. ".json"
		if isfile(path) then
			local ok, content = pcall(function() return readfile(path) end)
			if ok and type(content) == "string" then
				json = content
				self._store[name] = content
			end
		end
	end

	if not json then return end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(json :: string) end)
	if ok and typeof(decoded) == "table" then
		self._window:ApplyConfig(decoded :: {[string]: any})
	end
end

function ConfigManager:List(): {string}
	local out = {}
	for k in pairs(self._store) do table.insert(out, k) end

	-- Optional filesystem discovery
	if canFS() and typeof(listfiles) == "function" then
		ensureFolder()
		local ok, files = pcall(function() return listfiles(FOLDER) end)
		if ok and typeof(files) == "table" then
			for _, f in ipairs(files) do
				local n = tostring(f):match("([^/\\]+)%.json$")
				if n and not self._store[n] then
					table.insert(out, n)
				end
			end
		end
	end

	table.sort(out)
	return out
end

return ConfigManager
