--!strict
-- ConfigManager.lua (Roblox-safe)
-- Saves configs in DataStore per-player.
-- Requires SpareStackUI.lua update (window:GetConfig + window:LoadConfig)

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local ConfigManager = {}
ConfigManager.__index = ConfigManager

export type Manager = {
	StoreName: string,
	Store: GlobalDataStore,
	MakeKey: (self: Manager, userId: number, name: string) -> string,
	Save: (self: Manager, player: Player, name: string, data: {[string]: any}) -> (boolean, string?),
	Load: (self: Manager, player: Player, name: string) -> ({[string]: any}?, string?),
	Delete: (self: Manager, player: Player, name: string) -> (boolean, string?),
	List: (self: Manager, player: Player) -> ({string}?, string?),
	Rename: (self: Manager, player: Player, oldName: string, newName: string) -> (boolean, string?),
}

function ConfigManager.new(storeName: string?): Manager
	local self = setmetatable({}, ConfigManager)
	self.StoreName = storeName or "SpareStackUI_Configs"
	self.Store = DataStoreService:GetDataStore(self.StoreName)
	return (self :: any) :: Manager
end

function ConfigManager:MakeKey(userId: number, name: string): string
	return ("%d:%s"):format(userId, string.lower(name))
end

function ConfigManager:Save(player: Player, name: string, data: {[string]: any})
	local key = self:MakeKey(player.UserId, name)
	local ok, err = pcall(function()
		local payload = {
			name = name,
			updatedAt = os.time(),
			data = data,
		}
		self.Store:SetAsync(key, HttpService:JSONEncode(payload))
	end)
	if not ok then return false, tostring(err) end
	return true, nil
end

function ConfigManager:Load(player: Player, name: string)
	local key = self:MakeKey(player.UserId, name)
	local ok, res = pcall(function()
		return self.Store:GetAsync(key)
	end)
	if not ok then return nil, tostring(res) end
	if res == nil then return nil, "Config not found" end

	local decoded = HttpService:JSONDecode(res)
	return decoded.data :: {[string]: any}, nil
end

function ConfigManager:Delete(player: Player, name: string)
	local key = self:MakeKey(player.UserId, name)
	local ok, err = pcall(function()
		self.Store:RemoveAsync(key)
	end)
	if not ok then return false, tostring(err) end
	return true, nil
end

function ConfigManager:List(player: Player)
	-- DataStore can't list keys directly.
	-- Workaround: keep an index key.
	local indexKey = self:MakeKey(player.UserId, "__index__")
	local ok, res = pcall(function()
		return self.Store:GetAsync(indexKey)
	end)
	if not ok then return nil, tostring(res) end
	if res == nil then return {}, nil end
	return HttpService:JSONDecode(res), nil
end

local function updateIndex(store: GlobalDataStore, indexKey: string, fn: ({string})->{string})
	local raw = store:GetAsync(indexKey)
	local list: {string} = {}
	if raw then
		local ok = pcall(function()
			list = HttpService:JSONDecode(raw)
		end)
		if not ok then list = {} end
	end
	list = fn(list)
	store:SetAsync(indexKey, HttpService:JSONEncode(list))
end

function ConfigManager:Rename(player: Player, oldName: string, newName: string)
	local data, err = self:Load(player, oldName)
	if not data then return false, err end
	local ok1, err1 = self:Save(player, newName, data)
	if not ok1 then return false, err1 end
	local ok2, err2 = self:Delete(player, oldName)
	if not ok2 then return false, err2 end
	return true, nil
end

-- Optional helpers to maintain an index (call these in your own code)
function ConfigManager:AddToIndex(player: Player, name: string)
	local indexKey = self:MakeKey(player.UserId, "__index__")
	local ok, err = pcall(function()
		updateIndex(self.Store, indexKey, function(list)
			for _, n in ipairs(list) do
				if string.lower(n) == string.lower(name) then return list end
			end
			table.insert(list, name)
			table.sort(list)
			return list
		end)
	end)
	return ok, if ok then nil else tostring(err)
end

function ConfigManager:RemoveFromIndex(player: Player, name: string)
	local indexKey = self:MakeKey(player.UserId, "__index__")
	local ok, err = pcall(function()
		updateIndex(self.Store, indexKey, function(list)
			local out: {string} = {}
			for _, n in ipairs(list) do
				if string.lower(n) ~= string.lower(name) then
					table.insert(out, n)
				end
			end
			return out
		end)
	end)
	return ok, if ok then nil else tostring(err)
end

return ConfigManager
