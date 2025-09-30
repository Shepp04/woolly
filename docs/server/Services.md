# Services

## Introduction
**Services** are server-only *singleton* modules that manage the logic for a specific system in your game. They act as the backbone for various backend features and run exclusively on the server.

---

## Creating a service
To create a new service, run:
```sh
npx woolly create service <name> [--place <Place>]
```

## Location
Service modules are stored in:

```
src/server/services
```

In Roblox Studio, they are mapped to:

```
ServerScriptService.Server.Services
```

---

## Accessing Services

Services are accessed via a central registry module. Here's how to retrieve a service:

```lua
local Services = require(game.ServerScriptService.Server.Services)

-- Example:
local DataInterface = Services.Get("DataInterface")

-- With type inference (for IntelliSense and autocomplete):
local DataInterfaceTyped = Services.AsTyped().DataInterface
```

Each service has access to all other services via a `.Services` dictionary injected by the bootstrapper.

---

## Bootstrapping Services

To initialise and start all services, call the following from a single bootstrapper script:

```lua
local Services = require(ServerScriptService.Server.Services)

Services.InitAll(deps)
Services.StartAll()
```

Where `deps` is a dictionary of dependency modules required by each service (e.g., `DataInterface`, `SharedPackages`).

---

## Service Lifecycle

Each service module should define three lifecycle methods:

- `Init(deps)` — Called once, with dependency modules passed in.
- `Start()` — Called after all services are initialised.
- `Destroy()` — Called to clean up connections and memory.

A service can also optionally define a `Priority` field to control startup order.

A template is provided in `/src/server/_templates`.

---

## Service Template

```lua
--!strict

export type Deps = {
    DataInterface: {
        GetPlayerProfile: (player: Player, yield: boolean?) -> any,
        RegisterReconcileSection: (sectionType: "Info" | "Data", sectionName: string, template: {}) -> boolean,
    },
    SharedPackages: any,
}

export type Service = {
    _inited: boolean,
    _started: boolean,
    _conns: { RBXScriptConnection },

    Init: (self: Service, deps: Deps) -> (),
    Start: (self: Service) -> (),
    Destroy: (self: Service) -> (),
}

local Service = {
    _inited = false,
    _started = false,
    _conns = {},
    Priority = 50, -- Optional: higher priority services start earlier
    Services = nil :: any, -- Auto-filled by bootstrapper
}

-- // Private Dependencies
local _deps: Deps?

-- ========== Life Cycle ========== --

function Service:Init(deps: Deps)
    if self._inited then return end
    self._inited = true
    _deps = deps
    self._conns = {}
end

function Service:Start()
    if not self._inited or self._started then return end
    self._started = true

    -- Example: connect remotes, start tasks, etc.
end

function Service:Destroy()
    for _, conn in self._conns do
        conn:Disconnect()
    end
    table.clear(self._conns)
    _deps = nil
    self._started = false
    self._inited = false
end

return Service :: Service
```

---

## Notes

- Use the `Priority` field to control startup order of services. Lower values init and start first.
- Only access sibling services during or after `Start()`, not during `Init()` (as not all may be initialized yet).
- Keep services clean and focused on a single system (e.g., `MatchmakingService`, `CurrencyService`, `InventoryService`).