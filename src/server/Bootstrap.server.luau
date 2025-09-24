--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ========== Data Manager ========== --
local DataManager = require(ServerScriptService.Server.Packages.DataManager)
DataManager:Init()

-- ========== Packages ========== --
local ServerPackages = require(ServerScriptService.Server.Packages)
local SharedPackages = require(ReplicatedStorage.Shared.Packages)

-- ========== Game Data ========== --
local GameDataMaster = require(ServerScriptService.Server.GameDataMaster)
GameDataMaster:Init()

-- ========== Services ========== --
local deps = {
    DataInterface = require(ServerScriptService.Server.Services.DataInterface),
    SharedPackages = require(ReplicatedStorage.Shared.Packages),
    GameData = require(ReplicatedStorage.Shared.GameData),
    Monetisation = require(ReplicatedStorage.Shared.Monetisation),
    Config = require(ReplicatedStorage.Shared.Config),
}

local Services = require(ServerScriptService.Server.Services)
Services.InitAll(deps)
Services.StartAll()

-- ========== Monetisation ========== --
local Monetisation = require(ServerScriptService.Server.Monetisation)
Monetisation:Init({
    DataInterface = Services.Get("DataInterface"),
    ReplicatedData = SharedPackages.ReplicatedData,
})
Monetisation:Start()

-- ========== Init ========== --
print(`[SERVER | Loaded Successfully]`)