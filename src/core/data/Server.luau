--!strict
-- PascalCase facade over DataService's server API.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- DataService is mapped into ReplicatedStorage, but its server branch cannot be
-- used by clients. Returning an empty typed table keeps shared requires safe.
if RunService:IsClient() then
	return {} :: PlayerDataServer
end

local RawDataService = require(ReplicatedStorage.Packages.DataService)
local RawServer = RawDataService.server

local DEFAULT_PROFILE_STORE_DATA_PREFIX = "PLAYER_"

export type Path = string | { string }
export type Schema = { [string]: any }
export type MessagePayload = { [any]: any }
export type LeaderstatValueType = "IntValue" | "NumberValue" | "StringValue"
export type LeaderstatDefinition = {
	Name: string,
	Path: Path,
	ValueType: LeaderstatValueType?,
	IsPrimary: boolean?,
	Priority: number?,
}
export type InitOptions = {
	useMock: boolean?,
	viewedUserId: number?,
	overridenUserId: number?,
	dontSave: boolean?,
	resetData: boolean?,
	profileStoreIndex: string?,
	profileStoreDataPrefix: string?,
}

export type PlayerInitialisedCallback = (player: Player, data: any) -> ()
export type PlayerRemovingCallback = (player: Player, data: any) -> ()
export type GlobalCallback = (player: Player, data: MessagePayload) -> boolean?
export type Disconnect = () -> ()
type Connection = {
	Disconnect: (self: Connection) -> (),
}
type Leaderstat = IntValue | NumberValue | StringValue

local initialised = false
local schemaSections: Schema = {}
local playerInitialisedCallbacks: { PlayerInitialisedCallback } = {}
local leaderstatDefinitions: { LeaderstatDefinition } = {}
local leaderstatNames: { [string]: boolean } = {}
local leaderstatConnections: { [Player]: { Connection } } = {}

local PlayerDataServer = {}

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in value :: any do
		copy[key] = deepCopy(child)
	end

	return (copy :: any) :: T
end

local function addCallback<T>(callbacks: { T }, callback: T): Disconnect
	table.insert(callbacks, callback)

	return function()
		local index = table.find(callbacks, callback)
		if index then
			table.remove(callbacks, index)
		end
	end
end

local function getValueAtPath(data: any, path: Path): any
	if type(path) == "string" then
		return data[path]
	end

	local value = data
	for _, key in path do
		if type(value) ~= "table" then
			return nil
		end
		value = value[key]
	end

	return value
end

local function validatePath(path: Path): ()
	if type(path) == "string" then
		assert(path ~= "", "PlayerData paths cannot be empty")
		return
	end

	assert(#path > 0, "PlayerData paths cannot be empty")
	for _, key in path do
		assert(key ~= "", "PlayerData path keys cannot be empty")
	end
end

local function validateLeaderstatValue(definition: LeaderstatDefinition, value: any): ()
	if definition.ValueType == "IntValue" then
		assert(type(value) == "number" and value % 1 == 0, `Leaderstat "{definition.Name}" requires an integer value`)
	elseif definition.ValueType == "NumberValue" then
		assert(type(value) == "number", `Leaderstat "{definition.Name}" requires a number value`)
	elseif definition.ValueType == "StringValue" then
		assert(type(value) == "string", `Leaderstat "{definition.Name}" requires a string value`)
	else
		error(`Leaderstat "{definition.Name}" has an unsupported value type`)
	end
end

local function setLeaderstatValue(definition: LeaderstatDefinition, leaderstat: Leaderstat, value: any): ()
	validateLeaderstatValue(definition, value)
	local rawLeaderstat = leaderstat :: any
	rawLeaderstat.Value = value
end

local function createLeaderstat(definition: LeaderstatDefinition, value: any): Leaderstat
	local leaderstat: Leaderstat
	if definition.ValueType == "IntValue" then
		leaderstat = Instance.new("IntValue")
	elseif definition.ValueType == "NumberValue" then
		leaderstat = Instance.new("NumberValue")
	else
		leaderstat = Instance.new("StringValue")
	end

	local rawLeaderstat = leaderstat :: any
	rawLeaderstat.Name = definition.Name
	setLeaderstatValue(definition, leaderstat, value)

	if definition.IsPrimary then
		local isPrimary = Instance.new("BoolValue")
		isPrimary.Name = "IsPrimary"
		isPrimary.Value = true
		isPrimary.Parent = leaderstat
	end

	if definition.Priority ~= nil then
		local priority = Instance.new("NumberValue")
		priority.Name = "Priority"
		priority.Value = definition.Priority
		priority.Parent = leaderstat
	end

	return leaderstat
end

local function disconnectLeaderstats(player: Player): ()
	local connections = leaderstatConnections[player]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	leaderstatConnections[player] = nil
end

local function setupLeaderstats(player: Player, data: any): ()
	if #leaderstatDefinitions == 0 then
		return
	end

	disconnectLeaderstats(player)

	local leaderstats: Folder
	local existingLeaderstats = player:FindFirstChild("leaderstats")
	if existingLeaderstats then
		assert(
			existingLeaderstats:IsA("Folder"),
			`Player "{player.Name}" already has a non-Folder child named "leaderstats"`
		)
		leaderstats = existingLeaderstats
	else
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local connections = {}
	leaderstatConnections[player] = connections

	for _, definition in leaderstatDefinitions do
		assert(
			leaderstats:FindFirstChild(definition.Name) == nil,
			`Player "{player.Name}" already has a leaderstat named "{definition.Name}"`
		)

		local leaderstat = createLeaderstat(definition, getValueAtPath(data, definition.Path))
		local rawLeaderstat = leaderstat :: any
		rawLeaderstat.Parent = leaderstats

		local connection = RawServer:getChangedSignal(player, definition.Path):Connect(function(value)
			setLeaderstatValue(definition, leaderstat, value)
		end)
		table.insert(connections, connection)
	end
end

local function validateLeaderstats(schema: Schema): ()
	for _, definition in leaderstatDefinitions do
		local value = getValueAtPath(schema, definition.Path)
		assert(value ~= nil, `Leaderstat "{definition.Name}" points to a missing PlayerData schema value`)
		validateLeaderstatValue(definition, value)
	end
end

-- Register each system under a distinct top-level key before calling Init.
function PlayerDataServer:RegisterSchema(sectionName: string, schema: any): ()
	assert(not initialised, "Cannot register PlayerData schema sections after initialisation")
	assert(sectionName ~= "", "PlayerData schema section names cannot be empty")
	assert(schemaSections[sectionName] == nil, `PlayerData schema section "{sectionName}" is already registered`)

	schemaSections[sectionName] = deepCopy(schema)
end

function PlayerDataServer:GetSchema(): Schema
	return deepCopy(schemaSections)
end

function PlayerDataServer:RegisterLeaderstat(definition: LeaderstatDefinition): ()
	assert(not initialised, "Cannot register PlayerData leaderstats after initialisation")
	assert(definition.Name ~= "", "Leaderstat names cannot be empty")
	assert(not leaderstatNames[definition.Name], `Leaderstat "{definition.Name}" is already registered`)
	validatePath(definition.Path)

	local valueType = definition.ValueType or "IntValue"
	assert(
		valueType == "IntValue" or valueType == "NumberValue" or valueType == "StringValue",
		`Leaderstat "{definition.Name}" has an unsupported value type`
	)
	assert(
		definition.IsPrimary == nil or type(definition.IsPrimary) == "boolean",
		"Leaderstat IsPrimary must be a boolean"
	)
	assert(
		definition.Priority == nil or (type(definition.Priority) == "number" and definition.Priority % 1 == 0),
		"Leaderstat Priority must be an integer"
	)

	leaderstatNames[definition.Name] = true
	table.insert(leaderstatDefinitions, {
		Name = definition.Name,
		Path = deepCopy(definition.Path),
		ValueType = valueType,
		IsPrimary = definition.IsPrimary,
		Priority = definition.Priority,
	})
end

function PlayerDataServer:Init(options: InitOptions?): ()
	assert(not initialised, "PlayerData.Server has already been initialised")

	local rawOptions = deepCopy(options or {}) :: any
	rawOptions.template = self:GetSchema()
	validateLeaderstats(rawOptions.template)

	RawServer:addPlayerRemovingCallback(disconnectLeaderstats)
	RawServer:init(rawOptions)
	initialised = true
end

function PlayerDataServer:IsInitialised(): boolean
	return initialised
end

function PlayerDataServer:ResetData(player: Player): ()
	RawServer:resetData(player)
end

function PlayerDataServer:AddPlayerInitialisedCallback(callback: PlayerInitialisedCallback): Disconnect
	assert(not initialised, "Register player initialisation callbacks before calling PlayerData.Server:Init()")
	return addCallback(playerInitialisedCallbacks, callback)
end

function PlayerDataServer:AddPlayerRemovingCallback(callback: PlayerRemovingCallback): Disconnect
	return RawServer:addPlayerRemovingCallback(callback)
end

function PlayerDataServer:SendGlobalMessage(key: string, userId: number | string, data: MessagePayload): boolean
	return RawServer:sendGlobalMessage(key, userId, data :: any)
end

function PlayerDataServer:AddGlobalCallback(key: string, callback: GlobalCallback): ()
	RawServer:addGlobalCallback(key, callback :: any)
end

function PlayerDataServer:AsyncGetProfile(userId: number | string)
	local prefix = RawServer.options.profileStoreDataPrefix or DEFAULT_PROFILE_STORE_DATA_PREFIX
	return RawServer.playerStore:GetAsync(prefix .. tostring(userId))
end

function PlayerDataServer:HasProfile(player: Player): boolean
	return RawServer:hasProfile(player)
end

function PlayerDataServer:GetProfile(player: Player)
	return RawServer:getProfile(player)
end

function PlayerDataServer:WaitForData(player: Player): ()
	RawServer:waitForData(player)
end

function PlayerDataServer:Get<T>(player: Player, path: Path?): T
	return RawServer:get(player, path) :: T
end

function PlayerDataServer:Set<T>(player: Player, path: Path, value: T, dontReplicate: boolean?): ()
	RawServer:set(player, path, value, dontReplicate)
end

function PlayerDataServer:Update<T>(player: Player, path: Path, callback: (value: T) -> T, dontReplicate: boolean?): T
	return RawServer:update(player, path, callback :: any, dontReplicate) :: T
end

function PlayerDataServer:ArrayInsert<T>(player: Player, path: Path, value: T, index: number?, dontReplicate: boolean?): ()
	RawServer:arrayInsert(player, path, value, index, dontReplicate)
end

function PlayerDataServer:ArrayRemove<T>(player: Player, path: Path, index: number, dontReplicate: boolean?): T?
	return RawServer:arrayRemove(player, path, index, dontReplicate) :: T?
end

function PlayerDataServer:GetChangedSignal(player: Player, path: Path)
	return RawServer:getChangedSignal(player, path)
end

function PlayerDataServer:GetIndexChangedSignal(player: Player, path: Path)
	return RawServer:getIndexChangedSignal(player, path)
end

function PlayerDataServer:GetArrayInsertedSignal(player: Player, path: Path)
	return RawServer:getArrayInsertedSignal(player, path)
end

function PlayerDataServer:GetArrayRemovedSignal(player: Player, path: Path)
	return RawServer:getArrayRemovedSignal(player, path)
end

RawServer.onPlayerInit = function(_self, player: Player, data: any)
	for _, callback in playerInitialisedCallbacks do
		callback(player, data)
	end

	setupLeaderstats(player, data)
end

return PlayerDataServer