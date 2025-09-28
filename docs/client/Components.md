# Components

## Introduction
**Components** are client class modules that handle UI elements and self-contained client systems.

## Creating a component
To create a new component, run:
```sh
npx woolly create component <name> [--place <Place>]
```

---

## Location
Component modules are stored in:

```
src/client/components
```

In Roblox Studio, they are mapped to:

```
StarterPlayer.StarterPlayerScripts.Client.Components
```

---

## Accessing Components

Components are accessed manually by requiring them typically inside a `Controller`.

---

## Component Lifecycle

Each component class should define three lifecycle methods:

- `.new(args)` — The constructor. Pass arguments here.
- `Start()` — Call this method to setup connections and start running the component.
- `Destroy()` — Called to clean up connections and memory.

A template is provided below.

---

## Component Template

```lua
--!strict

export type Deps = {

}

export type Component = {
    _started: boolean,
    _deps: Deps?,
    _conns: { RBXScriptConnection },

    Start: (self: Component) -> (),
    Destroy: (self: Component) -> (),
}

local Component = {}
Component.__index = Component

-- ========== Constructor ========== --
function Component.new(deps: Deps?): Component
    local self = setmetatable({} :: any, Component) :: Component
    self._started = false
    self._deps = deps
    self._conns = {}
    return self
end

-- ========== Public API ========== --

-- ========== Internal ========== --

-- ========== Life Cycle ========== --
function Component:Start()
    if self._started then return end
    self._started = true
end

function Component:Destroy()
    for _, c in self._conns do c:Disconnect() end
    table.clear(self._conns)
    self._started = false
end

return Component
```

---