--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BindablesFolder : Folder

local Bindables = {}

-- // Private Variables
local BindableEvents : {[string] : BindableEvent} = {}
local BindableFunctions : {[string] : BindableFunction} = {}

function Bindables:GetBindable(bindableType : "BindableEvent" | "BindableFunction", name : string): BindableEvent | BindableFunction
	if (RunService:IsServer()) then
		local dict = (bindableType == "BindableEvent" and BindableEvents) or BindableFunctions
		if (dict[name]) then
			return dict[name]
		end
		
		-- If not found, create the bindable
		local bindable = Instance.new(bindableType)
		bindable.Parent = BindablesFolder
		bindable.Name = name
		
		dict[name] = bindable
		
		return bindable
	else
		local bindable = BindablesFolder:FindFirstChild(name) :: BindableEvent | BindableFunction
		if not bindable then
			print(`[SERVER | BINDABLES] Waiting for {bindableType} {name}`)
			bindable = BindablesFolder:WaitForChild(name, 20) :: BindableEvent | BindableFunction
			if not bindable then error(("Bindable %s not found!"):format(name)) end
		end
		return bindable
	end
end

local function initialise()
	-- Check for a bindables folder,
	-- If it doesn't exist then create one - either ServerStorage or ReplicatedStorage
	if (RunService:IsServer()) then
		local ServerStorage = game:GetService("ServerStorage")
		BindablesFolder = ServerStorage:FindFirstChild("Bindables")
		if not (BindablesFolder) then
			local folder = Instance.new("Folder")
			folder.Parent = ServerStorage
			folder.Name = "Bindables"
			BindablesFolder = folder
		end
	else
		BindablesFolder = ReplicatedStorage:FindFirstChild("Bindables")
		if not (BindablesFolder) then
			local folder = Instance.new("Folder")
			folder.Parent = ReplicatedStorage
			folder.Name = "Bindables"
			BindablesFolder = folder
		end
	end
end

-- Initialisation
initialise()

return Bindables