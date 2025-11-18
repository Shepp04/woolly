--!strict
-- // Services
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Config
local PlayersConfig = require(ReplicatedStorage.Shared.Config).Players

export type Deps = {
    DataInterface: {
        LoadPlayerProfile: (player: Player, yield: boolean?) -> any,
        ReleasePlayerProfile: (player: Player) -> boolean,
    },
    SharedPackages: any,
}

export type PlayerServiceAPI = {
    _inited: boolean,
    _started: boolean,
    _conns: { RBXScriptConnection },
    _playerConns: { [Player]: { RBXScriptConnection } },

    TeleportPlayers: (self: PlayerServiceAPI, players: { Player }, cf: CFrame, offset: number?, transition: boolean?) -> (),
    Init: (self: PlayerServiceAPI, deps: Deps) -> (),
    Start: (self: PlayerServiceAPI) -> (),
    Destroy: (self: PlayerServiceAPI) -> (),
}

local PlayerService = {
    _inited = false,
    _started = false,
    _conns = {},
    Priority = 0, -- start first
    Services = nil :: any -- auto-filled by bootstrapper
}

-- // Private State
local _deps: Deps?

-- ========== Public API ========== --

function PlayerService:TeleportPlayers(players: { Player }, cf: CFrame, offset: number?, transition: boolean?)
	for _, plr in (players or Players:GetPlayers()) do
		task.spawn(function()
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then return end

			if transition then
				self._transitionRemote:FireClient(plr)
				task.wait(1)
			end

			if offset then
				local x = math.random(-offset, offset)
				local z = math.random(-offset, offset)

				root.CFrame = cf * CFrame.new(Vector3.new(x, 0, z))
			else
				root.CFrame = cf
			end
		end)
	end
end

-- ========== Internal ========== --

function PlayerService:_onCharacterAdded(player: Player, char: Model)
    -- Get their humanoid
    local human = char:WaitForChild("Humanoid") :: Humanoid

    -- Set their walkspeed
    if PlayersConfig and PlayersConfig.defaultWalkSpeed then
        human.WalkSpeed = PlayersConfig.defaultWalkSpeed
    end

    -- Update their nametag if the service is provided
    if self.Services and self.Services.NametagService then
        if self.Services.NametagService.Update then
            self.Services.NametagService:Update(player)
        end
    end

    -- Set part collision groups
    for _, v in char:GetDescendants() do
        if v:IsA("BasePart") then
            v.CollisionGroup = "Player"
        end
    end

    table.insert(self._playerConns[player], char.DescendantAdded:Connect(function(v)
        if v:IsA("BasePart") then
            v.CollisionGroup = "Player"
        end
    end))
end

function PlayerService:_onPlayerAdded(player: Player)
    print(player.Name .. " has joined the game.")

    -- Initialise conns bucket
    self._playerConns[player] = {}

    -- Initialise player data
    local profile = _deps.DataInterface:LoadPlayerProfile(player)
    if not profile then
        warn(`[PlayerService] Failed to load profile for player {player}`)
        return
    end

    -- Get their character
    local char = player.Character or player.CharacterAdded:Wait()
    self:_onCharacterAdded(player, char)

    table.insert(self._playerConns[player], player.CharacterAdded:Connect(function(...)
        self:_onCharacterAdded(player, ...)
    end))
end

function PlayerService:_onPlayerRemove(player: Player)
    print(player.Name .. " has left the game.")

    -- Cleanup player data
    _deps.DataInterface:ReleasePlayerProfile(player)

    -- Cleanup conns
    if self._playerConns[player] then
        for _, c in self._playerConns[player] do c:Disconnect() end
        self._playerConns[player] = nil
    end
end

-- ========== Life Cycle ========== --
function PlayerService:Init(deps: Deps)
    if self._inited then return end
    self._inited = true
    _deps = deps

    self._conns = {}
    self._playerConns = {}

    -- // Connect player life cycle events
    -- // Important - define this in :Init() rather than :Start()
    -- // to avoid other services e.g. CurrencyService yielding for data in :Start() as it could have
    -- // been started before PlayerService

    for _, plr in Players:GetPlayers() do
        self:_onPlayerAdded(plr)
    end
    table.insert(self._conns, Players.PlayerAdded:Connect(function(...)
        self:_onPlayerAdded(...)
    end))
    table.insert(self._conns, Players.PlayerRemoving:Connect(function(...)
        self:_onPlayerRemove(...)
    end))

    -- Register player-player collision group
    local playerCollisionsEnabled = PlayersConfig and PlayersConfig.playerCollisionsEnabled
    if not PhysicsService:IsCollisionGroupRegistered("Player") then
        PhysicsService:RegisterCollisionGroup("Player")
        PhysicsService:CollisionGroupSetCollidable("Player", "Player", playerCollisionsEnabled)
    end

    -- Create remotes
	self._transitionRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "Transition") :: RemoteEvent
end

function PlayerService:Start()
    if not self._inited or self._started then return end
    self._started = true
end

function PlayerService:Destroy()
    for _, c in self._conns do c:Disconnect() end
    table.clear(self._conns)
    _deps = nil
    self._started = false
    self._inited = false
end

return PlayerService :: PlayerServiceAPI