# GrokBot Cursor

Version 1.0.0. This independent Alera distribution uses Cursor's native plugin format. The visible distribution name is exactly **GrokBot Cursor**; the supported manifest identifier is `alera-grokbot-cursor`. Cursor documents no `displayName` field, so the package does not invent one.

## Cursor Installation

Extract the ZIP and copy its complete `alera-grokbot-cursor` folder, including hidden `.cursor-plugin`, into `~/.cursor/plugins/local/`. The manifest must end up at `~/.cursor/plugins/local/alera-grokbot-cursor/.cursor-plugin/plugin.json`. Restart Cursor or run **Developer: Reload Window**, then open **Customize** and confirm five skills and the Alera MCP server. Connect through Cursor's MCP sign-in UI when prompted. Invoke `/alera-setup` for a read-only runtime and project check.

Local import must be allowed by your organization. Teams and Enterprise admins control **Allow Local Plugin Imports**; Enterprise defaults to off. An installed marketplace plugin with the same identifier takes precedence. This archive contains no installer, hooks, local MCP process, tokens, authentication headers, or static OAuth client configuration.

## Grok Bot Installation Boundary

Grok Bot's documented flow is **Plugins > search for an available plugin > Add > Authorize/Authenticate > Installed**. If Alera is not offered in your account's marketplace, this ZIP does not make it available there. The official connection guide does not document importing arbitrary ZIPs or Cursor local folders, loading this package's bundled skills, custom MCP OAuth registration, or synchronizing local Cursor installations into Grok Bot. Sharing an account does not establish those capabilities. This change does not publish a marketplace listing.

If an Alera connection is separately available in Grok Bot, complete provider sign-in there and verify tools before running setup. Do not promise that the bundled skills appear in Grok Bot. No real installation, OAuth exchange, token refresh, or runtime access is verified by package tests.

## Remote Access

The fixed endpoint is `https://api.alera.build/v1/mcp`. Cursor infers the remote transport from `url` and manages OAuth. Alera exposes public OAuth discovery and dynamic client registration; no credentials are bundled. Review actual consent: the server currently advertises read, execute, and administrative scopes, and the package does not constrain them. Runtime Read access is sufficient for inspection. Never upgrade permissions to test setup, bypass `insufficient_scope`, or paste tokens into chat.

Start Alera on the intended machine and sign in under **Settings > Account**. Runtime access is configured by its owner under **Settings > MCP Access > MCP Control**. Remote arguments and results pass through Alera's cloud over TLS, are readable during forwarding, and are not stored by the forwarding service. This is not the phone relay's end-to-end encryption.

See [Alera setup](https://alera.build/docs/grokbot-cursor-plugin), [Cursor plugin reference](https://cursor.com/docs/reference/plugins), [local import](https://cursor.com/docs/plugins#test-plugins-locally), [MCP authentication](https://cursor.com/docs/mcp), and [Grok Bot connections](https://cursor.com/help/grok-bot/connect-plugins). The Alera logo is bundled and committed at its declared relative path; actual client rendering is unverified. ChatGPT, Claude web, and the portable Agent Plugin remain separate distributions.
