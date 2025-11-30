#!/usr/bin/env node
/* Woolly CLI
   New commands:
     woolly gen [Place]            -> node tools/genRojoTree.js Place
     woolly serve [Place]          -> rojo serve Place.project.json
     woolly build [Place]          -> rojo build Place.project.json -o builds/Place.rbxl
     woolly switch <Place>         -> set default place in .woollyrc.json
     woolly create <kind> <Name> [--at <dir>] [--place <Place>] [class flags...]
       kinds: service | controller | component | system | data_type | class
       class flags: --target shared|server | --both | --system <SysName>
*/

const fs = require("fs");
const path = require("path");
const cp  = require("child_process");
const { get } = require("http");

const REPO = path.join(__dirname, "..");
const PLACES_DIR = REPO;
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

function listDirs(abs) {
  if (!fs.existsSync(abs)) return [];
  return fs.readdirSync(abs, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => path.join(abs, d.name));
}

function resolveModuleFile(absBaseDir, pasName) {
  let p = path.join(absBaseDir, `${pasName}.luau`);
  if (fs.existsSync(p)) return p;

  p = path.join(absBaseDir, `${pasName}.lua`);
  if (fs.existsSync(p)) return p;

  p = path.join(absBaseDir, pasName, "init.luau");
  if (fs.existsSync(p)) return p;

  p = path.join(absBaseDir, pasName, "init.lua");
  if (fs.existsSync(p)) return p;

  return null;
}

function resolveOpenPath(kind, name, _place, opts = {}) {
  const { atDirOpt, systemName, target, preferSrc, placeOpt } = opts;
  const pasName = toPascal(name);

  // If --at is used, respect it for non-system kinds
  if (atDirOpt && kind !== "system") {
    const abs = resolveModuleFile(path.resolve(REPO, atDirOpt), pasName);
    return abs || path.join(path.resolve(REPO, atDirOpt), `${pasName}.luau`);
  }

  if (kind === "system") {
    // If a specific system name was given, open that folder across roots; otherwise open src/_systems/<Name> or fall back to any override
    if (systemName) {
      const direct = [
        path.join(SRC_DIR, "_systems", systemName),
        ...(placeOpt ? [path.join(OVERRIDES_DIR, placeOpt, "_systems", systemName)]
                    : listDirs(OVERRIDES_DIR).map(ov => path.join(ov, "_systems", systemName))),
      ];
      for (const d of direct) if (fs.existsSync(d) && fs.statSync(d).isDirectory()) return d;
      return direct[0]; // best-effort path
    }
    return path.join(sourceRootFor(_place, preferSrc), "_systems"); // generic
  }

  // Build global search bases for this kind
  const bases = searchBasesForKind(kind, { target, placeOpt });

  // Try to resolve the module in order
  for (const base of bases) {
    const hit = resolveModuleFile(base, pasName);
    if (hit) return hit;
  }

  // Nothing found; return the first “expected” path (so the caller can print a helpful message)
  return bases.length ? path.join(bases[0], `${pasName}.luau`) : null;
}

function overridesRootFor(place) {
  const abs = path.join(OVERRIDES_DIR, place);
  return fs.existsSync(abs) && fs.statSync(abs).isDirectory() ? abs : null;
}

function sourceRootFor(place, preferSrc = false) {
  // If preferSrc is true, ignore overrides and use /src
  if (preferSrc) return SRC_DIR;

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

function LU(name) {
  return /\.lua(u)?$/i.test(name);
}
function isDir(p) { return fs.existsSync(p) && fs.statSync(p).isDirectory(); }
function isFile(p){ return fs.existsSync(p) && fs.statSync(p).isFile(); }

function listDirs(abs) {
  if (!fs.existsSync(abs)) return [];
  return fs.readdirSync(abs, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => path.join(abs, d.name));
}

// Return display names in a single directory for module-like entries:
// - <Name>.luau / <Name>.lua  => "Name"
// - <Name>/init.luau|lua      => "Name"
// (Never returns "init")
function enumerateDirModules(absDir) {
  if (!isDir(absDir)) return [];
  const names = new Set();

  for (const ent of fs.readdirSync(absDir, { withFileTypes: true })) {
    const full = path.join(absDir, ent.name);

    if (ent.isDirectory()) {
      const initLuau = path.join(full, "init.luau");
      const initLua  = path.join(full, "init.lua");
      if (isFile(initLuau) || isFile(initLua)) {
        names.add(ent.name);
      }
      continue;
    }

    if (ent.isFile() && LU(ent.name)) {
      const base = ent.name.replace(/\.(luau|lua)$/i, "");
      if (base.toLowerCase() !== "init") names.add(base);
    }
  }

  return [...names];
}

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

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types (generated)
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps inferred from real modules
type ServiceRegistry = ServicesTypes.Registry

type DataInterface  = ServicesTypes.DataInterface
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
\tDataInterface: DataInterface,
\tSharedPackages: SharedPackages,
\tGameData: GameData,
\tMonetisation: Monetisation,
\tConfig: Config,
\tTunables: Tunables,
}

export type ${Name}API = {
\t_inited: boolean,
\t_started: boolean,
\t_conns: { RBXScriptConnection },
\tPriority: number?,
\tServices: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

\tInit: (self: ${Name}API, deps: Deps) -> (),
\tStart: (self: ${Name}API) -> (),
\tDestroy: (self: ${Name}API) -> (),
}

local ${Name} = {
\t_inited = false,
\t_started = false,
\t_conns = {},
\tPriority = 50, -- higher -> starts earlier
\tServices = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Life Cycle ========== --

function ${Name}:Init(deps: Deps)
\tif self._inited then return end
\tself._inited = true
\tself._conns = {}
\t_deps = deps

\t-- // Example: get/create remotes
end

function ${Name}:Start()
\tif not self._inited or self._started then return end
\tself._started = true

\t-- // Example: connect remotes, start loops, etc.
end

function ${Name}:Destroy()
\tfor _, conn in self._conns do
\t\tpcall(function() conn:Disconnect() end)
\tend
\ttable.clear(self._conns)
\t_deps = nil
\tself._started = false
\tself._inited = false
end

return ${Name} :: ${Name}API
`;

const tmplController = (Name) => `--!strict
-- ${Name} (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Types (generated)
local ControllersTypes = require(ReplicatedStorage.Shared.Types.Controllers)

-- // Type aliases for deps inferred from real modules
type ControllerRegistry = ControllersTypes.Registry

type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
\tReplicatedData: ReplicatedData,
\tSharedPackages: SharedPackages,
\tGameData: GameData,
\tMonetisation: Monetisation,
\tConfig: Config,
\tTunables: Tunables,
}

export type ${Name}API = {
\t_inited: boolean,
\t_started: boolean,
\t_conns: { RBXScriptConnection },
\tPriority: number?,
\tControllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

\tInit: (self: ${Name}API, deps: Deps) -> (),
\tStart: (self: ${Name}API) -> (),
\tDestroy: (self: ${Name}API) -> (),
}

local ${Name} = {
\t_inited = false,
\t_started = false,
\t_conns = {},
\tPriority = 50, -- higher -> starts earlier
\tControllers = {} :: ControllerRegistry,
} :: ${Name}API

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Life Cycle ========== --

function ${Name}:Init(deps: Deps)
\tif self._inited then return end
\tself._inited = true
\tself._conns = {}
\t_deps = deps

\t-- // Example: get remotes / find UI elements
end

function ${Name}:Start()
\tif not self._inited or self._started then return end
\tself._started = true

\t-- // Example: connect remotes, bind UI, start loops, etc.
end

function ${Name}:Destroy()
\tfor _, conn in self._conns do
\t\tpcall(function() conn:Disconnect() end)
\tend
\ttable.clear(self._conns)
\t_deps = nil
\tself._started = false
\tself._inited = false
end

return ${Name} :: ${Name}API
`;

const tmplComponent = (Name) => `--!strict
-- ${Name} (Component)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)

-- // Custom types

-- // Type aliases for deps inferred from real modules
type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
\tReplicatedData: ReplicatedData,
\tSharedPackages: SharedPackages,
\tGameData: GameData,
\tMonetisation: Monetisation,
\tConfig: Config,
\tTunables: Tunables,
}

export type ${Name}API = {
\t_inited: boolean,
\t_conns: { RBXScriptConnection },

\tInit: (self: ${Name}API) -> (),
\tDestroy: (self: ${Name}API) -> (),
}

export type Opts = {}

local ${Name} = {}
${Name}.__index = ${Name}

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function ${Name}.new(deps: Deps, opts: Opts): ${Name}API
\tif not _deps then
\t\t_deps = deps
\tend

\tlocal self = setmetatable({ _inited = false, _conns = {} } :: any, ${Name}) :: ${Name}API
\treturn self
end

-- ========== Public API ========== --

function ${Name}:PublicMethod()
\t-- Example
end

-- ========== Internal ========== --

function ${Name}:_internalMethod()
\t-- Example
end

-- ========== Life Cycle ========== --

function ${Name}:Init()
\tif self._inited then return end
\tself._inited = true

\t-- // Bind signals, initialise state etc.
end

function ${Name}:Destroy()
\t-- Cleanup
\tfor _, c in pairs(self._conns) do
\t\tc:Disconnect()
\tend
\ttable.clear(self._conns)
\tself._inited = false
end

return ${Name} :: ${Name}API
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

function tmplSharedClass(Name) {
  return `--!strict
-- ${Name} (Shared Class) — usable on client or server.

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Type aliases for deps
type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
\tReplicatedData: ReplicatedData,
\tSharedPackages: SharedPackages,
\tGameData: GameData,
\tMonetisation: Monetisation,
\tConfig: Config,
\tTunables: Tunables,
}

export type Opts = {
\t-- args used when constructing the class
}

export type ${Name}API = {
\t_opts: Opts,
\t_conns: { RBXScriptConnection },

\tInit: (self: ${Name}API) -> (),
\tDestroy: (self: ${Name}API) -> (),
}

local ${Name} = {}
${Name}.__index = ${Name}

-- Private captured deps
local _deps: Deps?

-- ========== Constructor ========== --

function ${Name}.new(deps: Deps, opts: Opts?): ${Name}API
\t_deps = deps

\tlocal self = setmetatable({} :: any, ${Name}) :: ${Name}API
\tself._opts = opts or {}
\tself._conns = {}

\treturn self
end

-- ========== Life Cycle ========== --

function ${Name}:Init()
\t-- Client/server-specific wiring if needed
\tif RunService:IsClient() then
\t\t-- client-only setup
\telse
\t\t-- server-only setup
\tend
end

function ${Name}:Destroy()
\tfor _, c in self._conns do
\t\tpcall(function() c:Disconnect() end)
\tend
\ttable.clear(self._conns)
\t_deps = nil
end

return ${Name} :: ${Name}API
`;
}

function tmplServerClass(Name) {
  return `--!strict
-- ${Name} (Server Class)

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps
type ServiceRegistry = ServicesTypes.Registry

type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
\tReplicatedData: ReplicatedData,
\tServices: ServiceRegistry,
\tSharedPackages: SharedPackages,
\tGameData: GameData,
\tMonetisation: Monetisation,
\tConfig: Config,
\tTunables: Tunables,
}

export type Opts = {
\t-- args used when constructing the class
}

export type ${Name}API = {
\t_opts: Opts,
\t_conns: { RBXScriptConnection },

\tInit: (self: ${Name}API) -> (),
\tDestroy: (self: ${Name}API) -> (),
}

local ${Name} = {}
${Name}.__index = ${Name}

-- Private captured deps
local _deps: Deps?

function ${Name}.new(deps: Deps, opts: Opts?): ${Name}API
\t_deps = deps

\tlocal self = setmetatable({} :: any, ${Name}) :: ${Name}API
\tself._opts = opts or {}
\tself._conns = {}

\treturn self
end

function ${Name}:Init()
\t-- // Example: connect remotes/events
end

function ${Name}:Destroy()
\tfor _, c in self._conns do
\t\tpcall(function() c:Disconnect() end)
\tend
\ttable.clear(self._conns)
\t_deps = nil
end

return ${Name} :: ${Name}API
`;
}

function tmplPackage(Name) { 
  return `--!strict
-- ${Name} (Package)
export type ${Name}API = {}

local ${Name} = {}

return ${Name} :: ${Name}API
`;
}

function tmplConfig(Name) { 
  return `--!strict
-- ${Name} (Config)
export type ${Name}API = {}

local ${Name} = {}

return ${Name} :: ${Name}API
`;
}

function tmplUtil(Name) { 
  return `--!strict
-- ${Name} (Util)
export type ${Name}API = {}

local ${Name} = {}

return ${Name} :: ${Name}API
`;
}

// ----------------- default dirs + place-aware roots -----------------
const CLASS_DIRS = {
  shared: "src/shared/classes",
  server: "src/server/classes",
};

function baseDirFor(kind, place, explicitAt, preferSrc = false) {
  // If user passed --at, honor it absolutely.
  if (explicitAt) return path.resolve(REPO, explicitAt);

  // Otherwise use place-specific root if it exists, else src.
  const root = sourceRootFor(place, preferSrc);
  switch (kind) {
    case "service":         return path.join(root, "server/services");
    case "controller":      return path.join(root, "client/controllers");
    case "component":       return path.join(root, "client/components");
    case "system":          return path.join(root, "_systems");
    case "data_type":       return path.join(root, "_game_data/source/data_types");
    case "class_shared":    return path.join(root, "shared/classes");
    case "class_server":    return path.join(root, "server/classes");
    case "package_server":  return path.join(root, "server/packages");
    case "package_shared":  return path.join(root, "shared/packages");
    case "config":          return path.join(root, "shared/config");
    case "util":            return path.join(root, "shared/utils");
    default: return root;
  }
}

function searchBasesForKind(kind, opts = {}) {
  // opts: { target?, placeOpt?, preferSrc? }
  const { target, placeOpt } = opts;

  // Helper to map a root to a subpath by kind
  const subpathsFor = (root, mode /* "plain" | "system" */) => {
    const sysPrefix = mode === "system" ? path.join(root, "_systems", "*") : root;

    switch (kind) {
      case "service":    return [path.join(sysPrefix, "server", "services"), path.join(root, "server", "services")];
      case "controller": return [path.join(sysPrefix, "client", "controllers"), path.join(root, "client", "controllers")];
      case "component":  return [path.join(sysPrefix, "client", "components"),  path.join(root, "client", "components")];
      case "data_type":  return [path.join(sysPrefix, "data_types"), path.join(root, "_game_data", "source", "data_types")];
      case "config":     return [path.join(sysPrefix, "shared", "config"),      path.join(root, "shared", "config")];
      case "util":       return [path.join(sysPrefix, "shared", "utils"),       path.join(root, "shared", "utils")];

      case "package": {
        // target may be "shared" or "server"; if missing, we'll test both later
        const shared = [path.join(sysPrefix, "shared", "packages"), path.join(root, "shared", "packages")];
        const server = [path.join(sysPrefix, "server", "packages"), path.join(root, "server", "packages")];
        if ((target || "").toLowerCase() === "server") return server;
        if ((target || "").toLowerCase() === "shared") return shared;
        return [...shared, ...server]; // try both when target not specified
      }

      case "class": {
        // target may be "shared" or "server"; if missing, test shared then server
        const shared = [path.join(sysPrefix, "shared", "classes"), path.join(root, "shared", "classes")];
        const server = [path.join(sysPrefix, "server", "classes"), path.join(root, "server", "classes")];
        if ((target || "").toLowerCase() === "server") return server;
        if ((target || "").toLowerCase() === "shared") return shared;
        return [...shared, ...server]; // try shared first, then server
      }

      default:
        return [];
    }
  };

  // Build override roots
  let overrideRoots = [];
  if (placeOpt) {
    const one = path.join(OVERRIDES_DIR, placeOpt);
    if (fs.existsSync(one) && fs.statSync(one).isDirectory()) overrideRoots = [one];
  } else {
    overrideRoots = listDirs(OVERRIDES_DIR);
  }

  // Expand “system” paths by globs: we’ll just replace the '*' manually
  const expandSystems = (patterns) => {
    const out = [];
    for (const pat of patterns) {
      const parts = pat.split(path.sep);
      const starIdx = parts.indexOf("*");
      if (starIdx === -1) {
        out.push(pat);
        continue;
      }
      const sysRoot = parts.slice(0, starIdx).join(path.sep);
      const remainder = parts.slice(starIdx + 1).join(path.sep);
      if (!fs.existsSync(sysRoot)) continue;
      for (const sys of listDirs(sysRoot)) {
        out.push(path.join(sys, remainder));
      }
    }
    return out;
  };

  // Order:
  // 1) place_overrides/*/_systems/*/<...>, then place_overrides/*/<...>
  // 2) src/_systems/*/<...>, then src/<...>
  const bases = [];

  // overrides: system-first then plain
  for (const ov of overrideRoots) {
    bases.push(...expandSystems(subpathsFor(ov, "system")));
  }
  for (const ov of overrideRoots) {
    bases.push(...subpathsFor(ov, "plain"));
  }

  // src: system-first then plain
  bases.push(...expandSystems(subpathsFor(SRC_DIR, "system")));
  bases.push(...subpathsFor(SRC_DIR, "plain"));

  // Dedup & only keep existing dirs
  const seen = new Set();
  const existing = [];
  for (const b of bases) {
    const norm = path.normalize(b);
    if (seen.has(norm)) continue;
    seen.add(norm);
    if (fs.existsSync(norm) && fs.statSync(norm).isDirectory()) existing.push(norm);
  }
  return existing;
}

// For kinds that split by target (class/package), we can pass target.
// If target is omitted for class/package, we’ll aggregate shared+server and label them.
function collectModulesForKind(kind, { placeOpt } = {}) {
  const out = new Map(); // name -> Set<labels>  (labels used only for class/package sides)

  const add = (name, label) => {
    if (!out.has(name)) out.set(name, new Set());
    if (label) out.get(name).add(label);
  };

  const pushFromBases = (bases, label) => {
    for (const base of bases) {
      if (!isDir(base)) continue;
      for (const n of enumerateDirModules(base)) add(n, label);
    }
  };

  if (kind === "system") {
    // Systems are directories under _systems/
    const sysNames = new Set();
    // place_overrides/*/_systems/*
    const ovRoots = placeOpt
      ? [path.join(OVERRIDES_DIR, placeOpt)]
      : listDirs(OVERRIDES_DIR);

    for (const ov of ovRoots) {
      const sysRoot = path.join(ov, "_systems");
      if (!isDir(sysRoot)) continue;
      for (const d of listDirs(sysRoot)) sysNames.add(path.basename(d));
    }

    // src/_systems/*
    const srcSys = path.join(SRC_DIR, "_systems");
    if (isDir(srcSys)) {
      for (const d of listDirs(srcSys)) sysNames.add(path.basename(d));
    }

    return [...sysNames].sort();
  }

  if (kind === "class" || kind === "package") {
    // Try shared then server when target not specified
    const sharedBases = searchBasesForKind(kind, { target: "shared", placeOpt });
    const serverBases = searchBasesForKind(kind, { target: "server", placeOpt });
    pushFromBases(sharedBases, "shared");
    pushFromBases(serverBases, "server");

    // Return entries as "Name [shared]" / "Name [server]" if both present
    const lines = [];
    for (const [name, labels] of [...out.entries()].sort((a,b)=>a[0].localeCompare(b[0]))) {
      if (labels.size === 0) {
        lines.push(name);
      } else if (labels.size === 1) {
        lines.push(`${name} [${[...labels][0]}]`);
      } else {
        // both sides
        lines.push(`${name} [shared]`);
        lines.push(`${name} [server]`);
      }
    }
    return lines;
  }

  // Simple kinds (service/controller/component/data_type/config/util)
  const bases = searchBasesForKind(kind, { placeOpt });
  pushFromBases(bases, null);

  return [...out.keys()].sort();
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
  ensureDir(path.join(base, "shared/utils"));
  ensureDir(path.join(base, "shared/config"));

  // monetisation
  const monetisationDir = path.join(base, "monetisation");
  ensureDir(monetisationDir);

  const devProductsPath = path.join(monetisationDir, "DevProducts.luau");
  const gamepassesPath = path.join(monetisationDir, "Gamepasses.luau");

  const tmplDevProducts = (Name) => `--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type DevProductPrivate = Types.DevProductPrivate
type Handler = Types.Handler

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
  ["ExampleHandler"] = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
    -- Example handler
    print("Player " .. player.Name .. " purchased dev product " .. tostring(productId))
    return true
  end,
}

-- ========== Definitions ========== --
local defs: { devProducts: { [string]: DevProductPrivate } } = {
  devProducts = {
    ["${Name}_DevProduct"] = {
      id = 123456789,
      name = "Example Name",
      category = "Example Category",
      description = nil, -- hydrated automatically
      priceInRobux = nil, -- hydrated automatically
      iconImageAssetId = nil, -- hydrated automatically
      params = {  },
      handler = Handlers["ExampleHandler"],
    },
  },
}

return defs
`;

  const tmplGamepasses = (Name) => `--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type Handler = Types.Handler
type GamepassPrivate = Types.GamepassPrivate

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
  ["ExampleHandler"] = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
    -- Example handler
    print("Player " .. player.Name .. " purchased gamepass " .. tostring(productId))
    return true
  end,
}

-- ========== Definitions ========== --
local defs: { gamepasses: { [string]: GamepassPrivate } } = {
  gamepasses = {
    ["${Name}_Gamepass"] = {
      id = 123456789,
      name = "Example Name",
      category = "Example Category",
      description = nil, -- hydrated automatically
      priceInRobux = nil, -- hydrated automatically
      iconImageAssetId = nil, -- hydrated automatically
      params = {  },
      handler = Handlers["ExampleHandler"],
    },
  },
}

return defs
`;

  writeIfMissing(devProductsPath, tmplDevProducts(sysName));
  writeIfMissing(gamepassesPath, tmplGamepasses(sysName));

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

function createSharedPackage(rawName, parentAbsOrNull) {
  const pas = toPascal(rawName);
  const file = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(file, tmplPackage(pas)) ? [file] : [];
}

function createServerPackage(rawName, parentAbsOrNull) {
  const pas = toPascal(rawName);
  const file = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(file, tmplPackage(pas)) ? [file] : [];
}

function createConfig(rawName, parentAbsOrNull) {
  const pas = toPascal(rawName);

  const abs = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(abs, tmplConfig(pas)) ? [abs] : [];
}

function createUtil(rawName, parentAbsOrNull) {
  const pas = toPascal(rawName);
  const abs = path.resolve(parentAbsOrNull, `${pas}.luau`);
  return writeIfMissing(abs, tmplUtil(pas)) ? [abs] : [];
}

function createPlace(name) {
  const pas = name; // keep user casing
  const base = path.resolve("place_overrides", pas);

  // shared
  ensureDir(path.join(base, "shared/assets/ui"));
  ensureDir(path.join(base, "shared/assets/models"));
  ensureDir(path.join(base, "shared/classes"));
  ensureDir(path.join(base, "shared/config"));
  ensureDir(path.join(base, "shared/packages"));
  ensureDir(path.join(base, "shared/utils"));

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

  // generate types for intellisense
  const place = resolvePlace(sub);
  r = run("node", ["tools/genTypes.js", place]);
  if (r.status !== 0) return r.status;

  // build output (build-<place>.rbxl)
  console.log(`→ Building ${pas}`);
  ensureDir("builds");
  const outName = path.join("builds", `build-${pas}.rbxl`);
  r = run("rojo", ["build", `${pas}.project.json`, "-o", outName]);
  if (r.status !== 0) return r.status;

  console.log(`✓ Built ${outName}`);
  return 0;
}

// ----------------- usage -----------------
function usage() {
  console.log(`
Woolly CLI

  setup [Place]           Install deps, generate project, build, then serve

  gen [Place]             Generate <Place>.project.json (default: current place)
  serve [Place]           Run 'rojo serve' for that place
  build [Place]           Build 'builds/<Place>.rbxl' for that place
  switch <Place>          Make <Place> the default place in .woollyrc.json

  open        <kind> <Name> [--at <dir>] [--place <Place>] [--system <Sys>] [--target shared|server]
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
  let r = run("node", ["tools/genRojoTree.js", place]);
  if (r.status !== 0) process.exit(r.status);

  // generate types for intellisense
  r = run("node", ["tools/genTypes.js", place]);
  if (r.status !== 0) return process.exit(r.status);

  process.exit(r.status);
}

if (cmd === "serve") {
  const place = resolvePlace(sub);
  const project = placeProjectPath(place);
  if (!fs.existsSync(project)) {
    console.log(`No project for ${place} yet. Generating...`);
    const gen = run("node", ["tools/genRojoTree.js", place]);
    if (gen.status !== 0) process.exit(gen.status);
  }
  const res = run("rojo", ["serve", path.basename(project)]);
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
  const out = path.join(REPO, "builds", `${place}.rbxlx`);
  const res = run("rojo", ["build", path.basename(project), "-o", path.relative(REPO, out)]);
  process.exit(res.status);
}

if (cmd === "open") {
  const kind = sub;
  const name = rawName;
  if (!kind || !name) { usage(); process.exit(1); }

  const atDirOpt = getFlag("--at");
  const placeOpt = getFlag("--place");
  const place = resolvePlace(placeOpt);
  const preferSrc = !placeOpt;
  const systemName = getFlag("--system");
  const target = getFlag("--target");
  const both = hasFlag("--both"); // tolerated for symmetry. Open shared if both

  const abs = resolveOpenPath(kind, name, place, {
    atDirOpt, systemName, target, both, preferSrc, placeOpt
  });
  if (!abs) {
    console.error("Could not resolve path to open. For classes, pass --target shared|server.");
    process.exit(1);
  }

  if (!fs.existsSync(abs)) {
    console.error("File does not exist:", path.relative(REPO, abs));
    process.exit(1);
  }

  openInEditor(abs);
  process.exit(0);
}

if (cmd === "list") {
  const kindArg = sub; // optional
  const placeOpt = getFlag("--place"); // you can let users filter to a single place override if they want

  const supported = [
    "service","controller","component","class","data_type","package","util","config","system"
  ];

  const showOne = (kind) => {
    const items = collectModulesForKind(kind, { placeOpt });
    console.log(`\n${kind.toUpperCase()}:`);
    if (!items.length) {
      console.log("  (none)");
      return;
    }
    for (const n of items) console.log("  - " + n);
  };

  if (kindArg) {
    if (!supported.includes(kindArg)) {
      console.error("Unknown kind:", kindArg);
      console.error("Supported kinds:", supported.join(", "));
      process.exit(1);
    }
    showOne(kindArg);
    process.exit(0);
  }

  // No kind => list all, grouped by kind
  for (const k of supported) showOne(k);
  console.log(); // trailing newline
  process.exit(0);
}

if (cmd === "create") {
  const kind = sub;
  const name = rawName;
  if (!kind || !name) { usage(); process.exit(1); }

  // parse shared flags
  const atDirOpt = getFlag("--at");
  const placeOpt = getFlag("--place");
  const place = resolvePlace(placeOpt);
  const preferSrc = !placeOpt;
  
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
        baseAbs = path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "server", "services");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("service", place, null, preferSrc);
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
        baseAbs = path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "client", "controllers");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("controller", place, null, preferSrc);
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
        baseAbs = path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "client", "components");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("component", place, null, preferSrc);
      }

      // baseAbs = atDirOpt ? path.resolve(REPO, atDirOpt) : baseDirFor("component", place, null);
      created = createComponent(name, baseAbs);
      break;
    }
    case "system": {
      baseAbs = atDirOpt ? path.resolve(REPO, atDirOpt) : baseDirFor("system", place, null, preferSrc);
      created = createSystem(name, baseAbs);
      break;
    }
    case "data_type": {
      if (atDirOpt) {
        // --at always wins
        baseAbs = path.resolve(REPO, atDirOpt);
      } else if (systemName) {
        // If a system is specified, target its data_types folder
        baseAbs = path.join(sourceRootFor(place, true), "_systems", systemName, "data_types");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("data_type", place, null, true);
      }
      
      created = createDataType(name, baseAbs);
      break;
    }
    case "class": {
      // default roots for classes (place-aware)
      const sharedRoot = atDirOpt ? path.resolve(REPO, atDirOpt) :
        (systemName
          ? path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "shared/classes")
          : baseDirFor("class_shared", place, null, preferSrc));

      const serverRoot = atDirOpt ? path.resolve(REPO, atDirOpt) :
        (systemName
          ? path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "server/classes")
          : baseDirFor("class_server", place, null, preferSrc));

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
    case "package": {
      // default roots for classes (place-aware)
      const sharedRoot = atDirOpt ? path.resolve(REPO, atDirOpt) :
        (systemName
          ? path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "shared/packages")
          : baseDirFor("package_shared", place, null, preferSrc));

      const serverRoot = atDirOpt ? path.resolve(REPO, atDirOpt) :
        (systemName
          ? path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "server/packages")
          : baseDirFor("package_server", place, null, preferSrc));

      const made = [];

      if (!both && target !== "shared" && target !== "server") {
        console.error("Please specify --target shared|server or use --both");
        process.exit(1);
      }
      if (both || target === "shared") {
        ensureDir(sharedRoot);
        const p = createSharedPackage(name, sharedRoot);
        if (p) made.push(p);
      }
      if (both || target === "server") {
        ensureDir(serverRoot);
        const p = createServerPackage(name, serverRoot);
        if (p) made.push(p);
      }
      created = made;
      break;
    }
    case "config": {
      if (atDirOpt) {
        // --at always wins
        baseAbs = path.resolve(REPO, atDirOpt);
      } else if (systemName) {
        // If a system is specified, target its client/components folder
        baseAbs = path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "shared", "config");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("config", place, null, preferSrc);
      }

      // baseAbs = atDirOpt ? path.resolve(REPO, atDirOpt) : baseDirFor("component", place, null);
      created = createConfig(name, baseAbs);
      break;
    }
    case "util": {
      if (atDirOpt) {
        // --at always wins
        baseAbs = path.resolve(REPO, atDirOpt);
      } else if (systemName) {
        // If a system is specified, target its client/components folder
        baseAbs = path.join(sourceRootFor(place, preferSrc), "_systems", systemName, "shared", "utils");
      } else {
        // Fall back to global game data folder
        baseAbs = baseDirFor("util", place, null, preferSrc);
      }

      // baseAbs = atDirOpt ? path.resolve(REPO, atDirOpt) : baseDirFor("component", place, null);
      created = createUtil(name, baseAbs);
      break;
    }
    default:
      console.error("Unknown kind:", kind);
      usage();
      process.exit(1);
  }

  if (created.length > 0) openInEditor(created[0]);

  // Auto-regenerate mapping for this place
  let r = run("node", ["tools/genRojoTree.js", place]);
  r = run("node", ["tools/genTypes.js", place]);
  process.exit(r.status);
}

// Fallback
usage();
process.exit(1);