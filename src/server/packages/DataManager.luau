--!strict
-- Uses ProfileStore and ReplicatedData to save data and enable server/client communication

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

--// Packages
local ExternalPackages = ReplicatedStorage:WaitForChild("ExternalPackages")
local ProfileStore = require(ServerScriptService.Server.Packages.ProfileStore)
local Promise = require(ExternalPackages.Promise)

local SharedPackages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))
local ReplicatedData = SharedPackages.ReplicatedData

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Data)
type PlayerProfile = Types.PlayerProfile

--// Templates
local DATA_TEMPLATE = Config.Data.dataTemplate or {}
local INFO_TEMPLATE = Config.Data.infoTemplate or {}

-- // ProfileStore Setup
local PlayerStore = ProfileStore.New("PlayerStore", DATA_TEMPLATE)
local Profiles: { [Player]: PlayerProfile } = {}

--// Module
local DataManager = {}

--// Private Variables
local ReconcileSections = {
	Info = {},
	Data = {},
}

--// Helpers

-- Deep copies a table (including nested tables)
local function deepClone(original)
	local copy = {}
	for k, v in pairs(original) do
		if typeof(v) == "table" then
			copy[k] = deepClone(v)
		else
			copy[k] = v
		end
	end
	return copy
end

-- Recursively adds missing keys from template to target
local function deepReconcile(target: {}, template: {})
	for k, v in pairs(template) do
		if typeof(v) == "table" and typeof(target[k]) == "table" then
			deepReconcile(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

-- Initializes a player profile when loaded
local function onProfileLoad(player: Player, profile: PlayerProfile)
	-- Initialise Info
	profile.Info = deepClone(INFO_TEMPLATE)

	-- Reconcile all sections into data
	DataManager:ReconcileAllSections(player, profile)

	-- Extra temporary values
	local now = os.time()
	profile.Info.JoinTime = now

	-- Analytics
	profile.Data.Analytics.TotalLogins += 1
	if not profile.Data.Analytics.InitialJoinTime then
		profile.Data.Analytics.InitialJoinTime = now
	end

	-- Save join time locally for playtime calc
	profile.Info.JoinTime = os.time()

	-- Replicate main data sections (reconciled sections are also replicated)
	ReplicatedData:SetData("PlayerData", profile.Data, { player })
	ReplicatedData:SetData("PlayerInfo", profile.Info, { player })
end

--[[ 
	Returns the profile associated with the given player.
	If yield is true, waits for it to load using a Promise.

	@param player Player — The player whose profile to retrieve.
	@param yield? boolean — If true, waits until the profile is available or the player leaves.
	@return PlayerProfile? — The player's profile, or nil if unavailable.
]]
function DataManager:GetPlayerProfile(player: Player, yield: boolean?): PlayerProfile?
	if Profiles[player] then
        return Profiles[player]
    end

	if yield then
        local success, result = self:GetPlayerProfilePromise(player):await()
		if success then
            return result
        else
            warn("[DataManager:GetPlayerProfile] Failed to yield for player profile:", result)
			return nil
        end
	end

	return nil
end

--[[ 
	Returns the data table from a player's profile.

	@param player Player — The player to get data for.
	@param yield? boolean — Whether to wait until the profile is loaded.
	@return table? — The Data section of the player's profile, or nil.
]]
function DataManager:GetPlayerData(player: Player, yield: boolean?): {}?
	local profile = self:GetPlayerProfile(player, yield)
	return profile and profile.Data or nil
end

--[[ 
	Resets a player's profile data to defaults (excluding Info).

	@param player Player — The player whose data will be reset.
	@return boolean — True if data was reset successfully.
]]
function DataManager:ResetData(player: Player): boolean
	local profile = self:GetPlayerProfile(player)
	if not profile then return false end

	profile.Data = {}
	profile:Reconcile()
	onProfileLoad(player, profile)

	warn("Reset data for", player)
	return true
end

--[[ 
	Registers a section to be reconciled into player data or info.

	@param sectionType "Info" | "Data" — The type of section.
	@param sectionName string — The key in the section table.
	@param template table — The default values to apply.
]]
function DataManager:RegisterReconcileSection(sectionType: "Info" | "Data", sectionName: string, template: {})
	ReconcileSections[sectionType][sectionName] = template
end

--[[ 
	Reconciles a specific section into the player's profile.

	@param player Player — The player whose data is reconciled.
	@param profile PlayerProfile — The profile being reconciled.
	@param sectionType "Info" | "Data" — Which section to reconcile.
	@param sectionName string — The key in the section.
	@param template table — The template values to fill in.
	@return boolean — Whether reconciliation was successful.
]]
function DataManager:ReconcileProfileSection(player: Player, profile: PlayerProfile, sectionType: "Info" | "Data", sectionName: string, template: {}): boolean
	if not profile then return false end

	if sectionType == "Info" then
		profile.Info[sectionName] = profile.Info[sectionName] or {}
		deepReconcile(profile.Info[sectionName], template)
		ReplicatedData:SetData("PlayerInfo", profile.Info, { player })
	elseif sectionType == "Data" then
		profile.Data[sectionName] = profile.Data[sectionName] or {}
		deepReconcile(profile.Data[sectionName], template)
		ReplicatedData:SetData("PlayerData", profile.Data, { player })
	end

	-- Replicate this section to the client
	local sectionTable = (sectionType == "Info") and profile.Info[sectionName] or profile.Data[sectionName]
	ReplicatedData:SetData(sectionName, sectionTable, { player })

	return true
end

--[[ 
	Reconciles all registered sections into the player's profile.

	@param player Player — The player whose profile is reconciled.
	@param profile PlayerProfile — The profile to reconcile.
]]
function DataManager:ReconcileAllSections(player: Player, profile: PlayerProfile)
	for sectionName, template in pairs(ReconcileSections.Info) do
		self:ReconcileProfileSection(player, profile, "Info", sectionName, template)
	end
	for sectionName, template in pairs(ReconcileSections.Data) do
		self:ReconcileProfileSection(player, profile, "Data", sectionName, template)
	end
end

--[[ 
	Loads a player's profile from ProfileStore.
	Kicks the player if the session cannot be started.

	@param player Player — The player to load data for.
	@return PlayerProfile? — The loaded profile, or nil on failure.
]]
function DataManager:LoadPlayerProfile(player: Player): PlayerProfile?
	local profile = PlayerStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return not player:IsDescendantOf(Players)
		end,
	})

	if not profile then
		player:Kick("Profile load failed. Please rejoin.")
		return nil
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Profile session ended. Please rejoin.")
	end)

	if player:IsDescendantOf(Players) then
		onProfileLoad(player, profile)
		Profiles[player] = profile
		return profile
	else
		profile:EndSession()
	end

	return nil
end

--[[ 
	Releases and ends a player’s profile session.
	Usually called on leave.

	@param player Player — The player to release.
]]
function DataManager:ReleasePlayerProfile(player: Player)
	local profile = Profiles[player]
	if profile then
		-- Record last leave time and update total playtime
		local now = os.time()
		profile.Data.Analytics.LastLeaveTime = now
		profile.Data.Analytics.TotalPlaytime = now - (profile.Info.JoinTime or now)
		profile:EndSession()
	end
end

--[[ 
	Promise-based version of LoadPlayerProfile.
	Resolves with profile or rejects with error/kick reason.

	@param player Player — The player to load data for.
	@return Promise<PlayerProfile>
]]
function DataManager:LoadPlayerProfileAsync(player: Player): typeof(Promise.resolve(nil))
	return Promise.new(function(resolve, reject)
		local profile = PlayerStore:StartSessionAsync(tostring(player.UserId), {
			Cancel = function()
				return not player:IsDescendantOf(Players)
			end,
		})

		if not profile then
			player:Kick("Profile load failed. Please rejoin.")
			return reject("Profile load failed.")
		end

		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick("Profile session ended. Please rejoin.")
		end)

		if player:IsDescendantOf(Players) then
			onProfileLoad(player, profile)
			Profiles[player] = profile
			return resolve(profile)
		else
			profile:EndSession()
			return reject("Player left before profile load completed.")
		end
	end)
end

--[[ 
	Promise-based version of GetPlayerProfile.
	Waits until the profile is loaded, or rejects if player leaves.

	@param player Player — The player to retrieve the profile for.
	@return Promise<PlayerProfile>
]]
function DataManager:GetPlayerProfilePromise(player: Player): typeof(Promise.resolve(nil))
	return Promise.new(function(resolve, reject)
		if Profiles[player] then
			return resolve(Profiles[player])
		end

		local connection: RBXScriptConnection?
		connection = player.AncestryChanged:Connect(function()
			if not player:IsDescendantOf(Players) then
				connection:Disconnect()
				return reject("Player left before profile was loaded.")
			end
		end)

		repeat task.wait(0.1) until not player.Parent or Profiles[player]

		if connection then connection:Disconnect() end

		if Profiles[player] then
			return resolve(Profiles[player])
		else
			return reject("Profile never loaded.")
		end
	end)
end

function DataManager:Init()
	-- Register required sections
	self:RegisterReconcileSection("Data", "Analytics", {
		TotalLogins = 0,
		TotalPlaytime = 0,
		LastLeaveTime = nil,
		InitialJoinTime = nil,
	})
end

return DataManager