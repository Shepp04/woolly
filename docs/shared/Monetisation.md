# Monetisation
## Introduction
This framework provides a flexible and extensible **Monetisation** system. It uses a SSOT so that all monetisation data is defined in one place (on the server). At load time, the server redacts any sensitive fields (handlers etc.) and provides the client with a public view of `DevProducts` and `Gamepasses`

## Location
All monetisation logic is contained in:
```
src/_monetisation
```
Which, like GameData, includes a resolver (shared) and source (server-only) folders.

To add product definitions and handlers, edit the following module:
```
src/_monetisation/source/ProductDefs.luau
```

## Adding a Product
To add a dev product or gamepass, navigate to the `ProductDefs` section of ProductDefs.luau. Copy the templates, and remember to set the handler field and appropriate parameters. An example is shown below:

```lua
DevProduct01 = {
	id = 1151725677,
	name = "Dev Product 01",
	category = "Currency",
	description = nil, -- hydrated later
	priceInRobux = nil, -- hydrated later
	iconImageAssetId = nil, -- hydrated later
	handler = Handlers.devProducts.CurrencyDevProduct,
	params = { value = 10, currencyId = "Cash" },
},
```

`handler` can be any function of type `Handler` and it may be useful to define generic handlers such as CurrencyDevProduct that can be called with the appropriate params

`params` is a dictionary of any type, depending on your handler requirements for that type of product.

**Note:** `Gamepasses` are handled on character load and on `PromptGamepassPurchaseFinished`, not in `ProcessReceipt`

## Prompting a sale
To prompt a sale on the server or client, require the resolver, and call `.PromptSale()` providing the player if on the server (defaults to `game.Players.LocalPlayer` on client). Please see the examples below:
```lua
local MonetisationResolver = require(game.ReplicatedStorage.Shared.Monetisation)

-- Server
MonetisationResolver.PromptSale("DevProduct01", player)

-- Client
MonetisationResolver.PromptSale("Gamepass01")
```

**Note:** this single method works for gamepasses and dev products, and shows/hides a Gui overlay. This Gui can be modified by replacing the model at:
```
src/shared/assets/ui/MonetisationOverlay.rbxmx
```

## GetProductInfo
At load time, the monetisation server module calls `game.MarketplaceService:GetProductInfo` for each product during snapshot building. Always check that the fields:
* priceInRobux
* iconImageAssetId
* description

Are not nil before using them.