--!strict

local ServiceFolder = game.ServerScriptService.Server.Services

-- Import the *types* of each service
export type DataInterface = typeof(require(ServiceFolder.DataInterface))
-- export type CurrencyService = typeof(require(ServiceFolder.CurrencyService))
-- add more services here...

-- A typed view of the services registry
export type Registry = {
    DataInterface: DataInterface,
    -- CurrencyService: CurrencyService,
    -- ...
}

return {}