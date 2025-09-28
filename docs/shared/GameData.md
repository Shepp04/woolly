# Game Data
## Introduction
**GameData** includes any cutom data types or items used in a game, such as Pets, Items, or Currencies. This framework provides a flexible way to:
1) Define item categories and the items contained in them
2) Specify `public` (client-facing) and `private` (server-only) views of data. For example, the server can redact private handlers/models from item data
3) Find items via Ids using these separate views

---

## Location
GameData logic is stored in
```
src/_game_data
```
which contains two folders:
```
src/_game_data/resolver
```
(shared Resolver)
and
```
src/_game_data/source
```
which contains the SSOT for all items, as well as a redactor to be run by the server Bootstrapper.

## Adding a data type
To add a data type, run:
```sh
npx woolly create data_type <name> [systemName]
```
This will create and open a template data type file parented to the specified system, or to src/_game_data/source/data_types by default.

Please see the template at the bottom of this file.

## Getting Data
You can retrieve data from the server or client by accessing ReplicatedStorage.Shared.GameData (the resolver).
This module exposes the .Get() method, which is used like the example below:
```lua
local GameData = require(game.ReplicatedStorage.Shared.GameData)

local item = GameData.Get("Items", "Item1")
```

Note: you can add your own custom get wrappers towards the top of the script by pasting the below code and replacing TYPENAME with your data type:
```lua
function GameData.GetTYPENAME(id: string,  visibility: Types.DataVisibility?): Types.TYPENAMEPublic?
    return GameData.Get(TYPENAME, id, visibility)
end
```

## DataType Template
```lua
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
```