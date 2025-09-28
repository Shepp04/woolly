# Systems
## Introduction
**Systems** are a way of cleanly organising a bundle of Services, Controllers, Components, Assets, GameData, and Configuration in VSCode.

To create a new system, type:
```sh
npx woolly create system <name> [--place <Place>]
```

## Location
Systems are located in:
```
src/_systems
```
You can find a template system directory within this folder.

## Example
One example may be a Nametag System. This would include the following:
1) **Services:** NametagService
2) **Controllers:** NametagController (optional for animated nametags)
3) **Components:** Nametag (optional for animated nametags)
4) **Assets**: Nametag UI
5) **Config**: NametagConfig (display distance etc.)

The framework allows a self-contained structure which is mapped to Studio correctly.