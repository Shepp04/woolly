--!strict

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

--// Remotes and events
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Remotes"))
local ServerMessageRemote: RemoteEvent = Remotes:GetRemote("RemoteEvent", "ServerMessage")
local LocalMessageRemote: RemoteEvent = Remotes:GetRemote("RemoteEvent", "LocalMessage")

--// Assets
local UIAssets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("UI")
local DefaultGui = UIAssets:WaitForChild("MessageGui")
local SampleMessage = DefaultGui:WaitForChild("SampleMessage")

--// Constants
local isClient = RunService:IsClient()
local defaultMessageDuration = 4

--// Colours
local errorMessageColor = Color3.fromRGB(255, 0, 10)
local successMessageColor = Color3.fromRGB(10, 225, 100)
local warningMessageColor = Color3.fromRGB(255, 200, 0)

--// Module
local MessageModule = {
	DefaultProperties = {
		Text = "";
		Font = Enum.Font.FredokaOne;
		FontSize = Enum.FontSize.Size96;
		Color = Color3.fromRGB(255, 255, 255);
	},

	ChatColors = {
		Color3.fromRGB(255, 0, 0),
		Color3.fromRGB(255, 150, 0),
		Color3.fromRGB(255, 255, 0),
		Color3.fromRGB(0, 255, 0),
		Color3.fromRGB(0, 255, 255),
		Color3.fromRGB(50, 150, 255),
		Color3.fromRGB(255, 50, 200),
		Color3.fromRGB(255, 0, 255),
	},
}

--// Server/Client Message
function MessageModule.ServerMessage(properties)
	if isClient then
		local textChannel = TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXSystem")
		local color = properties.Color or Color3.fromRGB(255, 255, 255)
		local message = `<font color='#${color:ToHex()}'>${properties.Text}</font>`
		textChannel:DisplaySystemMessage(message)
	else
		ServerMessageRemote:FireAllClients(properties)
	end
end

--// Client-only Code
if isClient then
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Setup GUI
	local gui : ScreenGui = playerGui:FindFirstChild("MessageGui") or DefaultGui:Clone()
	gui.Name = "MessageGui"
	gui.Parent = playerGui

	local messages: Frame = gui:WaitForChild("Messages")

	function MessageModule:LocalMessage(text: string, msgType: "Error" | "Success" | "Warning" | nil, color: Color3?, duration: number?, override: boolean?)
		-- Search for existing frame with same message text
		local existingFrame: Frame? = nil
		for _, frame in messages:GetChildren() do
			if frame:IsA("Frame") and frame:FindFirstChild("TextLabel") then
				local label = frame.TextLabel
				local labelText = label.Text
				if labelText == text or string.sub(labelText, 1, #labelText - 3) == text then
					existingFrame = frame
					break
				end
			end
		end

		if override then
			for _, frame in messages:GetChildren() do
				if frame:IsA("Frame") and frame ~= existingFrame then
					frame:Destroy()
				end
			end
		end

		local newFrame = SampleMessage:Clone()
		local label = newFrame:WaitForChild("TextLabel")

		-- Color priority
		if msgType == "Error" then
			label.TextColor3 = errorMessageColor
		elseif msgType == "Success" then
			label.TextColor3 = successMessageColor
		elseif msgType == "Warning" then
			label.TextColor3 = warningMessageColor
		else
			label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
		end

		if existingFrame then
			local existingText = existingFrame.TextLabel.Text
			local count = tonumber(string.match(existingText, "X(%d+)$")) or 1
			label.Text = text .. " X" .. (count + 1)
			existingFrame:Destroy()
		else
			label.Text = text
		end

		newFrame.Visible = true
		newFrame.Parent = messages

		task.delay(duration or defaultMessageDuration, function()
			for i = 0, 1, 0.05 do
				if not newFrame:IsDescendantOf(messages) then return end
				label.TextTransparency = i
				if label:FindFirstChild("UIStroke") then
					label.UIStroke.Transparency = i
				end
				task.wait()
			end
			newFrame:Destroy()
		end)
	end
else
	function MessageModule:ShowMessage(...)
		LocalMessageRemote:FireClient(...)
	end
end

--// Initialization
local function initialise()
	if isClient then
		ServerMessageRemote.OnClientEvent:Connect(function(...)
			MessageModule.ServerMessage(...)
		end)

		LocalMessageRemote.OnClientEvent:Connect(function(...)
			MessageModule:LocalMessage(...)
		end)
	end
end

initialise()

return MessageModule