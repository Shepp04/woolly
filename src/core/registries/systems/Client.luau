--!strict
local Players = game:GetService("Players")
local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

local ClientSystemRegistry = {
    Currency = require(PlayerScripts.Client.Systems.Currency).API,
}

return ClientSystemRegistry