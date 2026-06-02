--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types
local Types = require(ReplicatedStorage.Shared.Core.Types)

-- // Require Core and prepare context
local PlayerDataServer = assert(
	require(ReplicatedStorage.Shared.Core.PlayerData).Server,
	"PlayerData.Server is unavailable outside the server runtime"
)
local CoreUtils = require(ReplicatedStorage.Shared.Core.Utils)
local ServerSystemsRegistry = require(ServerScriptService.Server.Core.SystemRegistry)

local ctx: Types.ServerContext = {
    PlayerData = PlayerDataServer,
    Systems = ServerSystemsRegistry,
    GameContent = nil,
    Monetisation = nil,
    Utils = CoreUtils,
}

-- ========== System Helpers ========== --

--[[
    discoverSystems
    Finds all systems and their manifests under a root folder
    Returns a list of systems: their folder and required manifest module
]]
local function discoverSystems(sharedRoot: Folder, serverRoot: Folder): { [string]: Types.ServerSystem }
    -- Find systems in the shared root
    -- look for manifests to define systems
    local systems = {}
    for _, child in sharedRoot:GetChildren() do
        -- Check that the child is a folder
        assert(child:IsA("Folder"), `Expected "{child:GetFullName()}" to be a Folder`)

        -- Get the system's manifest
        local manifestModule = child:FindFirstChild("Manifest")
        assert(manifestModule ~= nil, `Expected "{child:GetFullName()}.Manifest" to exist`)
	    assert(manifestModule:IsA("ModuleScript"), `Expected "{manifestModule:GetFullName()}" to be a ModuleScript`)
        local manifest = require(manifestModule) :: Types.SystemManifest

        -- Find the system's optional server loader
        local loaderModule = serverRoot:FindFirstChild(manifest.Name)
        local loader = nil
        if loaderModule and loaderModule:IsA("ModuleScript") then
            loader = require(loaderModule)
        end
        
        systems[manifest.Name] = {
            Loader = loader,
            Manifest = manifest,
        }
    end
    return systems
end

--[[
    sortSystems
    Recursively sorts systems based on dependencies
    with systems at the bottom of the dependency chain appearing first
]]
local function sortSystems(systems: { [string]: Types.ServerSystem }): { Types.ServerSystem }
    local sorted = {}
    local visited: { [string]: boolean } = {}
    local visiting: { [string]: boolean } = {}

    -- // Helper
    local function visit(systemName: string)
        if visited[systemName] then
            return
        end

        local system = systems[systemName]
        assert(system ~= nil, `System dependency "{systemName}" could not be found`)
		assert(not visiting[systemName], `Circular system dependency detected at "{systemName}"`)

        visiting[systemName] = true
        local dependencyNames: { string } = system.Manifest.Dependencies or {}
        for _, dependencyName in dependencyNames do
            visit(dependencyName)
        end
        visiting[systemName] = nil
        visited[systemName] = true
        table.insert(sorted, system)
    end

    local systemNames = {}
    for systemName in systems do
        table.insert(systemNames, systemName)
    end
    table.sort(systemNames)

    for _, systemName in systemNames do
        visit(systemName)
    end

    return sorted
end

--[[
    applySystemManifests
    Loops through all system manifest modules and merges
    player data schema fragments into one DataService template.
    Also creates remote/bindable functions and events
]]
local function applySystemManifests(systems: { Types.ServerSystem }): ()
    for _, system in systems do
        local manifest = system.Manifest

        -- Register the system's player data schema
        -- if it exists
        if next(manifest.PlayerDataRequirements.Schema) ~= nil then
            PlayerDataServer:RegisterSchema(manifest.Name, manifest.PlayerDataRequirements.Schema)
        end

        -- Do the same for leaderstats
        for _, leaderstat in manifest.PlayerDataRequirements.Leaderstats do
            PlayerDataServer:RegisterLeaderstat(leaderstat)
        end
        
        -- Create the required remotes for this system
        CoreUtils.Remotes:Register(manifest.Name, manifest.Remotes)
    end
end

-- ========== Bootstrap Process ========== --
-- ===== Systems ===== --
-- Find the shared systems folder
local sharedSystemsFolder = ReplicatedStorage.Shared:FindFirstChild("Systems")
local serverSystemsFolder = ServerScriptService.Server:FindFirstChild("Systems")
assert(
	sharedSystemsFolder ~= nil and sharedSystemsFolder:IsA("Folder"),
	"Expected ReplicatedStorage.Shared.Systems to be a Folder"
)
assert(
	serverSystemsFolder ~= nil and serverSystemsFolder:IsA("Folder"),
	"Expected ServerScriptService.Server.Systems to be a Folder"
)

-- Discover systems and sort them based on their dependencies
-- to each other
local discoveredSystems = discoverSystems(sharedSystemsFolder, serverSystemsFolder)
local sortedSystems = sortSystems(discoveredSystems)

-- Now apply manifests (merge player profile scheme and create remotes)
applySystemManifests(sortedSystems)

-- ===== Player Data ===== --
-- Here the schema from discovered systems have already been merged
-- and so the template for DataService:init() is composed and complete
PlayerDataServer:Init({
    useMock = nil,
    viewedUserId = nil,
    overridenUserId = nil,
    dontSave = nil,
    resetData = nil,
    profileStoreIndex = nil,
    profileStoreDataPrefix = nil,
})

-- ===== Context Injection ===== --
-- Call the server entry point for each system, providing the core context
-- Init all systems in order
for _, system in sortedSystems do
    print(`Initing {system.Manifest.Name}`)
    system.Loader:Init(ctx)
end

-- Start all systems in order
for _, system in sortedSystems do
    print(`Starting {system.Manifest.Name}`)
    system.Loader:Start()
end

print("[SERVER] Loaded Successfully!")