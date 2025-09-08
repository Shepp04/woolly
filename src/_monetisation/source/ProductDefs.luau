--!strict
-- Server-only SSOT for monetisation. Do not require from clients.

-- // Types
export type Handler = (player: Player, productId: number) -> boolean

export type BaseProductPublic = {
	id: number,
	name: string,
	category: string?,
	description: string?,
	priceInRobux: number?,
	iconImageAssetId: string?,
	params: { any }?,
}
export type BaseProductPrivate = BaseProductPublic & { handler: Handler }

export type DevProductPublic = BaseProductPublic
export type DevProductPrivate = BaseProductPrivate

export type GamepassPublic = BaseProductPublic
export type GamepassPrivate = BaseProductPrivate

export type ProductDefs = {
	public_field_blacklist: { [string]: boolean },
	items: {
		devProducts: { [string]: DevProductPrivate },
		gamepasses: { [string]: GamepassPrivate },
	},

	GetDevProductFromName: (name: string)->DevProductPrivate?,
	GetGamepassFromName: (name: string)->GamepassPrivate?,
	GetDevProductFromId: (id: number)->DevProductPrivate?,
	GetGamepassFromId: (id: number)->GamepassPrivate?,
}

-- ========== Handlers ========== --
local Handlers: { devProducts: { [string]: Handler }, gamepasses: { [string]: Handler } } = {
	devProducts = {},
	gamepasses = {},
}

Handlers.devProducts.CurrencyDevProduct = function(player: Player, productId: number): boolean
	-- TODO: Grant currency etc.
	return true
end

Handlers.gamepasses.MultiplierGamepass = function(player: Player, productId: number): boolean
	-- NOTE: Gamepasses are not fulfilled via receipts; handler can be used for side-effects elsewhere.
	return true
end

-- ========== Product Defs ========== --
local ProductDefs = {} :: ProductDefs
ProductDefs.public_field_blacklist = { handler = true }
ProductDefs.items = { devProducts = {}, gamepasses = {} }

ProductDefs.items.devProducts.DevProduct01 = {
	id = 12345678,
	name = "Dev Product 01",
	category = "Currency",
	description = nil, -- hydrated later
	priceInRobux = nil, -- hydrated later
	iconImageAssetId = nil, -- hydrated later
	handler = Handlers.devProducts.CurrencyDevProduct,
	params = { value = 10, currencyId = "Cash" },
}

ProductDefs.items.gamepasses.DoubleCurrency = {
	id = 12345678,
	name = "Double Currency",
	category = "Multipliers",
	description = nil,
	priceInRobux = nil,
	iconImageAssetId = nil,
	handler = Handlers.gamepasses.MultiplierGamepass,
	params = { value = 2, currencyId = "Cash" },
}

-- Simple lookup helpers (server-side, return private entries)
function ProductDefs.GetDevProductFromName(name: string): DevProductPrivate?
	return ProductDefs.items.devProducts[name]
end

function ProductDefs.GetGamepassFromName(name: string): GamepassPrivate?
	return ProductDefs.items.gamepasses[name]
end

function ProductDefs.GetDevProductFromId(id: number): DevProductPrivate?
	for _, def in ProductDefs.items.devProducts do
		if def.id == id then return def end
	end
end

function ProductDefs.GetGamepassFromId(id: number): GamepassPrivate?
	for _, def in ProductDefs.items.gamepasses do
		if def.id == id then return def end
	end
end

return ProductDefs