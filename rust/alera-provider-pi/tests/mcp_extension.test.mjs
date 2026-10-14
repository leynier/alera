import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execPath } from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { test } from "node:test";
import extension from "../src/mcp_extension.js";

const fixture = fileURLToPath(new URL("support/mcp_stdio_fixture.mjs", import.meta.url));
const host = fileURLToPath(new URL("support/mcp_extension_host.mjs", import.meta.url));
const extensionPath = fileURLToPath(new URL("../src/mcp_extension.js", import.meta.url));
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function eventually(action, timeout = 3_000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    try { return await action(); } catch (error) {
      if (Date.now() >= deadline) throw error;
      await pause(20);
    }
  }
}

async function running(pid) {
  try {
    process.kill(pid, 0);
    if (process.platform === "linux") {
      const status = await readFile(`/proc/${pid}/stat`, "utf8");
      return status.slice(status.lastIndexOf(")") + 2).split(" ")[0] !== "Z";
    }
    return true;
  } catch (error) {
    if (error.code === "ESRCH" || error.code === "ENOENT") return false;
    throw error;
  }
}

async function setup(mode = "paged", tree = false) {
  const directory = await mkdtemp(join(tmpdir(), "alera-pi-mcp-test-"));
  const path = join(directory, "servers.json");
  const records = join(directory, "records.jsonl");
  const specs = [{ name: "fixture", transport: "stdio", command: execPath, args: [fixture],
    env: { MCP_FIXTURE_DIRECTORY: directory, MCP_FIXTURE_MODE: mode,
      MCP_FIXTURE_TREE: tree ? "1" : "0", MCP_RECORD_FILE: records } }];
  await writeFile(path, JSON.stringify(specs));
  return { directory, path, records, specs };
}

async function fakePi(path) {
  const previous = process.env.ALERA_PI_MCP_SPEC_FILE;
  if (path === undefined) delete process.env.ALERA_PI_MCP_SPEC_FILE;
  else process.env.ALERA_PI_MCP_SPEC_FILE = path;
  const tools = [];
  const handlers = new Map();
  const warnings = [];
  const ctx = { ui: { notify(message) { warnings.push(message); } } };
  const pi = {
    on(name, handler) {
      const list = handlers.get(name) ?? [];
      list.push(handler);
      handlers.set(name, list);
    },
    registerTool(tool) { tools.push(tool); },
    getAllTools() { return tools; },
  };
  try { await extension(pi); } finally {
    if (previous === undefined) delete process.env.ALERA_PI_MCP_SPEC_FILE;
    else process.env.ALERA_PI_MCP_SPEC_FILE = previous;
  }
  const emit = async (name, event = {}, context = ctx) => {
    let result;
    for (const handler of handlers.get(name) ?? []) {
      const response = await handler(event, context);
      if (response) result = response;
      if (result?.block) break;
    }
    return result;
  };
  return { tools, handlers, warnings, emit,
    close: () => emit("session_shutdown", { reason: "quit" }) };
}

test("collects every tools/list page and preserves calls, schemas, errors, and cancellation ids", async () => {
  const fixture = await setup();
  const pi = await fakePi(fixture.path);
  try {
    assert.deepEqual(pi.tools.map((tool) => tool.name), ["chat_fixture_echo", "chat_fixture_second"]);
    assert.deepEqual(pi.tools[1].parameters.properties.text, { type: "string" });
    const result = await pi.tools[1].execute("call-1", { text: "hello", isError: true });
    assert.deepEqual(result.content, [{ type: "text", text: "hello" }]);
    assert.equal(result.isError, true);
    assert.deepEqual(result.details, { server: "fixture", tool: "second" });
    await assert.rejects(pi.tools[0].execute("error", { error: true }), /fixture tool failed/);
    const controller = new AbortController();
    const waiting = pi.tools[0].execute("call-2", { wait: true }, controller.signal);
    controller.abort();
    await assert.rejects(waiting, /cancelled/);
    const records = await eventually(async () => {
      const messages = (await readFile(fixture.records, "utf8")).trim().split("\n").map(JSON.parse);
      assert.ok(messages.some((message) => message.method === "notifications/cancelled"));
      return messages;
    });
    assert.deepEqual(records.filter((message) => message.method === "tools/list").map((message) => message.params), [{}, { cursor: "page-two" }]);
    const request = records.find((message) => message.method === "tools/call" && message.params.arguments.wait);
    const cancellation = records.find((message) => message.method === "notifications/cancelled");
    assert.equal(cancellation.params.requestId, request.id);
    assert.equal(typeof request.id, "number");
  } finally { await pi.close(); await rm(fixture.directory, { recursive: true, force: true }); }
});

test("supervisor preserves backpressure, the final response, and native exit codes", async () => {
  const fixture = await setup();
  const pi = await fakePi(fixture.path);
  try {
    const response = await pi.tools[0].execute("large", { bytes: 1_000_000, exitAfterReply: true });
    assert.equal(response.content[0].text.length, 1_000_000);
  } finally { await pi.close(); await rm(fixture.directory, { recursive: true, force: true }); }
  const second = await setup();
  const exited = await fakePi(second.path);
  try {
    await assert.rejects(exited.tools[0].execute("exit", { exit: true }), /exited \(23\)/);
  } finally { await exited.close(); await rm(second.directory, { recursive: true, force: true }); }
});

for (const [mode, message] of [["repeat-cursor", /repeated cursor/], ["duplicate-tool", /duplicate tool/],
  ["page-limit", /page limit/], ["tool-limit", /tool limit/], ["invalid-schema", /invalid tool schema/]]) {
  test(`rejects ${mode} without publishing partial tools or leaving a server`, async () => {
    const fixture = await setup(mode);
    const pi = await fakePi(fixture.path);
    try {
      await pi.emit("session_start");
      assert.equal(pi.tools.length, 0);
      assert.match(pi.warnings[0], message);
      const pid = Number(await readFile(join(fixture.directory, "server-pid"), "utf8"));
      assert.equal(await running(pid), false);
    } finally { await pi.close(); await rm(fixture.directory, { recursive: true, force: true }); }
  });
}

test("default approval gate remains loaded with zero servers and blocks declined or unavailable approval", async () => {
  const pi = await fakePi();
  try {
    for (const toolName of ["bash", "write", "edit", "external_tool"]) {
      let sideEffects = 0;
      const event = { toolName, input: { command: "a command", path: "file" } };
      const invoke = async (confirm) => {
        const result = await pi.emit("tool_call", event, { ui: { confirm } });
        if (!result?.block) sideEffects++;
        return result;
      };
      assert.equal((await invoke(async () => false)).block, true);
      assert.equal((await invoke(async () => undefined)).block, true);
      assert.equal((await invoke(async () => { throw new Error("unavailable"); })).block, true);
      assert.equal(sideEffects, 0);
      assert.equal(await invoke(async () => true), undefined);
      assert.equal(sideEffects, 1);
    }
    pi.tools.push({ name: "read", sourceInfo: { path: "builtin:read" } });
    assert.equal(await pi.emit("tool_call", { toolName: "read" }, { ui: {} }), undefined);
    pi.tools[0].sourceInfo.path = "external-extension";
    assert.equal((await pi.emit("tool_call", { toolName: "read" }, { ui: {} })).block, true);
  } finally { await pi.close(); }
});

test("cancel and extension shutdown block a pending approval", async () => {
  const pi = await fakePi();
  try {
    const controller = new AbortController();
    let dialogSignal;
    const ctx = { signal: controller.signal, ui: { confirm(_title, _input, options) {
      dialogSignal = options.signal;
      return new Promise(() => undefined);
    } } };
    const cancelled = pi.emit("tool_call", { toolName: "bash" }, ctx);
    controller.abort();
    assert.equal((await cancelled).block, true);
    assert.equal(dialogSignal.aborted, true);
    const pending = pi.emit("tool_call", { toolName: "write" }, { ui: ctx.ui });
    await pi.close();
    assert.equal((await pending).block, true);
    assert.equal(dialogSignal.aborted, true);
  } finally { await pi.close(); }
});

test("approval timeout blocks the tool and aborts the UI request", async (t) => {
  const pi = await fakePi();
  t.mock.timers.enable({ apis: ["setTimeout"] });
  let dialogSignal;
  try {
    const pending = pi.emit("tool_call", { toolName: "bash" }, { ui: {
      confirm(_title, _input, options) {
        assert.equal(options.timeout, 120_000);
        dialogSignal = options.signal;
        return new Promise(() => undefined);
      },
    } });
    t.mock.timers.tick(120_000);
    assert.equal((await pending).block, true);
    assert.equal(dialogSignal.aborted, true);
  } finally { t.mock.timers.reset(); await pi.close(); }
});

test("invalid MCP configuration cannot remove the default approval gate", async () => {
  const fixture = await setup();
  await writeFile(fixture.path, "invalid JSON");
  const pi = await fakePi(fixture.path);
  try {
    assert.equal((await pi.emit("tool_call", { toolName: "write" }, { ui: { confirm: async () => false } })).block, true);
    await pi.emit("session_start");
    assert.match(pi.warnings[0], /configuration unavailable/);
  } finally { await pi.close(); await rm(fixture.directory, { recursive: true, force: true }); }
});

test("awaited shutdown stops servers and descendants that ignore SIGTERM", async () => {
  const fixture = await setup("paged", true);
  const before = process.listenerCount("exit");
  const pi = await fakePi(fixture.path);
  try {
    const pids = await eventually(async () => Promise.all(["server-pid", "descendant-pid"].map(async (file) =>
      Number(await readFile(join(fixture.directory, file), "utf8")))));
    const waiting = pi.tools[0].execute("wait", { wait: true });
    const rejected = assert.rejects(waiting, /closed/);
    const start = Date.now();
    await pi.emit("session_shutdown", { reason: "reload" });
    await rejected;
    assert.ok(Date.now() - start < 2_000);
    for (const pid of pids) assert.equal(await running(pid), false);
    assert.equal(process.listenerCount("exit"), before);
    await pi.emit("session_start");
    assert.equal(pi.tools.length, 2);
  } finally { await pi.close(); await rm(fixture.directory, { recursive: true, force: true }); }
});

test("shutdown closes a server whose initialization is still pending", async () => {
  const fixture = await setup("hang-initialize", true);
  const previous = process.env.ALERA_PI_MCP_SPEC_FILE;
  process.env.ALERA_PI_MCP_SPEC_FILE = fixture.path;
  const handlers = new Map();
  const starting = extension({
    on(name, handler) { handlers.set(name, handler); },
    registerTool() { assert.fail("initializing server must not publish tools"); },
  });
  try {
    const pids = await eventually(async () => Promise.all(["server-pid", "descendant-pid"].map(async (file) =>
      Number(await readFile(join(fixture.directory, file), "utf8")))));
    await handlers.get("session_shutdown")({ reason: "reload" });
    await starting;
    for (const pid of pids) assert.equal(await running(pid), false);
  } finally {
    await handlers.get("session_shutdown")?.({ reason: "quit" });
    if (previous === undefined) delete process.env.ALERA_PI_MCP_SPEC_FILE;
    else process.env.ALERA_PI_MCP_SPEC_FILE = previous;
    await rm(fixture.directory, { recursive: true, force: true });
  }
});

test("reload cycles and synchronous process exit never leave MCP process trees alive", async () => {
  const fixture = await setup("paged", true);
  const child = spawn(execPath, [host], { env: { ...process.env, ALERA_PI_MCP_SPEC_FILE: fixture.path },
    stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
  let output = "";
  let errors = "";
  child.stdout.on("data", (chunk) => { output += chunk; });
  child.stderr.on("data", (chunk) => { errors += chunk; });
  const exited = new Promise((resolve) => child.once("exit", resolve));
  const allPids = new Set();
  try {
    await eventually(() => assert.match(output, /ready/));
    for (let cycle = 0; cycle < 3; cycle++) {
      const pids = await eventually(async () => Promise.all(["server-pid", "descendant-pid"].map(async (file) => {
        const pid = Number(await readFile(join(fixture.directory, file), "utf8"));
        assert.ok(!allPids.has(pid));
        assert.equal(await running(pid), true);
        return pid;
      })));
      for (const pid of pids) allPids.add(pid);
      if (cycle < 2) {
        output = "";
        child.stdin.write("reload\n");
        await eventually(() => assert.match(output, /reload/));
        for (const pid of pids) assert.equal(await running(pid), false);
      }
    }
    child.stdin.write("exit\n");
    assert.equal(await exited, 0, errors);
    for (const pid of allPids) await eventually(async () => assert.equal(await running(pid), false));
  } finally {
    if (child.exitCode === null) child.kill("SIGKILL");
    for (const pid of allPids) {
      if (await running(pid)) process.kill(pid, "SIGKILL");
    }
    await rm(fixture.directory, { recursive: true, force: true });
  }
});

async function abruptHostDeath(command, args, realPi = false) {
  const fixture = await setup("paged", true);
  const child = spawn(command, args, { cwd: fixture.directory,
    env: { ...process.env, ALERA_PI_MCP_SPEC_FILE: fixture.path, PI_CODING_AGENT_DIR: join(fixture.directory, "pi-home") },
    stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
  let output = "";
  let errors = "";
  child.stdout.on("data", (chunk) => { output += chunk; });
  child.stderr.on("data", (chunk) => { errors += chunk; });
  const exited = new Promise((resolve) => child.once("exit", (_code, signal) => resolve(signal)));
  let pids = [];
  try {
    if (realPi) child.stdin.write(JSON.stringify({ type: "get_state", id: "supervisor-test" }) + "\n");
    await eventually(() => assert.match(output, realPi ? /supervisor-test/ : /ready/, errors), 10_000);
    pids = await eventually(async () => Promise.all(["server-pid", "descendant-pid", "supervisor-pid"].map(async (file) => {
      const pid = Number(await readFile(join(fixture.directory, file), "utf8"));
      assert.equal(await running(pid), true);
      return pid;
    })));
    child.kill("SIGKILL");
    assert.equal(await exited, "SIGKILL", errors);
    for (const pid of pids) await eventually(async () => assert.equal(await running(pid), false));
  } finally {
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
    for (const pid of pids) if (await running(pid)) process.kill(pid, "SIGKILL");
    await rm(fixture.directory, { recursive: true, force: true });
  }
}

test("IPC disconnect stops every server process after the Node host is killed", async () => {
  await abruptHostDeath(execPath, [host]);
});

test("Bun host and supervisor IPC stop every server after abrupt host death", {
  skip: process.env.ALERA_PI_BUN_RUNTIME === undefined,
}, async () => {
  await abruptHostDeath(process.env.ALERA_PI_BUN_RUNTIME, [host]);
});

test("compiled Bun host uses an external JS runtime and retains abrupt-death cleanup", {
  skip: process.env.ALERA_PI_BUN_RUNTIME === undefined,
}, async () => {
  const directory = await mkdtemp(join(tmpdir(), "alera-pi-bun-host-"));
  const binary = join(directory, process.platform === "win32" ? "compiled-host.exe" : "compiled-host");
  const source = fileURLToPath(new URL("support/mcp_compiled_host.mjs", import.meta.url));
  const builder = spawn(process.env.ALERA_PI_BUN_RUNTIME, ["build", "--compile", source, "--outfile", binary], {
    stdio: ["ignore", "ignore", "pipe"], windowsHide: true, timeout: 30_000,
  });
  let errors = "";
  builder.stderr.on("data", (chunk) => { errors += chunk; });
  const previousHost = process.env.ALERA_PI_TEST_HOST_URL;
  const previousRuntime = process.env.ALERA_PI_MCP_JS_RUNTIME;
  try {
    const code = await new Promise((resolve, reject) => { builder.once("exit", resolve); builder.once("error", reject); });
    assert.equal(code, 0, errors);
    process.env.ALERA_PI_TEST_HOST_URL = pathToFileURL(host).href;
    process.env.ALERA_PI_MCP_JS_RUNTIME = execPath;
    await abruptHostDeath(binary, []);
  } finally {
    if (previousHost === undefined) delete process.env.ALERA_PI_TEST_HOST_URL;
    else process.env.ALERA_PI_TEST_HOST_URL = previousHost;
    if (previousRuntime === undefined) delete process.env.ALERA_PI_MCP_JS_RUNTIME;
    else process.env.ALERA_PI_MCP_JS_RUNTIME = previousRuntime;
    if (builder.exitCode === null && builder.signalCode === null) builder.kill("SIGKILL");
    await rm(directory, { recursive: true, force: true });
  }
});

test("SIGKILL of installed Pi RPC stops every owned MCP process without inference", {
  skip: process.env.ALERA_PI_CLI === undefined,
}, async () => {
  await abruptHostDeath(execPath, [process.env.ALERA_PI_CLI, "--mode", "rpc", "--no-session",
    "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes", "--extension", extensionPath], true);
});

test("installed Pi public factory loader accepts permission and MCP hooks without inference", {
  skip: process.env.ALERA_PI_EXTENSION_LOADER === undefined,
}, async () => {
  const fixture = await setup();
  const { createExtensionRuntime, loadExtensionFromFactory } = await import(process.env.ALERA_PI_EXTENSION_LOADER);
  const previous = process.env.ALERA_PI_MCP_SPEC_FILE;
  process.env.ALERA_PI_MCP_SPEC_FILE = fixture.path;
  const runtime = createExtensionRuntime();
  const loaded = await loadExtensionFromFactory(extension, fixture.directory,
    { emit() {}, on() { return () => undefined; } }, runtime);
  if (previous === undefined) delete process.env.ALERA_PI_MCP_SPEC_FILE;
  else process.env.ALERA_PI_MCP_SPEC_FILE = previous;
  const ctx = { ui: { confirm: async () => false, notify() {} } };
  try {
    assert.equal(loaded.tools.size, 2);
    const tool = loaded.tools.get("chat_fixture_second").definition;
    assert.deepEqual((await tool.execute("real-loader", { text: "real Pi" })).content, [{ type: "text", text: "real Pi" }]);
    const gate = loaded.handlers.get("tool_call")[0];
    for (const toolName of ["bash", "edit", "write"]) assert.equal((await gate({ toolName }, ctx)).block, true);
    assert.equal(await gate({ toolName: "write" }, { ui: { confirm: async () => true } }), undefined);
    const loaderUrl = process.env.ALERA_PI_EXTENSION_LOADER.startsWith("file:") ?
      new URL(process.env.ALERA_PI_EXTENSION_LOADER) : pathToFileURL(process.env.ALERA_PI_EXTENSION_LOADER);
    const { createWriteToolDefinition } = await import(new URL("../tools/write.js", loaderUrl));
    const write = createWriteToolDefinition(fixture.directory);
    const written = join(fixture.directory, "approved.txt");
    const input = { path: written, content: "accepted" };
    const invoke = async (accepted) => {
      const result = await gate({ toolName: "write", input }, { ui: { confirm: async () => accepted } });
      if (!result?.block) await write.execute("write", input);
    };
    await invoke(false);
    await assert.rejects(readFile(written), { code: "ENOENT" });
    await invoke(undefined);
    await assert.rejects(readFile(written), { code: "ENOENT" });
    await invoke(true);
    assert.equal(await readFile(written, "utf8"), "accepted");
  } finally {
    for (const handler of loaded.handlers.get("session_shutdown")) await handler({ reason: "reload" }, ctx);
    await rm(fixture.directory, { recursive: true, force: true });
  }
});
