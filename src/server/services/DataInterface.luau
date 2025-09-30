--!strict

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Packages
local Packages = require("../Packages")
local DataManager = Packages.DataManager

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Data)
export type PlayerProfile = Types.PlayerProfile

export type DataInterfaceAPI = {
	-- Lifecycle
	Init: (self: DataInterfaceAPI) -> DataInterfaceAPI,

	-- Data
	GetPlayerProfile: (self: DataInterfaceAPI, player: Player, yield: boolean?) -> PlayerProfile?,
	LoadPlayerProfile: (self: DataInterfaceAPI, player: Player) -> PlayerProfile?,
	LoadPlayerProfileAsync: (self: DataInterfaceAPI, player: Player) -> Promise<PlayerProfile>,
	GetPlayerProfilePromise: (self: DataInterfaceAPI, player: Player) -> Promise<PlayerProfile>,
	ReleasePlayerProfile: (self: DataInterfaceAPI, player: Player) -> boolean,

	-- Reconcile
	RegisterReconcileSection: (
		self: DataInterfaceAPI,
		sectionType: "Info" | "Data",
		sectionName: string,
		template: {}
	) -> boolean,
}

local DataInterface = {}

local _inited = false

-- ========== Public API ========== --
--[[ 
	Returns the profile associated with a player.
	Optionally waits for it to load.

	@param player Player — The player to get the profile for.
	@param yield? boolean — If true, yields until profile is loaded.
	@return PlayerProfile? — The player's profile, or nil.
]]
function DataInterface:GetPlayerProfile(player: Player, yield: boolean?): PlayerProfile?
	return DataManager:GetPlayerProfile(player, yield)
end

--[[ 
	Loads the profile for a player using the synchronous API.
	Kicks the player if loading fails.

	@param player Player — The player to load the profile for.
	@return PlayerProfile? — The loaded profile, or nil.
]]
function DataInterface:LoadPlayerProfile(player: Player): PlayerProfile?
	local profile = DataManager:LoadPlayerProfile(player)
	if not profile then
		warn("Failed to load profile for player:", player.Name)
	end
	return profile
end

--[[ 
	Loads the profile for a player using a Promise.
	Preferred for async use.

	@param player Player — The player to load the profile for.
	@return Promise<PlayerProfile>
]]
function DataInterface:LoadPlayerProfileAsync(player: Player)
	return DataManager:LoadPlayerProfileAsync(player)
end

--[[ 
	Returns a Promise that resolves when the player's profile is available.

	@param player Player — The player whose profile is requested.
	@return Promise<PlayerProfile>
]]
function DataInterface:GetPlayerProfilePromise(player: Player)
	return DataManager:GetPlayerProfilePromise(player)
end

--[[ 
	Releases the player's profile session.

	@param player Player — The player to release.
	@return boolean — Always true (for compatibility).
]]
function DataInterface:ReleasePlayerProfile(player: Player): boolean
	DataManager:ReleasePlayerProfile(player)
	return true
end

--[[ 
	Registers a reconcile section into DataManager.

	@param sectionType "Info" | "Data" — Which section to apply to.
	@param sectionName string — Key of the section.
	@param template table — Template to use for reconciliation.
	@return boolean — Always true (for compatibility).
]]
function DataInterface:RegisterReconcileSection(sectionType: "Info" | "Data", sectionName: string, template: {}): boolean
	DataManager:RegisterReconcileSection(sectionType, sectionName, template)
	return true
end

-- ========== Life Cycle ========== --
function DataInterface:Init()
	if _inited then return self end
	_inited = true

	return self
end

return DataInterface :: DataInterfaceAPI