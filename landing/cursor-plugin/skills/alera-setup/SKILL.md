---
name: alera-setup
description: Set up the GrokBot Cursor distribution, connect Alera, select an available runtime, and inspect projects. Use for missing tools, initial setup, reconnecting, or an offline runtime.
metadata:
  version: "1"
---

# Set Up GrokBot Cursor

1. In Cursor, confirm the extracted plugin folder is under `~/.cursor/plugins/local/alera-grokbot-cursor`, reload the window, and check **Customize**. Use Cursor's MCP connection UI to sign in to Alera when requested. See [installation](https://alera.build/docs/grokbot-cursor-plugin). If local import is blocked, explain the organization's policy; do not change it.
2. In Grok Bot, the official installation flow only covers available marketplace plugins: open **Plugins**, find Alera if it is offered, add it, complete **Authorize/Authenticate**, and confirm **Installed**. If Alera is unavailable, stop setup and explain that importing this ZIP or a Cursor local folder into Grok Bot is not documented. Never infer availability, shared skills, authentication, or synchronization from using the same account. If tools are missing, do not claim the connection works.
3. When Alera tools are actually available, call `list_runtimes`. If none is reachable, ask the user to start Alera on the intended machine and sign in under **Settings > Account**. The runtime owner chooses access under **Settings > MCP Access > MCP Control**. Read access is enough for inspection; full permits commands and changes; admin is a deliberate separate choice. Do not upgrade access to test setup.
4. If the intended runtime is unclear, show returned names and ids for the user to choose. Use the exact selected runtime on subsequent calls. Load the bundled `alera-mcp` skill if the client can read it; otherwise use the remote `read_skill` tool if exposed, explaining that its version may differ. Call `list_projects` as a read-only check. Do not create workspaces or agents as a setup test.

OAuth and credential storage belong to each client's connection flow. No tokens or secrets belong in chat or package files. Review actual consent; this package does not constrain requested scopes. For `insufficient_scope`, explain the level needed for the requested action and stop that action. Do not bypass it or reconnect automatically. Report only tools, access, and results actually observed. The agents described in the workflow skills run on Alera runtimes, not as native client subagents.
