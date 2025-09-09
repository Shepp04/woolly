--!strict
-- Unified accessor for both realms:
-- GameData.Get(typeName, id [, visibility])  -- visibility: "public" | "merged"
-- On client: public only (ignores visibility).
-- On server: "merged" (full) by default; pass "public" to force redacted view.

-- // Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local GameData = {}

-- // Custom Wrappers
--[[function GameData.GetItem(id: string, visibility: Types.DataVisibility?): Types.ItemPublic?
    return GameData.Get("Items", id, visibility)
--]]

if RunService:IsServer() then
    local ServerScriptService = game:GetService("ServerScriptService")
    local Master = require(ServerScriptService:WaitForChild("Server"):WaitForChild("GameDataMaster"))
	
    -- visibility: "public" | "merged" (default)
	function GameData.Get(typeName: string, id: string, visibility: ("public" | "merged")?)
		if not Master then
			warn("[GameData] Master not initialised; call GameDataMaster:Init() at server boot.")
			return nil
		end
		if visibility == "public" then
			return Master:GetPublic(typeName, id)
		else
			-- merged == full SSOT entry
			return Master:GetPrivate(typeName, id)
		end
	end

	function GameData.GetDataType(typeName: string): { [string]: any }?
		if not Master then
			warn("[GameData] Master not initialised; call GameDataMaster:Init() at server boot.")
			return nil
		end
		
		return Master:GetDataType(typeName)
	end

	function GameData.GetAllPublic()
		return Master:GetPublicBundle() or {}
	end

else
	-- Client reads the replicated static blob via your ReplicatedData
	local SharedPackages = require(ReplicatedStorage.Shared.Packages)
	local ReplicatedData = SharedPackages.ReplicatedData
	local CATEGORY = "GameData"

	local function getBlob(yieldForIt: boolean?): { version: string, data: { [string]: { [string]: any } } }?
		return ReplicatedData:GetStatic(CATEGORY, yieldForIt)
	end

	function GameData.GetDataType(typeName: string): { [string]: any }?
		local blob = getBlob(true)
		if not blob then return nil end
		if blob.data[typeName] then
			return blob.data[typeName]
		end
		warn("[GameData] No data type exists with name:", typeName)
		return nil
	end

	function GameData.Get(typeName: string, id: string)
		local blob = getBlob(true)
		if not blob then return nil end
		local byType = blob.data[typeName]
		return byType and byType[id] or nil
	end

	function GameData.GetAllPublic()
		local blob = getBlob(true)
		return blob and blob.data or {}
	end

	-- Subscribe to hot‑reloads of definitions
	function GameData.OnChanged(callback: (defs: { [string]: { [string]: any } }, version: string) -> ())
		if ReplicatedData.OnStaticChanged then
			return ReplicatedData:OnStaticChanged(CATEGORY, function(newBlob)
				if newBlob and newBlob.data then callback(newBlob.data, newBlob.version) end
			end)
		else
			return ReplicatedData.OnUpdate.Event:Connect(function(cat, data)
				if cat == CATEGORY and data and data.data then
					callback(data.data, data.version)
				end
			end)
		end
	end
end

return GameData