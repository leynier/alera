# Agent Quotas

Alera displays agent subscription and usage quotas in a status bar at the bottom of the active workbench. Each provider uses its agent icon and exposes all available windows directly in the bar, including Claude 5-hour, weekly, and Fable quotas and every Antigravity model-group window. Hovering a quota opens a structured card with one row per window, an exact remaining percentage, a semantic completion bar, and a reset countdown in a compact format such as `1d 3h 45m`. It behaves like a tooltip and does not require a click or open a menu. Quotas refresh every 5 minutes, can be refreshed manually from the button immediately after the last agent, and retain the last successful values as stale data when a refresh fails.

The left-to-right provider order is configurable in **Settings → Quotas → Providers**. Claude CCS profiles can also be reordered independently; Default remains first when enabled.

## Supported Providers

- Claude Code, including the default account and manually configured CCS profiles.
- Codex.
- Kimi Code.
- Grok Build.
- Antigravity.
- MiniMax Token Plan.
- Z.ai.

The quota host follows the active workspace. Local workspaces query the bundled `alera runtime-proxy` sidecar. SSH workspaces run the same command through the Alera runtime installed on that remote host, so credentials stay on the machine where the agent runs.

## Claude CCS Profiles

Configure the Claude provider, Default account, and CCS profiles together in **Settings → Quotas → Claude**. Each profile entry has:

- **Alias**: the familiar command name, such as `ccdev`.
- **Profile**: the CCS instance directory name under `$CCS_DIR/instances` or `~/.ccs/instances`.

Alera sets `CLAUDE_CONFIG_DIR` only for the hidden quota query. The default Claude account can be enabled or disabled independently from the Claude provider, so configured CCS profiles remain available without querying Default. When enabled, the status bar shows Default first, followed by every configured CCS profile in settings order using its configured alias. Quota queries do not change how terminals launch Claude.

## Environment-Based Plans

Alera stores only environment variable names, never API key values. Configure the values on every local or remote host where the provider is enabled:

- Kimi Code: `KIMI_API_KEY` and optionally `KIMI_CODE_BASE_URL`.
- MiniMax: `MINIMAX_API_KEY` and optionally `MINIMAX_API_HOST`.
- Z.ai: `ZAI_API_KEY` and optionally `ZAI_BASE_URL`.

The Kimi, MiniMax, and Z.ai variable names can be changed per host in settings. MiniMax chooses the global or China token-plan endpoint from the configured host.

## Provider Data Sources

- Claude and Antigravity use their official interactive usage commands in hidden PTYs.
- Codex uses the read-only app-server rate-limit method.
- Kimi calls its usage endpoint with the API key from the configured host environment variable, which defaults to `KIMI_API_KEY`.
- Grok reads its existing local login metadata and calls its usage endpoint.
- MiniMax and Z.ai call their plan usage endpoints with credentials read from the target host environment.

Reference projects remain implementation references only and are not runtime dependencies.
