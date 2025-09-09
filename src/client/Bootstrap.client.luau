
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========== Packages ========== --
local SharedPackages = require(ReplicatedStorage.Shared.Packages)
local ExternalPackages = ReplicatedStorage.Packages

-- ========== Game Data ========== --
local GameData = require(ReplicatedStorage.Shared.GameData)

-- ========== Monetisation =========== --
local Monetisation = require(ReplicatedStorage.Shared.Monetisation)

-- ========== UI/UX ========== --
local AnimatedElements

-- ========== Controllers ========== --

-- ========== Init ========== --
print(`[CLIENT | Loaded Successfully]`)