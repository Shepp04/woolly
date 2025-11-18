--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- // Config
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SoundsConfig = Config.Sounds

-- Constants
local IS_SERVER = RunService:IsServer()
local LOCAL_PLAYER = not IS_SERVER and Players.LocalPlayer or nil

-- Assets
local ReplicatedTemp = ReplicatedStorage:FindFirstChild("ReplicatedTemp") or Instance.new("Folder")
ReplicatedTemp.Name = "ReplicatedTemp"
ReplicatedTemp.Parent = ReplicatedStorage

-- // Types
export type SoundInfo = SoundsConfig.SoundInfo

-- RemoteEvent
local function getOrCreateRemote()
	local existing = script:FindFirstChild("PlaySound")
	if existing and existing:IsA("RemoteEvent") then return existing end

	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = "PlaySound"
	newRemote.Parent = script
	return newRemote
end

-- // Module
local SoundModule = {
	LoopingSoundCache = {},
	PlaySoundRemote = getOrCreateRemote(),
}

-- // Helpers

--- Creates a Sound instance from SoundInfo
local function createSoundFromInfo(info: SoundInfo): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = info.id
	sound.Name = "AutoSound"

    local volume = SoundsConfig.volume or 0.50
    if info.volume then
        volume *= info.volume
    end
	sound.Volume = volume

	sound.PlaybackSpeed = info.playbackSpeed or sound.PlaybackSpeed
	sound.RollOffMaxDistance = info.rolloffMaxDistance or sound.RollOffMaxDistance

	return sound
end

--- Creates a Sound from name or clones an instance
local function cloneSound(sound: Sound | string | number): Sound?
	if typeof(sound) == "string" then
		local soundInfo = SoundsConfig:Get(sound)
		if not soundInfo then
			warn("No sound found with name:", sound)
			return nil
		end
		return createSoundFromInfo(soundInfo)
	elseif typeof(sound) == "Instance" and sound:IsA("Sound") then
		return sound:Clone()
	elseif typeof(sound) == "number" then
		local soundInfo = {
			id = "rbxassetid://" .. tostring(sound),
			volume = 0.5,
		}
		return createSoundFromInfo(soundInfo)
	end
	return nil
end

--- Anchors and plays a sound at a given 3D position or BasePart
local function play3DSound(sound: Sound, target: Vector3 | BasePart)
	-- If target is a Vector3, create a transient anchored part to host the sound
	if typeof(target) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Position = target
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Name = "_SoundAnchor"
		anchor.Parent = workspace

		sound.RollOffMaxDistance = sound.RollOffMaxDistance or 150
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.PlayOnRemove = true
		sound.Parent = anchor
		-- Destroying the anchor will trigger PlayOnRemove and clean up the instance
		anchor:Destroy()
		return
	end

	-- If target is a BasePart, attach the sound to the part without modifying it
	if typeof(target) == "Instance" and target:IsA("BasePart") then
		local part = target :: BasePart
		sound.RollOffMaxDistance = sound.RollOffMaxDistance or 150
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.PlayOnRemove = false
		sound.Parent = part
		sound:Play()
		return
	end

	-- Fallback: treat as non-positional
	sound.RollOffMaxDistance = sound.RollOffMaxDistance or 150
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.PlayOnRemove = true
	sound.Parent = workspace
	sound:Destroy()
end

-- // Public API

--- Plays a one-shot sound
function SoundModule:PlaySound(sound: Sound | string | number, target: Vector3 | BasePart?, playerList: { Player }?)
	if not sound then return end

	if IS_SERVER then
		local targetPlayers = playerList or Players:GetPlayers()
		local payload = typeof(sound) == "Instance" and sound:Clone() or sound

		if typeof(payload) == "Instance" then
			payload.Parent = ReplicatedTemp
			Debris:AddItem(payload, payload.TimeLength + 3)
		end

		for _, player in targetPlayers do
			self.PlaySoundRemote:FireClient(player, payload, target)
		end
	else
		local s = cloneSound(sound)
		if not s then return end

		if target then
			play3DSound(s, target)
		else
			s.PlayOnRemove = true
			s.Parent = workspace
			s:Destroy()
		end
	end
end

--- Plays a looping sound (client-side only)
function SoundModule:PlayLoopingSound(sound: Sound | string, part: BasePart?, override: boolean?, fade: boolean?)
	if self.LoopingSoundCache[sound] and not override then return end

	local s = cloneSound(sound) :: Sound
	if not s then return end

	s.Looped = true
	s.RollOffMaxDistance = s.RollOffMaxDistance or 150
	s.Parent = part or ReplicatedTemp

	if fade then
		local initialVol = s.Volume
		s.Volume = 0
		s:Play()
		TweenService:Create(s, TweenInfo.new(1), { Volume = initialVol }):Play()
	else
		s:Play()
	end

	if self.LoopingSoundCache[sound] then
		self:StopLoopingSound(sound, false)
	end

	self.LoopingSoundCache[sound] = s
end

--- Stops a looping sound
function SoundModule:StopLoopingSound(sound: Sound | string, fade: boolean?)
	local s = self.LoopingSoundCache[sound]
	if not s then return end

	self.LoopingSoundCache[sound] = nil

	if fade then
		local tween = TweenService:Create(s, TweenInfo.new(1), { Volume = 0 })
		tween:Play()
		tween.Completed:Wait()
	end

	s:Destroy()
end

--- Toggles footstep audio on the local player
function SoundModule:ToggleFootsteps(state: boolean?)
	if IS_SERVER then
        warn(`[Sounds] Run ToggleFootsteps from the client for it to work!`)
        return
    end

    task.spawn(function()
        local char = LOCAL_PLAYER.Character or LOCAL_PLAYER.CharacterAdded:Wait()
        local root = char:WaitForChild("HumanoidRootPart")
        local running = root:WaitForChild("Running")
        
        if state == nil then
            state = running.Volume == 0
        end

        if state == true then
            -- If set to true, remove auto apply on character load
            if self._onCharacterAdded then
                self._onCharacterAdded:Disconnect()
                self._onCharacterAdded = nil
            end
        else
            -- If set to false, auto apply on character load
            if not self._onCharacterAdded then
                self._onCharacterAdded = LOCAL_PLAYER.CharacterAdded:Connect(function(char: Model)
                    local root = char:WaitForChild("HumanoidRootPart")
                    local running = root:WaitForChild("Running")
                    running.Volume = 0
                end)
            end
        end

        running.Volume = state and 0.5 or 0
    end)
end

-- // Client remote listener
if not IS_SERVER then
	SoundModule.PlaySoundRemote.OnClientEvent:Connect(function(...)
		SoundModule:PlaySound(...)
	end)
end

return SoundModule