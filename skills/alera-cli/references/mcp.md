# MCP Control And Account

Use these commands when the user wants an MCP client (Claude, ChatGPT, Cursor, Claude Code) to drive this runtime, or wants to sign the runtime in to an Alera account.

## Account

- `alera account status` shows the signed-in account. It reads the runtime database when no runtime host is running.
- `alera account login` signs in through the browser on this machine (`--provider github|google`, default `github`). On a machine without a browser, such as an SSH session, use `alera account login --device`: it prints a URL and a code to confirm on any other device, then waits until the sign-in completes.
- `alera account logout` signs the runtime out and stops its cloud link.

## Runtime Name

`alera runtime rename "<name>"` names the runtime. It needs a signed-in account, because the cloud reserves the name: it must be unique (ignoring case) within the account, and a taken name fails without changing anything. MCP clients and phones pick runtimes by this name. The name is kept locally and sent again on every sign-in.

## MCP Control

- `alera mcp enable` lets MCP clients connected to the user's Alera account reach this runtime through the Alera cloud. `--access read|full|admin` picks the level (default `full`; `--read-only` is the same as `--access read`). `alera mcp disable` turns it off. All need a signed-in account for remote access.
- Levels: `read` lists and inspects; `full` also runs tools that change state, including deleting workspaces and projects, merging pull requests, and automations; `admin` also allows agent profile changes, runtime settings, webhooks, and internal maintenance. A remote client needs both the runtime level and its own grant: `mcp:admin` is never granted by default, so the user reconnects the client and ticks administrative tools on the consent page.
- `alera mcp status` shows the level, the name, the cloud link state, and the endpoint to add to the MCP client (`https://api.alera.build/v1/mcp`).
- `alera mcp apps` lists connected MCP clients for the whole account; `alera mcp revoke <grant-id>` disconnects one immediately.
- `alera mcp tools` prints the tool catalog. `alera mcp serve [--access read|full|admin]` serves the same tools over stdio to a local MCP client without the cloud, for example `claude mcp add alera -- alera mcp serve`. MCP Control applies to remote clients only; a local server defaults to `full`, and administrative tools need `--access admin`.
- A local server also offers resources a client can subscribe to: `alera://events`, `alera://workspace-starts`, and `alera://inbox`. It sends `notifications/resources/updated` when they change.

Tool arguments and results pass through the Alera cloud in transit when a remote client calls a tool; they are not stored. Prefer `--access read` when the user only needs status and listings.

## Events And Webhooks

- `alera events list [--after <cursor>] [--kind <kind>,...] [--workspace-id <id>]` reads the runtime event journal: inbox replies, question states, agent states, terminal exits, task and run changes, decision gates, automation runs, workspace starts and lifecycle, and pull request watch actions. Events carry ids and states only. Pass the returned `cursor` as `--after` to read only what is new; `alera events wait` blocks until a matching event arrives or the timeout ends.
- `alera webhook add --url https://... [--kind <kind>,...]` sends this runtime's events to an HTTPS endpoint as signed POST requests (Standard Webhooks) and prints the signing secret once. `alera webhook list`, `alera webhook test --id <id>`, and `alera webhook remove --id <id>` manage them. Webhooks need a signed-in account; the runtime forwards events to the cloud only while some webhook or MCP Events subscription wants them.
