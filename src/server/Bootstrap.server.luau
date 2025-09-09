--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ========== Data Manager ========== --
local DataManager = require(ServerScriptService.Server.Packages.DataManager)
DataManager:Init()

-- ========== Packages ========== --
local ServerPackages = require(ServerScriptService.Server.Packages)
local SharedPackages = require(ReplicatedStorage.Shared.Packages)

-- ========== Services ========== --
local deps = {
    DataInterface = require(ServerScriptService.Server.Services.DataInterface),
}

local Services = require(ServerScriptService.Server.Services)
Services.InitAll(deps)
Services.StartAll()

-- ========== Game Data ========== --
local GameDataMaster = require(ServerScriptService.Server.GameDataMaster)
GameDataMaster:Init()

-- ========== Monetisation ========== --
local Monetisation = require(ServerScriptService.Server.Monetisation)
Monetisation:Init({
    DataInterface = Services.Get("DataInterface"),
    ReplicatedData = SharedPackages.ReplicatedData,
})
Monetisation:Start()

-- ========== Init ========== --
print(`[SERVER | Loaded Successfully]`)