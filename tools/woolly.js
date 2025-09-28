#!/usr/bin/env node
/* Woolly CLI
   New commands:
     woolly gen [Place]            -> node tools/genRojoTree.js Place
     woolly serve [Place]          -> rojo serve places/Place.project.json
     woolly build [Place]          -> rojo build places/Place.project.json -o builds/Place.rbxl
     woolly switch <Place>         -> set default place in .woollyrc.json
     woolly create <kind> <Name> [--at <dir>] [--place <Place>] [class flags...]
       kinds: service | controller | component | system | data_type | class
       class flags: --target shared|server | --both | --system <SysName>
*/

const fs = require("fs");
const path = require("path");
const cp  = require("child_process");

const REPO = path.join(__dirname, "..");
const PLACES_DIR = path.join(REPO, "places");
const OVERRIDES_DIR = path.join(REPO, "place_overrides");
const SRC_DIR = path.join(REPO, "src");
const CONFIG_PATH = path.join(REPO, ".woollyrc.json");

// ---------------- config helpers ----------------
function readConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, "utf8");
    return JSON.parse(raw);
  } catch {
    return { defaultPlace: "MainPlace" };
  }
}

function writeConfig(cfg) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
  console.log("✓ Updated", path.relative(process.cwd(), CONFIG_PATH));
}

function getDefaultPlace() {
  return readConfig().defaultPlace || "MainPlace";
}

function setDefaultPlace(place) {
  const cfg = readConfig();
  cfg.defaultPlace = place;
  writeConfig(cfg);
}

function placeProjectPath(place) {
  return path.join(PLACES_DIR, `${place}.project.json`);
}

function resolvePlace(argMaybe) {
  return argMaybe || getDefaultPlace();
}

function overridesRootFor(place) {
  const abs = path.join(OVERRIDES_DIR, place);
  return fs.existsSync(abs) && fs.statSync(abs).isDirectory() ? abs : null;
}

function sourceRootFor(place) {
  // If overrides/<place> exists, use it; else use /src
  const ov = overridesRootFor(place);
  console.log("Override place found:", ov);
  return ov || SRC_DIR;
}

// ---------------- run helpers ----------------
const run = (cmd, args, opts = {}) =>
  cp.spawnSync(cmd, args, { stdio: "inherit", cwd: REPO, ...opts });

function tryRun(cmd, args, opts = {}) {
  console.log(`→ ${cmd} ${args.join(" ")}`);
  const res = cp.spawnSync(cmd, args, { stdio: "inherit", cwd: REPO, ...opts  });
  return res.status;
}

function openInEditor(absPath) {
  try {
    const which = cp.spawnSync(process.platform === "win32" ? "where" : "which", ["code"], { stdio: "ignore" });
    if (which.status === 0) {
      cp.spawn("code", ["-g", `${absPath}:1`], { cwd: REPO, stdio: "ignore", detached: true });
      return;
    }
  } catch {}
  const editor = process.env.VISUAL || process.env.EDITOR;
  if (editor) {
    try {
      cp.spawn(editor, [absPath], { cwd: REPO, stdio: "ignore", detached: true });
      return;
    } catch {}
  }
  if (process.platform === "darwin") cp.spawn("open", [absPath], { cwd: REPO, stdio: "ignore", detached: true });
  else if (process.platform === "win32") cp.spawn("cmd", ["/c", "start", "", absPath], { cwd: REPO, stdio: "ignore", detached: true });
  else cp.spawn("xdg-open", [absPath], { cwd: REPO, stdio: "ignore", detached: true });
}

// ---------------- filesystem utils ----------------
const ensureDir = (dir) => { if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true }); };
const writeIfMissing = (abs, content) => {
  if (fs.existsSync(abs)) { console.log("• exists ", abs); return false; }
  ensureDir(path.dirname(abs));
  fs.writeFileSync(abs, content, "utf8");
  console.log("✓ wrote  ", abs);
  return true;
};

function ensurePlaceSkeleton(place) {
  const base = path.join(OVERRIDES_DIR, place);

  // shared
  ensureDir(path.join(base, "shared/assets/ui"));
  ensureDir(path.join(base, "shared/assets/models"));
  ensureDir(path.join(base, "shared/classes"));
  ensureDir(path.join(base, "shared/config"));
  ensureDir(path.join(base, "shared/packages"));

  // client
  ensureDir(path.join(base, "client/controllers"));
  ensureDir(path.join(base, "client/components"));
  ensureDir(path.join(base, "client/utils"));

  // server
  ensureDir(path.join(base, "server/services"));
  ensureDir(path.join(base, "server/packages"));
  ensureDir(path.join(base, "server/classes"));
}

const toPascal = (s) => {
  if (!s) return s;
  if (/^[A-Z0-9_]+$/.test(s)) return s;
  return s.split(/[^A-Za-z0-9]+/).filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join("");
};

// ---------------- templates (unchanged from your current) ----------------
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
}

local DataTypeDict: DataTypeDict = {
\tname = DATA_TYPE_NAME,
\tpublic_field_whitelist = PUBLIC_FIELD_WHITELIST,
\titems = DATA,
}

return DataTypeDict
`;

function tmplSharedClass(name) {
  return `--!strict
-- ${name} (Shared Class)

-- // Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Deps = {
  Config: any?,
  GameData: any?,
  Monetisation: any?,
}

export type ${name} = {
  _deps: Deps,
  _opts: { [string]: any },
  _conns: { RBXScriptConnection },

  Init: (self: ${name}) -> (),
  Destroy: (self: ${name}) -> (),

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
  for _, c in self._conns do pcall(function() c:Disconnect() end) end
  table.clear(self._conns)
end

return ${name}
`;
}

function tmplServerClass(name) {
  return `--!strict
-- ${name} (Server Class)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Deps = {
  Services: any,
  Config: any?,
  GameData: any?,
}

export type ${name} = {
  _deps: Deps,
  _opts: { [string]: any },
  _conns: { RBXScriptConnection },

  Init: (self: ${name}) -> (),
  Destroy: (self: ${name}) -> (),

  Spend: (self: ${name}, player: Player, currencyId: string, amount: number) -> boolean,
}

local ${name} = {}
${name}.__index = ${name}

function ${name}.new(deps: Deps, opts: { [string]: any }?): ${name}
  assert(deps ~= nil and deps.Services ~= nil, "${name}.new => deps.Services is required")
  local self = setmetatable({
    _deps = deps,
    _opts = opts or {},
    _conns = {},
  }, ${name})
  return self
end

function ${name}:Init()
  -- local CurrencyService = (self._deps.Services :: any).CurrencyService
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
  for _, c in self._conns do pcall(function() c:Disconnect() end) end
  table.clear(self._conns)
end

return ${name}
`;
}

// ----------------- default dirs + place-aware roots -----------------
const CLASS_DIRS = {
  shared: "src/shared/classes",
  server: "src/server/classes",
};

function baseDirFor(kind, place, explicitAt) {
  // If user passed --at, honor it absolutely.
  if (explicitAt) return path.resolve(REPO, explicitAt);

  // Otherwise use place-specific root if it exists, else src.
  const root = sourceRootFor(place);
  switch (kind) {
    case "service":    return path.join(root, "server/services");
    case "controller": return path.join(root, "client/controllers");
    case "component":  return path.join(root, "client/components");
    case "system":     return path.join(root, "_systems");
    case "data_type":  return path.join(root, "_game_data/source/data_types");
    case "class_shared": return path.join(root, "shared/classes");
    case "class_server": return path.join(root, "server/classes");
    default: return root;
  }
}

// ----------------- creators (now place-aware) -----------------
function createService(name, parentAbsOrNull) {
  const pas = toPascal(name);
  const file = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(file, tmplService(pas)) ? [file] : [];
}

function createController(name, parentAbsOrNull) {
  const pas = toPascal(name);
  const file = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(file, tmplController(pas)) ? [file] : [];
}

function createComponent(name, parentAbsOrNull) {
  const pas = toPascal(name);
  const file = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(file, tmplComponent(pas)) ? [file] : [];
}

function createSystem(name, parentAbsOrNull) {
  const sysName = name;
  const base = path.resolve(parentAbsOrNull, sysName);

  // server
  ensureDir(path.join(base, "server/services"));
  ensureDir(path.join(base, "server/packages"));
  ensureDir(path.join(base, "server/classes"));

  // client
  ensureDir(path.join(base, "client/controllers"));
  ensureDir(path.join(base, "client/components"));
  ensureDir(path.join(base, "client/utils"));

  // shared
  ensureDir(path.join(base, "shared/assets/ui"));
  ensureDir(path.join(base, "shared/assets/models"));
  ensureDir(path.join(base, "shared/classes"));
  ensureDir(path.join(base, "shared/config"));

  // data types
  ensureDir(path.join(base, "data_types"));
  
  console.log("✓ created system scaffold at", path.relative(process.cwd(), base));
  return [];
}

function createDataType(name, parentAbsOrNull) {
  const pas = toPascal(name);
  const file = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(file, tmplDataType(pas)) ? [file] : [];
}

function createSharedClass(rawName, parentAbs) {
  const pas = toPascal(rawName);
  const abs = path.join(parentAbs, `${pas}.luau`);
  writeIfMissing(abs, tmplSharedClass(pas));
  return abs;
}

function createServerClass(rawName, parentAbs) {
  const pas = toPascal(rawName);
  const abs = path.join(parentAbs, `${pas}.luau`);
  writeIfMissing(abs, tmplServerClass(pas));
  return abs;
}

function createPlace(name) {
  const pas = name; // keep user casing
  const base = path.resolve("place_overrides", pas);

  // shared
  ensureDir(path.join(base, "shared/assets/ui"));
  ensureDir(path.join(base, "shared/assets/models"));
  ensureDir(path.join(base, "shared/classes"));
  ensureDir(path.join(base, "shared/config"));
  ensureDir(path.join(base, "shared/packages")); // optional, in case you override shared packages/resolver

  // client
  ensureDir(path.join(base, "client/controllers"));
  ensureDir(path.join(base, "client/components"));
  ensureDir(path.join(base, "client/utils"));

  // server
  ensureDir(path.join(base, "server/services"));
  ensureDir(path.join(base, "server/packages"));
  ensureDir(path.join(base, "server/classes"));

  console.log("✓ place scaffolding:", base);

  // generate project file
  console.log(`→ Generating project for ${pas}`);
  let r = run("node", ["tools/genRojoTree.js", pas]);
  if (r.status !== 0) return r.status;

  // build output (build-<place>.rbxl)
  console.log(`→ Building ${pas}`);
  ensureDir("builds");
  const outName = path.join("builds", `build-${pas}.rbxl`);
  r = run("rojo", ["build", `places/${pas}.project.json`, "-o", outName]);
  if (r.status !== 0) return r.status;

  console.log(`✓ Built ${outName}`);
  return 0;
}

// ----------------- usage -----------------
function usage() {
  console.log(`
Woolly CLI

  setup [Place]           Install deps, generate project, build, then serve

  gen [Place]             Generate places/<Place>.project.json (default: current place)
  serve [Place]           Run 'rojo serve' for that place
  build [Place]           Build 'builds/<Place>.rbxl' for that place
  switch <Place>          Make <Place> the default place in .woollyrc.json

  create place       <Name>
  create service     <Name> [--at <dir>] [--place <Place>] [--system <Sys>]
  create controller  <Name> [--at <dir>] [--place <Place>] [--system <Sys>]
  create component   <Name> [--at <dir>] [--place <Place>] [--system <Sys>]
  create system      <Name> [--at <dir>] [--place <Place>] [--system <Sys>]
  create data_type   <Name> [--at <dir>] [--place <Place>] [--system <Sys>]
  create class       <Name> (--target shared|server | --both) [--system <Sys>] [--place <Place>]

Notes:
- If --place is given and /place_overrides/<Place> exists, scaffolding goes there; otherwise /src.
- --at always wins if provided.
`);
}

// ----------------- parse args -----------------
const args = process.argv.slice(2);
const [cmd, sub, rawName, ...rest] = args;

// quick flag helpers
function getFlag(name) {
  const idx = rest.indexOf(name);
  return idx >= 0 ? rest[idx + 1] : undefined;
}
function hasFlag(name) { return rest.includes(name); }

// Command routing
if (!cmd || cmd === "--help" || cmd === "-h") {
  usage();
  process.exit(0);
}

if (cmd === "setup") {
  // Default to current place if not provided
  const place = resolvePlace(sub);

  // Make sure place_overrides/<Place> exists with expected folders
  ensurePlaceSkeleton(place);

  // 1) wally install
  let code = tryRun("wally", ["install"]);
  if (code !== 0) {
    console.warn("⚠ wally install failed or wally not found. Continuing anyway...");
  }

  // 2) rokit install (ok if missing rokit.toml or rokit not installed)
  code = tryRun("rokit", ["install"]);
  if (code !== 0) {
    console.warn("⚠ rokit install failed (no rokit.toml or rokit not found). Continuing...");
  }

  // 3) generate project for this place
  code = tryRun("node", ["tools/genRojoTree.js", place]);
  if (code !== 0) process.exit(0);

  // 4) build to /builds
  ensureDir(path.join(REPO, "builds"));
  const outFile = path.join(REPO, "builds", `${place}.rbxlx`);
  code = tryRun("rojo", ["build", path.relative(REPO, placeProjectPath(place)), "-o", path.relative(REPO, outFile)]);
  if (code !== 0) process.exit(code);

  console.log(`✓ Built ${path.relative(process.cwd(), outFile)}`);

  // 5) serve
  console.log("→ Starting rojo serve");
  code = tryRun("rojo", ["serve", path.relative(REPO, placeProjectPath(place))]);
  process.exit(code);
}

if (cmd === "switch") {
  const place = sub;
  if (!place) { console.error("Usage: woolly switch <Place>"); process.exit(1); }
  setDefaultPlace(place);
  console.log("✓ Default place ->", place);
  process.exit(0);
}

if (cmd === "gen") {
  const place = resolvePlace(sub);
  const res = run("node", ["tools/genRojoTree.js", place]);
  process.exit(res.status);
}

if (cmd === "serve") {
  const place = resolvePlace(sub);
  const project = placeProjectPath(place);
  if (!fs.existsSync(project)) {
    console.log(`No project for ${place} yet. Generating...`);
    const gen = run("node", ["tools/genRojoTree.js", place]);
    if (gen.status !== 0) process.exit(gen.status);
  }
  const res = run("rojo", ["serve", path.relative(REPO, project)]);
  process.exit(res.status);
}

if (cmd === "build") {
  const place = resolvePlace(sub);
  const project = placeProjectPath(place);
  if (!fs.existsSync(project)) {
    console.log(`No project for ${place} yet. Generating...`);
    const gen = run("node", ["tools/genRojoTree.js", place]);
    if (gen.status !== 0) process.exit(gen.status);
  }
  ensureDir(path.join(REPO, "builds"));
  const out = path.join(REPO, "builds", `${place}.rbxl`);
  const res = run("rojo", ["build", path.relative(REPO, project), "-o", path.relative(REPO, out)]);
  process.exit(res.status);
}

if (cmd === "create") {
  const kind = sub;
  const name = rawName;
  if (!kind || !name) { usage(); process.exit(1); }

  // parse shared flags
  const atDirOpt = getFlag("--at");
  const placeOpt = getFlag("--place");
  const place = resolvePlace(placeOpt);

  // class-specific flags
  const target = getFlag("--target");
  const both = hasFlag("--both");
  const systemName = getFlag("--system");

  console.log("Place opt:", placeOpt);
  console.log("Place:", place);

  // Resolve default base directory (place-aware), then override with --at if provided
  let baseAbs;
  let created = [];

  switch (kind) {
    case "place": {
      const placeName = rawName;

      if (!placeName) {
        console.error("Usage: woolly create place <PlaceName>");
        process.exit(1);
      }

      const code = createPlace(placeName);
      process.exit(code);
      break;
    }
    case "service": {
      if (atDirOpt) {
        // --at always wins
        baseAbs = path.resolve(REPO, atDirOpt);
      } else if (systemName) {
        // If a system is specified, target its data_types folder
        baseAbs = path.join(sourceRootFor(place), "_systems", systemName, "server", "services");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("service", place, null);
      }
      
      created = createService(name, baseAbs);
      break;
    }
    case "controller": {
      if (atDirOpt) {
        // --at always wins
        baseAbs = path.resolve(REPO, atDirOpt);
      } else if (systemName) {
        // If a system is specified, target its data_types folder
        baseAbs = path.join(sourceRootFor(place), "_systems", systemName, "client", "controllers");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("controller", place, null);
      }

      created = createController(name, baseAbs);
      break;
    }
    case "component": {
      if (atDirOpt) {
        // --at always wins
        baseAbs = path.resolve(REPO, atDirOpt);
      } else if (systemName) {
        // If a system is specified, target its client/components folder
        baseAbs = path.join(sourceRootFor(place), "_systems", systemName, "client", "components");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("component", place, null);
      }

      // baseAbs = atDirOpt ? path.resolve(REPO, atDirOpt) : baseDirFor("component", place, null);
      created = createComponent(name, baseAbs);
      break;
    }
    case "system": {
      baseAbs = atDirOpt ? path.resolve(REPO, atDirOpt) : baseDirFor("system", place, null);
      created = createSystem(name, baseAbs);
      break;
    }
    case "data_type": {
      if (atDirOpt) {
        // --at always wins
        baseAbs = path.resolve(REPO, atDirOpt);
      } else if (systemName) {
        // If a system is specified, target its data_types folder
        baseAbs = path.join(sourceRootFor(place), "_systems", systemName, "data_types");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("data_type", place, null);
      }
      
      created = createDataType(name, baseAbs);
      break;
    }
    case "class": {
      // default roots for classes (place-aware)
      const sharedRoot = atDirOpt ? path.resolve(REPO, atDirOpt) :
        (systemName
          ? path.join(sourceRootFor(place), "_systems", systemName, "shared/classes")
          : baseDirFor("class_shared", place, null));

      const serverRoot = atDirOpt ? path.resolve(REPO, atDirOpt) :
        (systemName
          ? path.join(sourceRootFor(place), "_systems", systemName, "server/classes")
          : baseDirFor("class_server", place, null));

      const made = [];

      if (!both && target !== "shared" && target !== "server") {
        console.error("Please specify --target shared|server or use --both");
        process.exit(1);
      }
      if (both || target === "shared") {
        ensureDir(sharedRoot);
        const p = createSharedClass(name, sharedRoot);
        if (p) made.push(p);
      }
      if (both || target === "server") {
        ensureDir(serverRoot);
        const p = createServerClass(name, serverRoot);
        if (p) made.push(p);
      }
      created = made;
      break;
    }
    default:
      console.error("Unknown kind:", kind);
      usage();
      process.exit(1);
  }

  if (created.length > 0) openInEditor(created[0]);

  // Auto-regenerate mapping for this place
  const gen = run("node", ["tools/genRojoTree.js", place]);
  process.exit(gen.status);
}

// Fallback
usage();
process.exit(1);