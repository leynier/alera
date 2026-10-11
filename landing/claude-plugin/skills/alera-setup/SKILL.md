---
name: alera-setup
description: Connect Alera in Claude web, choose an available runtime, and verify access. Use for first-time plugin setup, missing connector tools, reconnecting Alera, or an offline runtime.
metadata:
  version: 1
---

# Set Up Alera In Claude Web

The plugin bundles a remote connector at `https://api.alera.build/v1/mcp`. Uploading it does not connect or authorize Alera. Credentials belong in Claude's connector sign-in flow, never in chat or plugin files.

1. If Alera tools are missing, guide the user to **Customize > Plugins > Alera > Connectors**. Add the connector if it shows **Not added**, then connect it and sign in to Alera. On Team or Enterprise, an Owner may need to add it first. Refer to [installation](https://alera.build/docs/claude-plugin) if the plugin is missing. Do not run a CLI installer or claim that a CLI install adds it to the web account.
2. Call `list_runtimes` when the connector is available. If no runtime is reachable, ask the user to start Alera on the intended machine, sign in under **Settings > Account**, and choose access under **Settings > MCP Access > MCP Control**. Read access is sufficient to inspect projects; full access permits commands and changes. Administrative access is a deliberate user choice. Recheck after the user reports completing setup.
3. If several runtimes are available and the intended one is unclear, show the returned names and ids for the user to choose. Pass the exact chosen runtime on subsequent calls.
4. Load the bundled `alera-mcp` skill through Claude's skill facilities, then call `list_projects` for a read-only check. Report only the runtime and access observed. Do not create a workspace, launch agents, or upgrade permissions to test setup.

If access fails with `insufficient_scope`, explain the required level for the requested action and stop that action. Do not bypass it or reconnect automatically. Claude web requests scopes from the server's OAuth metadata; this package does not restrict those scopes. Have the user review actual consent and runtime access. An offline runtime must be started by its owner.
