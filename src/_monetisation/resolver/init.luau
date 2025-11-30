--!strict
-- Monetisation resolver with server-initiated prompts & overlay control

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Shared shapes (align with ProductDefs)
type BasePublic = {
    id: number,
    name: string,
    category: string?,
    description: string?,
    priceInRobux: number?,
    iconImageAssetId: string?,
    params: { any }?,
}
type BasePrivate = BasePublic & {
    handler: (player: Player, params: any) -> boolean,
}

type SnapshotPublic = {
    devProducts: { [string]: BasePublic },
    gamepasses:  { [string]: BasePublic },
}

local Resolver = {}

-- // Remotes
local SharedPackages = require(game.ReplicatedStorage.Shared.Packages)
local Remotes = SharedPackages.Remotes
local PromptRemote = Remotes:GetRemote("RemoteEvent", "MonetisationPrompt") :: RemoteEvent
local CreditPurchaseRemote = Remotes:GetRemote("RemoteEvent", "MonetisationCreditPurchase") :: RemoteEvent

-- Payload we’ll send server->client
-- { action = "prompt" | "show" | "hide",
--   kind = "dev" | "gp" | "auto"?,
--   id: number?,
--   name: string?,
--   show: boolean? }
--

-- ========= Client branch =========
if RunService:IsClient() then
    local Packages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))
    local ReplicatedData = Packages.ReplicatedData

    -- UI overlay
    local UIAssets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("UI")
    local MonetisationOverlay = UIAssets:FindFirstChild("MonetisationOverlay")
    local MonetisationCreditGui = UIAssets:FindFirstChild("MonetisationCreditGui")

    local CATEGORY = "MonetisationData"

    local _data: SnapshotPublic = ReplicatedData:GetStatic(CATEGORY, true) or { devProducts = {}, gamepasses = {} }
    local _devById: { [number]: BasePublic } = {}
    local _gpById:  { [number]: BasePublic } = {}
    local _currentCreditProduct: (string | number)? = nil

    local function reindex()
        table.clear(_devById); table.clear(_gpById)
        for _, d in _data.devProducts do _devById[d.id] = d end
        for _, g in _data.gamepasses  do _gpById[g.id]  = g end
    end
    reindex()

    if typeof(ReplicatedData.OnStaticChanged) == "function" then
        ReplicatedData:OnStaticChanged(CATEGORY, function(newBlob)
            if newBlob then _data = newBlob :: SnapshotPublic; reindex() end
        end)
    else
        ReplicatedData.OnUpdate.Event:Connect(function(cat, value)
            if cat == CATEGORY then _data = value :: SnapshotPublic; reindex() end
        end)
    end

    -- Overlay helpers
    local function showOverlay(player: Player?)
        if not MonetisationOverlay then return end
        local plr = player or Players.LocalPlayer
        local pg = plr and plr:FindFirstChild("PlayerGui")
        if not pg then return end
        local old = pg:FindFirstChild("MonetisationOverlay")
        if old then old:Destroy() end
        local clone = MonetisationOverlay:Clone()
        clone.Parent = pg
    end

    local function hideOverlay(player: Player?)
        local plr = player or Players.LocalPlayer
        local pg = plr and plr:FindFirstChild("PlayerGui")
        local overlay = pg and pg:FindFirstChild("MonetisationOverlay")
        if overlay then
            task.spawn(function()
                for _, v in overlay:GetChildren() do
                    if v:IsA("CanvasGroup") then
                        for i = 0, 1, 0.05 do
                            v.GroupTransparency = i
                            task.wait()
                        end
                    end
                end
                overlay:Destroy()
            end)
        end
    end

    -- Credit Gui helpers
    local function hideCreditGui()
        _currentCreditProduct = nil
        
        local plr = Players.LocalPlayer
        local pg = plr and plr:FindFirstChild("PlayerGui")
        local gui = pg and pg:FindFirstChild("MonetisationCreditGui")
        if gui then
            -- Tween out
            local cg = gui:FindFirstChildWhichIsA("CanvasGroup")
            if cg then
                local tween = TweenService:Create(cg, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
                tween:Play()
                task.spawn(function()
                    tween.Completed:Wait()
                    if gui and gui.Parent then
                        gui:Destroy()
                    end
                end)
            else
                gui:Destroy()
            end
        end
    end

    local function showCreditGui(productKey: string | number, credits: number)
        if not MonetisationCreditGui then return end
        local plr = Players.LocalPlayer
        local pg = plr and plr:FindFirstChild("PlayerGui")
        if not pg then return end
        local old = pg:FindFirstChild("MonetisationCreditGui")
        if old then old:Destroy() end
        
        _currentCreditProduct = productKey
        
        local clone = MonetisationCreditGui:Clone()
        clone.Enabled = true
        clone.Parent = pg

        -- Update description with credit count
        local frame = clone:FindFirstChild("CanvasGroup") and clone.CanvasGroup:FindFirstChild("Frame")
        if frame then
            local desc = frame:FindFirstChild("Description")
            if desc and desc:IsA("TextLabel") then
                desc.Text = (`You have {credits} free credit{credits > 1 and "s" or ""} available. Would you like to use a credit instead?`)
            end
        end

        -- Wire up buttons
        local buttons = frame and frame:FindFirstChild("Buttons")
        if buttons then
            local useBtn = buttons:FindFirstChild("Use") and buttons.Use:FindFirstChild("Select")
            local cancelBtn = buttons:FindFirstChild("Cancel") and buttons.Cancel:FindFirstChild("Select")
            
            if useBtn and useBtn:IsA("TextButton") then
                useBtn.Activated:Connect(function()
                    if _currentCreditProduct then
                        Resolver.UseCreditPurchase(_currentCreditProduct)
                        hideCreditGui()
                    end
                end)
            end
            
            if cancelBtn and cancelBtn:IsA("TextButton") then
                cancelBtn.Activated:Connect(function()
                    hideCreditGui()
                    -- Prompt normal purchase
                    if _currentCreditProduct then
                        Resolver.PromptSale(_currentCreditProduct, plr, false)
                    end
                end)
            end
        end

        -- Tween in
        local cg = clone:FindFirstChildWhichIsA("CanvasGroup")
        if cg then
            cg.GroupTransparency = 1
            local tween = TweenService:Create(cg, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 })
            tween:Play()

            local gradient = cg:FindFirstChild("Gradient") :: Frame
            if gradient and gradient:IsA("Frame") then
                gradient.BackgroundTransparency = 1
                local gradTween = TweenService:Create(gradient, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { BackgroundTransparency = 0.45 })
                gradTween:Play()
            end
        end
    end

    -- Purchase finished → auto-hide
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
        hideOverlay()
    end)
    MarketplaceService.PromptProductPurchaseFinished:Connect(function()
        hideOverlay()
    end)

    -- Public API (client)
    local function resolveEntry(kind: string?, id: number?, name: string?): BasePublic?
        if kind == "dev" then
            if id then return _devById[id] end
            if name then return _data.devProducts[name] end
        elseif kind == "gp" then
            if id then return _gpById[id] end
            if name then return _data.gamepasses[name] end
        else -- auto
            if id then return _devById[id] or _gpById[id] end
            if name then return _data.devProducts[name] or _data.gamepasses[name] end
        end
        return nil
    end

    function Resolver.GetDevProductByName(name: string): BasePublic?
        local v = _data.devProducts[name]
        if not v then warn(("[Monetisation] No dev product named %s"):format(name)) end
        return v
    end
    function Resolver.GetDevProductById(id: number): BasePublic?
        local v = _devById[id]
        if not v then warn(("[Monetisation] No dev product id %d"):format(id)) end
        return v
    end
    function Resolver.GetGamepassByName(name: string): BasePublic?
        local v = _data.gamepasses[name]
        if not v then warn(("[Monetisation] No gamepass named %s"):format(name)) end
        return v
    end
    function Resolver.GetGamepassById(id: number): BasePublic?
        local v = _gpById[id]
        if not v then warn(("[Monetisation] No gamepass id %d"):format(id)) end
        return v
    end
    function Resolver.FindByName(name: string): BasePublic?
        return _data.devProducts[name] or _data.gamepasses[name]
    end
    function Resolver.FindById(id: number): BasePublic?
        return _devById[id] or _gpById[id]
    end
    function Resolver.GetCatalog(): SnapshotPublic
        return _data
    end
    function Resolver.IsForSale(entry: BasePublic?): boolean
        return entry ~= nil and entry.priceInRobux ~= nil
    end

    -- Get credits for a product from replicated data
    function Resolver.GetCredits(productId: number): number
        local credits = ReplicatedData:GetData("MonetisationCredits", false)
        if not credits or typeof(credits) ~= "table" then
            return 0
        end
        local productKey = tostring(productId)
        return credits[productKey] or 0
    end

    -- Get all credits (returns table of productId -> count)
    function Resolver.GetAllCredits(): { [string]: number }
        local credits = ReplicatedData:GetData("MonetisationCredits", true)
        if not credits or typeof(credits) ~= "table" then
            return {}
        end
        return credits
    end

    -- Attempt to use a credit for a dev product purchase
    function Resolver.UseCreditPurchase(key: string | number): boolean
        local dev: BasePublic?
        if typeof(key) == "number" then
            dev = _devById[key]
        else
            dev = _data.devProducts[key]
        end

        if not dev then
            warn("[Monetisation] UseCreditPurchase: product not found:", key)
            return false
        end

        -- Request credit purchase from server
        CreditPurchaseRemote:FireServer(dev.id)

        return true
    end

    -- Client-local prompt (UI action on client)
    -- If checkCredits is true (default) and credits exist for dev products, will show credit GUI
    function Resolver.PromptSale(key: string | number, player: Player?, checkCredits: boolean?): boolean
        local plr = player or Players.LocalPlayer
        if not plr then return false end

        local dev: BasePublic?; local gp: BasePublic?
        if typeof(key) == "number" then
            dev = _devById[key]; gp = _gpById[key]
        else
            dev = _data.devProducts[key]; gp = _data.gamepasses[key]
        end

        if dev then
            -- Check for credits if enabled (default true)
            if checkCredits ~= false then
                local credits = Resolver.GetCredits(dev.id)
                if credits > 0 then
                    -- Show credit GUI to let user choose
                    showCreditGui(key, credits)
                    return true
                end
            end
            
            showOverlay(plr)
            MarketplaceService:PromptProductPurchase(plr, dev.id)
            return true
        elseif gp then
            showOverlay(plr)
            MarketplaceService:PromptGamePassPurchase(plr, gp.id)
            return true
        end
        return false
    end

    -- Server -> client control
    PromptRemote.OnClientEvent:Connect(function(payload: any)
        local action = payload and payload.action
        if action == "show" then
            showOverlay(Players.LocalPlayer)
        elseif action == "hide" then
            hideOverlay(Players.LocalPlayer)
        elseif action == "prompt" then
            local entry = resolveEntry(payload.kind, payload.id, payload.name)
            if not entry then return end
            if payload.show ~= false then showOverlay(Players.LocalPlayer) end
            if payload.kind == "dev" or (not payload.kind and entry and _devById[entry.id]) then
                MarketplaceService:PromptProductPurchase(Players.LocalPlayer, entry.id)
            else
                MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, entry.id)
            end
        end
    end)

    return Resolver
end

-- ========= Server branch =========
do
    local ServerScriptService = game:GetService("ServerScriptService")
    local ProductDefs = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Monetisation"):WaitForChild("Aggregator"))

    local _devByName = (ProductDefs.items and ProductDefs.items.devProducts) or {}
    local _gpByName  = (ProductDefs.items and ProductDefs.items.gamepasses)  or {}

    local _devById: { [number]: BasePrivate } = {}
    local _gpById:  { [number]: BasePrivate } = {}
    for _, d in _devByName do _devById[d.id] = d end
    for _, g in _gpByName  do _gpById[g.id]  = g end

    -- Private read helpers
    function Resolver.GetDevProductByName(name: string): BasePrivate? return _devByName[name] end
    function Resolver.GetDevProductById(id: number): BasePrivate? return _devById[id] end
    function Resolver.GetGamepassByName(name: string): BasePrivate? return _gpByName[name] end
    function Resolver.GetGamepassById(id: number): BasePrivate? return _gpById[id] end
    function Resolver.FindByName(name: string): BasePrivate? return _devByName[name] or _gpByName[name] end
    function Resolver.FindById(id: number): BasePrivate? return _devById[id] or _gpById[id] end
    function Resolver.GetCatalog()
        return { devProducts = _devByName, gamepasses = _gpByName }
    end
    function Resolver.IsForSale(entry: BasePrivate?): boolean
        return entry ~= nil and entry.priceInRobux ~= nil
    end

    -- Get credits for a player/product (requires MonetisationService)
    function Resolver.GetCredits(player: Player, productId: number): number
        local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
        local ServicesAPI = require(Services)
        local MonetisationService = ServicesAPI.Get("Monetisation")
        if MonetisationService and MonetisationService.GetCredits then
            return MonetisationService:GetCredits(player, productId)
        end
        return 0
    end

    -- ===== Server -> Client controls =====
    local function send(player: Player, payload: any)
        if not player or not player:IsDescendantOf(Players) then return end
        PromptRemote:FireClient(player, payload)
    end

    -- Force overlay show/hide from server
    function Resolver.ShowOverlay(player: Player)
        send(player, { action = "show" })
    end
    function Resolver.HideOverlay(player: Player)
        send(player, { action = "hide" })
    end

    -- Server-initiated prompt (client performs the prompt)
    -- key can be name or id; kind optionally "dev"|"gp"|"auto"
    -- If checkCredits is true and credits exist for dev products, will attempt credit purchase instead
    function Resolver.PromptSale(player: Player, key: string | number, kind: ("dev"|"gp"|"auto")?, showOverlay: boolean?, checkCredits: boolean?)
        if not player then return false end

        local payload = { action = "prompt", show = (showOverlay ~= false) } :: any
        local productId: number?
        local isDevProduct = false

        if typeof(key) == "number" then
            local d = _devById[key]; local g = _gpById[key]
            if d then payload.kind = "dev"; payload.id = d.id; productId = d.id; isDevProduct = true
            elseif g then payload.kind = "gp"; payload.id = g.id
            else
                warn("[Monetisation] Unknown id:", key); return false
            end
        else
            local d = _devByName[key]; local g = _gpByName[key]
            if d then payload.kind = "dev"; payload.id = d.id; payload.name = key; productId = d.id; isDevProduct = true
            elseif g then payload.kind = "gp"; payload.id = g.id; payload.name = key
            else
                warn("[Monetisation] Unknown name:", key); return false
            end
        end

        -- optional override
        if kind == "dev" or kind == "gp" then payload.kind = kind end

        -- Check for credits if enabled and this is a dev product
        if checkCredits ~= false and isDevProduct and productId then
            local credits = Resolver.GetCredits(player, productId)
            if credits > 0 then
                -- Try to use a credit instead of prompting purchase
                local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
                local ServicesAPI = require(Services)
                local MonetisationService = ServicesAPI.Get("Monetisation")
                if MonetisationService and MonetisationService.AttemptCreditPurchase then
                    local success = MonetisationService:AttemptCreditPurchase(player, productId)
                    return success
                end
            end
        end

        send(player, payload)
        return true
    end

    return Resolver
end