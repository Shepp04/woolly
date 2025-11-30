--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type Handler = Types.Handler
type GamepassPrivate = Types.GamepassPrivate

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
  ["ExampleHandler"] = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
    -- Example handler
    print("Player " .. player.Name .. " purchased gamepass " .. tostring(productId))
    return true
  end,
}

-- ========== Definitions ========== --
local defs: { gamepasses: { [string]: GamepassPrivate } } = {
  gamepasses = {
    ["ExampleGamepass"] = {
      id = 123456789,
      name = "Example Name",
      category = "Example Category",
      description = nil, -- hydrated automatically
      priceInRobux = nil, -- hydrated automatically
      iconImageAssetId = nil, -- hydrated automatically
      params = {  },
      handler = Handlers["ExampleHandler"],
    },
  },
}

return defs