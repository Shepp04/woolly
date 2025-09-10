# Woolly Framework

A lightweight, production-ready framework for Roblox experiences. Batteries included for:
**Services, Packages, GameData, Monetisation, Config, Controllers, Components.**

- **Clear client/server boundaries**
- **Config-driven** features
- **Composable Components** for entities/UX
- **Controllers** for client UX & input flows
- **First-class Monetisation** hooks
- **GameData** abstraction for profile & session state

> This is the **MVP** release. See **Releases** for versioning and changelog.

## Contents
- [Quick Start](#quick-start)
- [Folder Structure](#folder-structure)
- [Lifecycle](#lifecycle)
- [Key Concepts](#key-concepts)
- [Docs](#docs)
- [Examples](#examples)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

1. **Install / Sync**
   - Clone or drop the framework folder into your place (e.g. under `ReplicatedStorage/Framework` + `ServerScriptService`).
   - If you use Rojo, add the path in your `default.project.json`.

2. **Bootstrap**
   - Server: require and start `ServerMain`.
   - Client: require and start `ClientMain`.

```lua
-- ServerScriptService/ServerMain.server.lua
local Framework = require(game.ReplicatedStorage.Framework)
Framework.StartServer()

-- StarterPlayerScripts/ClientMain.client.lua
local Framework = require(game.ReplicatedStorage.Framework)
Framework.StartClient()
```
3. **Configure**
    - Edit src/shared/config/*.luau to match the game (e.g Players, Sounds, Physics)

## Folder Structure
src
├── _game_data
│   ├── resolver
│   └── source
│       └─── data_types
├── _monetisation
│   ├── resolver
│   └── source
├── _systems
│   └── _TemplateSystem
│       ├── client
│       │   ├── components
│       │   ├── controllers
│       │   └── utils
│       ├── server
│       │   ├── packages
│       │   └── services
│       └── shared
│           ├── assets
│           │   ├── models
│           │   └── ui
│           └── config
├── _types
├── client
│   ├── components
│   ├── controllers
│   └── utils
├── server
│   ├── packages
│   └── services
├── shared
│   ├── assets
│   │   ├── models
│   │   └── ui
│   ├── config
│   └── packages
└── tree.txt

## LifeCycle
    - Server: Single Bootstrapper. Does the following:
        - Initialises DataManager (backend)
        - Requires shared and external packages
        - Initialises all Services (in priority order)
        - Starts all Services (in priority order)
        - Initialises GameDataMaster
        - Initialises Monetisation
        - Starts Monetisation

    - Client: Single Bootstrapper. Does the following:
        - Requires shared and external packages
        - Requires GameData
        - Requires Monetisation
        - Requires UX (animated Gui elements)
        - Initialises Controllers
        - Starts Controllers

## Key Concepts
    - Services: Singletons that manage large game features. Has :Init(), :Start(), :Destroy() methods (e.g DataInterface, CurrencyService)
    - Controllers (Client): Orchestrates UX, input, and client components. Has :Init(), :Start(), :Destroy() methods.
    - Components (Client): Small, focused behaviours attached to instances/UI. Has .new() constructor, and :Start() and :Destroy() methods
    - GameData: Flexible data library that provides public and private views of data, redacted by the server. Provides a public Resolver in ReplicatedStorage. Add new data types by adding new child modules.
    - Monetisation: Flexible product library that provides public and private views (e.g server handlers are kept private). Provides a public Resolver that exposes useful methods such as PromptSale.
    - Config: Central SOT for Ids, flags, tunables, and constants