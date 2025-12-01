--!strict
-- MonetisationService (server) — hydrate, redact & publish public catalog;
-- grant gamepass perks; process developer product receipts idempotently.

-- // Services
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Datastores
local PurchaseHistoryStore = DataStoreService:GetDataStore("PurchaseHistory")

-- // Data (server-only SSOT)
local ProductDefs = require(script.Aggregator)

-- // Packages (shared replication)
local Packages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))

-- // Types (generated)
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps inferred from real modules
type ServiceRegistry = ServicesTypes.Registry

type DataInterface  = ServicesTypes.DataInterface
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	DataInterface: DataInterface,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
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

	GetCredits: (self: MonetisationService, player: Player, productId: number) -> number,
	GrantCredit: (self: MonetisationService, player: Player, productId: number) -> boolean,
	ConsumeCredit: (self: MonetisationService, player: Player, productId: number) -> boolean,
	AttemptCreditPurchase: (self: MonetisationService, player: Player, productId: number) -> boolean,

	_processGamepass: (self: MonetisationService, player: Player, gamepassId: number) -> boolean,
	_processReceipt: (self: MonetisationService, receiptInfo: ReceiptInfo) -> Enum.ProductPurchaseDecision,
	_onCharacterAdded: (self: MonetisationService, player: Player, char: Model) -> (),
	_onPlayerAdded: (self: MonetisationService, player: Player) -> (),
	_onCreditPurchaseRequested: (self: MonetisationService, player: Player, productId: number) -> (),
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

-- ========== Credit Management ========== --

--[[ Get the number of credits a player has for a specific product ]]
function MonetisationService:GetCredits(player: Player, productId: number): number
	if not _deps or not _deps.DataInterface then
		warn("[Monetisation] DataInterface not available")
		return 0
	end

	local profile = _deps.DataInterface:GetPlayerProfile(player)
	if not profile or not profile.Data then
		return 0
	end

	local credits = profile.Data.MonetisationCredits
	if not credits or typeof(credits) ~= "table" then
		return 0
	end

	local productKey = tostring(productId)
	return credits[productKey] or 0
end

--[[ Grant a credit to a player for a failed purchase ]]
function MonetisationService:GrantCredit(player: Player, productId: number): boolean
	if not _deps or not _deps.DataInterface then
		warn("[Monetisation] DataInterface not available")
		return false
	end

	local profile = _deps.DataInterface:GetPlayerProfile(player)
	if not profile or not profile.Data then
		warn("[Monetisation] Profile not available for", player.Name)
		return false
	end

	local productKey = tostring(productId)
	local credits = profile.Data.MonetisationCredits
	if not credits or typeof(credits) ~= "table" then
		profile.Data.MonetisationCredits = {}
		credits = profile.Data.MonetisationCredits
	end

	credits[productKey] = (credits[productKey] or 0) + 1

	print((`[Monetisation] Granted credit to {player.Name} for product {productId}`))

	-- Show the client a message
	if _deps.SharedPackages.Messages then
		_deps.SharedPackages.Messages:ShowMessage(player, "Purchase Failed: Free Credit Granted - try again!", "Error")
	end

	return true
end

--[[ Consume a credit for a product (returns true if credit was available and consumed) ]]
function MonetisationService:ConsumeCredit(player: Player, productId: number): boolean
	if not _deps or not _deps.DataInterface then
		warn("[Monetisation] DataInterface not available")
		return false
	end

	local profile = _deps.DataInterface:GetPlayerProfile(player)
	if not profile or not profile.Data then
		warn("[Monetisation] Profile not available for", player.Name)
		return false
	end

	local productKey = tostring(productId)
	local credits = profile.Data.MonetisationCredits
	if not credits or typeof(credits) ~= "table" then
		return false
	end

	local current = credits[productKey] or 0
	if current <= 0 then
		return false
	end

	credits[productKey] = current - 1

	return true
end

--[[ Attempt to use a credit to execute a product handler ]]
function MonetisationService:AttemptCreditPurchase(player: Player, productId: number): boolean
	-- Find the product
	local prod = ProductDefs.GetDevProductFromId(productId)
	if not prod then
		warn("[Monetisation] Unknown product id for credit purchase:", productId)
		return false
	end

	local handler = (prod :: any).handler
	if not handler then
		warn((`[Monetisation] Product {prod.name} has no handler for credit purchase`))
		return false
	end

	-- Execute handler
	local success = false
	local okHandler, result = pcall(function()
		return handler(player, prod.id, prod.params, _deps)
	end)

	if okHandler and result == true then
		-- Handler succeeded, consume the credit
		if self:ConsumeCredit(player, productId) then
			print((`[Monetisation] Credit purchase successful for {player.Name}, product {prod.name}`))
			success = true
		else
			warn("[Monetisation] Handler succeeded but failed to consume credit")
		end
	else
		-- Handler failed or returned false
		if not okHandler then
			warn("[Monetisation] Credit purchase handler error:", result)
		else
			print((`[Monetisation] Credit purchase failed for {player.Name}, product {prod.name} - handler returned false`))
		end
	end
	
	return success
end

--[[ Publish the catalog snapshot to ReplicatedData ]]
function MonetisationService:Republish()
	local snapshot = buildSnapshot()
	if _deps and _deps.SharedPackages and _deps.SharedPackages.ReplicatedData then
		if _deps.SharedPackages.ReplicatedData.RegisterStatic then
			_deps.SharedPackages.ReplicatedData:RegisterStatic("MonetisationData", snapshot)
			if _deps.SharedPackages.ReplicatedData.UpdateStatic then
				_deps.SharedPackages.ReplicatedData:UpdateStatic("MonetisationData", snapshot)
			else
				_deps.SharedPackages.ReplicatedData:UpdateData("MonetisationData", snapshot, nil)
			end
		else
			_deps.SharedPackages.ReplicatedData:SetData("MonetisationData", snapshot)
			_deps.SharedPackages.ReplicatedData:UpdateData("MonetisationData", snapshot, nil)
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
		local ok, err = pcall(handler, player, gamepassId, passDef.params, _deps)
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

	-- Execute handler
	local okHandler, result = pcall(function()
		return handler(player, prod.id, prod.params, _deps)
	end)
	if not okHandler then
		warn("[Monetisation] Handler error:", result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- If handler returned false, grant a credit for retry
	if result == false then
		print((`[Monetisation] Handler failed for {player.Name}, product {prod.name} - granting credit`))
		self:GrantCredit(player, prod.id)
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

--[[ Handle credit purchase request from client ]]
function MonetisationService:_onCreditPurchaseRequested(player: Player, productId: number)
	if typeof(productId) ~= "number" then
		warn("[Monetisation] Invalid productId in credit purchase request")
		return
	end

	-- Check if player has credits
	local credits = self:GetCredits(player, productId)
	if credits <= 0 then
		warn((`[Monetisation] {player.Name} attempted credit purchase with no credits for product {productId}`))
		return
	end

	-- Attempt the credit purchase
	self:AttemptCreditPurchase(player, productId)
end

-- ========== Life Cycle ========== --

--[[ Init: capture deps and publish initial redacted catalog ]]
function MonetisationService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true

	_deps = deps
	self._conns = {}

	self._version = tostring(os.time()) -- swap to a content hash later if desired

	-- Create remotes
	self._creditPurchaseRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "MonetisationCreditPurchase") :: RemoteEvent

	-- Register reconcile section for credits storage
	if deps.DataInterface and deps.DataInterface.RegisterReconcileSection then
		deps.DataInterface:RegisterReconcileSection("Data", "MonetisationCredits", {})
	end

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

	-- Handle credit-based purchase attempts from client
	table.insert(self._conns, self._creditPurchaseRemote.OnServerEvent:Connect(function(...)
		self:_onCreditPurchaseRequested(...)
	end))
end

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