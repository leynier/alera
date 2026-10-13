import { spawn } from "node:child_process";
import { appendFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import readline from "node:readline";

const directory = process.env.MCP_FIXTURE_DIRECTORY;
const descendant = process.argv[2] === "descendant";
if (directory) writeFileSync(join(directory, descendant ? "descendant-pid" : "server-pid"), String(process.pid));
if (directory && !descendant) writeFileSync(join(directory, "supervisor-pid"), String(process.ppid));
if (process.env.MCP_FIXTURE_TREE === "1") process.on("SIGTERM", () => undefined);
if (descendant) {
  setInterval(() => undefined, 1_000);
} else {
  if (process.env.MCP_FIXTURE_TREE === "1") {
    spawn(process.execPath, [import.meta.filename, "descendant"], {
      stdio: "ignore", windowsHide: true,
    });
  }
  const input = readline.createInterface({ input: process.stdin });
  const reply = (id, result, error, callback) => process.stdout.write(JSON.stringify({
    jsonrpc: "2.0", id, ...(error ? { error } : { result }),
  }) + "\n", callback);
  let page = 0;
  input.on("line", (line) => {
    const message = JSON.parse(line);
    if (process.env.MCP_RECORD_FILE) appendFileSync(process.env.MCP_RECORD_FILE, line + "\n");
    if (message.method === "initialize") {
      if (process.env.MCP_FIXTURE_MODE !== "hang-initialize") reply(message.id, {});
    } else if (message.method === "tools/list") {
      page++;
      const mode = process.env.MCP_FIXTURE_MODE;
      const name = page === 1 || mode === "duplicate-tool" ? "echo" : "second";
      const tools = [{ name, description: name, inputSchema: { type: "object", properties: { text: { type: "string" } } } }];
      if (mode === "page-limit") tools[0].name = `echo_${page}`;
      if (mode === "invalid-schema" && page === 2) tools[0].inputSchema = [];
      if (mode === "tool-limit") {
        for (let index = 0; index < 10_000; index++) tools.push({ name: `extra_${index}` });
      }
      const nextCursor = mode === "page-limit" ? String(page) :
        mode === "repeat-cursor" || page === 1 && mode !== "tool-limit" ? "page-two" : undefined;
      reply(message.id, { tools, ...(nextCursor === undefined ? {} : { nextCursor }) });
    } else if (message.method === "tools/call") {
      if (message.params.arguments.wait) return;
      if (message.params.arguments.exit) return process.exit(23);
      if (message.params.arguments.error) reply(message.id, undefined, { code: -32000, message: "fixture tool failed" });
      else reply(message.id, {
        content: [{ type: "text", text: message.params.arguments.bytes ? "x".repeat(message.params.arguments.bytes) :
          message.params.arguments.text ?? message.params.name }],
        ...(message.params.arguments.isError ? { isError: true } : {}),
      }, undefined, message.params.arguments.exitAfterReply ? () => process.exit(23) : undefined);
    }
  });
}
