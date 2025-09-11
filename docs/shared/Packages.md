# Packages
## Introduction
This framework uses three types of packages: `ExternalPackages`, `SharedPackages` and `ServerPackages`. Packages are modules that contain useful methods that aren't game-specific, such as the examples below:

#### Server Packages
* DataManager
* ProfileStore

#### Shared Packages
* Remotes
* Bindables
* Sounds

#### External Packages
* Promise
* Trove

## How to install External Packages
External packages are mapped from:
```
/Packages
```
to `game.ReplicatedStorage.ExternalPackages`
and installed via the command:
```
wally install
```
To add more external packages, update the `wally.toml` to include any extra dependencies. Note that `ProfileStore` is classed as a `ServerPackage` since it is not (officially) registered with Wally.

## Creating a Package
Packages can contain code for any system, but they should be kept self-contained and reusable. `SharedPackages` are required by a simple resolver which allows for manual linking (good for intellisense), but auto-loads any remaining child modules on load. Please see the example `Debounce.luau` below:

## Debounce Example
```lua
--!strict

--[[

	DEBOUNCE MODULE
	Use to prevent rapid repeated execution of code using string keys.

	USAGE EXAMPLES:

	if not Debounce:Try("KeyName", 1) then return end
	if Debounce:IsActive("KeyName") then ...

	Debounce:Reset("KeyName")
	Debounce:ClearAll()

	Supports optional `scope` to isolate keys across systems/users:
	Debounce:Try("Jump", 2, nil, player.UserId)
]]

local Debounce = {}

-- Internal storage
local ActiveDebounces: { [string]: boolean } = {}

-- Constructs a unique key string, optionally using a scope (e.g. per-player or system)
local function getKey(key: string, scope: string?): string
	return scope and (scope .. "::" .. key) or key
end

--[[ 
	Attempts to start a debounce. Returns false if already active.

	@param key string — The debounce identifier.
	@param delay number — How long to wait before clearing the key.
	@param callback? () -> () — Optional callback to run after delay.
	@param scope? string — Optional scope to isolate keyspace.
	@return boolean — Whether the debounce started successfully.
]]
function Debounce:Try(key: string, delay: number, callback: (() -> ())?, scope: string?): boolean
	local fullKey = getKey(key, scope)

	if ActiveDebounces[fullKey] then
		return false
	end

	ActiveDebounces[fullKey] = true

	task.delay(delay, function()
		ActiveDebounces[fullKey] = nil
		if callback then callback() end
	end)

	return true
end

--[[
	Returns whether a given key is currently active.

	@param key string
	@param scope? string
	@return boolean
]]
function Debounce:IsActive(key: string, scope: string?): boolean
	return ActiveDebounces[getKey(key, scope)] == true
end

--[[
	Clears a specific debounce key early.

	@param key string
	@param scope? string
]]
function Debounce:Reset(key: string, scope: string?)
	ActiveDebounces[getKey(key, scope)] = nil
end

--[[
	Clears all debounces (use with care, especially on client).
]]
function Debounce:ClearAll()
	table.clear(ActiveDebounces)
end

return Debounce
```