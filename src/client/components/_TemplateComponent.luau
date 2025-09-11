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