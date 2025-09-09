--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemotesFolder : Folder

local Remotes = {}

-- // Private Variables
local RemoteEvents : {[string] : RemoteEvent} = {}
local RemoteFunctions : {[string] : RemoteFunction} = {}

function Remotes:GetRemote(remoteType : "RemoteEvent" | "RemoteFunction", name : string): RemoteEvent | RemoteFunction
	if (RunService:IsServer()) then
		local dict = (remoteType == "RemoteEvent" and RemoteEvents) or RemoteFunctions
		if (dict[name]) then
			return dict[name]
		end
		
		-- If not found, create the remote
		local remote = Instance.new(remoteType)
		remote.Parent = RemotesFolder
		remote.Name = name
		
		dict[name] = remote
		
		return remote
	else
		local remote = RemotesFolder:FindFirstChild(name) :: RemoteEvent | RemoteFunction
		if (not remote) then
			print(`[CLIENT | REMOTES] Waiting for {remoteType} {name}`)
			remote = RemotesFolder:WaitForChild(name, 20) :: RemoteEvent | RemoteFunction
			if not (remote) then error(("Remote %s not found!"):format(name)) end
		end
		return remote
	end
end

local function initialise()
	if (RunService:IsServer()) then
		RemotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		if not (RemotesFolder) then
			local folder = Instance.new("Folder")
			folder.Parent = ReplicatedStorage
			folder.Name = "Remotes"
			RemotesFolder = folder
		end
	else
		RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5.0)
	end
end

-- Initialisation
initialise()

return Remotes