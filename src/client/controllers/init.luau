--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = require(ReplicatedStorage.Shared.Packages)
local Config = require(ReplicatedStorage.Shared.Config)

-- Optional: bring in typed registry if you keep client types
-- local Types = require(ReplicatedStorage.Shared.Types.Controllers)

export type Controller = {
	Priority: number?, -- lower runs earlier
	Init: (self: Controller, deps: any?) -> (),
	Start: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
	Controllers: any?, -- backref to registry
}

type Registry = {
	_registry: { [string]: Controller },
	_ordered: { Controller },
	_inited: boolean,
	_started: boolean,

	InitAll: (extraDeps: any?) -> (),
	StartAll: () -> (),
	DestroyAll: () -> (),
	Get: <T>(name: string) -> T,
	List: () -> { string },
}

local Controllers: Registry = {
	_registry = {},
	_ordered = {},
	_inited = false,
	_started = false,
}

local ControllersFolder = script -- folder-backed; children are controller ModuleScripts

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
			Controllers._registry[child.Name] = mod :: Controller
		end
	end
end

local function _rebuildOrder()
	Controllers._ordered = {}
	for _, c in pairs(Controllers._registry) do
		table.insert(Controllers._ordered, c);
		-- give each controller a backref (like Services)
		(c :: any).Controllers = Controllers._registry
	end
	table.sort(Controllers._ordered, function(a, b)
		local pa = a.Priority or 100
		local pb = b.Priority or 100
		if pa == pb then
			return tostring(a) < tostring(b)
		end
		return pa < pb
	end)
end

function Controllers.InitAll(extraDeps: any?)
	if Controllers._inited then return end
	_loadAll()

	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local deps = extraDeps or {}
	deps.Controllers = Controllers._registry
	deps.Packages = Packages
	deps.Config = Config
	deps.LocalPlayer = localPlayer
	deps.PlayerGui = playerGui

	_rebuildOrder()

	for _, c in ipairs(Controllers._ordered) do
		if typeof((c :: any).Init) == "function" then
			(c :: any):Init(deps)
		end
	end

	Controllers._inited = true
end

function Controllers.StartAll()
	if not Controllers._inited or Controllers._started then return end
	for _, c in ipairs(Controllers._ordered) do
		if typeof((c :: any).Start) == "function" then
			(c :: any):Start()
		end
	end
	Controllers._started = true
end

function Controllers.DestroyAll()
	for i = #Controllers._ordered, 1, -1 do
		local c = Controllers._ordered[i]
		if typeof((c :: any).Destroy) == "function" then
			pcall(function() (c :: any):Destroy() end)
		end
	end
	Controllers._started = false
	Controllers._inited = false
end

function Controllers.Get<T>(name: string): T
	local c = Controllers._registry[name]
	if not c then
		error(("[Controllers] Unknown controller '%s'"):format(name))
	end
	return (c :: any) :: T
end

function Controllers.List(): { string }
	local names = {}
	for name in pairs(Controllers._registry) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return Controllers