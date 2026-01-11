--!strict
-- ConfigManager.lua
-- Safe Roblox config manager (DataStore-backed via server RemoteFunction)
-- - Saves toggles/sliders/dropdowns/multidropdowns/colorpickers via window:GetConfig()
-- - Loads via window:LoadConfig()
--
-- REQUIRED server companion (create yourself):
--   ReplicatedStorage/BlueView_ConfigRF (RemoteFunction)
-- with OnServerInvoke actions:
--   "list" -> {string}
--   "save", name:string, data:table -> (boolean, string?)
--   "load", name:string -> (table?, string?)
--   "delete", name:string -> (boolean, string?)
--   "rename", old:string, new:string -> (boolean, string?)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigManager = {}

export type SetupOpts = {
	TabName: string?,
	GroupTitle: string?,
	Side: ("Left"|"Right")?,
}

local function safeList(t: any): {string}
	if typeof(t) ~= "table" then return {} end
	local out: {string} = {}
	for _, v in ipairs(t :: any) do
		if typeof(v) == "string" then table.insert(out, v) end
	end
	table.sort(out)
	return out
end

function ConfigManager.Setup(window: any, opts: SetupOpts?)
	opts = opts or {}
	local tabName = opts.TabName or "Configs"
	local groupTitle = opts.GroupTitle or "Config Manager"
	local side = opts.Side or "Left"

	local tab = window.Tabs and window.Tabs[tabName]
	if not tab then
		tab = window:AddTab(tabName, "lucide:save")
	end

	local rf = ReplicatedStorage:FindFirstChild("BlueView_ConfigRF")
	if not rf or not rf:IsA("RemoteFunction") then
		warn("[ConfigManager] Missing ReplicatedStorage/BlueView_ConfigRF RemoteFunction. Config UI will still show, but won't work.")
	end

	local gb = tab:AddGroupbox(groupTitle, {Side = side})

	local selected = "default"
	local configs: {string} = {}

	local dropdown = gb:AddDropdown("Select Config", {"default"}, "default", function(v: string)
		selected = v
	end)

	local nameBox = gb:AddTextbox("Name", "config name", function() end)

	local function call(action: string, a: any?, b: any?)
		if not rf then return nil end
		local ok, res1, res2 = pcall(function()
			return (rf :: RemoteFunction):InvokeServer(action, a, b)
		end)
		if not ok then
			warn("[ConfigManager] call failed:", action, res1)
			return nil
		end
		return res1, res2
	end

	local function refresh()
		local list = call("list")
		configs = safeList(list)

		if #configs == 0 then
			configs = {"default"}
		end
		dropdown.SetOptions(configs)

		if table.find(configs, selected) == nil then
			selected = configs[1]
			dropdown.Set(selected)
		end
	end

	gb:AddButton("Save", function()
		local name = (nameBox.Get() :: string)
		if name == "" then return end
		local data = window:GetConfig()
		local ok, err = call("save", name, data)
		if ok == true then
			selected = name
			refresh()
		else
			warn("[ConfigManager] save failed:", err)
		end
	end)

	gb:AddButton("Load", function()
		local data, err = call("load", selected)
		if typeof(data) == "table" then
			window:LoadConfig(data :: any)
		else
			warn("[ConfigManager] load failed:", err)
		end
	end)

	gb:AddButton("Delete", function()
		local ok, err = call("delete", selected)
		if ok == true then
			selected = "default"
			refresh()
		else
			warn("[ConfigManager] delete failed:", err)
		end
	end)

	gb:AddButton("Rename (to Name box)", function()
		local newName = (nameBox.Get() :: string)
		if newName == "" then return end
		local ok, err = call("rename", selected, newName)
		if ok == true then
			selected = newName
			refresh()
		else
			warn("[ConfigManager] rename failed:", err)
		end
	end)

	gb:AddButton("Refresh", function()
		refresh()
	end)

	refresh()
end

return ConfigManager
