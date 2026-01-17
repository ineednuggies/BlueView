-- LucideProvider.lua
-- Put this file in the same GitHub folder as BlueView.lua.
-- It returns an IconProvider function: (name: string) -> string?
--
-- Behind the scenes, it mirrors the approach used by Obsidian:
-- it loads a Lucide name->asset mapping at runtime.

local LUCIDE_URL = "https://raw.githubusercontent.com/deividcomsono/lucide-roblox-direct/refs/heads/main/source.lua"

local function getIconTable(mod)
	if type(mod) ~= "table" then
		return {}
	end
	-- common nesting patterns
	if type(mod.icons) == "table" then return mod.icons end
	if type(mod.Icons) == "table" then return mod.Icons end
	if type(mod.Icon) == "table" then return mod.Icon end
	return mod
end

local ok, result = pcall(function()
	return loadstring(game:HttpGet(LUCIDE_URL))()
end)

local ICONS = {}
if ok then
	ICONS = getIconTable(result)
else
	warn("[BlueView] Lucide map failed to load:", result)
end

local function norm(name: string): string
	name = string.lower(name)
	name = name:gsub("_", "-")
	return name
end

return function(name: string)
	name = norm(name)
	return ICONS[name]
		or ICONS[name:gsub("-", "")]
		or ICONS[name:gsub("-", "_")]
		or ICONS[name:gsub("-", " ")]
end
