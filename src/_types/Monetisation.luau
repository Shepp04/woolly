--!strict

export type Handler = (player: Player, productId: number, params: { any }?, deps: { any }?) -> boolean

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

return {}