--!strict
-- ServerScriptService/GameDataMaster/init.luau
-- SSOT + runtime redaction + static publish via ReplicatedData
-- Usage (once at server boot):
--   local GameDataMaster = require(path.to.GameDataMaster):Init() -- auto-publishes
-- Or:
--   require(...):Init({ container = script:WaitForChild("data_types"), autoPublish = true })

-- // Services
local RunService = game:GetService("RunService")
assert(RunService:IsServer(), "GameDataMaster must be required on the server")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Packages
local SharedPackages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))
local ReplicatedData = SharedPackages.ReplicatedData

export type DataTypeDict = {
	name: string,
	-- whitelist can be boolean (shallow) or string "deep" to force deep copy
	public_field_whitelist: { [string]: boolean | "deep" },
	items: { [string]: { [string]: any } },
}

local GameDataMaster = {}
GameDataMaster.__index = GameDataMaster

-- ===== internal state (singleton) =====
GameDataMaster._inited = false
GameDataMaster._privateByType = {} :: { [string]: DataTypeDict }      -- full SSOT per type (frozen entries)
GameDataMaster._publicByType  = {} :: { [string]: { [string]: any } } -- redacted per type (frozen entries)
GameDataMaster._version = ""                                          -- simple timestamp or a hash

-- ===== utils =====

local function deepCopy(v: any): any
	if typeof(v) ~= "table" then return v end
	local t = table.create(#v)
	for k, x in pairs(v) do
		t[k] = deepCopy(x)
	end
	return t
end

local function copyWithWhitelist(src: { [string]: any }, wl: { [string]: boolean | "deep" })
	local out = {}
	for k, mode in pairs(wl) do
		local v = src[k]
		if v ~= nil then
			out[k] = (mode == "deep") and deepCopy(v) or v
		end
	end
	-- Public entries should be immutable to consumers
	if not table.isfrozen(out) then table.freeze(out) end
	return out
end

local function redactTypeDict(dict: DataTypeDict): { [string]: any }
	local public = {}
	for id, def in pairs(dict.items) do
		public[id] = copyWithWhitelist(def, dict.public_field_whitelist)
	end
	-- The *map* may be frozen later; each entry is already frozen individually.
	return public
end

local function freezeIfNeeded(t: any)
	if typeof(t) == "table" and not table.isfrozen(t) then
		table.freeze(t)
	end
end

-- ===== ingest =====

--[[
	Ingests all DataType modules under `container`:
	- Requires each ModuleScript (skips "init")
	- Validates the dict shape
	- Builds server-private and client-public maps

	@param container Instance  (folder containing DataType modules)
]]
function GameDataMaster:_ingest(container: Instance)
	if not container then
		warn(`[GameDataMaster] No container or data types provided!`)
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") and child.Name ~= "init" then
			local ok, dictOrErr = pcall(require, child)
			if not ok then
				warn("[GameDataMaster] Failed to require:", child:GetFullName(), dictOrErr)
			elseif typeof(dictOrErr) ~= "table" then
				warn("[GameDataMaster] Module did not return a table:", child:GetFullName())
			else
				local dict = dictOrErr :: DataTypeDict
				if not (dict.name and dict.public_field_whitelist and dict.items) then
					warn("[GameDataMaster] Bad data dict (missing fields) in", child:GetFullName())
				else
					self._privateByType[dict.name] = dict
					self._publicByType[dict.name]  = redactTypeDict(dict)
				end
			end
		end
	end

	-- Freeze top-level maps to discourage mutation (guard against re-freezing).
	for _, v in pairs(self._privateByType) do freezeIfNeeded(v) end
	for _, v in pairs(self._publicByType)  do freezeIfNeeded(v) end
	freezeIfNeeded(self._privateByType)
	freezeIfNeeded(self._publicByType)
end

-- ===== public API (server) =====

--[[
	Returns a dictionary of items for a data type
	Warns user if type doesn't exist
]]
function GameDataMaster:GetDataType(typeName: string): any
	if self._privateByType[typeName] then
		return self._privateByType[typeName]
	end
	warn("[GameDataMaster] No data type exists with name:", typeName)
	return nil
end

--[[
	Returns a *private* (server) definition entry by type & id.
	@readonly to consumers; do not mutate returned tables.
]]
function GameDataMaster:GetPrivate(typeName: string, id: string): any
	local dict = self._privateByType[typeName]
	return dict and dict.items[id] or nil
end

--[[
	Returns a *public* (client-safe) definition entry by type & id.
	@readonly to consumers; do not mutate returned tables.
]]
function GameDataMaster:GetPublic(typeName: string, id: string): any
	local dict = self._publicByType[typeName]
	return dict and dict[id] or nil
end

--[[
	Returns the full public bundle: { [typeName]: { [id]: entry } }
	Safe to return by reference (frozen).
]]
function GameDataMaster:GetPublicBundle(): { [string]: { [string]: any } }
	return self._publicByType
end

--[[
	Returns the current data version string (timestamp or hash).
]]
function GameDataMaster:GetVersion(): string
	return self._version
end

--[[
	Publishes the public bundle to clients via ReplicatedData under "GameData".
	If ReplicatedData:RegisterStatic exists, uses that and triggers an immediate push.
]]
function GameDataMaster:PublishStatic()
	local payload = {
		version = self._version,
		data = self:GetPublicBundle(), -- { Items = {...}, Pets = {...}, ... }
	}
	if ReplicatedData.RegisterStatic then
		ReplicatedData:RegisterStatic("GameData", payload)
		if ReplicatedData.UpdateStatic then
			ReplicatedData:UpdateStatic("GameData", payload)
		else
			ReplicatedData:UpdateData("GameData", payload, nil)
		end
	else
		ReplicatedData:SetData("GameData", payload)
		ReplicatedData:UpdateData("GameData", payload, nil)
	end
end

-- ===== init (singleton) =====

--[[
	Initialises once (idempotent). Reads DataTypes, builds public/private bundles,
	sets a version string, and (by default) publishes to clients.

	@param opts? { container: Instance?, autoPublish: boolean? }
	        container    — Folder containing DataType modules. Defaults to script:WaitForChild("data_types")
	        autoPublish  — If true (default), calls :PublishStatic() after ingest.

	@return GameDataMaster (module table)
]]
function GameDataMaster:Init(opts: { container: Instance?, autoPublish: boolean? }?)
	if self._inited then
		return self
	end
	self._inited = true

	local container = (opts and opts.container) or script:FindFirstChild("data_types")
	self._privateByType = {}
	self._publicByType  = {}
	self._version = tostring(os.time()) -- swap to a content hash later if desired

	self:_ingest(container)

	if not (opts and opts.autoPublish == false) then
		self:PublishStatic()
	end

	return self
end

return GameDataMaster