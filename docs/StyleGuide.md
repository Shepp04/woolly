# Woolly Style Guide

## Comments
1. Inline/line-level comments should begin with a Capital letter (e.g -- Connect remotes)
2. Section-level comments should begin with a Capital letter and also be preceded by // (e.g -- // Initialisation)

## Variable Names
1. All internal variables/fields should begin with a '_' and be camelCase (e.g. _inited or self._opts)
2. Public variables should be camelCase without '_' preceding them (e.g player or self.model)
3. Shared Constants defined near the top of a script should prefer ALL_CAPS (e.g. MAX_PLAYERS = 12)
4. When referencing players, the variable name 'player' should be used for params/args, but the variable name 'plr' should be used when iterating in a for loop. Please see the example below:
```lua
local function onPlayerAdded(player: Player)
    -- Fire a remote to each player in the game
    for _, plr in game.Players:GetPlayers() do
        remote:FireClient(plr, ...)
    end
end
```

## Method Names
1. Internal methods should begin with '_' (e.g. Service:_onPlayerAdded(...))
2. Public methods should use PascalCase and a colon (e.g. Service:GetAll(...))
3. Local functions should use camelCase (e.g. local function deepCopy(...))
4. Prefer `Class:Method()` instead of `local function method(self)`

## Tables & Fields
1. Table keys should not be quoted (e.g. { foo = "bar" } not { ["foo"] = "bar" })
2. Trailing commas for multi-line tables are required

## Error Handling
1. Handle optional services with `warn` instead of `error` unless startup must fail
2. All `error()`, `warn()`, and `print()` statements must be formatted as: [{ScriptName}] {message} e.g.:
```lua
if not model:FindFirstChild("Trigger") then
    warn(`[TestService] {model} has no Trigger part!`)
end
```

## Types
1. All arguments/params should be typed where possible (e.g. local function add(a: number, b: number): number)
2. All return values must be type annotated in the function/method definition
3. Avoid `any` type where possible to improve intellisense discovery. Types are provided in src/_types for Services, Controllers, PlayerData, and other structures.
4. All ModuleScripts (especially Services, Controllers, and Classes) must expose an API type named '{ModuleScriptName}API' and return a API type cast e.g.:
```lua
export type TestServiceAPI = {
    _inited: boolean,
    _started: boolean,
    _conns: { RBXScriptConnection },

    Init: (self: TestServiceAPI) -> (),
    Start: (self: TestServiceAPI) -> (),
    Destroy: (self: TestServiceAPI) -> (),
}

local TestService = {}

...

return TestService :: TestServiceAPI
```
5. Prefer self._field over local captured variables

## Deps
* Each Service, Controller, and Class is provided with a deps dictionary. For server modules, this includes:
```lua
local deps = {
    DataInterface,
    SharedPackages,
    GameData,
    Monetisation,
    Config,
}
```
which are typed in the Service/ServerClass templates.

* For shared/client modules, this includes:
```lua
local deps = {
    ReplicatedData,
    SharedPackages,
    GameData,
    Monetisation,
    Config,
}
```

## Formatting/Layout
1. To separate sections, use '-- ========== SectionName ========== --' with exactly 10 '=' characters each side, surrounded by a pair of '--' on each side. There should be one blank line before and after each header. e.g.:
```lua
-- ========== Helpers ========== --
function Service:_helper(arg1: number): number
    return 0
end

-- ========== Public API ========== --
```
2. If used, the sections should appear in this order:
    1. Helpers
    2. Constructor (for classes only)
    3. Public API
    4. Internal
    5. Life Cycle

## Documentation
1. All methods should be documented on the line above their definition, using the below format:
```lua
--[[ 
    {MethodName}
    {Description}

    @param {paramName}: {paramType}, {paramDescription?}
    ...

    @return {returnValue}: {returnType}, {returnDescription?}
]]
```
2. In-line comments should be used throughout to make scripts easy to read and understand the logic

## File/Folder Naming
* Modules should use PascalCase (e.g. PlayerService.luau)
* VSCode folders should be lowercase with underscores (e.g. data_types, services, client, packages)