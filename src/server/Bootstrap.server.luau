--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ========== Packages ========== --
local ServerPackages = require(ServerScriptService.Server.Packages)
local SharedPackages = require(ReplicatedStorage.Shared.Packages)

-- ========== Game Data ========== --
local GameDataMaster = require(ServerScriptService.Server.GameDataMaster)

-- ========== Monetisation ========== --
local Monetisation = require(ServerScriptService.Server.Monetisation)

-- ========== Services ========== --
local Services = require(ServerScriptService.Server.Services)
Services.InitAll({})
Services.StartAll()

-- ========== Init ========== --
print(`[SERVER | Loaded Successfully]`)