--!strict
-- PascalCase facade over DataService's client API.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Returning an empty typed table keeps direct shared requires safe on the server.
if RunService:IsServer() then
	return {} :: PlayerDataClient
end

local RawDataService = require(ReplicatedStorage.Packages.DataService)
local RawClient = RawDataService.client

export type Path = string | { string }
export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
	Destroy: (self: Connection) -> (),
}
export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
}

local initialised = false

local PlayerDataClient = {}

-- Initialises the replicated local cache and yields until the server sends data.
function PlayerDataClient:Init(data: any?): ()
	assert(not initialised, "PlayerData.Client has already been initialised")
	RawClient:init(data)
	initialised = true
end

function PlayerDataClient:IsInitialised(): boolean
	return initialised
end

-- Fetches an authoritative value from the server. Prefer Get during normal use.
function PlayerDataClient:Fetch<T>(path: Path?, dontSet: boolean?): T
	assert(path ~= nil or dontSet == true, "Fetching all PlayerData requires dontSet = true")
	return RawClient:fetch(path, dontSet) :: T
end

function PlayerDataClient:Get<T>(path: Path?): T
	return RawClient:get(path) :: T
end

-- Local mutation methods never write data back to the server.
function PlayerDataClient:SetLocal<T>(path: Path, value: T): ()
	RawClient:set(path, value)
end

function PlayerDataClient:UpdateLocal<T>(path: Path, callback: (value: T) -> T): T
	return RawClient:update(path, callback :: any) :: T
end

function PlayerDataClient:ArrayInsertLocal<T>(path: Path, value: T, index: number?): ()
	RawClient:arrayInsert(path, value, index)
end

function PlayerDataClient:ArrayRemoveLocal<T>(path: Path, index: number): T?
	return RawClient:arrayRemove(path, index) :: T?
end

function PlayerDataClient:GetChangedSignal<T>(path: Path): Signal<T, T?>
	return RawClient:getChangedSignal(path) :: any
end

function PlayerDataClient:GetIndexChangedSignal<T>(path: Path): Signal<string | number, T, T?>
	return RawClient:getIndexChangedSignal(path) :: any
end

function PlayerDataClient:GetArrayInsertedSignal<T>(path: Path): Signal<number, T>
	return RawClient:getArrayInsertedSignal(path) :: any
end

function PlayerDataClient:GetArrayRemovedSignal<T>(path: Path): Signal<number, T?>
	return RawClient:getArrayRemovedSignal(path) :: any
end

function PlayerDataClient:WaitForData(): ()
	RawClient:waitForData()
end

export type PlayerDataClient = typeof(PlayerDataClient)

return PlayerDataClient