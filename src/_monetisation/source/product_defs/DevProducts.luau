--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type DevProductPrivate = Types.DevProductPrivate
type Handler = Types.Handler

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
    CurrencyDevProduct = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
        -- TODO: Grant currency etc.
        print("Granted")
        return true
    end,
}

-- ========== Definitions ========== --
local defs: { devProducts: { DevProductPrivate } } = {
    devProducts = {
        DevProduct01 = {
            id = 1151725677,
            name = "Dev Product 01",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 10, currencyId = "Cash" },
        }
	},
}

return defs