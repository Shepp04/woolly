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
const OUT_DIR    = REPO_ROOT;
const OUT_PATH   = path.join(REPO_ROOT, `${PLACE}.project.json`);
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

function setFileNode(parent, nodeName, absPath, className /* optional */) {
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

  // If the directory itself is folder-backed, mount/replace whole node
  if (hasInit(leafAbs)) {
    const nodeName = toPascal(path.basename(leafAbs));
    // overlay wins: replace whatever is there
    addFolderModule(destParent, nodeName, leafAbs);
    return;
  }

  for (const entry of fs.readdirSync(leafAbs, { withFileTypes: true })) {
    const full = path.join(leafAbs, entry.name);
    if (entry.isDirectory()) {
      if (hasInit(full)) {
        const nodeName = toPascal(entry.name);
        // overlay wins: replace whatever is there
        addFolderModule(destParent, nodeName, full);
      } else {
        // plain folder -> recurse, creating the folder if needed
        const node = ensureFolder(destParent, toPascal(entry.name));
        mergeSystemLeaf(node, full);
      }
    } else if (entry.isFile() && LU(entry.name)) {
      const nodeName = stripExt(entry.name);
      // overlay wins: replace file node
      setFileNode(destParent, nodeName, full);
    } else if (entry.isFile() && isModelFile(entry.name)) {
      const nodeName = stripExt(entry.name);
      // overlay wins: replace asset node
      setFileNode(destParent, nodeName, full);
    }
  }
}

function mergeDataTypes(destObj, srcDir) {
  if (!isDir(srcDir)) return 0;
  let added = 0;

  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const full = path.join(srcDir, entry.name);
    if (entry.isDirectory()) {
      added += mergeDataTypes(destObj, full); // recurse
    } else if (entry.isFile() && LU(entry.name)) {
      const nodeName = stripExt(entry.name);
      setFileNode(destObj, nodeName, full); // overlay wins
      added++;
    }
  }
  return added;
}

function mergeFlatModules(destObj, srcDir) {
  if (!isDir(srcDir)) return 0;
  let added = 0;
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const full = path.join(srcDir, entry.name);
    if (entry.isDirectory()) {
      // allow nesting, but still flatten files into the same dest
      added += mergeFlatModules(destObj, full);
    } else if (entry.isFile() && LU(entry.name)) {
      const nodeName = stripExt(entry.name);
      setFileNode(destObj, nodeName, full); // overlay wins
      added++;
    }
  }
  return added;
}

// Helper: mount base, then overlay (overlay wins by name)
function overlaySection(parent, nodeName, baseAbs, overAbs) {
  const overlayIsFB = isDir(overAbs) && hasInit(overAbs);
  const baseIsFB    = isDir(baseAbs) && hasInit(baseAbs);

  if (overlayIsFB) {
    // Overlay provides a folder-backed module: replace entirely
    addFolderModule(parent, nodeName, overAbs);
    return;
  }

  // Otherwise, mount base (folder-backed or mirrored folder)
  if (baseIsFB) {
    addFolderModule(parent, nodeName, baseAbs);
  } else if (isDir(baseAbs)) {
    mirrorFolderAsModules(ensureFolder(parent, nodeName), baseAbs);
  }

  // Now merge overlay *files/folders* in, letting overlay replace conflicts
  if (isDir(overAbs)) {
    const target = ensureFolder(parent, nodeName);
    mergeSystemLeaf(target, overAbs);
  }
}

function mountExternalPackages(node /* ReplicatedStorage root */) {
  const PKG_DIR = path.join(REPO_ROOT, "Packages");
  if (!isDir(PKG_DIR)) return;

  node.ExternalPackages = {
    $className: "Folder",
    $path: relFromProject(PKG_DIR),
  };
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
  overlaySection(sharedRoot, "Packages",     path.join(SRC_SHARED, "packages"),      path.join(OV_SHARED, "packages"));
  overlaySection(sharedRoot, "Utils",        path.join(SRC_SHARED, "utils"),         path.join(OV_SHARED, "utils"));
  overlaySection(sharedRoot, "GameData",     path.join(GD_ROOT, "resolver"),         path.join(OV_SHARED, "game_data_resolver"));
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
  
  // --- Monetisation as a single ModuleScript + synthetic product_defs
  const monFileBase = path.join(MON_ROOT, "source", "Monetisation.luau");   // renamed from init.luau
  const monFileOv   = path.join(OV_SERVER, "monetisation", "Monetisation.luau");

  // Map the ModuleScript
  if (isFile(monFileOv)) {
    addFile(serverRoot, "Monetisation", monFileOv);
  } else if (isFile(monFileBase)) {
    addFile(serverRoot, "Monetisation", monFileBase);
  } else {
    // Back-compat fallback if someone still has folder-backed source
    overlaySection(
      serverRoot,
      "Monetisation",
      path.join(MON_ROOT, "source"),
      path.join(OV_SERVER, "monetisation")
    );
  }

  // Build ONE synthetic product_defs folder under Monetisation
  const monNode = serverRoot.Monetisation || ensureFolder(serverRoot, "Monetisation");
  const productDefsFolder = monNode.product_defs || (monNode.product_defs = { $className: "Folder" });

  // Base bucket for core product defs
  const baseBucket = ensureFolder(productDefsFolder, "Base");
  const BASE_PD_DIR = path.join(MON_ROOT, "source", "product_defs");
  const OV_BASE_PD_DIR = path.join(OV_SERVER, "monetisation", "product_defs");
  mergeFlatModules(baseBucket, BASE_PD_DIR);
  mergeFlatModules(baseBucket, OV_BASE_PD_DIR);

  // Keep Aggregator.luau mapped next to product_defs
  const pdFileBase = path.join(MON_ROOT, "source", "Aggregator.luau");
  const pdFileOv   = path.join(OV_SERVER, "monetisation", "Aggregator.luau");
  if (isFile(pdFileOv)) {
    addFile(monNode, "Aggregator", pdFileOv);
  } else if (isFile(pdFileBase)) {
    addFile(monNode, "Aggregator", pdFileBase);
  }

  // Classes (server)
  overlaySection(serverRoot, "Classes",        path.join(SRC_SERVER, "classes"),      path.join(OV_SERVER, "classes"));

  // --- New: map GameDataMaster as a single ModuleScript if present
  const gdmFileBase = path.join(GD_ROOT, "source", "GameDataMaster.luau");
  const gdmFileOv   = path.join(OV_SERVER, "game_data_master", "GameDataMaster.luau");

  if (isFile(gdmFileOv)) {
    addFile(serverRoot, "GameDataMaster", gdmFileOv);
  } else if (isFile(gdmFileBase)) {
    addFile(serverRoot, "GameDataMaster", gdmFileBase);
  } else {
    // fallback to old behavior if someone hasn't renamed the file yet
    overlaySection(serverRoot, "GameDataMaster",
      path.join(GD_ROOT, "source"),
      path.join(OV_SERVER, "game_data_master")
    );
  }

  // Always ensure an empty data_types folder exists under GameDataMaster
  const gdmNode = serverRoot.GameDataMaster || ensureFolder(serverRoot, "GameDataMaster");
  gdmNode.data_types = gdmNode.data_types || { $className: "Folder" };
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
  // Ensure these nodes exist (respecting folder-back if base was mounted)
  overlaySection(clientRoot, "Controllers", path.join(SRC_CLIENT, "controllers"), path.join(OV_CLIENT, "controllers"));
  overlaySection(clientRoot, "Components",  path.join(SRC_CLIENT, "components"),  path.join(OV_CLIENT, "components"));
  overlaySection(clientRoot, "Utils",       path.join(SRC_CLIENT, "utils"),       path.join(OV_CLIENT, "utils"));
  overlaySection(serverRoot, "Services",    path.join(SRC_SERVER, "services"),    path.join(OV_SERVER, "services"));
  overlaySection(serverRoot, "Packages",    path.join(SRC_SERVER, "packages"),    path.join(OV_SERVER, "packages"));
  overlaySection(serverRoot, "Classes",     path.join(SRC_SERVER, "classes"),     path.join(OV_SERVER, "classes"));
  overlaySection(sharedRoot, "Classes",     path.join(SRC_SHARED, "classes"),     path.join(OV_SHARED, "classes"));
  overlaySection(sharedRoot, "Utils",       path.join(SRC_SHARED, "utils"),       path.join(OV_SHARED, "utils"));

  const clientControllers = ensureFolder(clientRoot, "Controllers");
  const clientComponents  = ensureFolder(clientRoot, "Components");
  const clientUtils       = ensureFolder(clientRoot, "Utils");
  const sharedClasses     = ensureFolder(sharedRoot, "Classes");
  const serverClasses     = ensureFolder(serverRoot, "Classes");
  const sharedUtils       = ensureFolder(sharedRoot, "Utils");

  const assets = ensureFolder(sharedRoot, "Assets");
  const ui = ensureFolder(assets, "UI");
  const models = ensureFolder(assets, "Models");
  
  const gdm = serverRoot.GameDataMaster || ensureFolder(serverRoot, "GameDataMaster");
  const dtFolder = gdm.data_types || (gdm.data_types = { $className: "Folder" });

  const monNode = serverRoot.Monetisation || ensureFolder(serverRoot, "Monetisation");
  const productDefsFolder = monNode.product_defs || (monNode.product_defs = { $className: "Folder" });

  // Merge base repo data types (on disk: src/_game_data/source/data_types)
  const BASE_DT_DIR = path.join(GD_ROOT, "source", "data_types");
  mergeDataTypes(dtFolder, BASE_DT_DIR);

  // Helper function to merge a single system directory
  function mergeSystemDir(sysDir, sysName) {
    if (!isDir(sysDir)) return;

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
      mergeSystemLeaf(serverClasses,                        path.join(sRoot, "classes"));
    }

    // systems/<name>/data_types
    const dtRoot = path.join(sysDir, "data_types");
    if (isDir(dtRoot)) {
      mergeDataTypes(dtFolder, dtRoot);
    }

    // systems/<name>/monetisation
    // Ensure the same Monetisation.product_defs node exists (created in buildServer)
    const monNode = serverRoot.Monetisation || ensureFolder(serverRoot, "Monetisation");
    const productDefsFolder = monNode.product_defs || (monNode.product_defs = { $className: "Folder" });

    // Create a per-system subfolder to avoid filename collisions
    const sysBucket = ensureFolder(productDefsFolder, sysName);

    // systems/<Sys>/monetisation
    mergeFlatModules(sysBucket, path.join(sysDir, "monetisation"));

    // shared parts
    const shRoot = path.join(sysDir, "shared");
    if (isDir(shRoot)) {
      mirrorAssets(ui,     path.join(shRoot, "assets", "ui"));
      mirrorAssets(models, path.join(shRoot, "assets", "models"));
      mergeSystemLeaf(ensureFolder(sharedRoot, "Config"), path.join(shRoot, "config"));
      mergeSystemLeaf(sharedClasses,                      path.join(shRoot, "classes"));
      mergeSystemLeaf(sharedUtils,                       path.join(shRoot, "utils"));
    }
  }

  // Merge base systems from src/_systems/*
  if (isDir(SYS_ROOT)) {
    for (const sysName of fs.readdirSync(SYS_ROOT)) {
      const sysDir = path.join(SYS_ROOT, sysName);
      mergeSystemDir(sysDir, sysName);
    }
  }

  // Merge place-specific systems from place_overrides/<PLACE>/_systems/*
  const PLACE_SYS_ROOT = path.join(OV_BASE, "_systems");
  if (isDir(PLACE_SYS_ROOT)) {
    for (const sysName of fs.readdirSync(PLACE_SYS_ROOT)) {
      const sysDir = path.join(PLACE_SYS_ROOT, sysName);
      mergeSystemDir(sysDir, sysName);
    }
  }
})();

// ====== Write project ======
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(OUT_PATH, JSON.stringify(project, null, 2));
console.log(`✅ Wrote ${toPosix(path.relative(process.cwd(), OUT_PATH))}`);
console.log(`   Base: src/*  Overlay: ${exists(OV_BASE) ? toPosix(path.relative(process.cwd(), OV_BASE)) : "(none)"}`);