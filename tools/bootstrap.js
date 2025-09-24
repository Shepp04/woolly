#!/usr/bin/env node
/* bootstrap project: install deps, generate project, build, then serve */
const { spawn } = require("child_process");
const path = require("path");

const STEPS = [
  { cmd: "wally", args: ["install"],        when: () => true },
  { cmd: "rokit", args: ["install"],        when: () => true }, // harmless if no rokit.toml
  { cmd: "node",  args: ["tools/genRojoTree.js"], when: () => true },
  // rojo init is *not* needed if you generate default.project.json yourself
  { cmd: "rojo",  args: ["build", "-o", "build.rbxlx"], when: () => true },
  { cmd: "rojo",  args: ["serve"],          when: () => true }, // blocks; runs last
];

function runStep(i = 0) {
  if (i >= STEPS.length) return;
  const { cmd, args } = STEPS[i];
  const child = spawn(cmd, args, { stdio: "inherit", cwd: path.resolve(__dirname, "..") });
  child.on("exit", (code) => {
    if (code !== 0) process.exit(code);
    runStep(i + 1);
  });
}

runStep();