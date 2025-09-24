# Woolly Framework
A scalable Roblox framework that handles **data saving** and **replication**, provides **monetisation** features, supports self-contained **systems**, and uses the `Services` `Controllers` `Components` pattern.

---

## Setup
This framework requires Rojo - see Rojo's docs here: [rojo docs](https://rojo.space/docs)

To create a new project, clone this repository and run:
```
npm run setup
```

<details>
<summary> For older versions of this framework (0.1.2 and earlier), expand this dropdown.</summary>


To setup, run:
```
wally install
```
This will install the necessary dependencies (Promise, Trove etc.) and put them in the /Packages directory.

Run:
```
rojo build -o build.rbxl
```
to build a Roblox place file.
Any time you add a new folder as a descendant of src, run:
```
node tools/genRojoTree.js
```
to regenerate the `default.project.json` file, and then run
```
rojo serve
```
to re-sync to Studio.
</details>

---

## Documentation
Please see /docs for documentation on the various types of file. Below is a quick summary of these types:

#### Services
> server-only *singleton* modules that manage the logic for a specific system in your game.

#### Controllers
> client-only *singleton* modules that manage the client logic for a specific system in your game.

#### Components
> client class modules that handle UI elements and self-contained client systems.

#### Packages
> modules that contain useful methods that aren't game-specific

#### Config
> contains ids, constants, and tunables and is accessed through a central registry.