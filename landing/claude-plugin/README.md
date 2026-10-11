# Alera For Claude Web

This independent plugin bundles the remote Alera MCP connector, guided setup, four workflow skills with their reference files, the Alera logo, and the MIT license. It uses the existing Alera service and requires your own Alera account and a running runtime. The ChatGPT/Codex plugin is a separate download.

## Install In Claude Web

1. On a paid Claude plan, open Customize > Plugins > Add > Upload plugin and select `alera-claude-plugin.zip` or `alera-claude.plugin`. Upload the archive directly; do not upload it as a standalone skill.
2. Open Alera's Connectors tab. Add the Alera connector if it is not added, then connect it and sign in through Alera's OAuth flow. Organization policies may require an Owner to add it first.
3. Open Alera on the machine you intend to use, sign in under Settings > Account, and choose MCP Control under Settings > MCP Access. Read access is enough for inspection; full access allows commands and workspace changes. Administrative access requires a separate deliberate choice.
4. In a web chat, type `/`, select the Alera setup skill, and ask to list runtimes and projects. Use returned runtime ids. An empty project list is valid.

Plugin upload alone does not add a connector, authorize Alera, start a runtime, or change existing permissions. Never paste credentials into a conversation or into these files.

## OAuth And Limits

The fixed public HTTP MCP URL uses standard OAuth discovery. The package carries no OAuth client id, secret, bearer header, callback port, or requested scope override. Alera advertises CIMD and DCR with S256 PKCE. Claude web chooses requested scopes from the server's challenge/resource metadata, which currently includes administrative scope. This package cannot pin web scopes to read and execute; inspect the actual consent screen and choose runtime access deliberately. No grants or server policy are modified by packaging.

The logo and listing URLs use documented manifest fields; a custom upload is not a directory listing and its icon rendering is not guaranteed. Local servers, hooks, subagents, executable scripts, CLI installers, and OpenAI-specific metadata are absent. Orchestration skills control agents in your Alera runtime, not Claude chat subagents. Installing or validating this folder in Claude Code does not verify web upload, real OAuth, token refresh, or runtime access.

See https://alera.build/docs/claude-plugin for installation and https://github.com/leynier/alera/blob/main/docs/claude-plugin-bundle.md for source-backed compatibility and validation limits.
