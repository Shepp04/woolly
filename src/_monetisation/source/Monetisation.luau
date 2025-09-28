--!strict
-- MonetisationService (server) — hydrate, redact & publish public catalog;
-- grant gamepass perks; process developer product receipts idempotently.

-- // Services
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Datastores
local PurchaseHistoryStore
if game.PlaceVersion ~= 0 then
	PurchaseHistoryStore = DataStoreService:GetDataStore("PurchaseHistory")
else
	warn(`[MonetisationService] Please publish this place to use MonetisationService fully!`)
end

-- // Data (server-only SSOT)
local ProductDefs = require(script.Aggregator)

-- // Packages (shared replication)
local Packages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))

-- // Types
export type Deps = {
	-- Optional facade for rewarding currency, etc.
	DataInterface: any?,
	ReplicatedData: any?,
}

export type ReceiptInfo = {
	PlayerId: number,
	PurchaseId: string,
	ProductId: number,
	CurrencySpent: number?,
	PlaceIdWherePurchased: number?,
}

export type MonetisationService = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },

	_version: string,

	Init: (self: MonetisationService, deps: Deps) -> (),
	Start: (self: MonetisationService) -> (),
	Destroy: (self: MonetisationService) -> (),

	Republish: (self: MonetisationService) -> (),

	_processGamepass: (self: MonetisationService, player: Player, gamepassId: number) -> boolean,
	_processReceipt: (self: MonetisationService, receiptInfo: ReceiptInfo) -> Enum.ProductPurchaseDecision,
	_onCharacterAdded: (self: MonetisationService, player: Player, char: Model) -> (),
	_onPlayerAdded: (self: MonetisationService, player: Player) -> (),
}

local MonetisationService = {
	_inited = false,
	_started = false,
	_conns = {} :: { RBXScriptConnection },
	Priority = 50, -- start early
	Services = nil :: any, -- auto-filled by bootstrapper
} :: MonetisationService

-- // Private State
local _deps: Deps? = nil

-- // Public snapshot key (shared with resolver)
local SNAPSHOT_KEY = "MonetisationProducts"

-- ========== Redaction & Publish ========== --

--[[ Copy fields except those in blacklist (e.g. 'handler') ]]
local function redact(obj: any, blacklist: { [string]: boolean })
	local out = {}
	for k, v in obj do
		if not blacklist[k] then
			out[k] = v
		end
	end
	return out
end

--[[ Fill description/price/icon via GetProductInfo ]]
local function hydrateInfo(def: any, infoType: Enum.InfoType)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(def.id, infoType)
	end)
	if ok and info then
		def.description = info.Description or def.description
		def.priceInRobux = info.PriceInRobux or def.priceInRobux
		def.iconImageAssetId = tostring(info.IconImageAssetId or def.iconImageAssetId)
	else
		warn(("[Monetisation] GetProductInfo failed for id %s: %s"):format(tostring(def.id), tostring(info)))
	end
end

--[[ Build the public snapshot that will be replicated ]]
local function buildSnapshot()
	local snap = {
		devProducts = {} :: { [string]: any },
		gamepasses  = {} :: { [string]: any },
	}

	for name, def in ProductDefs.items.devProducts do
		hydrateInfo(def, Enum.InfoType.Product)
		snap.devProducts[name] = redact(def, ProductDefs.public_field_blacklist)
	end

	for name, def in ProductDefs.items.gamepasses do
		hydrateInfo(def, Enum.InfoType.GamePass)
		snap.gamepasses[name] = redact(def, ProductDefs.public_field_blacklist)
	end

	return snap
end

--[[ Publish the catalog snapshot to ReplicatedData ]]
function MonetisationService:Republish()
	local snapshot = buildSnapshot()
	if _deps and _deps.ReplicatedData then
		if _deps.ReplicatedData.RegisterStatic then
			_deps.ReplicatedData:RegisterStatic("MonetisationData", snapshot)
			if _deps.ReplicatedData.UpdateStatic then
				_deps.ReplicatedData:UpdateStatic("MonetisationData", snapshot)
			else
				_deps.ReplicatedData:UpdateData("MonetisationData", snapshot, nil)
			end
		else
			_deps.ReplicatedData:SetData("MonetisationData", snapshot)
			_deps.ReplicatedData:UpdateData("MonetisationData", snapshot, nil)
		end
	end
end

-- ========== Internal ========== --

--[[ Apply a single gamepass' effects by id ]]
function MonetisationService:_processGamepass(player: Player, gamepassId: number): boolean
	local passDef = ProductDefs.GetGamepassFromId(gamepassId)
	if not passDef then
		warn("[Monetisation] No Gamepass found with id:", gamepassId)
		return false
	end

	local handler = (passDef :: any).handler
	if handler ~= nil then
		local ok, err = pcall(handler, player, gamepassId)
		if not ok then
			warn(("[Monetisation] Gamepass handler error for id %d: %s"):format(gamepassId, tostring(err)))
			return false
		end
	end

	return true
end

--[[ Roblox ProcessReceipt for DevProducts (idempotent via PurchaseHistoryStore) ]]
function MonetisationService:_processReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	-- print("[Monetisation] Receipt:", receiptInfo.PlayerId, receiptInfo.ProductId, receiptInfo.PurchaseId)

	local key = (`{receiptInfo.PlayerId}_{receiptInfo.PurchaseId}`)
	
	-- Idempotency check
	local seen: boolean? = nil
	local okGet, errGet = pcall(function()
		seen = PurchaseHistoryStore:GetAsync(key)
	end)
	if okGet and seen == true then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif not okGet then
		warn("[Monetisation] Datastore GetAsync error:", errGet)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Player must be in-server
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Find product + handler
	local prod = ProductDefs.GetDevProductFromId(receiptInfo.ProductId)
	if not prod then
		warn("[Monetisation] Unknown dev product id:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted -- avoid charge loop
	end

	local handler = (prod :: any).handler
	if not handler then
		warn(("[Monetisation] Product %s (%d) has no handler."):format(prod.name, prod.id))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Execute handler (adapt if your handlers expect params/DataInterface)
	local okHandler, errHandler = pcall(function()
		handler(player, prod.id)
		-- Example if you want params/DI:
		-- handler(player, prod.id, prod.params, _deps and _deps.DataInterface)
	end)
	if not okHandler then
		warn("[Monetisation] Handler error:", errHandler)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Record purchase (safe under concurrency)
	local okSet, errSet = pcall(function()
		PurchaseHistoryStore:UpdateAsync(key, function()
			return true
		end)
	end)
	if not okSet then
		warn("[Monetisation] Record purchase failed:", errSet)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--[[ Re-apply owned gamepasses on spawn ]]
function MonetisationService:_onCharacterAdded(player: Player, _char: Model)
	for _, def in ProductDefs.items.gamepasses do
		local id = def.id
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		if ok and owns then
			self:_processGamepass(player, id)
		elseif not ok then
			warn(("[Monetisation] UserOwnsGamePassAsync failed for %s (%d)"):format(player.Name, id))
		end
	end
end

--[[ Wire per-player lifecycle ]]
function MonetisationService:_onPlayerAdded(player: Player)
	local char = player.Character or player.CharacterAdded:Wait()
	self:_onCharacterAdded(player, char)

	table.insert(self._conns, player.CharacterAdded:Connect(function(model)
		self:_onCharacterAdded(player, model)
	end))
end

-- ========== Life Cycle ========== --

--[[ Init: capture deps and publish initial redacted catalog ]]
function MonetisationService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true

	_deps = deps
	self._conns = {}

	self._version = tostring(os.time()) -- swap to a content hash later if desired

	-- Build & publish the public catalog now
	self:Republish()
end

--[[ Start: hook player/gamepass events and install ProcessReceipt ]]
function MonetisationService:Start()
	if (not self._inited) or self._started then return end
	self._started = true

	-- Existing players
	for _, plr in Players:GetPlayers() do
		self:_onPlayerAdded(plr)
	end
	table.insert(self._conns, Players.PlayerAdded:Connect(function(p)
		self:_onPlayerAdded(p)
	end))

	-- Apply gamepass after purchase prompts
	table.insert(self._conns,
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
			if wasPurchased then
				self:_processGamepass(player, gamepassId)
			end
		end)
	)

	MarketplaceService.ProcessReceipt = function(receiptInfo: ReceiptInfo)
		return self:_processReceipt(receiptInfo)
	end
end

--[[ Teardown ]]
function MonetisationService:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)

	_deps = nil
	self._started = false
	self._inited = false
end

return MonetisationService