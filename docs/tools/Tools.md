# Woolly Framework – Tools Guide

This guide explains how to use the development tools included with the Woolly framework.  
It covers setup, generating Rojo mappings, and creating new framework structures using the CLI.

---

## 0. Install dependencies
1. Install [Node.js](https://nodejs.org/)
2. Clone this repo and run `npm install`
3. Use commands with `npx woolly` (e.g. `npx woolly gen MainPlace`)

To omit `npx`, use `npm link` (as administrator) to use `woolly ...` commands.

## 1. Project Setup

Run the setup command after cloning the repository to install dependencies and generate initial project files.

```sh
npx woolly setup
```

This will:
* Run `wally install` to fetch external Roblox packages.
* Run `rokit install` to fetch dependencies such as Lune.
* Initialise Rojo if needed using `rojo init`.
* Generate `MainPlace.project.json` via `genRojoTree.js`.
* Optionally build a starting place file using `rojo build -o build.rbxl`.
* Start rojo server if desired.

**Tip:** Run this once after cloning or when resetting your environment.

---

## 2. Generate Rojo Mapping
Whenever you add/remove files or scaffolding, regenerate the Rojo mapping:
```sh
npx woolly gen
```

This calls:
```sh
node tools/genRojoTree.js
```

and writes a fresh `MainPlace.project.json`.

**Tip:** Always run this before syncing with Studio to keep file mappings correct.

---

## 3. Woolly CLI - Create Structures
Use the Woolly CLI to quickly scaffold new files and systems.

```sh
npx woolly create <kind> <Name> [options]
```

#### Global Options
* --at <dir> → override parent directory.
* --place <Place> → create inside /place_overrides/<Place> instead of /src.
* --system <System> → for classes/data_types, place under src/_systems/<System>/….


#### Available Kinds
**Place**
```sh
npx woolly create place SecondaryPlace
```
* Creates a new /place_overrides/SecondaryPlace scaffold (server/client/shared).
* Immediately runs gen and build for that place.

**Service**
```sh
npx woolly create service CurrencyService
```
* Default parent: src/server/services
* Use --at <dir> to override.

**Controller**
```sh
npx woolly create controller InventoryController
```
* Default parent: src/client/controllers
* Use --at <dir> to override.

**Component**
```sh
npx woolly create component ItemButton
```
* Default parent: src/client/components
* Use --at <dir> to override.

**System**
```sh
npx woolly create system Inventory
```
* Default parent: src/_systems
* Creates client/server/shared subfolders automatically.

**Data Type**
```sh
npx woolly create data_type Items
```
* Always created in src/_game_data/source/data_types.

**Class**
```sh
npx woolly create class ItemStand --target server
npx woolly create class InventoryItem --target shared
npx woolly create class PlayerData --both
```
* Defaults:
    * server -> src/server/classes
    * shared -> src/shared/classes
* Use --system <Name> to place under a system instead (e.g., src/_systems/Inventory/server/classes).
* Requires --target shared|server or --both

## 4. Place Management
Woolly supports multiple places in one repo.
All place configs live in /places and overrides in /place_overrides/<Place>.

#### Generate Place Config
```sh
npx woolly gen [Place]
```
* Generates places/<Place>.project.json
* Defaults to the current place (see switch).

---

#### Serve Place
```sh
npx woolly serve <Place>
```
* Runs rojo server places/<Place>.project.json
* Defaults to the current place

---

#### Build Place
```sh
npx woolly create <Place>
```
* Builds places/<Place>.project.json into /builds/<Place>.rbxl.

---

#### Switch Default Place
```sh
npx woolly switch SecondaryPlace
```
* Updates .woollyrc.json so all commands (gen, serve, build, create) target that place by default.
* Example: after switching, npx woolly gen will generate places/SecondaryPlace.project.json.

---

## Tips
* The first created file will auto-open in your editor.
* After creating new files, `genRojoTree.js` is automatically run to refresh `default.project.json`
* Combine flags for fine-grained control:
```sh
npx woolly create class EnemyAI --target shared --system Combat
```
-> Creates src/_systems/Combat/shared/classes/EnemyAI.luau.

---