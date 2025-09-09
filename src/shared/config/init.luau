--!strict
-- Shared Config index *typed for known modules

export type DataConfig = typeof(require(script.Data))
export type PlayerConfig = typeof(require(script.Players))
export type SoundsConfig = typeof(require(script.Sounds))

export type ConfigIndex = {
    Data: DataConfig,
    Players: PlayerConfig,
    Sounds: SoundsConfig,
    -- more types modules here
}

local Config = {} :: any

-- Typed, explicit requires
Config.Data = require(script:WaitForChild("Data"))
Config.Players = require(script:WaitForChild("Players"))
Config.Sounds = require(script:WaitForChild("Sounds"))

-- Auto-loader
for _, child in ipairs(script:GetChildren()) do
    if child:IsA("ModuleScript") and Config[child.Name] == nil then
        local ok, mod = pcall(require, child)
        if ok then Config[child.Name] = mod end
    end
end

return Config :: ConfigIndex