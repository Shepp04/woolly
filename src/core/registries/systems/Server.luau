--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local ServerSystemRegistry = {
    Currency = require(ServerScriptService.Server.Systems.Currency).API,
}

return ServerSystemRegistry