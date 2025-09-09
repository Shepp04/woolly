
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========== Packages ========== --
local SharedPackages = require(ReplicatedStorage.Shared.Packages)
local ExternalPackages = ReplicatedStorage.ExternalPackages

-- ========== Game Data ========== --
local GameData = require(ReplicatedStorage.Shared.GameData)

-- ========== Monetisation =========== --
local Monetisation = require(ReplicatedStorage.Shared.Monetisation)

-- ========== UI/UX ========== --
local UX = require(script.Parent.Components.UX)
UX:Init(); UX:Start()

-- ========== Controllers ========== --

-- ========== Init ========== --
print(`[CLIENT | Loaded Successfully]`)