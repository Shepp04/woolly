
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type PlayerData = typeof(Config.DATA_TEMPLATE)
export type PlayerInfo = typeof(Config.INFO_TEMPLATE)

export type PlayerProfile = {
	Data: PlayerData,
	Info: PlayerInfo,
	Reconcile: (self: PlayerProfile) -> (),
	EndSession: (self: PlayerProfile) -> (),
	AddUserId: (self: PlayerProfile, userId: number) -> (),
	OnSessionEnd: RBXScriptSignal,
}

return {}