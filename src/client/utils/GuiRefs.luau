--!strict

-- // Services
local Players = game:GetService("Players")

--[[
================================================================================
GuiRefs: A tiny utility module for safely retrieving common GUI instances on the client.
================================================================================

Usage example:
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local playerGui = GuiRefs.GetPlayerGui(player)
    local hud = GuiRefs.GetScreenGui(playerGui, "HUD")
    local coinsLabel = GuiRefs.Get(hud, { "TopBar", "CoinsLabel" }) :: TextLabel
    coinsLabel.Text = "0"

API:
- GuiRefs.GetPlayerGui(p: Player): PlayerGui
- GuiRefs.GetScreenGui(playerGui: PlayerGui, name: string): ScreenGui
- GuiRefs.Get(root: Instance, path: {string}): Instance

================================================================================
]]--
local GuiRefs = {}

function GuiRefs.GetPlayerGui(player: Player?): PlayerGui
	-- `PlayerGui` is a direct child of the Player object on the client.
	-- `WaitForChild` ensures we don't race against creation/replication.
	if not player then player = Players.LocalPlayer end
    return (player:WaitForChild("PlayerGui")) :: PlayerGui
end

function GuiRefs.GetScreenGui(playerGui: PlayerGui, name: string): ScreenGui
	-- Using `WaitForChild` allows UI that is created slightly later to still be found.
	return (playerGui:WaitForChild(name) :: ScreenGui)
end

function GuiRefs.Get(root: Instance, path: {string}): Instance
	-- Start from the provided root and traverse down the hierarchy.
	local cur = root
	-- Iterate deterministically through the provided path order.
	for _, name in ipairs(path) do
		-- For each segment, yield until the child exists under `cur`.
		cur = cur:WaitForChild(name)
	end
	-- At this point, `cur` is the final instance in the chain.
	return cur
end

return GuiRefs