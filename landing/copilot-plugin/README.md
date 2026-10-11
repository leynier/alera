# Alera For GitHub Copilot

An independent GitHub Copilot distribution using the officially recommended Agent Plugins 1.0.0 format. Its identifier is `alera-copilot`, version 1.0.0. Includes five skills and the remote Alera MCP server. This is GitHub Copilot, not Microsoft 365 Copilot.

## Copilot CLI

Extract the ZIP and install the complete folder with `copilot plugin install ./alera-copilot`. Confirm it with `copilot plugin list`, and invoke `/alera-setup` in a session. For a session-only mount instead, use `copilot --plugin-dir ./alera-copilot`; that is not a persisted installation. Connect the remote server through Copilot's MCP authentication interface when requested. Do not paste credentials in chat or package files. Installation is not proof of OAuth or runtime connectivity.

## VS Code

Current VS Code documentation supports Agent Plugins 1.0.0. With plugin support enabled, register the extracted folder using `chat.pluginLocations`, mapping its absolute path to `true`. Inspect it in Agent Customizations and check **MCP: List Servers**. VS Code also documents discovery of CLI-installed plugins in `~/.copilot/installed-plugins/`; verify the actual inventory on your machine rather than assuming authentication synchronization. Agent Host `/plugin` operations and Agent Customizations currently use separate inventories. Organization policy can restrict availability. This package does not change your settings or policy.

## GitHub Copilot App

The documented app flow is **Customize > Plugins**, browsing marketplaces and installing available plugins. The general plugin documentation covers Agent Plugins 1.0 across the app, CLI, and cloud agent, but does not establish that a standalone ZIP can be uploaded in the app. If Alera is separately available in a configured marketplace, install and authorize it there. This change does not publish Alera into a marketplace or verify app installation. Local CLI or VS Code loading is not proof of app availability or sign-in.

## Logo Investigation

The official GitHub CLI manifest reference and VS Code plugin guide do not document `logo`, `icon`, or `interface` for these manifests, nor an image field under `extensions.com.github.copilot`. That namespace is documented for client components such as agents, commands, rules, hooks, LSP, and VS Code automation paths. Namespace support alone does not define a logo field. No such field or decorative asset is added to this package. Alera's website download card uses its existing logo; rendering inside Copilot remains unsupported by the reviewed documentation and unverified.

## Access And Verification

The standard MCP configuration declares `streamable-http` at `https://api.alera.build/v1/mcp`. OAuth is client-managed. Public discovery and dynamic registration at Alera do not prove a successful grant in any Copilot surface. Review actual consent: the package does not constrain advertised read, execute, or administrative scopes. Start Alera on the intended runtime, sign in under **Settings > Account**, and let the owner choose runtime access under **Settings > MCP Access > MCP Control**. Read access is enough for setup. Never upgrade grants or bypass `insufficient_scope` to test setup.

Remote arguments and results pass through Alera's cloud over TLS, readable during forwarding and not stored by the forwarding service. Package, schema, and website tests do not prove real installation, authorization, token exchange, refresh, or runtime access. Keep client policies and credentials unchanged.

See [Alera installation](https://alera.build/docs/copilot-plugin), [GitHub plugin overview](https://docs.github.com/en/copilot/concepts/agents/about-plugins), [CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference), [MCP setup](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#using-copilot-mcp), and [VS Code plugins](https://code.visualstudio.com/docs/agent-customization/agent-plugins).
