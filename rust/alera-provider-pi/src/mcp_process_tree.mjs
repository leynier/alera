import { spawn, spawnSync } from "node:child_process";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";

const TERM_GRACE_MS = 500;
const REAP_TIMEOUT_MS = 1_000;
const START_TIMEOUT_MS = 120_000;
const SUPERVISOR = fileURLToPath(new URL("./mcp_stdio_supervisor.mjs", import.meta.url));
const TASKKILL = process.platform === "win32" ?
  join(process.env.SystemRoot ?? process.env.WINDIR ?? "C:\\Windows", "System32", "taskkill.exe") : "taskkill";

function pause(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function bounded(promise, timeout) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((resolve) => { timer = setTimeout(() => resolve(false), timeout); }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function signalGroup(pid, signal) {
  try {
    process.kill(-pid, signal);
    return true;
  } catch (error) {
    if (error.code === "ESRCH") return false;
    throw error;
  }
}

function taskkillArgs(pid) {
  return ["/PID", String(pid), "/T", "/F"];
}

function runtimeCommand() {
  if (!process.versions.bun || /^bun(?:\.exe)?$/i.test(basename(process.execPath))) return process.execPath;
  // A compiled Pi Bun executable cannot interpret a separate JavaScript file.
  return process.env.ALERA_PI_MCP_JS_RUNTIME ?? "node";
}

// The IPC-owning supervisor survives Pi's SIGKILL long enough to terminate
// its own server group when the channel disconnects.
export class McpProcessTree {
  constructor(spec) {
    this.child = spawn(runtimeCommand(), [SUPERVISOR], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe", "ipc"],
      serialization: "json",
      detached: process.platform !== "win32",
      windowsHide: true,
    });
    this.hasExited = false;
    this.exited = new Promise((resolve) => {
      this.child.once("exit", () => { this.hasExited = true; resolve(true); });
      this.child.once("error", () => { if (!this.child.pid) resolve(true); });
    });
    this.ready = new Promise((resolve, reject) => {
      let settled = false;
      const finish = (error) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (error) reject(error);
        else resolve();
      };
      const timer = setTimeout(() => finish(new Error("MCP supervisor startup timed out")), START_TIMEOUT_MS);
      this.child.on("message", (message) => {
        if (message?.type === "ready") finish();
        else if (message?.type === "failure") finish(new Error(message.message ?? "MCP server failed to start"));
        else if (message?.type === "server_exit") this.serverExitStatus = message;
      });
      this.child.once("error", finish);
      this.child.once("exit", () => finish(new Error("MCP supervisor exited before startup")));
      this.child.send({ type: "launch", spec }, (error) => { if (error) finish(error); });
    });
  }

  terminateNow() {
    const pid = this.child.pid;
    // A supervisor that exited has already killed its group. Never retain
    // authority over its numeric pid after the parent reaped it.
    if (!pid || this.hasExited) return;
    if (process.platform === "win32") {
      // Exit handlers cannot await a timer or an asynchronous subprocess.
      spawnSync(TASKKILL, taskkillArgs(pid), {
        windowsHide: true, stdio: "ignore", timeout: REAP_TIMEOUT_MS,
      });
    } else {
      signalGroup(pid, "SIGKILL");
    }
  }

  async close() {
    const pid = this.child.pid;
    if (this.hasExited) return;
    if (!pid) {
      await bounded(this.exited, REAP_TIMEOUT_MS);
      return;
    }
    if (process.platform === "win32") {
      const killer = spawn(TASKKILL, taskkillArgs(pid), {
        windowsHide: true, stdio: "ignore", timeout: REAP_TIMEOUT_MS,
      });
      const killed = await bounded(new Promise((resolve) => {
        killer.once("exit", resolve);
        killer.once("error", resolve);
      }), REAP_TIMEOUT_MS);
      if (killed === false) killer.kill("SIGKILL");
    } else {
      signalGroup(pid, "SIGTERM");
      const deadline = Date.now() + TERM_GRACE_MS;
      while (!this.hasExited && signalGroup(pid, 0) && Date.now() < deadline) await pause(25);
      // The leader may exit before a descendant that ignores SIGTERM.
      if (!this.hasExited) signalGroup(pid, "SIGKILL");
    }
    if (!await bounded(this.exited, REAP_TIMEOUT_MS)) {
      this.terminateNow();
      throw new Error("MCP server did not exit before the shutdown deadline");
    }
  }
}
