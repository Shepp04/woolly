--!strict
-- // Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types.Services)

local ServicesFolder = script

-- Generic service type
export type Registry = Types.Registry
export type Service = {
    Priority: number?, -- lowest first
    Init: (self: Service, deps: any) -> (),
    Start: (self: Service) -> (),
    Destroy: (self: Service) -> (),
    Services: any?, -- auto-filled reference to the registry
}

export type ServicesAPI = Registry & {
    _registry: { [string]: Service },
    _inited: boolean,
    _started: boolean,

    InitAll: (extraDeps: any?) -> (),
    StartAll: () -> (),
    DestroyAll: () -> (),
    Get: <T>(name: string) -> T,
    List: () -> {string},
    AsTyped: () -> Registry,
}

local API: ServicesAPI = {
    _registry = {},
    _inited = false,
    _started = false,
}

-- ========== Internal ========== --

-- sorted list for lifecycle calls
local _ordered: { Service } = {}

-- Discover and require all ModuleScripts directly under this folder
local function _loadAll()
    for _, child in ipairs(ServicesFolder:GetChildren()) do
        if child:IsA("ModuleScript") then
            local ok, mod = pcall(require, child)
            if not ok then
                error(("[Services] Failed to require %s: %s"):format(child:GetFullName(), tostring(mod)))
            end
            if type(mod) ~= "table" then
                error(("[Services] %s did not return a table"):format(child.Name))
            end
            -- Store by module name
            API._registry[child.Name] = mod :: Service
        end
    end
end

-- Build deterministic order by priority, with lowest first
local function _rebuildOrder()
    _ordered = {}
    for _, svc in pairs(API._registry) do
        table.insert(_ordered, svc)
    end
    table.sort(_ordered, function(a: Service, b:Service)
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
    Requires/collects all services once and injects deps.
    Calls :Init(deps) in priority order 
]]
function API.InitAll(extraDeps: any?)
    if API._inited then return end
    _loadAll()

    local deps = extraDeps or {}

    -- Give services a live reference to the registry
    deps.Services = API._registry

    -- Also set .Services on each service for convenience
    for _, svc in pairs(API._registry) do
        (svc :: any).Services = API._registry
    end

    _rebuildOrder()

    -- Call Init in priority order
    for _, svc in ipairs(_ordered) do
        if typeof((svc :: any).Init) == "function" then
            (svc :: any):Init(deps)
        end
    end

    API._inited = true

    if RunService:IsServer() then
        game:BindToClose(function()
            pcall(API.DestroyAll)
        end)
    end
end

--[[
    .StartAll()
    Calls :Start() in priority order after InitAll
]]
function API.StartAll()
    if not API._inited or API._started then return end
    for _, svc in ipairs(_ordered) do
        if typeof((svc :: any).Start) == "function" then
            (svc :: any):Start()
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
        local svc = _ordered[i]
        if typeof((svc :: any).Destroy == "function") then
            pcall(function() (svc :: any):Destroy() end)
        end
    end
    API._started = false
    API._inited = false
end

--[[
    .Get(name: string)
    Typed accessor for a service by module name
    e.g local CurrencyService = Services.Get("CurrencyService")
]]
function API.Get<T>(name: string): T
    local svc = API._registry[name]
    if not svc then
        error(("[Services] Unknown service '%s'"):format(name))
    end
    return (svc :: any) :: T
end

--[[
    .List()
    Returns an array of service names in priority order
]]
function API.List(): {string}
    local names = {}
    for _, svc in pairs(_ordered) do
        for k, v in pairs(API._registry) do
            if v == svc then table.insert(names, k) end
        end
    end
    return names
end

function API.AsTyped(): Registry
    return (API._registry :: any) :: Registry
end

return API