# MCP Control And Account

Use these commands when the user wants an MCP client (Claude, ChatGPT, Cursor, Claude Code) to drive this runtime, or wants to sign the runtime in to an Alera account.

## Account

- `alera account status` shows the signed-in account. It reads the runtime database when no runtime host is running.
- `alera account login` signs in through the browser on this machine (`--provider github|google`, default `github`). On a machine without a browser, such as an SSH session, use `alera account login --device`: it prints a URL and a code to confirm on any other device, then waits until the sign-in completes.
- `alera account logout` signs the runtime out and stops its cloud link.

## Runtime Name

`alera runtime rename "<name>"` names the runtime. It needs a signed-in account, because the cloud reserves the name: it must be unique (ignoring case) within the account, and a taken name fails without changing anything. MCP clients and phones pick runtimes by this name. The name is kept locally and sent again on every sign-in.

## MCP Control

- `alera mcp enable` lets MCP clients connected to the user's Alera account reach this runtime through the Alera cloud with full control. `alera mcp enable --read-only` allows only tools that read state. `alera mcp disable` turns it off. All three need a signed-in account for remote access.
- `alera mcp status` shows the level, the name, the cloud link state, and the endpoint to add to the MCP client (`https://api.alera.build/v1/mcp`).
- `alera mcp apps` lists connected MCP clients for the whole account; `alera mcp revoke <grant-id>` disconnects one immediately.
- `alera mcp tools` prints the tool catalog. `alera mcp serve [--read-only]` serves the same tools over stdio to a local MCP client without the cloud, for example `claude mcp add alera -- alera mcp serve`.

Tool arguments and results pass through the Alera cloud in transit when a remote client calls a tool; they are not stored. Prefer `--read-only` when the user only needs status and listings.
