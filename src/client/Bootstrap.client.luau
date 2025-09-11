
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========== Packages ========== --
local SharedPackages = require(ReplicatedStorage.Shared.Packages)
local ExternalPackages = ReplicatedStorage.ExternalPackages

-- ========== Game Data ========== --
local GameData = require(ReplicatedStorage.Shared.GameData)

-- ========== Monetisation =========== --
local Monetisation = require(ReplicatedStorage.Shared.Monetisation)

-- ========== Controllers ========== --
local Controllers = require(script.Parent.Controllers)
Controllers.InitAll()
Controllers.StartAll()

-- ========== Init ========== --
print(`[CLIENT | Loaded Successfully]`)