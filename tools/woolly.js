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

// Where classes live by default
const CLASS_DIRS = {
  shared: "src/shared/classes",
  server: "src/server/classes",
};

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

// ---- class templates ----
function tmplSharedClass(name) {
  return `--!strict
-- ${name} (Shared Class)
-- Reusable logic for both server & client. DI makes it easy to pass Config/GameData/etc.

--[=[
USAGE (client or server):
  local ${name} = require(ReplicatedStorage.Shared.Classes.${name})
  local inst = ${name}.new({
      Config = require(ReplicatedStorage.Shared.Config),
      GameData = require(ReplicatedStorage.Shared.GameData),
      Monetisation = require(ReplicatedStorage.Shared.Monetisation),
  }, {
      -- opts for this instance
      id = "Foo",
  })
  inst:Init()
  -- ...
  inst:Destroy()
]=]

-- // Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Deps = {
  Config: any?,
  GameData: any?,
  Monetisation: any?,
  -- add more shared deps as needed
}

export type ${name} = {
  _deps: Deps,
  _opts: { [string]: any },
  _conns: { RBXScriptConnection },

  Init: (self: ${name}) -> (),
  Destroy: (self: ${name}) -> (),

  -- example shared API
  FormatCurrency: (self: ${name}, currencyId: string, amount: number) -> string,
}

local ${name} = {}
${name}.__index = ${name}

function ${name}.new(deps: Deps, opts: { [string]: any }?): ${name}
  local self = setmetatable({
    _deps = deps or {},
    _opts = opts or {},
    _conns = {},
  }, ${name})

  return self
end

function ${name}:Init()
  -- Hook Bindables/Remotes conditionally:
  if RunService:IsClient() then
    -- client-only wiring
  else
    -- server-only wiring
  end
end

function ${name}:FormatCurrency(currencyId: string, amount: number): string
  local Config = self._deps.Config
  if Config and Config.Currency and Config.Currency.GetCurrencyText then
    return Config.Currency:GetCurrencyText(currencyId, amount)
  end
  return tostring(amount) .. " " .. currencyId
end

function ${name}:Destroy()
  for _, c in self._conns do
    pcall(function() c:Disconnect() end)
  end
  table.clear(self._conns)
end

return ${name}
`;
}

function tmplServerClass(name) {
  return `--!strict
-- ${name} (Server Class)
-- Dependency-injected helper owned by Services or other classes.

--[=[
USAGE (inside a Service):
  local ${name} = require(script.Parent.Classes.${name})
  local inst = ${name}.new({
      Services = self.Services, -- from Services registry
      Config = require(ReplicatedStorage.Shared.Config),
      -- any other server deps...
  }, {
      -- opts for this instance
      id = "Stand01",
  })
  inst:Init()

  -- later
  inst:Destroy()
]=]

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
-- If you have a typed Services registry:
-- local Types = require(ReplicatedStorage.Shared.Types.Services)
-- type ServicesRegistry = Types.Registry

export type Deps = {
  Services: any, -- recommend narrowing to \`ServicesRegistry\` if you have it
  Config: any?,
  GameData: any?,
}

export type ${name} = {
  _deps: Deps,
  _opts: { [string]: any },
  _conns: { RBXScriptConnection },

  Init: (self: ${name}) -> (),
  Destroy: (self: ${name}) -> (),

  -- example public API
  Spend: (self: ${name}, player: Player, currencyId: string, amount: number) -> boolean,
}

local ${name} = {}
${name}.__index = ${name}

function ${name}.new(deps: Deps, opts: { [string]: any }?): ${name}
  assert(deps ~= nil, "${name}.new => deps is required")
  assert(deps.Services ~= nil, "${name}.new => deps.Services is required")

  local self = setmetatable({
    _deps = deps,
    _opts = opts or {},
    _conns = {},
  }, ${name})

  return self
end

function ${name}:Init()
  -- Example: pull frequently used services once
  -- local CurrencyService = (self._deps.Services :: any).CurrencyService

  -- Bind events here and store connections in self._conns
  -- table.insert(self._conns, someSignal:Connect(function() ... end))
end

function ${name}:Spend(player: Player, currencyId: string, amount: number): boolean
  local CurrencyService = (self._deps.Services :: any).CurrencyService
  if not CurrencyService then
    warn("[${name}] CurrencyService not available")
    return false
  end
  return CurrencyService:SpendCurrency(player, currencyId, amount)
end

function ${name}:Destroy()
  for _, c in self._conns do
    pcall(function() c:Disconnect() end)
  end
  table.clear(self._conns)
end

return ${name}
`;
}

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
  ensureDir(path.join(base, "server/classes"));

  // client
  const controllersDir = path.join(base, "client/controllers");
  const componentsDir  = path.join(base, "client/components");
  ensureDir(controllersDir);
  ensureDir(componentsDir);
  ensureDir(path.join(base, "client/utils"));

  // shared
  ensureDir(path.join(base, "shared/assets/ui"));
  ensureDir(path.join(base, "shared/assets/models"));
  ensureDir(path.join(base, "shared/classes"));
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

function createSharedClass(rawName, systemName /* optional */) {
  const pas = toPascal(rawName);
  const baseDir = systemName
    ? path.join("src/_systems", systemName, "shared/classes")
    : CLASS_DIRS.shared;
  const abs = path.join(baseDir, `${pas}.luau`);
  writeIfMissing(abs, tmplSharedClass(pas));
  return abs;
}

function createServerClass(rawName, systemName /* optional */) {
  const pas = toPascal(rawName);
  const baseDir = systemName
    ? path.join("src/_systems", systemName, "server/classes")
    : CLASS_DIRS.server;
  const abs = path.join(baseDir, `${pas}.luau`);
  writeIfMissing(abs, tmplServerClass(pas));
  return abs;
}

// ---------- parse args ----------
const args = process.argv.slice(2);
const [cmd, kind, rawName, ...rest] = args;

const atFlagIdx = rest.findIndex(a => a === "--at");
const parentDir = atFlagIdx >= 0 ? rest[atFlagIdx + 1] : undefined;

function usage() {
  console.log(`
Woolly CLI

  create service <Name>        [--at <dir>]           # default src/server/services
  create controller <Name>     [--at <dir>]           # default src/client/controllers
  create component <Name>      [--at <dir>]           # default src/client/components
  create system <Name>         [--at <dir>]           # default src/_systems
  create data_type <Name>                             # default src/_game_data/source/data_types
  create class <Name>          (--target shared|server | --both) [--system <SysName>]
                              # shared -> src/shared/classes or src/_systems/<Sys>/shared/classes
                              # server -> src/server/classes or src/_systems/<Sys>/server/classes
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

// ---- tiny flag parser for class options ----
let target = null;        // "shared" | "server"
let both = false;
let system = null;

for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (a === "--both") {
    both = true;
  } else if ((a === "--target" || a === "-t") && rest[i + 1]) {
    target = rest[++i];
  } else if (a === "--system" && rest[i + 1]) {
    system = rest[++i];
  }
}

// normalize helper: make sure we always have an array of file paths
const toArray = (v) =>
  v == null ? [] : Array.isArray(v) ? v : [v];

let created = [];

switch (kind) {
  case "service": {
    created = toArray(createService(rawName, parentDir));
    break;
  }
  case "controller": {
    created = toArray(createController(rawName, parentDir));
    break;
  }
  case "component": {
    created = toArray(createComponent(rawName, parentDir));
    break;
  }
  case "system": {
    created = toArray(createSystem(rawName, parentDir));
    break;
  }
  case "data_type": {
    created = toArray(createDataType(rawName));
    break;
  }
  case "class": {
    const made = [];

    // If no --target and not --both, fail fast with a helpful message
    if (!both && target !== "shared" && target !== "server") {
      console.error("Please specify --target shared|server or use --both");
      process.exit(1);
    }

    // Let creators handle default dirs if system is null/undefined
    if (both || target === "shared") {
      const p = createSharedClass(rawName, system || undefined);
      if (p) made.push(p);
    }
    if (both || target === "server") {
      const p = createServerClass(rawName, system || undefined);
      if (p) made.push(p);
    }

    created = made;
    break;
  }
  default: {
    console.error("Unknown kind:", kind);
    usage();
    process.exit(1);
  }
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