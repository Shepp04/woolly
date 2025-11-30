# Monetisation Credit System

## Overview

The credit system provides a robust way to handle developer product purchases that may fail due to transient conditions (e.g., player left game, match ended, target unavailable). When a purchase handler fails, players receive a **credit** that can be used to retry the effect without paying again.

## How It Works

### 1. Handler Return Values

Dev product handlers should return a **boolean**:
- `true` - Effect successfully applied, purchase/credit consumed
- `false` - Effect failed to apply, credit granted for retry

```lua
-- Example: Powerup that requires an active game
local function PowerupHandler(player: Player, productId: number, params: any, deps: any): boolean
    local gameActive = deps.Services.GameService:IsGameActive()
    local target = deps.Services.GameService:GetPlayerTarget(player)
    
    if not gameActive or not target then
        -- Game ended or target left - return false to grant credit
        return false
    end
    
    -- Apply the powerup effect
    target:TakeDamage(params.damage)
    return true -- Success, consume the purchase
end
```

### 2. Automatic Credit Granting

When a handler returns `false`, the MonetisationService automatically:
1. Records the purchase as processed (no refund loop)
2. Grants a credit to the player for that specific product
3. Logs the credit grant

### 3. Credit Storage

Credits are stored in player profiles via the DataInterface:
- **Location**: `profile.Data.MonetisationCredits`
- **Format**: Dictionary `{ [productId: string]: count: number }`
- **Replication**: Automatically synced to clients via ReplicatedData
- **Persistence**: Credits persist across sessions in player profiles

### 4. Using Credits

#### Server-Side (Recommended)

When calling `PromptSale` from the server, credits are checked automatically:

```lua
-- In a server service
local Monetisation = require(ReplicatedStorage.Shared.Monetisation)

-- checkCredits defaults to true - will use credit if available
Monetisation.PromptSale(player, "SuperPowerup", "dev", true, true)

-- Or explicitly disable credit checking
Monetisation.PromptSale(player, "SuperPowerup", "dev", true, false)
```

**Behavior**:
- If player has credits: Attempts credit purchase immediately
- If no credits: Shows normal Roblox purchase prompt
- If credit purchase fails: Credit is NOT consumed

#### Client-Side

Players can check credits locally and manually use them:

```lua
-- In a client controller
local Monetisation = require(ReplicatedStorage.Shared.Monetisation)

-- Check if player has credits (local, no server call needed)
local credits = Monetisation.GetCredits(productId)
if credits > 0 then
    print("You have", credits, "free attempts!")
    
    -- Use a credit (sends request to server)
    Monetisation.UseCreditPurchase(productId)
else
    -- No credits, prompt normal purchase
    Monetisation.PromptSale(productId)
end

-- Or check all credits at once
local allCredits = Monetisation.GetAllCredits()
for productId, count in allCredits do
    print(`Product {productId}: {count} credits`)
end
```

## API Reference

### Server API

#### `MonetisationService:GetCredits(player: Player, productId: number): number`
Returns the number of credits a player has for a specific product.

#### `MonetisationService:GrantCredit(player: Player, productId: number): boolean`
Manually grant a credit to a player. Returns true on success.

#### `MonetisationService:ConsumeCredit(player: Player, productId: number): boolean`
Manually consume a credit. Returns true if credit was available and consumed.

#### `MonetisationService:AttemptCreditPurchase(player: Player, productId: number): boolean`
Attempts to execute a product handler using a credit. Only consumes credit if handler succeeds.

### Resolver API (Client & Server)

#### `Monetisation.GetCredits(productId: number): number` (Client)
Get credit count for a product from local replicated data. Returns 0 if no credits.

#### `Monetisation.GetAllCredits(): { [string]: number }` (Client)
Get all credits as a dictionary of productId -> count.

#### `Monetisation.UseCreditPurchase(key: string | number): boolean` (Client)
Request a credit-based purchase from the server.

#### `Monetisation.PromptSale(player, key, kind?, showOverlay?, checkCredits?)` (Server)
- **checkCredits** (default: true) - If true, checks for credits before prompting purchase

#### `Monetisation.GetCredits(player: Player, productId: number): number` (Server)
Get credit count for a player/product.

## Best Practices

### 1. Clear Failure Conditions

Define clear conditions for when a purchase should fail:

```lua
local function Handler(player, productId, params, deps): boolean
    -- Check all preconditions
    if not player:IsDescendantOf(game.Players) then
        return false -- Player left
    end
    
    local match = deps.Services.MatchService:GetPlayerMatch(player)
    if not match or match.State ~= "Active" then
        return false -- No active match
    end
    
    -- Apply effect
    match:ApplyPowerup(player, params.powerup)
    return true
end
```

### 2. User Feedback

Inform players about credits:

```lua
-- Server-side after failed purchase
local credits = MonetisationService:GetCredits(player, productId)
Remotes:GetRemote("RemoteEvent", "ShowNotification"):FireClient(
    player,
    `Purchase saved! You have {credits} free attempt(s) remaining.`
)
```

### 3. Credit Limits (Optional)

Consider implementing maximum credit caps to prevent abuse:

```lua
function MonetisationService:GrantCredit(player: Player, productId: number): boolean
    local current = self:GetCredits(player, productId)
    if current >= 5 then
        warn("Credit limit reached for player", player.Name)
        return false
    end
    -- ... grant credit
end
```

### 4. Credit Expiry (Future Enhancement)

For time-sensitive products, consider storing timestamps and implementing expiry:

```lua
-- Store as: { count = 3, expiry = os.time() + 86400 }
-- Check expiry before allowing credit use
```

## Example: Match-Based Powerup

```lua
-- In DevProducts.luau
local Handlers: { [string]: Handler } = {
    RespawnBoost = function(player: Player, productId: number, params: any, deps: any): boolean
        local MatchService = deps.Services.MatchService
        local match = MatchService:GetPlayerMatch(player)
        
        if not match then
            -- Player not in a match
            print(`[Monetisation] {player.Name} purchased RespawnBoost but not in match - granting credit`)
            return false
        end
        
        if match.State ~= "Active" then
            -- Match ended or not started
            print(`[Monetisation] {player.Name} purchased RespawnBoost but match not active - granting credit`)
            return false
        end
        
        -- Apply the boost
        match:ApplyRespawnBoost(player, params.duration)
        return true
    end,
}

local defs: { devProducts: { DevProductPrivate } } = {
    devProducts = {
        {
            id = 123456789,
            name = "RespawnBoost",
            category = "powerups",
            params = { duration = 30 },
            handler = Handlers.RespawnBoost,
        },
    },
}
```

## Troubleshooting

### Credits Not Being Granted

1. Check handler is returning `false` (not nil or error)
2. Verify DataInterface is properly initialized
3. Check player profile exists and is loaded
4. Check server output for "[Monetisation] Granted credit..." messages

### Credits Not Being Consumed

1. Ensure handler returns `true` on success
2. Check player profile exists
3. Verify ConsumeCredit is called after successful handler execution
4. Check ReplicatedData updates are syncing to client

### Race Conditions

The credit system uses profile-based storage with automatic replication:
- Credits stored in `profile.Data.MonetisationCredits` 
- Changes automatically synced to client via ReplicatedData
- Profile system handles concurrent access safely
- No race conditions between credit checks and consumption

## Migration

Existing handlers that don't return a value are treated as successful (default behavior). To enable credits, simply add return statements:

```lua
-- Before (always consumes purchase)
handler = function(player, productId, params, deps)
    player.Stats.Coins.Value += params.amount
end

-- After (can grant credits on failure)
handler = function(player, productId, params, deps): boolean
    if not player:IsDescendantOf(game.Players) then
        return false -- Player left, grant credit
    end
    player.Stats.Coins.Value += params.amount
    return true
end
```
