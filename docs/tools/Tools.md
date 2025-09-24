# Woolly Framework – Tools Guide

This guide explains how to use the development tools included with the Woolly framework.  
It covers setup, generating Rojo mappings, and creating new framework structures using the CLI.

---

## 1. Project Setup

Run the setup command after cloning the repository to install dependencies and generate initial project files.

```sh
npm run setup
```

This will:
* Run `wally install` to fetch external Roblox packages.
* Run `rokit install` to fetch dependencies such as Lune.
* Initialise Rojo if needed using `rojo init`.
* Generate `default.project.json` via `genRojoTree.js`.
* Optionally build a starting place file using `rojo build -o build.rbxl`.
* Start rojo server if desired.

**Tip:** Run this once after cloning or when resetting your environment.

---

## 2. Generate Rojo Mapping
Whenever you add/remove files or scaffolding, regenerate the Rojo mapping:
```sh
npm run gen:rojo
```

This calls:
```sh
node tools/genRojoTree.js
```

and writes a fresh `default.project.json`.

**Tip:** Always run this before syncing with Studio to keep file mappings correct.

---

## 3. Woolly CLI - Create Structures
Use the Woolly CLI to quickly scaffold new files and systems.

```sh
npm run woolly -- create <kind> <Name> [options]
```

#### Available Kinds
**Service**
```sh
npm run woolly -- create service CurrencyService
```
* Default parent: src/server/services
* Use --at <dir> to override.

**Controller**
```sh
npm run woolly -- create controller InventoryController
```
* Default parent: src/client/controllers
* Use --at <dir> to override.

**Component**
```sh
npm run woolly -- create component ItemButton
```
* Default parent: src/client/components
* Use --at <dir> to override.

**System**
```sh
npm run woolly -- create system Inventory
```
* Default parent: src/_systems
* Creates client/server/shared subfolders automatically.

**Data Type**
```sh
npm run woolly -- create data_type Items
```
* Always created in src/_game_data/source/data_types.

**Class**
```sh
npm run woolly -- create class ItemStand --target server
npm run woolly -- create class InventoryItem --target shared
npm run woolly -- create class PlayerData --both
```
* Defaults:
    * server -> src/server/classes
    * shared -> src/shared/classes
* Use --system <Name> to place under a system instead (e.g., src/_systems/Inventory/server/classes).
* Requires --target shared|server or --both

---

## Tips
* The first created file will auto-open in your editor.
* After creating new files, `genRojoTree.js` is automatically run to refresh `default.project.json`
* Combine flags for fine-grained control:
```sh
npm run woolly -- create class EnemyAI --target shared --system Combat
```
-> Creates src/_systems/Combat/shared/classes/EnemyAI.luau.

---