/* eslint-disable */
const fs = require("fs");
const path = require("path");

// ====== Args & validation ======
const PLACE = process.argv[2];
if (!PLACE || !/^[A-Za-z0-9_-]+$/.test(PLACE)) {
  console.error("Usage: node tools/genRojoTree.js <PlaceName>");
  console.error("PlaceName must be alphanumeric, dashes, or underscores.");
  process.exit(1);
}

// ====== Paths ======
const REPO_ROOT  = path.join(__dirname, "..");
const SRC_BASE   = path.join(REPO_ROOT, "src");
const OV_BASE    = path.join(REPO_ROOT, "place_overrides", PLACE);
const OUT_DIR    = path.join(REPO_ROOT, "places");
const OUT_PATH   = path.join(OUT_DIR, `${PLACE}.project.json`);
const REL_BASE = path.dirname(OUT_PATH);

const SRC_SHARED = path.join(SRC_BASE, "shared");
const SRC_SERVER = path.join(SRC_BASE, "server");
const SRC_CLIENT = path.join(SRC_BASE, "client");
const SYS_ROOT   = path.join(SRC_BASE, "_systems");
const GD_ROOT    = path.join(SRC_BASE, "_game_data");
const MON_ROOT   = path.join(SRC_BASE, "_monetisation");
const TYPES_ROOT = path.join(SRC_BASE, "_types");

const OV_SHARED  = path.join(OV_BASE, "shared");
const OV_SERVER  = path.join(OV_BASE, "server");
const OV_CLIENT  = path.join(OV_BASE, "client");

// ====== Utils ======
const toPosix = (p) => p.split(path.sep).join("/");
const exists  = (p) => fs.existsSync(p);
const stat    = (p) => exists(p) ? fs.statSync(p) : null;
const isDir   = (p) => !!(stat(p) && stat(p).isDirectory());
const isFile  = (p) => !!(stat(p) && stat(p).isFile());
const hasInit = (dir) => isFile(path.join(dir, "init.luau")) || isFile(path.join(dir, "init.lua"));
const relFromProject = (abs) => toPosix(path.relative(REL_BASE, abs));

const LU = (name) => /\.lua(u)?$/i.test(name);
const isModelFile = (name) => /\.rbx(m|mx)$/i.test(name);
const stripExt = (n) => n.replace(/\.(luau|lua|rbxm|rbxmx)$/i, "");
const toPascal = (s) => /^[A-Z0-9_]+$/.test(s)
  ? s
  : s.split(/[^A-Za-z0-9]+/).filter(Boolean).map(w => w[0].toUpperCase()+w.slice(1)).join("");

function ensureFolder(parent, key) {
  if (!parent[key]) parent[key] = { $className: "Folder" };
  return parent[key];
}

function addFile(parent, nodeName, absPath, className /* optional */) {
  const rel = relFromProject(absPath);
  parent[nodeName] = className ? { $className: className, $path: rel } : { $path: rel };
}

function addFolderModule(parent, nodeName, absDir) {
  if (!isDir(absDir) || !hasInit(absDir)) return;
  const relDir = relFromProject(absDir);
  parent[nodeName] = { $path: relDir }; // folder-backed ModuleScript
}

// If directory is folder-backed, mount as ModuleScript; else as Folder with mirrored children
function mountSection(parent, nodeName, absDir) {
  if (!isDir(absDir)) return;
  if (hasInit(absDir)) addFolderModule(parent, nodeName, absDir);
  else mirrorFolderAsModules(ensureFolder(parent, nodeName), absDir);
}

function mirrorFolderAsModules(destParent, srcDir) {
  if (!isDir(srcDir)) return;

  // Mount the directory itself if it's folder-backed
  if (hasInit(srcDir)) {
    const nodeName = toPascal(path.basename(srcDir));
    addFolderModule(destParent, nodeName, srcDir);
    return;
  }

  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const full = path.join(srcDir, entry.name);
    if (entry.isDirectory()) {
      if (hasInit(full)) addFolderModule(destParent, toPascal(entry.name), full);
      else mirrorFolderAsModules(ensureFolder(destParent, toPascal(entry.name)), full);
    } else if (entry.isFile() && LU(entry.name)) {
      addFile(destParent, stripExt(entry.name), full);
    }
  }
}

function mirrorAssets(destParent, srcDir) {
  if (!isDir(srcDir)) return;
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const full = path.join(srcDir, entry.name);
    if (entry.isDirectory()) {
      mirrorAssets(ensureFolder(destParent, toPascal(entry.name)), full);
    } else if (entry.isFile() && isModelFile(entry.name)) {
      const nodeName = stripExt(entry.name);
      if (destParent[nodeName]) throw new Error(`[gen] Asset name collision: ${nodeName}`);
      addFile(destParent, nodeName, full);
    }
  }
}

// Merge system leaf (controllers/components/utils/services/packages/classes/config) into destination
function mergeSystemLeaf(destParent, leafAbs) {
  if (!isDir(leafAbs)) return;

  if (hasInit(leafAbs)) {
    const nodeName = toPascal(path.basename(leafAbs));
    if (destParent[nodeName]) throw new Error(`[gen] Name collision merging systems: ${nodeName}`);
    addFolderModule(destParent, nodeName, leafAbs);
    return;
  }

  for (const entry of fs.readdirSync(leafAbs, { withFileTypes: true })) {
    const full = path.join(leafAbs, entry.name);
    if (entry.isDirectory()) {
      if (hasInit(full)) {
        const nodeName = toPascal(entry.name);
        if (destParent[nodeName]) throw new Error(`[gen] Name collision merging systems: ${nodeName}`);
        addFolderModule(destParent, nodeName, full);
      } else {
        mergeSystemLeaf(ensureFolder(destParent, toPascal(entry.name)), full);
      }
    } else if (entry.isFile() && LU(entry.name)) {
      const nodeName = stripExt(entry.name);
      if (destParent[nodeName]) throw new Error(`[gen] Name collision merging systems: ${nodeName}`);
      addFile(destParent, nodeName, full);
    }
  }
}

// Helper: mount base, then overlay (overlay wins by name)
function overlaySection(parent, nodeName, baseAbs, overAbs) {
  // If overlay exists and is folder-backed, prefer folder-backed replacement
  if (isDir(overAbs) && hasInit(overAbs)) {
    addFolderModule(parent, nodeName, overAbs);
    return;
  }

  if (hasInit(baseAbs)) addFolderModule(parent, nodeName, baseAbs);
  else if (isDir(baseAbs)) mirrorFolderAsModules(ensureFolder(parent, nodeName), baseAbs);

  // Merge overlay content into the (possibly created) node
  if (isDir(overAbs)) {
    const target = ensureFolder(parent, nodeName);
    mergeSystemLeaf(target, overAbs);
  }
}

// Mount ExternalPackages by enumerating Packages/* and skipping _*
function mountExternalPackages(node /* ReplicatedStorage root */) {
  const ext = ensureFolder(node, "ExternalPackages");
  const PKG_DIR = path.join(REPO_ROOT, "Packages");
  if (!isDir(PKG_DIR)) return;

  for (const entry of fs.readdirSync(PKG_DIR, { withFileTypes: true })) {
    const name = entry.name;

    // Skip Wally's internals and any other private/hidden entries
    if (name.startsWith("_")) continue;

    const abs = path.join(PKG_DIR, name);

    // If it's a folder-backed module (contains init.lua/luau), mount as such
    if (entry.isDirectory() && hasInit(abs)) {
      addFolderModule(ext, name, abs); // keep package name as-is
      continue;
    }

    // If it's a directory without init, or a loose file module, just map the path
    if (entry.isDirectory() || LU(name)) {
      // Use raw name; don't PascalCase package names
      addFile(ext, entry.isDirectory() ? name : stripExt(name), abs);
    }
  }
}

// ====== Project skeleton ======
const project = {
  name: `woolly-${PLACE}`,
  tree: {
    $className: "DataModel",

    ReplicatedStorage: {
      Shared: { $className: "Folder" },
      ExternalPackages: { $className: "Folder" }
    },

    ServerScriptService: {
      Server: { $className: "Folder" }
    },

    StarterPlayer: {
      StarterPlayerScripts: {
        Client: { $className: "Folder" }
      }
    }
  }
};

const sharedRoot = project.tree.ReplicatedStorage.Shared;
const serverRoot = project.tree.ServerScriptService.Server;
const clientRoot = project.tree.StarterPlayer.StarterPlayerScripts.Client;

// Mount External Packages, ignoring _Index and _Index 2 dirs
mountExternalPackages(project.tree.ReplicatedStorage);

// ====== Build: Shared (base + overlay) ======
(function buildShared() {
  overlaySection(sharedRoot, "Packages",     path.join(SRC_SHARED, "packages"),     path.join(OV_SHARED, "packages"));
  overlaySection(sharedRoot, "GameData",     path.join(GD_ROOT, "resolver"),        path.join(OV_SHARED, "game_data_resolver"));
  overlaySection(sharedRoot, "Types",        TYPES_ROOT,                             path.join(OV_SHARED, "types"));
  overlaySection(sharedRoot, "Config",       path.join(SRC_SHARED, "config"),        path.join(OV_SHARED, "config"));
  overlaySection(sharedRoot, "Monetisation", path.join(MON_ROOT, "resolver"),        path.join(OV_SHARED, "monetisation_resolver"));

  // Classes (shared)
  overlaySection(sharedRoot, "Classes",      path.join(SRC_SHARED, "classes"),       path.join(OV_SHARED, "classes"));

  // Assets/UI & Assets/Models
  const assets = ensureFolder(sharedRoot, "Assets");
  const ui = ensureFolder(assets, "UI");
  const models = ensureFolder(assets, "Models");

  mirrorAssets(ui,     path.join(SRC_SHARED, "assets", "ui"));
  mirrorAssets(models, path.join(SRC_SHARED, "assets", "models"));
  mirrorAssets(ui,     path.join(OV_SHARED,  "assets", "ui"));
  mirrorAssets(models, path.join(OV_SHARED,  "assets", "models"));
})();

// ====== Build: Server (base + overlay) ======
(function buildServer() {
  // Bootstrap (file can be overridden)
  const bsBase = path.join(SRC_SERVER, "Bootstrap.server.luau");
  const bsOv   = path.join(OV_SERVER,  "Bootstrap.server.luau");
  if (isFile(bsOv)) addFile(serverRoot, "Bootstrap", bsOv);
  else if (isFile(bsBase)) addFile(serverRoot, "Bootstrap", bsBase);

  // Folder-backed registries
  overlaySection(serverRoot, "Services",       path.join(SRC_SERVER, "services"),     path.join(OV_SERVER, "services"));
  overlaySection(serverRoot, "Packages",       path.join(SRC_SERVER, "packages"),     path.join(OV_SERVER, "packages"));
  overlaySection(serverRoot, "GameDataMaster", path.join(GD_ROOT, "source"),          path.join(OV_SERVER, "game_data_master"));
  overlaySection(serverRoot, "Monetisation",   path.join(MON_ROOT, "source"),         path.join(OV_SERVER, "monetisation"));

  // Classes (server)
  overlaySection(serverRoot, "Classes",        path.join(SRC_SERVER, "classes"),      path.join(OV_SERVER, "classes"));
})();

// ====== Build: Client (base + overlay) ======
(function buildClient() {
  // Bootstrap (file can be overridden)
  const bcBase = path.join(SRC_CLIENT, "Bootstrap.client.luau");
  const bcOv   = path.join(OV_CLIENT,  "Bootstrap.client.luau");
  if (isFile(bcOv)) addFile(clientRoot, "Bootstrap", bcOv);
  else if (isFile(bcBase)) addFile(clientRoot, "Bootstrap", bcBase);

  // Sections: Controllers / Components / Utils (folder-backed or plain)
  overlaySection(clientRoot, "Controllers", path.join(SRC_CLIENT, "controllers"), path.join(OV_CLIENT, "controllers"));
  overlaySection(clientRoot, "Components",  path.join(SRC_CLIENT, "components"),  path.join(OV_CLIENT, "components"));
  overlaySection(clientRoot, "Utils",       path.join(SRC_CLIENT, "utils"),       path.join(OV_CLIENT, "utils"));
})();

// ====== Systems merge (applies to all places) ======
(function mergeSystems() {
  if (!isDir(SYS_ROOT)) return;

  // Ensure these nodes exist (respecting folder-back if base was mounted)
  overlaySection(clientRoot, "Controllers", path.join(SRC_CLIENT, "controllers"), path.join(OV_CLIENT, "controllers"));
  overlaySection(clientRoot, "Components",  path.join(SRC_CLIENT, "components"),  path.join(OV_CLIENT, "components"));
  overlaySection(clientRoot, "Utils",       path.join(SRC_CLIENT, "utils"),       path.join(OV_CLIENT, "utils"));
  overlaySection(serverRoot, "Services",    path.join(SRC_SERVER, "services"),    path.join(OV_SERVER, "services"));
  overlaySection(serverRoot, "Packages",    path.join(SRC_SERVER, "packages"),    path.join(OV_SERVER, "packages"));
  overlaySection(serverRoot, "Classes",     path.join(SRC_SERVER, "classes"),     path.join(OV_SERVER, "classes"));
  overlaySection(sharedRoot, "Classes",     path.join(SRC_SHARED, "classes"),     path.join(OV_SHARED, "classes"));

  const clientControllers = ensureFolder(clientRoot, "Controllers");
  const clientComponents  = ensureFolder(clientRoot, "Components");
  const clientUtils       = ensureFolder(clientRoot, "Utils");
  const sharedClasses     = ensureFolder(sharedRoot, "Classes");
  const serverClasses     = ensureFolder(serverRoot, "Classes");

  const assets = ensureFolder(sharedRoot, "Assets");
  const ui = ensureFolder(assets, "UI");
  const models = ensureFolder(assets, "Models");

  for (const sysName of fs.readdirSync(SYS_ROOT)) {
    const sysDir = path.join(SYS_ROOT, sysName);
    if (!isDir(sysDir)) continue;

    // client parts
    const cRoot = path.join(sysDir, "client");
    if (isDir(cRoot)) {
      mergeSystemLeaf(clientControllers, path.join(cRoot, "controllers"));
      mergeSystemLeaf(clientComponents,  path.join(cRoot, "components"));
      mergeSystemLeaf(clientUtils,       path.join(cRoot, "utils"));
    }

    // server parts
    const sRoot = path.join(sysDir, "server");
    if (isDir(sRoot)) {
      mergeSystemLeaf(ensureFolder(serverRoot, "Services"), path.join(sRoot, "services"));
      mergeSystemLeaf(ensureFolder(serverRoot, "Packages"), path.join(sRoot, "packages"));
      mergeSystemLeaf(serverClasses,                         path.join(sRoot, "classes"));
    }

    // shared parts
    const shRoot = path.join(sysDir, "shared");
    if (isDir(shRoot)) {
      mirrorAssets(ui,     path.join(shRoot, "assets", "ui"));
      mirrorAssets(models, path.join(shRoot, "assets", "models"));
      mergeSystemLeaf(ensureFolder(sharedRoot, "Config"), path.join(shRoot, "config"));
      mergeSystemLeaf(sharedClasses,                      path.join(shRoot, "classes"));
    }
  }
})();

// ====== Write project ======
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(OUT_PATH, JSON.stringify(project, null, 2));
console.log(`✅ Wrote ${toPosix(path.relative(process.cwd(), OUT_PATH))}`);
console.log(`   Base: src/*  Overlay: ${exists(OV_BASE) ? toPosix(path.relative(process.cwd(), OV_BASE)) : "(none)"}`);