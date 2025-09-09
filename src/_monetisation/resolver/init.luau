--!strict
-- Shared resolver: read public catalog from ReplicatedData and provide helpers

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Packages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))
local ReplicatedData = Packages.ReplicatedData

-- // Assets
local UIAssets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("UI")
local MonetisationOverlay = UIAssets:WaitForChild("MonetisationOverlay")

-- // Constants
local SNAPSHOT_KEY = "MonetisationData"

type BasePublic = {
	id: number,
	name: string,
	category: string?,
	description: string?,
	priceInRobux: number?,
	iconImageAssetId: string?,
	params: { any }?,
}
type Snapshot = {
	devProducts: { [string]: BasePublic },
	gamepasses:  { [string]: BasePublic },
}

-- Local cache + indexes
local _data: Snapshot = ReplicatedData:GetData(SNAPSHOT_KEY, true) or { devProducts = {}, gamepasses = {} }
local _devById: { [number]: BasePublic } = {}
local _gpById:  { [number]: BasePublic } = {}

local function reindex()
	_devById = {}; _gpById = {}
	for _, d in _data.devProducts do _devById[d.id] = d end
	for _, g in _data.gamepasses  do _gpById[g.id] = g end
end
reindex()

-- Keep fresh on client
if not RunService:IsServer() then
	ReplicatedData.OnUpdate.Event:Connect(function(category: string, value: any)
		if category == SNAPSHOT_KEY then
			_data = value :: Snapshot
			reindex()
		end
	end)
end

-- ========== Internal ========== --
local Resolver = {}
function Resolver._showOverlay(player: Player?)
    local player = player or Players.LocalPlayer
    if not player then
        warn("[MonetisationPublic] Show Overlay error: missing player argument")
        return
    end

    local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui then
		local old = playerGui:FindFirstChild("MonetisationOverlay")
		if old then old:Destroy() end
		
		local overlayGui = MonetisationOverlay:Clone()
		overlayGui.Parent = playerGui
	end
end

function Resolver._hideOverlay(player: Player?)
    local player = player or Players.LocalPlayer
    if not player then
        warn("[MonetisationPublic] Show Overlay error: missing player argument")
        return
    end

    local playerGui = player:FindFirstChild("PlayerGui")
	local overlayGui = playerGui and playerGui:FindFirstChild("MonetisationOverlay")
	if overlayGui then
		task.spawn(function()
			for _, v in overlayGui:GetChildren() do
				if (v:IsA("CanvasGroup")) then
					for i = 0, 1, 0.05 do
						v.GroupTransparency = i
						task.wait()
					end
				end
			end
			overlayGui:Destroy()
		end)
	end
end

-- ========== Public API ========== --

function Resolver.GetDevProductByName(name: string): BasePublic?
	if _data.devProducts[name] then
        return _data.devProducts[name]
    end
    warn(`[MonetisationPublic] No dev product with name {name}`)
    return nil
end

function Resolver.GetDevProductById(id: number): BasePublic?
	if _devById[id] then
        return _devById[id]
    end
    warn(`[MonetisationPublic] No dev product with id {id}`)
    return nil
end

function Resolver.GetGamepassByName(name: string): BasePublic?
	if _data.gamepasses[name] then
        return _data.gamepasses[name]
    end
    warn(`[MonetisationPublic] No gamepass with name {name}`)
    return nil
end

function Resolver.GetGamepassById(id: number): BasePublic?
	if _gpById[id] then
        return _gpById[id]
    end
    warn(`[MonetisationPublic] No gamepass with id {id}`)
    return nil
end

function Resolver.FindByName(name: string): BasePublic?
	return _data.devProducts[name] or _data.gamepasses[name]
end
function Resolver.FindById(id: number): BasePublic?
	return _devById[id] or _gpById[id]
end

function Resolver.GetCatalog(): Snapshot
	return _data
end

-- Convenience: check if a catalog entry reports for sale
function Resolver.IsForSale(entry: BasePublic?): boolean
	return entry ~= nil and entry.priceInRobux ~= nil
end

-- Prompt by name or id (dev product or gamepass)
function Resolver.PromptSale(key: string | number, player: Player?)
    player = player or Players.LocalPlayer
    if not player then
        warn(`[MonetisationPublic] Prompt Sale error: no player provided`)
        return
    end

    -- Find the dev product or gamepass to sell
    local dev, gp
	if typeof(key) == "number" then
		dev = _devById[key]; gp = _gpById[key]
	else
		dev = _data.devProducts[key]; gp = _data.gamepasses[key]
	end

	if dev then
        Resolver._showOverlay(player)
		MarketplaceService:PromptProductPurchase(player, dev.id)
		return true
	elseif gp then
        Resolver._showOverlay(player)
		MarketplaceService:PromptGamePassPurchase(player, gp.id)
		return true
	end
	return false
end

local function initialise()
    if RunService:IsClient() then
        MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
            Resolver._hideOverlay()
        end)
        MarketplaceService.PromptProductPurchaseFinished:Connect(function()
            Resolver._hideOverlay()
        end)
    end
end

-- Initialisation
initialise()

return Resolver