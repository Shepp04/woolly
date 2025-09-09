--!strict
export type PlayerConfig = {
    playerCollisionsEnabled: boolean,
    defaultWalkSpeed: number?,
}

local PlayerConfig: PlayerConfig = {
    playerCollisionsEnabled = false,
    defaultWalkSpeed = 16,
}

return PlayerConfig