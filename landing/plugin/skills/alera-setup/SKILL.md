---
name: alera-setup
description: Help a user connect the Alera plugin, select an available runtime, and verify access. Use for first-time setup, reconnecting Alera, or diagnosing a plugin with no reachable runtime.
metadata:
  version: 1
---

# Set Up Alera

The plugin connects to `https://api.alera.build/v1/mcp` through OAuth. The user signs in to Alera, chooses the runtimes to grant, and enables MCP Control on those machines. Credentials are handled by the client connection flow; never ask the user to paste a token or put one in plugin files.

1. Call `list_runtimes` if the Alera MCP connection is available. If the client requires authentication, guide the user through its Alera connection or sign-in control. If the MCP tools are missing, refer them to [the installation guide](https://alera.build/docs/plugin) and explain that the plugin must be installed and enabled in this client.
2. If no runtime is reachable, ask the user to open Alera on the target machine, sign in under **Settings > Account**, and choose an access level under **Settings > MCP Access > MCP Control**. Read access is enough for inspection. Full access is needed for launching agents and changing workspaces and allows commands on that machine. Leave administrative access to an explicit user decision. Check that the connection grants the intended runtime, then call `list_runtimes` again after the user reports completing setup.
3. When several runtimes are available and the intended machine is unclear, show their returned names and ids and let the user choose. Pass that exact runtime on subsequent calls. Never infer a machine from its list position.
4. Load the bundled `alera-mcp` skill before continuing with projects, workspaces, or agents. Use `list_projects` for a read-only connection check on the selected runtime; an empty project list is a valid result. Report the runtime and the access actually observed. Do not create a workspace, launch an agent, change settings, or upgrade access merely to test setup.

If access fails with `insufficient_scope`, explain which connection permission or runtime access level is missing for the requested action. Do not bypass it or repeatedly retry. A runtime that is offline must be started by its owner; plugin installation alone does not start Alera.
