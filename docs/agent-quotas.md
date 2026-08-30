# Agent Quotas

Alera displays agent subscription and usage quotas in a status bar at the bottom of the active workbench. Each provider uses its agent icon and exposes all available windows directly in the bar, including Claude 5-hour, weekly, and Fable quotas and every Antigravity model-group window. Hovering a quota opens a structured card with one row per window, an exact remaining percentage, a semantic completion bar, and a reset countdown in a compact format such as `1d 3h 45m`. Clicking the quota opens the same card and pins it, so it stays visible after the pointer leaves and its contents stay reachable; clicking the quota again, clicking another quota, or clicking anywhere outside the card closes it. Only one card is open at a time. Quotas refresh every 15 minutes, can be refreshed manually from the button immediately after the last agent, and retain the last successful values as stale data when a refresh fails.

The left-to-right provider order is configurable in **Settings → Quotas → Providers**. Claude CCS profiles can also be reordered independently; Default remains first when enabled.

## Supported Providers

- Claude Code, including the default account and manually configured CCS profiles.
- Codex.
- Kimi Code.
- Grok Build.
- Cursor.
- Antigravity.
- MiniMax Token Plan.
- Z.ai.
- OpenCode Go and OpenCode Zen.

The quota host follows the active workspace. Local desktop and mobile requests go through the runtime-host quota service, which keeps a 15-minute in-memory cache and returns the last successful snapshot as stale data when a provider refresh fails. Automatic reads reuse that cache; the explicit refresh button bypasses it. For the local desktop host, Alera resolves configured variables missing from the GUI process through the user's login shell and sends their values directly to the runtime host in memory. Values are never persisted or returned in quota responses. Alera must be restarted after changing those shell exports because the resolver caches them for the app lifetime. SSH workspaces run `alera runtime-proxy` through the Alera runtime installed on that remote host, so credentials stay on the machine where the agent runs.

Mobile exposes a dedicated **Quotas** screen with the same provider ordering, Claude Default and CCS profile configuration, environment variable names, manual refresh, and remaining/reset details as desktop. When a Claude profile is not `ok` and the runtime advertises `agentQuotaClaudeTuiV1`, the card also offers **Try With TUI**. Codex reset credits and their next expiry appear when the runtime advertises `codexResetCreditsV1`. It refreshes when opened and every 15 minutes while visible. Disabling every provider is supported and produces an empty snapshot rather than falling back to defaults.

Mobile Home shows quotas from all available hosts by default. Use **Settings > Quota Hosts** or **Choose Hosts** beside the Home quota heading to hide hosts that share the same accounts. Each switch applies to all quotas from that host in the Home summary, and hidden hosts are not polled for quotas by that summary. The selection is saved only on this phone by runtime ID, survives host renaming and reconnection, and includes newly added hosts by default. All hosts may be hidden; **Choose Hosts** remains available to restore them. Individual host Quotas screens, provider settings, and desktop behavior are unchanged.

## Codex Reset Credits

For the default Codex account, desktop hover cards, the desktop quota overview, and the mobile Quotas card show how many earned rate-limit resets are available and when the next available credit expires. Alera always asks for confirmation before spending one.

Consumption is account- and offer-scoped. Alera re-reads the active Codex account and current offer immediately before the request, refuses the action if either changed, and requires the account identity from `auth.json`. The opaque offer revision never exposes that identity. Before contacting Codex, Alera stores a pending attempt and its idempotency key in `runtime.sqlite`; a retry after a timeout or restart reuses the same key. If that durable write fails, Alera does not call the provider. The host returns the provider outcome and a refreshed Codex snapshot, then updates all connected quota views.

## Claude CCS Profiles

Configure the Claude provider, Default account, and CCS profiles together in **Settings → Quotas → Claude**. Each profile entry has:

- **Alias**: the familiar command name, such as `ccdev`.
- **Profile**: the CCS instance directory name under `$CCS_DIR/instances` or `~/.ccs/instances`.

Alera sets `CLAUDE_CONFIG_DIR` only for the quota query. On macOS it reads each profile's scoped Claude Code Keychain item and queries the OAuth usage endpoint directly; older credential files remain a cross-platform fallback. A CCS profile never falls back to Default's legacy Keychain item. Snapshot and force-refresh stay on that OAuth path; if OAuth fails, the profile is reported as unavailable or error without launching Claude. When a profile is not `ok`, desktop hover cards and the mobile Quotas screen offer **Try With TUI**, which scrapes `/usage` for that account only through `agentQuota.fetchClaudeTui` (requires runtime capability `agentQuotaClaudeTuiV1`). Accounts without OAuth or API credentials are reported as signed out without launching Claude.

The default Claude account can be enabled or disabled independently from the Claude provider, so configured CCS profiles remain available without querying Default. When enabled, the status bar shows Default first, followed by every configured CCS profile in settings order using its configured alias. Quota queries do not change how terminals launch Claude.

## Environment-Based Plans

## OpenCode Go And Zen

OpenCode is enabled as one provider with separate **Go** and **Zen** snapshots. Alera follows OpenCode's current data location (`XDG_DATA_HOME/opencode`, falling back to `~/.local/share/opencode`) on Windows, macOS, and Linux, then checks the platform-native legacy data location for older installs. It reads the OpenCode API credentials from the target host's OpenCode `auth.json`. Go uses OpenCode's authenticated `/zen/go/v1/usage` endpoint, so its 5-hour, weekly, and monthly percentages and reset times reflect account usage across OpenCode clients and hosts. The published Go limits are $12 per 5-hour, $30 weekly, and $60 monthly, but Alera does not reconstruct them from local message costs. Zen is shown as local 30-day spend from the OpenCode SQLite history when a Zen API key is configured; authoritative Zen balance data is not currently exposed by the provider. Zen rows are labeled **Estimated** and must not be treated as billing records.

Alera stores only environment variable names in its own settings and never API key values. OpenCode credentials remain in OpenCode's `auth.json`. Configure the values on every local or remote host where the provider is enabled:

- Kimi Code: `KIMI_API_KEY` and optionally `KIMI_CODE_BASE_URL`.
- MiniMax: `MINIMAX_API_KEY` and optionally `MINIMAX_API_HOST`.
- Z.ai: `ZAI_API_KEY` and optionally `ZAI_BASE_URL`.

The Kimi, MiniMax, and Z.ai variable names can be changed per host in settings. MiniMax chooses the global or China token-plan endpoint from the configured host.

## Where The Host Reads Variables From

Quota lookups for the local host run inside the `alera terminal-host` sidecar, which the app starts as a detached child. A GUI launch (Finder, Dock, Spotlight, a `.desktop` entry) starts the app with a minimal environment that contains none of the user's shell rc exports, so the sidecar would not see them either.

The sidecar therefore resolves these variables through the user's login shell (`$SHELL -ilc`), cached for the process lifetime and refreshable through the `shellEnvironment.reload` request. A value already present in the sidecar's own environment always wins, so an explicit override is never masked. This covers `CCS_DIR`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CODEX_HOME`, `GROK_HOME`, `CURSOR_CONFIG_DIR`, `XDG_CONFIG_HOME`, the configurable Kimi / MiniMax / Z.ai names, and the base-URL overrides. The same environment is handed to the **Try With TUI** scrape, so the CLI it launches resolves on `PATH` and reads the same configuration it would in a terminal tab. Windows is unaffected: user and system variables already reach GUI processes there.

Resolved values may be secrets. They are held in memory only, never logged and never written to disk.

## Claude Credential States

A Claude account with no usable OAuth credentials reports which of these it hit, because they need different things from the user:

- **Not signed in to Claude** - no credential store holds anything for that config directory.
- **Claude credentials could not be read** - a credential store holds an entry that could not be read. On macOS this is usually a Keychain item whose access control has not been granted yet; allowing the access prompt resolves it. The probe waits long enough for that prompt to be answered.
- **Claude credentials are not OAuth credentials** - credentials were read but carry no `claudeAiOauth` entry, so the account authenticates some other way.

## Provider Data Sources

- Claude prefers scoped Keychain or credential-file OAuth data and the official usage endpoint. A hidden PTY `/usage` scrape runs only when the user chooses **Try With TUI** for that profile.
- Antigravity scrapes its official interactive usage command in a hidden PTY on normal snapshot and refresh paths.
- Codex first queries the authenticated `wham/usage` backend used by Codex itself, including reset-credit metadata, and falls back to the read-only app-server rate-limit method. Older app-server responses are enriched from the reset-credit endpoint when possible.
- Kimi calls its usage endpoint with the API key from the configured host environment variable, which defaults to `KIMI_API_KEY`.
- Grok reads its existing local login metadata and calls its usage endpoint.
- Cursor reads the local Cursor CLI session (`~/.config/cursor/auth.json`, or `$CURSOR_CONFIG_DIR/auth.json` / `$XDG_CONFIG_HOME/cursor/auth.json`) and queries the current-period usage endpoint used by `cursor-agent /usage`. Windows map to Included, Auto, and API percentages. This path is not a documented public Cursor API.
- MiniMax and Z.ai call their plan usage endpoints with credentials read from the target host environment.

Reference projects remain implementation references only and are not runtime dependencies.
