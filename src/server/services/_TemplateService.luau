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
    Priority = 50, -- start early
    Services = nil :: any -- auto-filled by bootstrapper
}

-- // Private State
local _deps: Deps?

-- ========== Public API ========== --

-- ========== Internal ========== --

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

    -- // Example: connect remotes
end

function Service:Destroy()
    for _, c in self._conns do c:Disconnect() end
    table.clear(self._conns)
    _deps = nil
    self._started = false
    self._inited = false
end

return Service