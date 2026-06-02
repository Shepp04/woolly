--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

export type ServerContext = {
    PlayerData: typeof(require(ReplicatedStorage.Shared.Core.PlayerData.Server)),
    Systems: typeof(require(game.ServerScriptService.Server.Core.SystemRegistry)),
    GameContent: nil,
    Monetisation: nil,
    Utils: typeof(require(ReplicatedStorage.Shared.Core.Utils)),
}

export type ClientContext = {
    PlayerData: typeof(require(ReplicatedStorage.Shared.Core.PlayerData.Client)),
    Systems: typeof(require(StarterPlayer.StarterPlayerScripts.Client.Core.SystemRegistry)),
    GameContent: nil,
    Monetisation: nil,
    Utils: typeof(require(ReplicatedStorage.Shared.Core.Utils)),
}

export type Leaderstat = {
    Name: string,
    DataPath: { string },
    ValueType: "IntValue" | "NumberValue" | "StringValue",
    IsPrimary: boolean,
}

export type SystemManifest = {
    Name: string,
    Dependencies: { string },
    PlayerDataRequirements: { Schema: { [string]: any }, Leaderstats: { Leaderstat } },
    Remotes: { Events: { string }, Functions: { string } },
}

export type ServerSystemLoader = {
    Init: (self: ServerSystemLoader, ctx: ServerContext) -> (),
    Start: (self: ServerSystemLoader) -> (),
}

export type ClientSystemLoader = {
    Init: (self: ClientSystemLoader, ctx: ClientContext) -> (),
    Start: (self: ClientSystemLoader) -> (),
}

export type ServerSystem = {
    Loader: ServerSystemLoader?,
    Manifest: SystemManifest,
}

export type ClientSystem = {
    Loader: ClientSystemLoader?,
    Manifest: SystemManifest,
}

return {}