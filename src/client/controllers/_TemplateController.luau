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