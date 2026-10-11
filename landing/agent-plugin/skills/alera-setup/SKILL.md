---
name: alera-setup
description: Connect the portable Alera Agent Plugin, choose an available runtime, and verify read-only project access. Use for initial setup, missing MCP tools, reconnection, or an offline runtime.
metadata:
  version: "1"
---

# Set Up Alera

Use a client that explicitly supports Agent Plugins 1.0.0, Agent Skills, and Streamable HTTP MCP. Installation and authorization are client-managed; this standard has no universal install command, directory, ZIP upload, OAuth settings, or portable credential-reference fields.

1. If Alera tools are missing, help the user verify that the client loaded the extracted plugin root with `plugin.json`, `skills/`, and `mcp.json`. Follow the client's documented plugin and MCP interface to connect. If that client lacks support for the declared standard, transport, or authorization flow, report the limitation and stop setup. Do not invent an installer or assume compatibility.
2. Complete authorization only through the client's connection interface. Do not request tokens in chat or edit credentials into package files. Have the user review the actual consent and runtime access; the package does not constrain requested scopes or change grants. Do not reconnect automatically or upgrade permissions for a setup test.
3. When tools are available, call `list_runtimes`. If none is reachable, ask the user to start Alera on the intended machine and sign in under **Settings > Account**. Runtime owners choose access under **Settings > MCP Access > MCP Control**. Read access is sufficient for inspection; full permits commands and changes; admin is a deliberate separate choice.
4. If the intended runtime is unclear, show returned names and ids for the user to choose. Pass the exact selected runtime on subsequent calls. Load `alera-mcp` through the client's skill interface and read its bundled references with available file-reading tools. If a bundled file cannot be read and the remote `read_skill` tool is exposed, use it while explaining that its version can differ. Call `list_projects` as a read-only check. Do not create workspaces, launch agents, or change settings to test connectivity.

For `insufficient_scope`, explain the level required by the requested action and stop that action. Do not bypass it. Preserve preview-before-removal, explicit merge authorization, administrative-access, idempotent-retry, and reduced-protection rules from the workflow skills. Report only the installation, tools, access, and results actually observed. Agents described here run on the user's Alera runtime, not as native plugin subagents.
