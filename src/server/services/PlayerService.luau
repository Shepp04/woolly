--!strict
-- // Services
local Players = game:GetService("Players")

export type Deps = {
    DataInterface: {
        LoadPlayerProfile: (player: Player, yield: boolean?) -> any,
        ReleasePlayerProfile: (player: Player) -> boolean,
    },
    SharedPackages: any,
}

export type PlayerService = {
    _inited: boolean,
    _started: boolean,
    _conns: { RBXScriptConnection },

    Init: (self: PlayerService, deps: Deps) -> (),
    Start: (self: PlayerService) -> (),
    Destroy: (self: PlayerService) -> (),
}

local PlayerService = {
    _inited = false,
    _started = false,
    _conns = {},
    Priority = 99, -- start last
    Services = nil :: any -- auto-filled by bootstrapper
}

-- // Private State
local _deps: Deps?

-- ========== Public API ========== --

-- ========== Internal ========== --
function PlayerService:_onCharacterAdded(player: Player, char: Model)
    -- Update their nametag if the service is provided
    if self.Services and self.Services.NametagService then
        if self.Services.NametagService.Update then
            self.Services.NametagService:Update(player)
        end
    end
end

function PlayerService:_onPlayerAdded(player: Player)
    print(player.Name .. " has joined the game.")

    -- Initialise player data
    local profile = _deps.DataInterface:LoadPlayerProfile(player)
    if not profile then
        warn(`[PlayerService] Failed to load profile for player {player}`)
        return
    end

    -- Get their character
    local char = player.Character or player.CharacterAdded:Wait()
    self:_onCharacterAdded(player, char)

    table.insert(self._conns, player.CharacterAdded:Connect(function(...)
        self:_onCharacterAdded(player, ...)
    end))
end

function PlayerService:_onPlayerRemove(player: Player)
    print(player.Name .. " has left the game.")

    -- Cleanup player data
    _deps.DataInterface:ReleasePlayerProfile(player)
end

-- ========== Life Cycle ========== --
function PlayerService:Init(deps: Deps)
    if self._inited then return end
    self._inited = true
    _deps = deps

    self._conns = {}
end

function PlayerService:Start()
    if not self._inited or self._started then return end
    self._started = true

    -- // Connect player life cycle events
    for _, plr in Players:GetPlayers() do
        self:_onPlayerAdded(plr)
    end
    table.insert(self._conns, Players.PlayerAdded:Connect(function(...)
        self:_onPlayerAdded(...)
    end))
    table.insert(self._conns, Players.PlayerRemoving:Connect(function(...)
        self:_onPlayerRemove(...)
    end))
end

function PlayerService:Destroy()
    for _, c in self._conns do c:Disconnect() end
    table.clear(self._conns)
    _deps = nil
    self._started = false
    self._inited = false
end

return PlayerService