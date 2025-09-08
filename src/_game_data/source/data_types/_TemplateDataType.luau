--!strict
export type DataEntry = {
    id: string,
    name: string,
    icon: string?,
    rarity: "common" | "uncommon" | "rare" | "epic" | "legendary",
    stackable: boolean?,
    maxStack: number?,

    -- Server-only:
    Activated: ((player: Player, ctx: any?) -> ())?,
    ModelPath: {string}?,
    Drops: { [string]: number }?
}

type DataTypeDict = {
    name: string,
    public_field_whitelist: { [string]: boolean },
    items: { [string]: DataEntry }
}

local DATA_TYPE_NAME = "Template"
local PUBLIC_FIELD_WHITELIST = {
    id = true, name = true, icon = true, rarity = true, stackable = true, maxStack = true,
}
local DATA: { [string]: DataEntry } = {

}

local DataTypeDict: DataTypeDict = {
    name = DATA_TYPE_NAME,
    public_field_whitelist = PUBLIC_FIELD_WHITELIST,
    items = DATA,
}

return DataTypeDict