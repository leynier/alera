import readline from "node:readline";
import extension from "../../src/mcp_extension.js";

const handlers = new Map();
const pi = {
  on(name, handler) {
    const list = handlers.get(name) ?? [];
    list.push(handler);
    handlers.set(name, list);
  },
  registerTool() {},
};
const context = { ui: { notify() {} } };
await extension(pi);
process.stdout.write("ready\n");
readline.createInterface({ input: process.stdin }).on("line", async (line) => {
  if (line === "exit") process.exit(0);
  if (line === "reload" || line === "quit") {
    for (const handler of handlers.get("session_shutdown") ?? []) {
      await handler({ type: "session_shutdown", reason: line }, context);
    }
    handlers.clear();
    if (line === "reload") await extension(pi);
    process.stdout.write(line + "\n");
    if (line === "quit") process.exit(0);
  }
});
