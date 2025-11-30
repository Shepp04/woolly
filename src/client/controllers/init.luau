--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Types.Controllers)

local ControllersFolder = script -- folder-backed; children are controller ModuleScripts

-- Generic controller type
export type Registry = Types.Registry
export type Controller = {
    Priority: number?, -- lowest first
    Init: (self: Controller, deps: any) -> (),
    Start: (self: Controller) -> (),
    Destroy: (self: Controller) -> (),
    Controllers: Controller?,
}

type ControllersAPI = Registry & {
	_registry: { [string]: Controller },
	_inited: boolean,
	_started: boolean,

	InitAll: (extraDeps: any?) -> (),
	StartAll: () -> (),
	DestroyAll: () -> (),
	Get: <T>(name: string) -> T,
	List: () -> { string },
}

local API: ControllersAPI = {
	_registry = {},
	_inited = false,
	_started = false,
}

-- ========== Internal ========== --

-- sorted list for lifecycle calls
local _ordered: { Controller } = {}

-- Discover and require all ModuleScripts directly under this folder
local function _loadAll()
	for _, child in ipairs(ControllersFolder:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name ~= "init" then
			local ok, mod = pcall(require, child)
			if not ok then
				error(("[Controllers] Failed to require %s: %s"):format(child:GetFullName(), tostring(mod)))
			end
			if type(mod) ~= "table" then
				error(("[Controllers] %s did not return a table"):format(child.Name))
			end
			API._registry[child.Name] = mod :: Controller
		end
	end
end

-- Build deterministic order by priority, with lowest first
local function _rebuildOrder()
	_ordered = {}
	for _, c in pairs(API._registry) do
		table.insert(_ordered, c);
		-- give each controller a backref (like Services)
		(c :: any).Controllers = API._registry
	end
	table.sort(_ordered, function(a, b)
		local pa = a.Priority or 100
		local pb = b.Priority or 100
		if pa == pb then
			return tostring(a) < tostring(b)
		end
		return pa < pb
	end)
end

--[[
    .InitAll(extraDeps?)
    Requires/collects all controllers once and injects deps.
    Calls :Init(deps) in priority order 
]]
function API.InitAll(extraDeps: any?)
	if API._inited then return end
	_loadAll()

	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local deps = extraDeps or {}
	deps.Controllers = API._registry
	
	_rebuildOrder()

	for _, c in ipairs(_ordered) do
		if typeof((c :: any).Init) == "function" then
			(c :: any):Init(deps)
		end
	end

	API._inited = true
end

--[[
    .StartAll()
    Calls :Start() in priority order after InitAll
]]
function API.StartAll()
	if not API._inited or API._started then return end
	for _, c in ipairs(_ordered) do
		if typeof((c :: any).Start) == "function" then
			(c :: any):Start()
		end
	end
	API._started = true
end

--[[
    .DestroyAll()
    Calls :Destroy() in reverse order so that dependencies stop last
]]
function API.DestroyAll()
	for i = #_ordered, 1, -1 do
		local c = _ordered[i]
		if typeof((c :: any).Destroy) == "function" then
			pcall(function() (c :: any):Destroy() end)
		end
	end
	API._started = false
	API._inited = false
end

--[[
    .Get(name: string)
    Typed accessor for a controller by module name
    e.g local CurrencyService = Controllers.Get("CurrencyService")
]]
function API.Get<T>(name: string): T
	local c = API._registry[name]
	if not c then
		error(("[Controllers] Unknown controller '%s'"):format(name))
	end
	return (c :: any) :: T
end

--[[
    .List()
    Returns an array of controller names in priority order
]]
function API.List(): { string }
	local names = {}
	for name in pairs(API._registry) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function API.AsTyped(): Registry
    return (API._registry :: any) :: Registry
end

return API :: Registry