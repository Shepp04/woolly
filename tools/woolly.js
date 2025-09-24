#!/usr/bin/env node
/* Woolly scaffolder: create services/controllers/components/systems
   Usage examples:
     node tools/woolly.js create service CurrencyService
     node tools/woolly.js create controller MenuController --at src/client/controllers
     node tools/woolly.js create component PlaytimeRewardBar
     node tools/woolly.js create system TimedRewards --at src/_systems
*/

const fs = require("fs");
const path = require("path");
const cp  = require("child_process");

// ---------- utils ----------
const toPascal = (s) => {
  if (!s) return s;
  if (/^[A-Z0-9_]+$/.test(s)) return s; // keep UX/UI/ID etc
  return s
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map(w => w[0].toUpperCase() + w.slice(1))
    .join("");
};

const ensureDir = (dir) => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
};

const writeIfMissing = (abs, content) => {
  if (fs.existsSync(abs)) {
    console.log("• exists ", abs);
    return false;
  }
  ensureDir(path.dirname(abs));
  fs.writeFileSync(abs, content, "utf8");
  console.log("✓ wrote  ", abs);
  return true;
};

const run = (cmd, args, opts = {}) =>
  cp.spawnSync(cmd, args, { stdio: "inherit", ...opts });

function openInEditor(absPath) {
  // Prefer VS Code if available
  try {
    const which = cp.spawnSync(process.platform === "win32" ? "where" : "which", ["code"], { stdio: "ignore" });
    if (which.status === 0) {
      cp.spawn("code", ["-g", `${absPath}:1`], { stdio: "ignore", detached: true });
      return;
    }
  } catch {}

  // Respect VISUAL/EDITOR
  const editor = process.env.VISUAL || process.env.EDITOR;
  if (editor) {
    try {
      cp.spawn(editor, [absPath], { stdio: "ignore", detached: true });
      return;
    } catch {}
  }

  // OS fallback
  if (process.platform === "darwin") {
    cp.spawn("open", [absPath], { stdio: "ignore", detached: true });
  } else if (process.platform === "win32") {
    cp.spawn("cmd", ["/c", "start", "", absPath], { stdio: "ignore", detached: true });
  } else {
    cp.spawn("xdg-open", [absPath], { stdio: "ignore", detached: true });
  }
}

// ---------- templates ----------
const tmplService = (Name) => `--!strict
-- ${Name} (Service) — lifecycle-first singleton discovered by Services registry.

export type Deps = { Services: any }
export type ${Name} = {
\tPriority: number?,
\tInit: (self: ${Name}, deps: Deps) -> (),
\tStart: (self: ${Name}) -> (),
\tDestroy: (self: ${Name}) -> (),
\tServices: any?, -- auto-filled
}

local ${Name} = {
\tPriority = 100,
\t_inited = false,
\t_started = false,
\t_conns = {},
\tServices = nil,
}

function ${Name}:Init(deps: Deps)
\tif self._inited then return end
\tself._inited = true
\tself.Services = deps.Services
\t-- init here
end

function ${Name}:Start()
\tif not self._inited or self._started then return end
\tself._started = true
\t-- start here
end

function ${Name}:Destroy()
\tfor _, c in self._conns do pcall(function() c:Disconnect() end) end
\ttable.clear(self._conns)
\tself._started = false
\tself._inited = false
end

return ${Name}
`;

const tmplController = (Name) => `--!strict
-- ${Name} (Controller) — client controller discovered by Controllers registry.

export type ${Name} = {
\tPriority: number?,
\tInit: (self: ${Name}) -> (),
\tStart: (self: ${Name}) -> (),
\tDestroy: (self: ${Name}) -> (),
}

local ${Name} = {
\tPriority = 100,
\t_inited = false,
\t_started = false,
\t_conns = {},
}

function ${Name}:Init()
\tif self._inited then return end
\tself._inited = true
\t-- init UI state / refs
end

function ${Name}:Start()
\tif not self._inited or self._started then return end
\tself._started = true
\t-- hook events
end

function ${Name}:Destroy()
\tfor _, c in self._conns do pcall(function() c:Disconnect() end) end
\ttable.clear(self._conns)
\tself._started = false
\tself._inited = false
end

return ${Name}
`;

const tmplComponent = (Name) => `--!strict
-- ${Name} (Component) — reusable client UI/gameplay piece (class-like).

export type ${Name} = {
\t_inited: boolean,
\tInit: (self: ${Name}) -> (),
\tDestroy: (self: ${Name}) -> (),
}

local ${Name} = {}
${Name}.__index = ${Name}

function ${Name}.new(...)
\tlocal self = setmetatable({ _inited = false }, ${Name})
\t-- capture args
\treturn self
end

function ${Name}:Init()
\tif self._inited then return end
\tself._inited = true
\t-- bind signals
end

function ${Name}:Destroy()
\t-- cleanup
end

return ${Name}
`;

const tmplDataType = (Name) => `--!strict
-- ${Name} (GameData type)

export type DataEntry = {
\tid: string,
\tname: string,
\ticon: string?,
\trarity: "common" | "uncommon" | "rare" | "epic" | "legendary",
\tstackable: boolean?,
\tmaxStack: number?,

\t-- Server-only:
\tActivated: ((player: Player, ctx: any?) -> ())?,
\tModelPath: {string}?,
\tDrops: { [string]: number }?
}

type DataTypeDict = {
\tname: string,
\tpublic_field_whitelist: { [string]: boolean },
\titems: { [string]: DataEntry }
}

local DATA_TYPE_NAME = "${Name}"
local PUBLIC_FIELD_WHITELIST = {
\tid = true, name = true, icon = true, rarity = true, stackable = true, maxStack = true,
}
local DATA: { [string]: DataEntry } = {
\t-- Example entry:
\t-- ExampleItem = {
\t-- \tid = "example",
\t-- \tname = "Example Item",
\t-- \ticon = "rbxassetid://123456",
\t-- \trarity = "common",
\t-- \tstackable = true,
\t-- \tmaxStack = 99,
\t-- \tActivated = function(player, ctx)
\t-- \t\tprint(player, "used Example Item with context", ctx)
\t-- \tend,
\t-- \tModelPath = {"ExampleModels", "ExampleItem"},
\t-- \tDrops = { Coins = 10 },
\t-- },
}

local DataTypeDict: DataTypeDict = {
\tname = DATA_TYPE_NAME,
\tpublic_field_whitelist = PUBLIC_FIELD_WHITELIST,
\titems = DATA,
}

return DataTypeDict
`;

// ---------- creators ----------
function createService(name, parent) {
  const pas = toPascal(name);
  const dir = parent || "src/server/services";
  const file = path.resolve(dir, `${pas}.luau`);
  const created = writeIfMissing(file, tmplService(pas));
  return created ? [file] : [];
}

function createController(name, parent) {
  const pas = toPascal(name);
  const dir = parent || "src/client/controllers";
  const file = path.resolve(dir, `${pas}.luau`);
  const created = writeIfMissing(file, tmplController(pas));
  return created ? [file] : [];
}

function createComponent(name, parent) {
  const pas = toPascal(name);
  const dir = parent || "src/client/components";
  const file = path.resolve(dir, `${pas}.luau`);
  const created = writeIfMissing(file, tmplComponent(pas));
  return created ? [file] : [];
}

function createSystem(name, parent) {
  const sysName = name; // keep user casing on folder; files inside can be Pascal
  const base = path.resolve(parent || "src/_systems", sysName);

  // server
  ensureDir(path.join(base, "server/services"));
  ensureDir(path.join(base, "server/packages"));

  // client
  const controllersDir = path.join(base, "client/controllers");
  const componentsDir  = path.join(base, "client/components");
  ensureDir(controllersDir);
  ensureDir(componentsDir);
  ensureDir(path.join(base, "client/utils"));

  // shared
  ensureDir(path.join(base, "shared/assets/ui"));
  ensureDir(path.join(base, "shared/assets/models"));
  const cfgDir = path.join(base, "shared/config");
  ensureDir(cfgDir);

  return [];
}

function createDataType(name) {
  const pas = toPascal(name);
  const dir = "src/_game_data/source/data_types";
  const file = path.resolve(dir, `${pas}.luau`);
  const created = writeIfMissing(file, tmplDataType(pas));
  return created ? [file] : [];
}

// ---------- parse args ----------
const args = process.argv.slice(2);
const [cmd, kind, rawName, ...rest] = args;

const atFlagIdx = rest.findIndex(a => a === "--at");
const parentDir = atFlagIdx >= 0 ? rest[atFlagIdx + 1] : undefined;

function usage() {
  console.log(`
Woolly CLI
  create service <Name>      [--at <dir>]  # default src/server/services
  create controller <Name>   [--at <dir>]  # default src/client/controllers
  create component <Name>    [--at <dir>]  # default src/client/components
  create system <Name>       [--at <dir>]  # default src/_systems
`);
}

if (!cmd || cmd === "--help" || cmd === "-h") {
  usage();
  process.exit(0);
}

if (cmd !== "create") {
  console.error("Unknown command:", cmd);
  usage();
  process.exit(1);
}

if (!kind || !rawName) {
  usage();
  process.exit(1);
}

let created = [];
switch (kind) {
  case "service":
    created = createService(rawName, parentDir);    break;
    break;
  case "controller":
    created = createController(rawName, parentDir); break;
    break;
  case "component":
    created = createComponent(rawName, parentDir);  break;
    break;
  case "system":
    created = createSystem(rawName, parentDir);     break;
    break;
  case "data_type":
    created = createDataType(rawName);
    break;
  default:
    console.error("Unknown kind:", kind);
    usage();
    process.exit(1);
}

// Auto-open the first created file if any
if (created.length > 0) {
  openInEditor(created[0]);
}

// Regenerate Rojo mapping
if (fs.existsSync("tools/genRojoTree.js")) {
  console.log("→ Refreshing default.project.json via genRojoTree.js");
  const res = run("node", ["tools/genRojoTree.js"]);
  if (res.status !== 0) process.exit(res.status);
} else {
  console.log("⚠ Skipped genRojoTree.js (not found)");
}