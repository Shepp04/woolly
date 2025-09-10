--!strict
export type SoundInfo = {
    id: string,
    playbackSpeed: number?,
    rolloffMaxDistance: number?,
    volume: number?
}

export type SoundsConfig = {
    volume: number,
    sounds: { [string]: SoundInfo },
    Get: (self: SoundsConfig, name: string) -> SoundInfo?,
}

local Sounds: SoundsConfig = {
    volume = 0.50, -- [0.00, 1.00]
    sounds = {
        UIClick01 = {
			id = "rbxassetid://4499400560",
			playbackSpeed = 1.0,
			rolloffMaxDistance = 50,
			volume = 1.00, -- [0.00, 1.00]
        },
    },
    Get = function(self: SoundsConfig, name: string)
        if self.sounds[name] then
            return self.sounds[name]
        end
        warn(`[SoundConfig] No sound with name {name}`)
    end,
}

return Sounds