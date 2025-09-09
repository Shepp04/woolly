/* eslint-disable */
const fs = require("fs");
const path = require("path");

// ==== Paths ====
const BASE = path.join(__dirname, "../src");
const SRC_SHARED = path.join(BASE, "shared");
const SRC_SERVER = path.join(BASE, "server");
const SRC_CLIENT = path.join(BASE, "client");

const SYS_ROOT  = path.join(BASE, "_systems");
const GD_ROOT   = path.join(BASE, "_game_data");
const MON_ROOT  = path.join(BASE, "_monetisation");
const TYPES_ROOT= path.join(BASE, "_types");

// ==== Utils ====
const toPosix = (p) => p.split(path.sep).join("/");
const exists  = (p) => fs.existsSync(p);
const stat    = (p) => exists(p) ? fs.statSync(p) : null;
const isDir   = (p) => !!(stat(p) && stat(p).isDirectory());
const isFile  = (p) => !!(stat(p) && stat(p).isFile());
const hasInitFile = (dir) =>
  isFile(path.join(dir, "init.luau")) || isFile(path.join(dir, "init.lua"));

const LU = (name) => name.endsWith(".luau") || name.endsWith(".lua");
const stripExt = (n) => n.replace(/\.(luau|lua|rbxm|rbxmx)$/i, "");
const toPascal = (s) => {
  // Keep all-caps words as-is (UX, UI, ID)
  if (/^[A-Z0-9_]+$/.test(s)) return s;
  return s
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map(w => w[0].toUpperCase() + w.slice(1))
    .join("");
};

const isModelFile = (name) => name.endsWith(".rbxm") || name.endsWith(".rbxmx");

// Ensure & get folder node
function ensureFolder(parent, key) {
  if (!parent[key]) parent[key] = { $className: "Folder" };
  return parent[key];
}

// Add file node; className optional (Script / LocalScript)
function addFile(parent, nodeName, absPath, className /* optional */) {
  const rel = toPosix(path.relative(process.cwd(), absPath));
  if (className) {
    parent[nodeName] = { $className: className, $path: rel };
  } else {
    parent[nodeName] = { $path: rel }; // ModuleScript inferred for .lua/.luau; models mapped as Models
  }
}

// Add a folder-backed ModuleScript node (directory must contain init.luau or init.lua)
function addFolderModule(parent, nodeName, absDir) {
  const hasInit = isFile(path.join(absDir, "init.luau")) || isFile(path.join(absDir, "init.lua"));
  if (!hasInit) return; // must contain init

  const relDir = toPosix(path.relative(process.cwd(), absDir));
  parent[nodeName] = { $path: relDir }; // Rojo infers ModuleScript; allows children
}

// Copy all .lua/.luau (recursively) from `srcDir` into `destParent` (creating PascalCase folders)
function mirrorFolderAsModules(destParent, srcDir) {
  if (!isDir(srcDir)) return;

  // If this directory itself is a folder-backed module, mount it and stop
  if (hasInitFile(srcDir)) {
    const nodeName = toPascal(path.basename(srcDir));
    addFolderModule(destParent, nodeName, srcDir);
    return;
  }

  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const full = path.join(srcDir, entry.name);
    if (entry.isDirectory()) {
      if (hasInitFile(full)) {
        // Child folder is a folder-backed module
        const nodeName = toPascal(entry.name);
        addFolderModule(destParent, nodeName, full);
      } else {
        // Plain folder: recurse and mirror plain ModuleScripts inside
        const node = ensureFolder(destParent, toPascal(entry.name));
        mirrorFolderAsModules(node, full);
      }
    } else if (entry.isFile() && LU(entry.name)) {
      addFile(destParent, stripExt(entry.name), full);
    }
  }
}

// NEW: Copy all .rbxm/.rbxmx (recursively) from `srcDir` into `destParent`
function mirrorAssets(destParent, srcDir) {
  if (!isDir(srcDir)) return;
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const full = path.join(srcDir, entry.name);
    if (entry.isDirectory()) {
      const node = ensureFolder(destParent, toPascal(entry.name));
      mirrorAssets(node, full);
    } else if (entry.isFile() && isModelFile(entry.name)) {
      const nodeName = stripExt(entry.name);
      if (destParent[nodeName]) {
        throw new Error(`[gen] Asset name collision: ${nodeName} already exists in destination`);
      }
      addFile(destParent, nodeName, full);
    }
  }
}

// Merge a system leaf folder (controllers/components/utils/services/packages/config) into a dest folderish node
// Flat merge by names; errors on collisions.
function mergeSystemLeaf(destParent, leafAbs) {
  if (!isDir(leafAbs)) return;

  // If this directory itself is a folder-backed module, mount it and stop
  if (hasInitFile(leafAbs)) {
    const nodeName = toPascal(path.basename(leafAbs));
    if (destParent[nodeName]) {
      throw new Error(`[gen] Name collision while merging systems: ${nodeName} already exists in destination`);
    }
    addFolderModule(destParent, nodeName, leafAbs);
    return;
  }

  for (const entry of fs.readdirSync(leafAbs, { withFileTypes: true })) {
    const full = path.join(leafAbs, entry.name);
    if (entry.isDirectory()) {
      if (hasInitFile(full)) {
        const nodeName = toPascal(entry.name);
        if (destParent[nodeName]) {
          throw new Error(`[gen] Name collision while merging systems: ${nodeName} already exists in destination`);
        }
        addFolderModule(destParent, nodeName, full);
      } else {
        const node = ensureFolder(destParent, toPascal(entry.name));
        mergeSystemLeaf(node, full);
      }
    } else if (entry.isFile() && LU(entry.name)) {
      const nodeName = stripExt(entry.name);
      if (destParent[nodeName]) {
        throw new Error(`[gen] Name collision while merging systems: ${nodeName} already exists in destination`);
      }
      addFile(destParent, nodeName, full);
    }
  }
}

// ==== Base skeleton ====
const tree = {
  name: "woolly",
  tree: {
    $className: "DataModel",

    ReplicatedStorage: {
      Shared: {
        $className: "Folder",
      },
    //  ExternalPackages/Wally: map if you need it here instead
      ExternalPackages: { $path: "Packages" }
    },

    ServerScriptService: {
      Server: {
        $className: "Folder",
      }
    },

    StarterPlayer: {
      StarterPlayerScripts: {
        Client: {
          $className: "Folder",
          Controllers: { $className: "Folder" },
          Components:  { $className: "Folder" },
          Utils:       { $className: "Folder" },
        }
      }
    }
  }
};

const sharedRoot = tree.tree.ReplicatedStorage.Shared;
const serverRoot = tree.tree.ServerScriptService.Server;
const clientRoot = tree.tree.StarterPlayer.StarterPlayerScripts.Client;
const clientControllers = clientRoot.Controllers;
const clientComponents  = clientRoot.Components;
const clientUtils       = clientRoot.Utils;

// ==== 1) Core shared ====
(function buildShared() {
  // Shared/Packages (folder-backed ModuleScript) ← src/shared/packages/
  addFolderModule(sharedRoot, "Packages", path.join(SRC_SHARED, "packages"));

  // Shared/GameData (folder-backed) ← src/_game_data/resolver/
  addFolderModule(sharedRoot, "GameData", path.join(GD_ROOT, "resolver"));

  // Shared/Types (folder-backed) ← src/_types/
  addFolderModule(sharedRoot, "Types", TYPES_ROOT);

  // Shared/Config (folder-backed) ← src/shared/config/
  addFolderModule(sharedRoot, "Config", path.join(SRC_SHARED, "config"));

  // Shared/Monetisation (folder-backed) ← src/_monetisation/resolver/
  addFolderModule(sharedRoot, "Monetisation", path.join(MON_ROOT, "resolver"));

  // Shared/Assets/UI + Models
  const assetsFolder = ensureFolder(sharedRoot, "Assets");
  const assetsUI = ensureFolder(assetsFolder, "UI");
  const assetsModels = ensureFolder(assetsFolder, "Models");

  mirrorAssets(assetsUI,     path.join(SRC_SHARED, "assets", "ui"));
  mirrorAssets(assetsModels, path.join(SRC_SHARED, "assets", "models"));
})();

// ==== 2) Core server ====
(function buildServer() {
  const bootSrv = path.join(SRC_SERVER, "Bootstrap.server.luau");
  if (isFile(bootSrv)) addFile(serverRoot, "Bootstrap", bootSrv);

  addFolderModule(serverRoot, "Services", path.join(SRC_SERVER, "services"));
  addFolderModule(serverRoot, "Packages", path.join(SRC_SERVER, "packages"));
  addFolderModule(serverRoot, "GameDataMaster", path.join(GD_ROOT, "source"));
  addFolderModule(serverRoot, "Monetisation", path.join(MON_ROOT, "source"));
})();

// ==== 3) Core client ====
(function buildClient() {
  const bootCli = path.join(SRC_CLIENT, "Bootstrap.client.luau");
  if (isFile(bootCli)) addFile(clientRoot, "Bootstrap", bootCli);

  mirrorFolderAsModules(clientControllers, path.join(SRC_CLIENT, "controllers"));
  mirrorFolderAsModules(clientComponents,  path.join(SRC_CLIENT, "components"));
  mirrorFolderAsModules(clientUtils,       path.join(SRC_CLIENT, "utils"));
})();

// ==== 4) Systems merge ====
(function mergeSystems() {
  if (!isDir(SYS_ROOT)) return;

  // Prepare shared assets nodes once
  const assetsFolder = ensureFolder(sharedRoot, "Assets");
  const assetsUI = ensureFolder(assetsFolder, "UI");
  const assetsModels = ensureFolder(assetsFolder, "Models");

  for (const sysName of fs.readdirSync(SYS_ROOT)) {
    const sysDir = path.join(SYS_ROOT, sysName);
    if (!isDir(sysDir)) continue;

    // client
    const cRoot = path.join(sysDir, "client");
    if (isDir(cRoot)) {
      mergeSystemLeaf(clientControllers, path.join(cRoot, "controllers"));
      mergeSystemLeaf(clientComponents,  path.join(cRoot, "components"));
      mergeSystemLeaf(clientUtils,       path.join(cRoot, "utils"));
    }

    // server
    const sRoot = path.join(sysDir, "server");
    if (isDir(sRoot)) {
      if (!serverRoot.Services) addFolderModule(serverRoot, "Services", path.join(SRC_SERVER, "services"));
      if (serverRoot.Services)  mergeSystemLeaf(serverRoot.Services, path.join(sRoot, "services"));

      if (!serverRoot.Packages) addFolderModule(serverRoot, "Packages", path.join(SRC_SERVER, "packages"));
      if (serverRoot.Packages)  mergeSystemLeaf(serverRoot.Packages, path.join(sRoot, "packages"));
    }

    // shared assets/config under systems
    const shRoot = path.join(sysDir, "shared");
    if (isDir(shRoot)) {
      // Merge UI/models from systems into Shared/Assets children
      mirrorAssets(assetsUI,     path.join(shRoot, "assets", "ui"));
      mirrorAssets(assetsModels, path.join(shRoot, "assets", "models"));

      // Merge Config under Shared.Config (folder-backed ModuleScript)
      if (!sharedRoot.Config) addFolderModule(sharedRoot, "Config", path.join(SRC_SHARED, "config"));
      if (sharedRoot.Config)  mergeSystemLeaf(sharedRoot.Config, path.join(shRoot, "config"));
    }
  }
})();

// ==== Write project ====
fs.writeFileSync("default.project.json", JSON.stringify(tree, null, 2));
console.log("✅ default.project.json generated.");