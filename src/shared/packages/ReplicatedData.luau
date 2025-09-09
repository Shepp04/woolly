--!strict
-- // Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataRemoteEvent : RemoteEvent

-- // Constants
local DEBUG_CATEGORIES -- Categories that will print on update (for debugging)
	= {}

-- // Module // --
local ReplicatedData = {}

if RunService:IsServer() then
	-- Server code
	DataRemoteEvent = Instance.new("RemoteEvent", Remotes)
	DataRemoteEvent.Name = "GetData"
	
	ReplicatedData.Replications = {Public = {}, Private = {}}
	
	-- playertable is optional, if no table replicate to all
	function ReplicatedData:SetData(category, data, playerTable)
		if playerTable then
			-- Private data to a group of players
			table.insert(ReplicatedData.Replications.Private, {category, data, playerTable})
		else
			-- Public data
			ReplicatedData.Replications.Public[category] = data
		end
	end
	
	function ReplicatedData:UpdateData(category, data, playerTable)
		if playerTable then
			for _, localPlayer in ipairs(playerTable) do
				DataRemoteEvent:FireClient(localPlayer, category, data)
			end
		else
			DataRemoteEvent:FireAllClients(category, data)
		end
	end
	
	function ReplicatedData:RemoveData(category)
		if ReplicatedData.Replications.Public[category] then
			ReplicatedData.Replications.Public[category] = nil
		end
		for index, replicationInfo in ipairs(ReplicatedData.Replications.Private) do
			if replicationInfo[1] == category then
				table.remove(ReplicatedData.Replications.Private, index)
			end
		end
	end
	
	function ReplicatedData:RegisterStatic(category: string, value: any)
		-- Save initial value (public) and let the main loop push it
		self:SetData(category, value)
	end

	function ReplicatedData:SetStatic(category: string, value: any)
		-- Update value (public); comparison loop will detect change and broadcast
		self:SetData(category, value)
	end

	function ReplicatedData:UpdateStatic(category: string, value: any)
		-- Force a push now (skip waiting for comparison loop)
		self:UpdateData(category, value, nil)
		-- Keep Replications.Public in sync so future diffs work
		self:SetData(category, value)
	end

	DataRemoteEvent.OnServerEvent:Connect(function(p)
		-- Return all public data
		for publicCategory, publicData in pairs(ReplicatedData.Replications.Public) do
			DataRemoteEvent:FireClient(p, publicCategory, publicData)
		end
		-- Return their private data
		for _, replicationInfo in ipairs(ReplicatedData.Replications.Private) do
			local category, data, playerTable = unpack(replicationInfo)
			if table.find(playerTable, p) then
				DataRemoteEvent:FireClient(p, category, data)
			end
		end
	end)
	
	-- Main loop
	task.spawn(function()
		local publicComparisonCache = {} -- Category = cached_string
		local privateComparisonCache = {} -- userId -> { [category]: encoded }
		
		Players.PlayerRemoving:Connect(function(plr)
			privateComparisonCache[plr.UserId] = nil
		end)

		while task.wait(0.2) do
			
			-- Public data replicates to all
			for category, publicData in pairs(ReplicatedData.Replications.Public) do
				-- print("Public data:", category, publicData)
				local newEncodedString = HttpService:JSONEncode(publicData)
				if (not publicComparisonCache[category]) or newEncodedString ~= publicComparisonCache[category] then
					-- Update the data
					publicComparisonCache[category] = newEncodedString
					ReplicatedData:UpdateData(category, publicData, nil)
				end
			end
			
			-- Private data replicates to specific players
			for _, replicationInfo in pairs(ReplicatedData.Replications.Private) do
				local category, data, playerTable = unpack(replicationInfo)
				local newEncodedString = HttpService:JSONEncode(data)
				
				local userIds = {}
				for _, plr in ipairs(playerTable) do
					userIds[plr.UserId] = true
				end

				for _, plr in ipairs(playerTable) do
					local uid = plr.UserId
					privateComparisonCache[uid] = privateComparisonCache[uid] or {}

					local comparisonString = privateComparisonCache[uid][category]
					if (not comparisonString) or newEncodedString ~= comparisonString then
						-- Update the data
						privateComparisonCache[uid][category] = newEncodedString
						ReplicatedData:UpdateData(category, data, playerTable)
					end
				end
			end
		end
	end)
else
	-- Client code
	DataRemoteEvent = Remotes:WaitForChild("GetData")
	ReplicatedData.OnUpdate = Instance.new("BindableEvent")
	
	local dataContainer = {}
	
	function ReplicatedData:GetData(category, yield)
		if dataContainer[category] then
			return dataContainer[category]
		end
		
		if yield then
			local yieldStart = tick()
			repeat task.wait(0.2)
			until dataContainer[category] or (tick() - yieldStart) > 25
		end
		return dataContainer[category]
	end

	function ReplicatedData:GetStatic(category: string, yield: boolean?)
		return self:GetData(category, yield)
	end

	function ReplicatedData:OnStaticChanged(category: string, callback: (any) -> ())
		local conn
		conn = self.OnUpdate.Event:Connect(function(cat, data)
			if cat == category then
				callback(data)
			end
		end)
		return conn
	end
	
	-- Keep track of which categories have been printed to the console
	local received_categories = {}
	
	DataRemoteEvent.OnClientEvent:Connect(function(category, data)
		if not received_categories[category] then
			task.delay(1.5, print, "Data recieved: Category =", category, " Data =", data)
		elseif table.find(DEBUG_CATEGORIES, category) then
			print("Data recieved: Category =", category, " Data =", data)
		end
		received_categories[category] = true
		
		ReplicatedData.OnUpdate:Fire(category, data)
		dataContainer[category] = data
	end)
	
	-- Get initial data
	DataRemoteEvent:FireServer()
end

return ReplicatedData