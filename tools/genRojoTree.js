/* eslint-disable */
const fs = require("fs");
const path = require("path");

const BASE_PATH = path.join(__dirname, "../src");
const SRC_SHARED = path.join(BASE_PATH, "shared");
const SRC_SERVER = path.join(BASE_PATH, "server");
const SRC_CLIENT = path.join(BASE_PATH, "client");

const BLACKLISTED_DIRS = []; // add any absolute POSIX paths here if needed
const initClaimedFolders = new Set(); // folders claimed by init.luau

const toPosix = (p) => p.split(path.sep).join("/");
const exists = (p) => fs.existsSync(p);
const isDir = (p) => exists(p) && fs.statSync(p).isDirectory();
const isFile = (p) => exists(p) && fs.statSync(p).isFile();

function ensureFolderNode(parent, key) {
  if (!parent[key]) parent[key] = { $className: "Folder" };
  return parent[key];
}

function addFileNode(parent, name, filePath, className /* optional */) {
  if (className) {
    parent[name] = { $className: className, $path: toPosix(filePath) };
  } else {
    parent[name] = { $path: toPosix(filePath) }; // Rojo infers ModuleScript
  }
}

function toPascalCase(s) {
  if (!s) return s;
  return s
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join("");
}

function walk(dir, cb) {
  const posixDir = toPosix(dir);
  if (BLACKLISTED_DIRS.includes(posixDir)) return;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, cb);
    } else if (entry.isFile() && (entry.name.endsWith(".luau") || entry.name.endsWith(".lua"))) {
      cb(full);
    }
  }
}

// -------------------- Desired static skeleton --------------------

const tree = {
  name: "farlands",
  tree: {
    $className: "DataModel",

    ReplicatedStorage: {
      Shared: {
        $className: "Folder",
        // We'll inject:
        //  - Packages (ModuleScript + children)
        //  - GameData (ModuleScript)
        //  - Types (ModuleScript)
        //  - Config (ModuleScript)
      },
      Packages: { $path: "Packages" } // Wally/vendor only
    },

    ServerScriptService: {
      Server: {
        $className: "Folder",
        // We'll inject:
        //  - Bootstrap (Script)
        //  - Services (ModuleScript + children)
        //  - Packages (ModuleScript + children)
        //  - GameDataMaster (ModuleScript)
        //  - DataTypes (Folder) + children
      }
    },

    StarterPlayer: {
      StarterPlayerScripts: {
        Client: {
          $className: "Folder",
          Controllers: { $className: "Folder" },
          Components: { $className: "Folder" },
          Utils: { $className: "Folder" }
          // We'll inject:
          //  - Bootstrap (LocalScript)
          //  - Controllers/*  (ModuleScripts)
          //  - Components/*   (ModuleScripts)
          //  - Utils/*        (ModuleScripts)
        }
      }
    }
  }
};

const sharedRoot = tree.tree.ReplicatedStorage.Shared;
const serverRoot = tree.tree.ServerScriptService.Server;
const clientRoot = tree.tree.StarterPlayer.StarterPlayerScripts.Client;
const clientControllersRoot = clientRoot.Controllers;
const clientComponentsRoot = clientRoot.Components;
const clientUtilsRoot = clientRoot.Utils;

// -------------------- Helpers for special “registry ModuleScript with children” --------------------

function mountRegistryModule(registryFileAbs, childrenDirAbs, destParent, nodeName) {
  if (!isFile(registryFileAbs)) return;
  // Create the registry module with children under it
  destParent[nodeName] = { $className: "ModuleScript", $path: toPosix(registryFileAbs) };
  const dest = destParent[nodeName];

  if (isDir(childrenDirAbs)) {
    for (const entry of fs.readdirSync(childrenDirAbs, { withFileTypes: true })) {
      if (!entry.isFile()) continue;
      if (!(entry.name.endsWith(".luau") || entry.name.endsWith(".lua"))) continue;
      const childName = path.basename(entry.name).replace(/\.(luau|lua)$/, "");
      const childPath = path.join(childrenDirAbs, entry.name);
      // Child modules appear as ModuleScripts under the registry ModuleScript
      addFileNode(dest, childName, childPath);
    }
  }
}

// -------------------- 1) Shared --------------------

(function buildShared() {
  // Packages.luau (registry) + children: src/shared/Packages/*
  mountRegistryModule(
    path.join(SRC_SHARED, "Packages.luau"),
    path.join(SRC_SHARED, "Packages"),
    sharedRoot,
    "Packages"
  );

  // GameData.luau / Types.luau / Config.luau (plain ModuleScripts)
  const sharedSingles = ["GameData", "Types", "Config"];
  for (const base of sharedSingles) {
    const f = path.join(SRC_SHARED, `${base}.luau`);
    if (isFile(f)) addFileNode(sharedRoot, base, f);
  }
})();

// -------------------- 2) Server --------------------

(function buildServer() {
  // Bootstrap.server.luau → Script
  const bootstrap = path.join(SRC_SERVER, "Bootstrap.server.luau");
  if (isFile(bootstrap)) addFileNode(serverRoot, "Bootstrap", bootstrap, "Script");

  // Services.luau (registry) + children in src/server/Services/*
  mountRegistryModule(
    path.join(SRC_SERVER, "Services.luau"),
    path.join(SRC_SERVER, "Services"),
    serverRoot,
    "Services"
  );

  // Packages.luau (registry) + children in src/server/Packages/*
  mountRegistryModule(
    path.join(SRC_SERVER, "Packages.luau"),
    path.join(SRC_SERVER, "Packages"),
    serverRoot,
    "Packages"
  );

  // GameDataMaster.luau
  const gdm = path.join(SRC_SERVER, "GameDataMaster.luau");
  if (isFile(gdm)) addFileNode(serverRoot, "GameDataMaster", gdm);

  // DataTypes folder and any ModuleScripts inside it
  const dataTypesDir = path.join(SRC_SERVER, "DataTypes");
  if (isDir(dataTypesDir)) {
    const dataTypesNode = ensureFolderNode(serverRoot, "DataTypes");
    for (const entry of fs.readdirSync(dataTypesDir, { withFileTypes: true })) {
      if (!entry.isFile()) continue;
      if (!(entry.name.endsWith(".luau") || entry.name.endsWith(".lua"))) continue;
      const name = path.basename(entry.name).replace(/\.(luau|lua)$/, "");
      addFileNode(dataTypesNode, name, path.join(dataTypesDir, entry.name));
    }
  }
})();

// -------------------- 3) Client --------------------

(function buildClient() {
  // Bootstrap.client.luau → LocalScript
  const bootstrap = path.join(SRC_CLIENT, "Bootstrap.client.luau");
  if (isFile(bootstrap)) addFileNode(clientRoot, "Bootstrap", bootstrap, "LocalScript");

  // Controllers / Components / Utils : recursive map of modules (with init.luau claiming)
  const mapLeafDir = (absDir, destParent) => {
    if (!isDir(absDir)) return;

    const walkStack = [absDir];
    while (walkStack.length) {
      const cur = walkStack.pop();
      for (const entry of fs.readdirSync(cur, { withFileTypes: true })) {
        const full = path.join(cur, entry.name);
        if (entry.isDirectory()) {
          walkStack.push(full);
          continue;
        }
        if (!(entry.isFile() && (entry.name.endsWith(".luau") || entry.name.endsWith(".lua")))) continue;

        const relFromRoot = path.relative(absDir, full); // relative to Controllers/Components/Utils root
        const relParts = relFromRoot.split(path.sep);
        const filename = path.basename(entry.name).replace(/\.(luau|lua)$/, "");
        const parentParts = relParts.slice(0, -1);

        // init.luau promotion
        if (filename === "init") {
          const claimKey = toPosix(path.join(absDir, ...parentParts)); // absolute
          if (claimKey) initClaimedFolders.add(claimKey);
          // create folder nodes in dest
          let node = destParent;
          for (const p of parentParts) node = ensureFolderNode(node, toPascalCase(p));
          // mount the folder (not the file)
          addFileNode(node, toPascalCase(path.basename(path.dirname(full))), path.join(absDir, ...parentParts));
          continue;
        }

        // skip if this file is inside a claimed folder
        const folderAbs = toPosix(path.join(absDir, ...parentParts));
        if (initClaimedFolders.has(folderAbs)) continue;

        // create path and file node
        let node = destParent;
        for (const p of parentParts) node = ensureFolderNode(node, toPascalCase(p));
        addFileNode(node, filename, full);
      }
    }
  };

  mapLeafDir(path.join(SRC_CLIENT, "Controllers"), clientControllersRoot);
  mapLeafDir(path.join(SRC_CLIENT, "Components"), clientComponentsRoot);
  mapLeafDir(path.join(SRC_CLIENT, "Utils"), clientUtilsRoot);
})();

// -------------------- Write file --------------------
fs.writeFileSync("default.project.json", JSON.stringify(tree, null, 2));
console.log("✅ default.project.json generated.");