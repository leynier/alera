import { spawn, spawnSync } from "node:child_process";
import { join } from "node:path";

const TASKKILL = process.platform === "win32" ?
  join(process.env.SystemRoot ?? process.env.WINDIR ?? "C:\\Windows", "System32", "taskkill.exe") : "taskkill";
let child;
let launched = false;
let stopping = false;

function stopTree() {
  if (stopping) return;
  stopping = true;
  if (process.platform === "win32") {
    spawnSync(TASKKILL, ["/PID", String(process.pid), "/T", "/F"], {
      windowsHide: true, stdio: "ignore", timeout: 1_000,
    });
    child?.kill("SIGKILL");
    process.exit(1);
  } else {
    // This still-running session leader owns the group, so its id cannot be reused.
    process.kill(-process.pid, "SIGKILL");
  }
}

function reportAndStop(message) {
  if (!process.connected) return stopTree();
  const timer = setTimeout(stopTree, 1_000);
  process.send(message, () => { clearTimeout(timer); stopTree(); });
}

function flushed(stream) {
  if (stream.writableFinished) return Promise.resolve();
  return new Promise((resolve) => {
    const finish = () => { clearTimeout(timer); stream.removeListener("finish", finish); resolve(); };
    const timer = setTimeout(finish, 1_000);
    stream.once("finish", finish);
  });
}

process.on("disconnect", stopTree);
// A group SIGTERM reaches the server too. Keep its supervisor alive until the
// server exits or the parent's bounded SIGKILL escalation reaches the group.
process.on("SIGTERM", () => undefined);
process.once("exit", stopTree);
process.on("message", (message) => {
  if (launched || message?.type !== "launch") return;
  launched = true;
  const spec = message.spec;
  try {
    child = spawn(spec.command, spec.args ?? [], {
      cwd: spec.cwd ?? undefined,
      env: { ...process.env, ...(spec.env ?? {}) },
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
    });
    process.stdin.pipe(child.stdin);
    child.stdout.pipe(process.stdout);
    child.stderr.pipe(process.stderr);
    child.stdin.on("error", () => undefined);
    child.once("spawn", () => {
      if (!process.connected) return stopTree();
      process.send({ type: "ready" }, (error) => { if (error) stopTree(); });
    });
    child.once("error", (error) => reportAndStop({ type: "failure", message: error.message }));
    child.once("exit", (code, signal) => {
      if (process.connected) process.send({ type: "server_exit", code, signal }, () => undefined);
    });
    child.once("close", async (code, signal) => {
      await Promise.all([flushed(process.stdout), flushed(process.stderr)]);
      reportAndStop({ type: "server_exit", code, signal });
    });
  } catch (error) {
    reportAndStop({ type: "failure", message: error.message });
  }
});
if (!process.connected) stopTree();
