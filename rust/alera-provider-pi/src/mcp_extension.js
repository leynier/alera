import { readFile } from "node:fs/promises";
import { McpProcessTree } from "./mcp_process_tree.mjs";
import { registerPermissionGate } from "./permission_extension.mjs";
import { registerSkillMentions } from "./skill_mentions_extension.mjs";

const PROTOCOL_VERSION = "2025-06-18";
const SPEC_FILE_ENV = "ALERA_PI_MCP_SPEC_FILE";
const MAX_FRAME_BYTES = 4 * 1024 * 1024;
const REQUEST_TIMEOUT_MS = 120_000;
const MAX_TOOL_PAGES = 256;
const MAX_TOOLS = 10_000;

function idKey(id) {
  return `${typeof id}:${JSON.stringify(id)}`;
}

function safePart(value) {
  const safe = String(value).replace(/[^A-Za-z0-9_.-]+/g, "_").replace(/^_+|_+$/g, "");
  return safe || "server";
}

function schema(value) {
  return value ?? { type: "object", properties: {}, additionalProperties: true };
}

function closeStream(stream) {
  if (!stream || stream.closed) return Promise.resolve();
  return new Promise((resolve) => {
    const finish = () => { clearTimeout(timer); stream.removeListener("close", finish); resolve(); };
    const timer = setTimeout(finish, 1_000);
    stream.once("close", finish);
    stream.destroy();
  });
}

function content(result) {
  if (result === null || result === undefined) return [];
  if (typeof result !== "object") return [{ type: "text", text: String(result) }];
  const blocks = [];
  for (const block of Array.isArray(result.content) ? result.content : []) {
    if (block?.type === "text" && typeof block.text === "string") {
      blocks.push({ type: "text", text: block.text });
    } else if (
      block?.type === "image" &&
      typeof block.data === "string" &&
      typeof block.mimeType === "string"
    ) {
      blocks.push({ type: "image", data: block.data, mimeType: block.mimeType });
    }
  }
  if (blocks.length === 0) {
    blocks.push({ type: "text", text: JSON.stringify(result.structuredContent ?? result) });
  }
  return blocks;
}

class StdioClient {
  constructor(spec) {
    this.spec = spec;
    this.child = undefined;
    this.buffer = "";
    this.nextId = 1;
    this.pending = new Map();
    this.writers = new Set();
    this.closed = false;
  }

  async connect() {
    const spec = this.spec;
    if (this.closed) throw new Error("MCP server is closed");
    this.tree = new McpProcessTree(spec);
    this.child = this.tree.child;
    this.child.stdout.setEncoding("utf8");
    this.child.stdin.on("error", (error) => this.failAll(error));
    this.child.stderr.on("data", () => undefined);
    this.child.stdout.on("data", (chunk) => this.read(String(chunk)));
    this.child.on("error", (error) => this.failAll(error));
    this.child.on("exit", (code, signal) => {
      const status = this.tree.serverExitStatus;
      if (!this.closed) this.failAll(new Error(`MCP server exited (${status?.code ?? status?.signal ?? code ?? signal ?? "unknown"})`));
    });
    await this.tree.ready;
    await this.request("initialize", {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {},
      clientInfo: { name: "alera-pi-mcp", version: "0.1.0" },
    });
    await this.notify("notifications/initialized", {});
  }

  read(chunk) {
    if (this.closed) return;
    this.buffer += chunk;
    if (this.buffer.length > MAX_FRAME_BYTES) {
      this.failAll(new Error("MCP server frame exceeds the size limit"));
      void this.close().catch(() => undefined);
      return;
    }
    for (;;) {
      const newline = this.buffer.indexOf("\n");
      if (newline < 0) return;
      const line = this.buffer.slice(0, newline).replace(/\r$/, "");
      this.buffer = this.buffer.slice(newline + 1);
      if (!line.trim()) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        this.failAll(new Error("MCP server returned invalid JSON"));
        void this.close().catch(() => undefined);
        return;
      }
      if (!message || typeof message !== "object" || Array.isArray(message)) {
        this.failAll(new Error("MCP server returned an invalid JSON-RPC record"));
        void this.close().catch(() => undefined);
        return;
      }
      if (message.id === undefined) continue;
      const key = idKey(message.id);
      const pending = this.pending.get(key);
      if (!pending) continue;
      this.pending.delete(key);
      pending.cleanup?.();
      if (message.error) {
        pending.reject(new Error(message.error.message ?? "MCP request failed"));
      } else {
        pending.resolve(message.result);
      }
    }
  }

  async send(message) {
    if (this.closed || !this.child?.stdin?.writable) throw new Error("MCP server is closed");
    const line = JSON.stringify(message) + "\n";
    await new Promise((resolve, reject) => {
      let settled = false;
      const finish = (error) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        this.writers.delete(finish);
        if (error) reject(error);
        else resolve();
      };
      const timer = setTimeout(() => finish(new Error("MCP write timed out")), REQUEST_TIMEOUT_MS);
      this.writers.add(finish);
      try {
        this.child.stdin.write(line, "utf8", finish);
      } catch (error) {
        finish(error);
      }
    });
  }

  async notify(method, params) {
    await this.send({ jsonrpc: "2.0", method, params });
  }

  request(method, params, signal) {
    const id = this.nextId++;
    const key = idKey(id);
    return new Promise((resolve, reject) => {
      let settled = false;
      let timer;
      const cleanup = () => {
        if (signal) signal.removeEventListener("abort", onAbort);
        if (timer) clearTimeout(timer);
      };
      const finish = (callback, value) => {
        if (settled) return;
        settled = true;
        this.pending.delete(key);
        cleanup();
        callback(value);
      };
      const onAbort = () => {
        void this.notify("notifications/cancelled", { requestId: id, reason: "cancelled" }).catch(() => undefined);
        finish(reject, new Error("MCP request cancelled"));
      };
      const onTimeout = () => {
        void this.notify("notifications/cancelled", { requestId: id, reason: "timeout" }).catch(() => undefined);
        finish(reject, new Error("MCP request timed out"));
      };
      if (signal?.aborted) {
        onAbort();
        return;
      }
      signal?.addEventListener("abort", onAbort, { once: true });
      timer = setTimeout(onTimeout, REQUEST_TIMEOUT_MS);
      timer.unref?.();
      this.pending.set(key, { resolve: (value) => finish(resolve, value), reject: (error) => finish(reject, error), cleanup });
      void this.send({ jsonrpc: "2.0", id, method, params }).catch((error) => finish(reject, error));
    });
  }

  async tools() {
    const tools = [];
    const names = new Set();
    const cursors = new Set();
    let cursor;
    for (let page = 0; page < MAX_TOOL_PAGES; page++) {
      const result = await this.request("tools/list", cursor === undefined ? {} : { cursor });
      for (const tool of Array.isArray(result?.tools) ? result.tools : []) {
        if (!tool || typeof tool.name !== "string" || !tool.name.trim()) continue;
        if (names.has(tool.name)) throw new Error("MCP tools/list returned a duplicate tool name");
        if (typeof schema(tool.inputSchema) !== "object" || Array.isArray(tool.inputSchema)) {
          throw new Error("MCP tools/list returned an invalid tool schema");
        }
        names.add(tool.name);
        tools.push(tool);
        if (tools.length > MAX_TOOLS) throw new Error("MCP tools/list exceeds the tool limit");
      }
      if (result?.nextCursor === undefined || result.nextCursor === null) return tools;
      cursor = result.nextCursor;
      if (typeof cursor !== "string" || !cursor || cursors.has(cursor)) {
        throw new Error("MCP tools/list returned an invalid or repeated cursor");
      }
      cursors.add(cursor);
    }
    throw new Error("MCP tools/list exceeds the page limit");
  }

  async call(name, args, signal) {
    return this.request("tools/call", { name, arguments: args ?? {} }, signal);
  }

  failAll(error) {
    for (const pending of this.pending.values()) {
      pending.cleanup?.();
      pending.reject(error);
    }
    this.pending.clear();
  }

  stopRequests() {
    this.closed = true;
    this.failAll(new Error("MCP server closed"));
    for (const finish of this.writers) finish(new Error("MCP server closed"));
  }

  terminateNow() {
    this.stopRequests();
    this.tree?.terminateNow();
  }

  close() {
    if (this.closing) return this.closing;
    this.stopRequests();
    this.closing = (async () => {
      try {
        await this.tree?.close();
      } finally {
        await Promise.all([this.child?.stdin, this.child?.stdout, this.child?.stderr].map(closeStream));
      }
    })();
    return this.closing;
  }
}

async function readSpecs() {
  const path = process.env[SPEC_FILE_ENV];
  if (!path) return [];
  const value = JSON.parse(await readFile(path, "utf8"));
  if (!Array.isArray(value)) throw new Error("Pi MCP spec file must contain an array");
  return value.filter((spec) => spec?.transport === "stdio" && typeof spec.command === "string");
}

export default async function aleraMcpExtension(pi) {
  const shutdown = new AbortController();
  registerPermissionGate(pi, shutdown.signal);
  registerSkillMentions(pi);
  let specs = [];
  const clients = new Map();
  const ownedClients = new Set();
  const names = new Set();
  let starting;
  let closing;

  const onExit = () => {
    shutdown.abort();
    for (const client of ownedClients) {
      try { client.terminateNow(); } catch { /* Other servers must still be stopped. */ }
    }
  };
  process.once("exit", onExit);

  pi.on("session_shutdown", async () => {
    if (closing) return closing;
    shutdown.abort();
    closing = (async () => {
      const results = await Promise.allSettled([...ownedClients].map((client) => client.close()));
      await starting;
      const failure = results.find((result) => result.status === "rejected");
      if (failure) throw failure.reason;
      ownedClients.clear();
      clients.clear();
      process.removeListener("exit", onExit);
    })();
    return closing;
  });

  try {
    specs = await readSpecs();
  } catch (error) {
    pi.on("session_start", (_event, ctx) => ctx.ui.notify(`MCP configuration unavailable: ${String(error)}`, "warning"));
    return;
  }

  const registerServer = async (spec) => {
    const client = new StdioClient(spec);
    ownedClients.add(client);
    try {
      await client.connect();
      const tools = await client.tools();
      if (shutdown.signal.aborted) throw new Error("MCP extension is shutting down");
      for (const tool of tools) {
        if (!tool || typeof tool.name !== "string" || !tool.name.trim()) continue;
        const base = `chat_${safePart(spec.name)}_${safePart(tool.name)}`;
        let name = base;
        let suffix = 2;
        while (names.has(name)) name = `${base}_${suffix++}`;
        names.add(name);
        pi.registerTool({
          name,
          label: tool.name,
          description: tool.description ?? `${spec.name}/${tool.name}`,
          parameters: schema(tool.inputSchema),
          async execute(_toolCallId, params, signal) {
            const result = await client.call(tool.name, params, signal);
            return {
              content: content(result),
              structuredContent: result,
              details: { server: spec.name, tool: tool.name },
              ...(result?.isError === true ? { isError: true } : {}),
            };
          },
        });
      }
      clients.set(spec.name, client);
    } catch (error) {
      await client.close();
      ownedClients.delete(client);
      throw error;
    }
  };

  const start = async (ctx) => {
    if (shutdown.signal.aborted) return;
    for (const spec of specs) {
      if (shutdown.signal.aborted) return;
      if (clients.has(spec.name)) continue;
      try {
        await registerServer(spec);
      } catch (error) {
        ctx?.ui?.notify?.(`MCP server ${spec.name} unavailable: ${String(error)}`, "warning");
      }
    }
  };

  const begin = (ctx) => {
    if (!starting) starting = start(ctx).finally(() => { starting = undefined; });
    return starting;
  };
  pi.on("session_start", (_event, ctx) => begin(ctx));
  await begin();
}
