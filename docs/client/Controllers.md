# Controllers

## Introduction
**Controllers** are client-only *singleton* modules that manage the client logic for a specific system in your game. They manage state, UX, and UI through client `Components`.

## Creating a controller
To create a new controller, run:
```sh
npx woolly create controller <name> [--place <Place>]
```

---

## Location
Controller modules are stored in:

```
src/client/controllers
```

In Roblox Studio, they are mapped to:

```
StarterPlayer.StarterPlayerScripts.Client.Controllers
```

---

## Accessing Controllers

Controllers are accessed by a central registry module. Here is how to retrieve a controller:

```lua
local Controllers = require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers)

-- Example:
local MenuController = Controllers.Get("MenuController")

-- With type inference (for IntelliSense and autocomplete):
local MenuControllerTyped = Controllers.AsTyped().MenuController
```

Each controller has access to all other controllers via a `.Controllers` dictionary injected by the bootstrapper.

---

## Bootstrapping Services

To initialise and start all controller, call the following from a single client bootstrapper local script:

```lua
local Controllers = require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers)

Controllers.InitAll(deps)
Controllers.StartAll()
```

Where `deps` is a dictionary of dependency modules required by each service (e.g., `Monetisation`, `SharedPackages`).

---

## Controller Lifecycle

Each controller module should define three lifecycle methods:

- `Init(deps)` — Called once, with dependency modules passed in.
- `Start()` — Called after all controllers are initialised.
- `Destroy()` — Called to clean up connections and memory.

A controller can also optionally define a `Priority` field to control startup order.

A template is provided below.

---

## Controller Template

```lua
--!strict

export type Deps = {

}

export type Controller = {
    _inited: boolean,
    _started: boolean,
    _conns: { RBXScriptConnection },

    Init: (self: Controller, deps: Deps?) -> (),
    Start: (self: Controller) -> (),
    Destroy: (self: Controller) -> (),
}

local Controller = {
    _inited = false,
    _started = false,
    _conns = {},
    Priority = 50,
    Controllers = nil :: any?,
} :: Controller

-- // Private State
local _deps: Deps?

-- ========== Public API ========== --

-- ========== Internal ========== --

-- ========== Life Cycle ========== --
function Controller:Init(deps: Deps?)
    if self._inited then return end
    self._inited = true
    _deps = deps

    -- Example: locate UI elements
end

function Controller:Start()
    if not self._inited or self._started then return end
    self._started = true

    -- Example: start a heartbeat to update progress
end

function Controller:Destroy()
    for _, c in self._conns do c:Disconnect() end
    table.clear(self._conns)
    self._started = false
    self._inited = false
end

return Controller
```

---

## Notes

- Use the `Priority` field to control startup order of controllers. Lower values init and start first.
- Only access sibling controllers during or after `Start()`, not during `Init()` (as not all may be initialized yet).
- Keep controllers clean and focused on a single system (e.g., `MenuController`, `MonetisationController`).