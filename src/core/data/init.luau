--!strict
-- // Services
local RunService = game:GetService("RunService")

return {
	Server = if RunService:IsServer() then require(script.Server) else nil,
	Client = if RunService:IsClient() then require(script.Client) else nil,
}