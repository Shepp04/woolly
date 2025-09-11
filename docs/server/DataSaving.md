# Data Saving

## Introduction
This framework uses **ProfileStore** (by *loleris*) to save and load player data.  
On top of that, we layer:

- **DataManager** (server): owns profile sessions, reconciliation, analytics counters, and pushes initial/changed data to clients.
- **ReplicatedData** (shared): a lightweight replication bus for **public** and **per-player private** data categories.
- **DataInterface** (server): convenience façade for other systems (currency, inventory, rewards) to read/mutate player data through `DataManager`.

---

## Data Manager
**File:** `Server/Packages/DataManager.luau`  
**Responsibilities:**

- Start/end ProfileStore sessions per-player
- Reconcile loaded profiles with current templates
- Maintain session analytics (logins, playtime)
- Publish initial data snapshots to clients via `ReplicatedData`
- Offer simple APIs for other code to access/reset data

### Lifecycle
1. **Join → Start session**
   - `PlayerStore:StartSessionAsync(userIdString, cancelPredicate)`
   - `profile:AddUserId(player.UserId)`
   - `profile:Reconcile()` (ProfileStore-level reconciliation)
2. **Framework reconciliation & init**
   - `DataManager:ReconcileAllSections(player, profile)` (see below)
   - Initialize `profile.Info` from `INFO_TEMPLATE`
   - Analytics counters: `TotalLogins`, `InitialJoinTime`, `JoinTime`
3. **Replicate initial state (private to player)**
   - `ReplicatedData:SetData("PlayerData", profile.Data, { player })`
   - `ReplicatedData:SetData("PlayerInfo", profile.Info, { player })`
   - `ReplicatedData:SetData("Stats", profile.Data.Stats, { player })`
4. **Session end guard**
   - `profile.OnSessionEnd` → kick + clear cache
5. **Leave → End session**
   - Update `LastLeaveTime`, `TotalPlaytime`
   - `profile:EndSession()`

### Public API (server)
- `GetPlayerProfile(player, yield?) → profile?`  
  Quick getter; optional yield using `GetPlayerProfilePromise`.
- `GetPlayerData(player, yield?) → table?`  
  Shorthand for `profile.Data`.
- `ResetData(player) → boolean`  
  Clears `profile.Data`, re-runs reconciliation/init, republishes.
- `LoadPlayerProfile(player) → profile?`  
  Direct (kicks on failure).
- `LoadPlayerProfileAsync(player) → Promise<profile>`  
  Promise variant (rejects if player leaves).
- `GetPlayerProfilePromise(player) → Promise<profile>`  
  Wait until profile appears.
- `RegisterReconcileSection(sectionType: "Info" | "Data", sectionName: string, template: {})`
- `ReconcileProfileSection(...)`
- `ReconcileAllSections(player, profile)`

### Data Reconciliation
You have **two layers** of reconciliation:

1) **ProfileStore’s `profile:Reconcile()`**  
   Fills missing keys using the **store-level default** (your `DATA_TEMPLATE` passed to `ProfileStore.New("PlayerStore", DATA_TEMPLATE)`).

2) **Framework sections** (fine-grained, per feature):  
   - Register sections at init time:
     ```lua
     DataManager:RegisterReconcileSection("Data", "Analytics", {
       TotalLogins = 0,
       TotalPlaytime = 0,
       LastLeaveTime = nil,
       InitialJoinTime = nil,
     })
     ```
   - At load, `ReconcileAllSections` calls `deepReconcile` for:
     - `profile.Info[sectionName]`
     - `profile.Data[sectionName]`

This lets you **add features incrementally** without migrating old profiles:
- Keep a **minimal, stable** `DATA_TEMPLATE`
- Add feature templates through `RegisterReconcileSection` anywhere (services/modules) during server boot

> Tip: If a section is derived/ephemeral, keep it under `Info` (non-persisted) and don’t write it back to the store.

---

## Replication
**File:** `Shared/Packages/ReplicatedData.luau` (shared module with server & client codepaths)

### Concepts
- **Public categories** — visible to *all* clients (e.g. “LeaderboardMetadata”).
- **Private categories** — visible only to a *specific list* of players (e.g. a player’s own “PlayerData”, “Stats”, etc.).

### Server API
- `SetData(category: string, data: any, playerTable?: { Player })`  
  Stage a category value. If `playerTable` is omitted → **Public**; otherwise it’s **Private** for those players.
- `UpdateData(category, data, playerTable?)`  
  Immediately fire to client(s) now (used by internal ticker or manual pushes).
- `RemoveData(category)`  
  Remove a category (public or any private entries).
- **Static helpers** (sugar when treating a category as authoritative “static”):
  - `RegisterStatic(category, value)` → `SetData(category, value)`
  - `SetStatic(category, value)` → `SetData(category, value)` (will be picked up by diff loop)
  - `UpdateStatic(category, value)` → fire now + sync the staged value

### Replication loop (server)
- Every **0.2s**, the server:
  - JSON-encodes staged **public** categories and compares by string to a cached value. If changed, it `FireAllClients`.
  - For **private** categories, it caches per-user **encoded strings** and only fires changed ones to the relevant players.
- Clients can request a **full snapshot** on join via a single `RemoteEvent:FireServer()` (server replies with all public + that client’s private categories).

Benefits:
- Simple, diff-based; avoids needless `RemoteEvent` churn.
- Private updates don’t leak to other clients.
- Manual `UpdateData` gives you an “urgent push” when needed.

### Client API
- `GetData(category: string, yield?: boolean) → any?`  
  Local cache lookup; optional wait (max ~25s) for first arrival.
- Aliases for static:
  - `GetStatic(category, yield?)`
  - `OnStaticChanged(category, callback)` → `RBXScriptConnection`

**Usage examples (client):**
```lua
local ReplicatedData = require(ReplicatedStorage.Shared.Packages.ReplicatedData)

-- One-shot read when UI opens
local stats = ReplicatedData:GetData("Stats", true)
if stats then
  CoinsLabel.Text = tostring(stats.Coins)
end

-- React to changes
local conn = ReplicatedData.OnUpdate.Event:Connect(function(category, data)
  if category == "Stats" then
    CoinsLabel.Text = tostring(data.Coins)
  end
end)
```

**Usage examples (server):**
```lua
-- Update a player’s stats privately
ReplicatedData:SetData("Stats", profile.Data.Stats, { player })

-- Push a global config change publicly
ReplicatedData:SetStatic("MatchConfig", currentConfig)  -- staged
-- or
ReplicatedData:UpdateStatic("MatchConfig", currentConfig) -- push now
```

**Best practices**
- Use **stable category names** (`"PlayerData"`, `"PlayerInfo"`, `"Stats"`) for UI/components.
- Put **sensitive data** in **private** categories only.
- Avoid huge tables every tick—prefer partial categories per feature if size grows.

---

## Data Interface (Service)
A server-only facade used by services to get/add/manipulate player data using `DataManager`.

This service should be injected as a dependency into all other services, so they can easily get/update player data and reconcile sections during initialisation.

## Putting it together (flow)
```
Player joins
  ↳ DataManager:LoadPlayerProfile
      ↳ ProfileStore session + reconcile
      ↳ DataManager:ReconcileAllSections
      ↳ Initialize Info (JoinTime, analytics)
      ↳ ReplicatedData:SetData("PlayerData", Data, { player })
      ↳ ReplicatedData:SetData("PlayerInfo", Info, { player })
      ↳ ReplicatedData:SetData("Stats", Data.Stats, { player })
Client starts / opens UI
  ↳ ReplicatedData:GetData("Stats", true) // waits until first push
  ↳ ReplicatedData:OnStaticChanged("Stats", ...)
Server mutates data later (e.g., reward)
  ↳ DataInterface:SetStat(player, "Coins", newValue)
  ↳ ReplicatedData:SetData("Stats", data.Stats, { player })
  ↳ Diff loop pushes change to that player
Player leaves
  ↳ DataManager:ReleasePlayerProfile
      ↳ Update analytics + EndSession
```

---

## Tips & gotchas

- **Don’t** store volatile timestamps inside replicated categories unless the client really needs them; it will trigger constant diffs.
- Keep `ReplicatedData` categories **coherent** and **feature-scoped**. If a single category gets huge, split into `"InventoryMeta"`, `"InventoryItems"`, etc.
- If a UI needs a value **immediately on open**, always call `GetData(category, true)` once, then subscribe with `OnStaticChanged`.
- For new features, **register reconcile sections** early in server boot (e.g., in the relevant Service’s `Init`) so all new keys appear for all players.

---

**Summary**
- **ProfileStore** manages persistence and base reconciliation.
- **DataManager** owns sessions, per-feature reconciliation, and initial replication.
- **ReplicatedData** is a simple, efficient transport for public/private categories.
- **DataInterface** is your ergonomic, server-only façade for feature code to read/mutate/replicate safely.
