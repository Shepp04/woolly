# Config
## Introduction
This framework allows for flexible `config` files separated by system. Each `config` type contains ids, constants, and tunables and is accessed through a central registry.

## Usage
Config files are located at:
```
src/shared/config
```
To add a new config, copy the template below into a child module. For better intellisense, add the type of the module to the main config/init.luau file.

**Note:** Do not put state or methods inside config files, since they are best kept for ids, constants, and tunables only.

## Template
```lua
--!strict
export type ConfigModule = {

}

local Config: ConfigModule = {
    
}

return Config
```