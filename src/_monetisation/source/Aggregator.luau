local ServerScriptService = game:GetService("ServerScriptService")
--!strict

-- // Types
export type Handler = (player: Player, productId: number, params: { any }?, deps: { any }?) -> boolean

export type DevProductPrivate = {
  id: number, name: string, category: string?, description: string?,
  priceInRobux: number?, iconImageAssetId: string?, params: { any }?,
  handler: Handler,
}

export type GamepassPrivate = DevProductPrivate

local Aggregator = {
    public_field_blacklist = { handler = true },
    items = { devProducts = {}, gamepasses = {} },
}

local function shallowMerge(dst, src)
    for k, v in src do
        dst[k] = v
    end
end

local function safeRequire(mod: Instance): any?
    local ok, ret = pcall(require, mod)
    if ok then return ret end
end

-- 1) Pull from base buckets
do
    local folder = script.Parent:FindFirstChild("product_defs")
    if folder then
        for _, child in folder:GetChildren() do
            if child:IsA("Folder") then
                for _, mod in child:GetChildren() do
                    local ok, defs = pcall(require, mod)
                    if ok and type(defs) == "table" then
                    if defs.devProducts then shallowMerge(Aggregator.items.devProducts, defs.devProducts) end
                    if defs.gamepasses  then shallowMerge(Aggregator.items.gamepasses,  defs.gamepasses)  end
                    end
                end
            else
                local ok, defs = pcall(require, child)
                if ok and type(defs) == "table" then
                    if defs.devProducts then shallowMerge(Aggregator.items.devProducts, defs.devProducts) end
                    if defs.gamepasses  then shallowMerge(Aggregator.items.gamepasses,  defs.gamepasses)  end
                end
            end
        end
    end
end

-- Validate names
do
  local seenIds = {}
  for name, def in Aggregator.items.devProducts do
    if seenIds[def.id] then warn(("[Monetisation] Duplicate DevProduct id %d (%s)"):format(def.id, name)) end
    seenIds[def.id] = true
  end
  table.clear(seenIds)
  for name, def in Aggregator.items.gamepasses do
    if seenIds[def.id] then warn(("[Monetisation] Duplicate Gamepass id %d (%s)"):format(def.id, name)) end
    seenIds[def.id] = true
  end
end

-- Lookup helpers
function Aggregator.GetDevProductFromName(name: string)
  return Aggregator.items.devProducts[name]
end
function Aggregator.GetGamepassFromName(name: string)
  return Aggregator.items.gamepasses[name]
end
function Aggregator.GetDevProductFromId(id: number)
  for _, def in Aggregator.items.devProducts do if def.id == id then return def end end
end
function Aggregator.GetGamepassFromId(id: number)
  for _, def in Aggregator.items.gamepasses do if def.id == id then return def end end
end

return Aggregator