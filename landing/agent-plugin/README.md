# Agent Plugin

This independent Alera distribution targets Agent Plugins 1.0.0. Its manifest identifier is `alera-agent` and package version is 1.0.0. The visible distribution channel is **Agent Plugin**. Root `plugin.json` and `mcp.json` declare the official 1.0.0 schema identifiers; five Agent Skills are immediate children of `skills/`. It contains no provider extension metadata, client manifests, client-specific skill metadata, hooks, installer, or embedded credentials. The standard defines no logo or display-name field; neither is added.

## Generic Installation

Download the ZIP and its SHA-256 checksum, verify the bytes, and extract the complete `alera-agent` directory. Choose a client that explicitly supports Agent Plugins 1.0.0, Agent Skills, and Streamable HTTP MCP. Follow that client's documented plugin import or directory-loading procedure, selecting the folder containing root `plugin.json`. The standard does not define a universal install directory, command, ZIP upload, marketplace, or enabled state.

Confirm the client discovered all five skills and the `alera` MCP server. Connect using the client's authorization interface when prompted. Credentials belong in client-managed storage, never in package files or chat. Invoke or load `alera-setup` through the client's skill interface, then check runtimes and projects with read-only calls. The Alera app or standalone runtime must be running and signed in on the selected machine. Its owner chooses runtime access under **Settings > MCP Access > MCP Control**.

## Interoperability And OAuth

The server declares `type: streamable-http` and the fixed HTTPS endpoint `https://api.alera.build/v1/mcp`. Agent Plugins standardizes the configuration format, not OAuth settings, scopes, credential references, installation, or UI. A conforming client may support skills without remote MCP or may lack the authorization implementation needed by this server. Authentication failure is not schema failure. Review actual consent; the package does not constrain server-advertised read, execute, and administrative scopes. Read access is enough for inspection. Do not bypass scope failures or upgrade access to test setup.

Bundled references are read through the client's file-reading facilities; the remote `read_skill` tool is a fallback only if exposed, and can return a newer version. Agent-profile examples refer to programs launched on Alera runtimes; they do not require those programs as the plugin client. Existing authorization, preview, retry-deduplication, administrative-access, and reduced-protection rules remain in the skills. Agents run on Alera runtimes, not as native plugin subagents.

Remote MCP arguments and results pass through Alera's cloud over TLS. They are readable during forwarding and are not stored by the forwarding service; this is not the phone relay's end-to-end encryption.

Build tests validate the two JSON documents against pinned official draft 2020-12 schemas, contained regular files, skill format, deterministic ZIPs, and absence of vendor extensions. They do not verify real installation, authorization, token exchange, refresh, logo rendering, or runtime access in any client. ChatGPT, Claude web, and GrokBot Cursor remain separate downloads with their own formats.

See [Alera guide](https://alera.build/docs/agent-plugin), [Agent Plugins specification](https://agent-plugins.org/specification), [official schemas](https://agent-plugins.org/schemas), and [Agent Skills specification](https://agentskills.io/specification).
