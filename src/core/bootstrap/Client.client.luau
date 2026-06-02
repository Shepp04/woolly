--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

-- // Types
local Types = require(ReplicatedStorage.Shared.Core.Types)

-- // Require Core and prepare context
local PlayerDataClient = assert(
	require(ReplicatedStorage.Shared.Core.PlayerData).Client,
	"PlayerData.Client is unavailable outside the client runtime"
)
local CoreUtils = require(ReplicatedStorage.Shared.Core.Utils)
local ClientSystemsRegistry = require(PlayerScripts.Client.Core.SystemRegistry)

local ctx: Types.ClientContext = {
    PlayerData = PlayerDataClient,
    Systems = ClientSystemsRegistry,
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
local function discoverSystems(sharedRoot: Folder, clientRoot: Folder): { [string]: Types.ClientSystem }
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
        local loaderModule = clientRoot:FindFirstChild(manifest.Name)
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
local function sortSystems(systems: { [string]: Types.ClientSystem }): { Types.ClientSystem }
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

-- ========== Bootstrap Process ========== --
-- ===== Systems ===== --
-- Find the shared systems folder
local sharedSystemsFolder = ReplicatedStorage.Shared:FindFirstChild("Systems")
local clientSystemsFolder = PlayerScripts.Client:FindFirstChild("Systems")
assert(
	sharedSystemsFolder ~= nil and sharedSystemsFolder:IsA("Folder"),
	"Expected ReplicatedStorage.Shared.Systems to be a Folder"
)
assert(
	clientSystemsFolder ~= nil and clientSystemsFolder:IsA("Folder"),
	"Expected StarterPlayer.StarterPlayerScripts.Client.Systems to be a Folder"
)

-- Discover systems and sort them based on their dependencies
-- to each other
local discoveredSystems = discoverSystems(sharedSystemsFolder, clientSystemsFolder)
local sortedSystems = sortSystems(discoveredSystems)

-- ===== Player Data ===== --
PlayerDataClient:Init()

-- ===== Context Injection ===== --
-- Call the client entry point for each system, providing the core context
-- Init all systems in order
for _, system in sortedSystems do
    print(`[Client] Initing {system.Manifest.Name}`)
    system.Loader:Init(ctx)
end

-- Start all systems in order
for _, system in sortedSystems do
    print(`[Client] Starting {system.Manifest.Name}`)
    system.Loader:Start()
end

print("[CLIENT] Loaded Successfully!")