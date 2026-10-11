---
name: alera-setup
description: Set up Alera with GitHub Copilot CLI, the GitHub Copilot app, or VS Code, choose an available runtime, and verify read-only project access. Use for initial setup, missing tools, reconnection, or an offline runtime.
metadata:
  version: "1"
---

# Set Up Alera With GitHub Copilot

1. Identify the actual GitHub Copilot surface. In CLI, install the extracted `alera-copilot` directory with `copilot plugin install ./alera-copilot`, or use a session-only `--plugin-dir` mount. In VS Code, follow its documented local-plugin registration and inspect Agent Customizations and **MCP: List Servers**. In the GitHub Copilot app, use **Customize > Plugins** only if Alera is available in a configured marketplace. Do not invent an app ZIP upload, claim that CLI loading verifies the app, or confuse GitHub Copilot with Microsoft 365 Copilot. See [installation](https://alera.build/docs/copilot-plugin). Do not change persistent settings or organization policy on the user's behalf merely to test setup.
2. If tools are missing, verify plugin discovery and use that surface's MCP connection interface to complete provider authorization when prompted. Do not request credentials in chat or insert headers into package files. OAuth remains client-managed. Review actual consent and runtime access; this package does not constrain requested scopes. Never infer shared grants or successful authentication from client inventory discovery.
3. When tools are actually available, call `list_runtimes`. If none is reachable, ask the user to start Alera on the intended machine and sign in under **Settings > Account**. The owner chooses access under **Settings > MCP Access > MCP Control**. Read is sufficient for inspection, full allows changes, and admin is a deliberate separate choice. Do not upgrade access as a connectivity test.
4. Show returned names and ids if the intended runtime is unclear, then pass the exact selected runtime on subsequent calls. Load `alera-mcp` with the client's skill facilities and read only needed bundled references. If unavailable, use the remote `read_skill` tool only if exposed, disclosing that its version may differ. Call `list_projects` for a read-only check. Do not create workspaces, agents, or settings as a setup test.

For `insufficient_scope`, explain the access level needed for the requested action and stop it. Do not bypass the failure or reconnect automatically. Preserve the workflow skills' authorization, preview-before-removal, retry-deduplication, administrative-access, and reduced-protection rules. Report only observed installation, tools, access, and results. Alera agents run on the selected Alera runtime, not as native plugin subagents.
