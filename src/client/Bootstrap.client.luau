
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

-- // Show message if no Tunables found
if not ReplicatedStorage:FindFirstChild("Tunables") then
    warn("[Bootstrap] No Tunables module found in ReplicatedStorage. Using default values.")
end

local deps = {
    ReplicatedData = require(ReplicatedStorage.Shared.Packages).ReplicatedData,
    SharedPackages = require(ReplicatedStorage.Shared.Packages),
    GameData = require(ReplicatedStorage.Shared.GameData),
    Monetisation = require(ReplicatedStorage.Shared.Monetisation),
    Config = require(ReplicatedStorage.Shared.Config),
    Tunables = ReplicatedStorage:FindFirstChild("Tunables") and require(ReplicatedStorage.Tunables) or {}, -- external tunables not synced by rojo
}

local Controllers = require(script.Parent.Controllers)
Controllers.InitAll(deps)
Controllers.StartAll()

-- ========== Init ========== --
print(`[CLIENT | Loaded Successfully]`)