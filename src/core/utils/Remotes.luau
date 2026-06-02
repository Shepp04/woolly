--!strict
-- Namespaced registry for remotes declared by system manifests.

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Constants
local DEFAULT_COOLDOWN = 0.25
local REMOTES_FOLDER_NAME = "Remotes"
local WAIT_TIMEOUT = 10

-- // Types
export type Definitions = {
	Events: { string }?,
	Functions: { string }?,
}

type Remote = RemoteEvent | RemoteFunction
type RemoteType = "RemoteEvent" | "RemoteFunction"

-- // Variables
local discoveredRemotes: { [string]: Remote } = {}
local registeredRemotes: { [string]: RemoteType } = {}
local debounceExpiries: { [Player]: { [string]: number } } = {}

-- // Util
local Remotes = {}

-- ========== Helpers ========== --
local function validateName(label: string, value: string): ()
	assert(value ~= "", `{label} cannot be empty`)
	assert(
		string.match(value, "^[%w_]+$") ~= nil,
		`{label} "{value}" may only contain letters, numbers, and underscores`
	)
end

local function getRemoteId(namespace: string, remoteName: string): string
	return `{namespace}/{remoteName}`
end

local function getOrCreateFolder(parent: Instance, folderName: string): Folder
	local existing = parent:FindFirstChild(folderName)
	if existing then
		assert(existing:IsA("Folder"), `Expected "{parent:GetFullName()}.{folderName}" to be a Folder`)
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent
	return folder
end

local function waitForFolder(parent: Instance, folderName: string): Folder
	local folder = parent:WaitForChild(folderName, WAIT_TIMEOUT)
	assert(folder ~= nil, `Timed out waiting for Folder "{parent:GetFullName()}.{folderName}"`)
	assert(folder:IsA("Folder"), `Expected "{folder:GetFullName()}" to be a Folder`)
	return folder
end

local function getNamespaceFolder(namespace: string, shouldCreate: boolean): Folder
	validateName("Remote namespace", namespace)

	if shouldCreate then
		local remotesFolder = getOrCreateFolder(ReplicatedStorage, REMOTES_FOLDER_NAME)
		return getOrCreateFolder(remotesFolder, namespace)
	end

	local remotesFolder = waitForFolder(ReplicatedStorage, REMOTES_FOLDER_NAME)
	return waitForFolder(remotesFolder, namespace)
end

local function getRemote(namespace: string, remoteName: string, remoteType: RemoteType, shouldCreate: boolean): Remote
	validateName("Remote name", remoteName)

	local remoteId = getRemoteId(namespace, remoteName)
	local cachedRemote = discoveredRemotes[remoteId]
	if cachedRemote then
		assert(cachedRemote:IsA(remoteType), `Remote "{remoteId}" is not a {remoteType}`)
		return cachedRemote
	end

	local namespaceFolder = getNamespaceFolder(namespace, shouldCreate)
	local remote = namespaceFolder:FindFirstChild(remoteName)

	if not remote and shouldCreate then
		local createdRemote: Remote
		if remoteType == "RemoteEvent" then
			createdRemote = Instance.new("RemoteEvent")
		else
			createdRemote = Instance.new("RemoteFunction")
		end

		local createdInstance = createdRemote :: Instance
		createdInstance.Name = remoteName
		createdInstance.Parent = namespaceFolder
		remote = createdRemote
	elseif not remote then
		remote = namespaceFolder:WaitForChild(remoteName, WAIT_TIMEOUT)
	end

	assert(remote ~= nil, `Timed out waiting for {remoteType} "{remoteId}"`)
	assert(remote:IsA(remoteType), `Remote "{remoteId}" is not a {remoteType}`)

	local resolvedRemote = remote :: Remote
	discoveredRemotes[remoteId] = resolvedRemote
	return resolvedRemote
end

local function registerRemote(namespace: string, remoteName: string, remoteType: RemoteType): ()
	local remoteId = getRemoteId(namespace, remoteName)
	assert(registeredRemotes[remoteId] == nil, `Remote "{remoteId}" has already been registered`)

	getRemote(namespace, remoteName, remoteType, true)
	registeredRemotes[remoteId] = remoteType
end

local function passDebounce(player: Player, remoteId: string, cooldown: number): boolean
	local playerDebounces = debounceExpiries[player]
	if not playerDebounces then
		playerDebounces = {}
		debounceExpiries[player] = playerDebounces
	end

	local now = os.clock()
	if now < (playerDebounces[remoteId] or 0) then
		return false
	end

	playerDebounces[remoteId] = now + cooldown
	return true
end

-- ========== API ========== --
function Remotes:Register(namespace: string, definitions: Definitions): ()
	assert(RunService:IsServer(), "Remotes can only be registered on the server")
	validateName("Remote namespace", namespace)

	local events: { string } = definitions.Events or {}
	for _, remoteName in events do
		registerRemote(namespace, remoteName, "RemoteEvent")
	end

	local functions: { string } = definitions.Functions or {}
	for _, remoteName in functions do
		registerRemote(namespace, remoteName, "RemoteFunction")
	end
end

function Remotes:GetEvent(namespace: string, remoteName: string): RemoteEvent
	local remoteId = getRemoteId(namespace, remoteName)
	if RunService:IsServer() then
		assert(registeredRemotes[remoteId] == "RemoteEvent", `RemoteEvent "{remoteId}" has not been registered. Check the manifest for this system.`)
	end

	return getRemote(namespace, remoteName, "RemoteEvent", false) :: RemoteEvent
end

function Remotes:GetFunction(namespace: string, remoteName: string): RemoteFunction
	local remoteId = getRemoteId(namespace, remoteName)
	if RunService:IsServer() then
		assert(registeredRemotes[remoteId] == "RemoteFunction", `RemoteFunction "{remoteId}" has not been registered. Check the manifest for this system.`)
	end

	return getRemote(namespace, remoteName, "RemoteFunction", false) :: RemoteFunction
end

-- Cooldowns are basic rate limiting. Server callbacks must still validate all client input.
function Remotes:BindServerEvent(
	namespace: string,
	remoteName: string,
	callback: (player: Player, ...any) -> (),
	cooldown: number?
): RBXScriptConnection
	assert(RunService:IsServer(), "Server remote events can only be bound on the server")

	local remoteId = getRemoteId(namespace, remoteName)
	local event = self:GetEvent(namespace, remoteName)
	local resolvedCooldown = cooldown or DEFAULT_COOLDOWN
	assert(resolvedCooldown >= 0, "Remote event cooldown cannot be negative")

	return event.OnServerEvent:Connect(function(player: Player, ...)
		if passDebounce(player, remoteId, resolvedCooldown) then
			callback(player, ...)
		end
	end)
end

function Remotes:BindClientEvent(namespace: string, remoteName: string, callback: (...any) -> ()): RBXScriptConnection
	assert(RunService:IsClient(), "Client remote events can only be bound on the client")
	return self:GetEvent(namespace, remoteName).OnClientEvent:Connect(callback)
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		debounceExpiries[player] = nil
	end)
end

return Remotes