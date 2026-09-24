# Agent Status Hooks

Alera recognizes agent activity by installing hooks into each agent's **user global config**. It does not use runtime homes, config overlays, symlinks, or per-agent wrappers for that path. fx is the exception: it reports through its built-in Herdr integration and does not write user hook files.

Every switch defaults off. Enabling a switch writes Alera-scoped entries; disabling it removes only those entries. User-owned config stays. The runtime host is the writer (`prepare_enabled_integrations`). Install is idempotent: an already-current file is left byte-identical.

## What Alera writes

Alera-managed hook commands include `alera-runtime-agent-hook` in the command string. Older versions used per-agent names such as `alera-claude-hook.sh`; cleanup still recognizes those. Plugin files start with the comment `ALERA_AGENT_STATUS_MANAGED_FILE`.

| Agent | File | Shape |
| --- | --- | --- |
| Codex | `~/.codex/hooks.json` and `~/.codex/config.toml` | Merged hook definitions plus Alera-owned trust records. `$CODEX_HOME` is used when it is not an older Alera runtime-home leftover. |
| Claude Code | `~/.claude/settings.json` | Merged `hooks` object. `~/.claude/settings.local.json` is cleaned of leftovers only. |
| GitHub Copilot | `~/.copilot/hooks/alera.json` | Dedicated Alera file. `$COPILOT_HOME` is honored. |
| Cursor | `~/.cursor/hooks.json` | Merged command entries with a 5s timeout. `sessionStart` is not registered. |
| Antigravity | `~/.gemini/config/hooks.json` | Top-level `alera-status` bundle. |
| Grok Build | `~/.grok/hooks/alera-status.json` | Dedicated Alera file. `$GROK_HOME` is honored. |
| OpenCode | `~/.config/opencode/plugins/alera-agent-status.js` | Dedicated plugin. `$OPENCODE_CONFIG_DIR` is honored. |
| OpenCode 2 | `~/.config/opencode/plugins/alera-agent-status-v2.js` | Dedicated plugin. Same config dir as v1. |
| Pi | `~/.pi/agent/extensions/alera-agent-status.ts` | Dedicated extension. `$PI_CODING_AGENT_DIR` is honored. |
| Amp | `~/.config/amp/plugins/alera-agent-status.ts` | Dedicated plugin. `$AMP_CONFIG_DIR` is honored. |
| fx | none | Herdr socket and pane id in the terminal environment. |

The shared hook script lives at `~/.alera/agent-hooks/alera-runtime-agent-hook.sh` (`.cmd` on Windows). It no-ops unless the terminal identity environment is present, so hooks that fire outside an Alera terminal do not report.

## How to clean

The reversible path is the matching Settings (or `alera runtime agents disable`) toggle. That removes only Alera-marked definitions or dedicated Alera files.

To clean by hand without Alera:

1. Dedicated files (Copilot `hooks/alera.json`, Grok `hooks/alera-status.json`, OpenCode/Pi/Amp plugin files): delete the file if it contains `alera-runtime-agent-hook` or `ALERA_AGENT_STATUS_MANAGED_FILE`. Do not delete sibling user files in the same directory.
2. Merged JSON (Claude `settings.json`, Cursor `hooks.json`, Codex `hooks.json`, Antigravity `hooks.json`): remove array entries whose command contains `alera-runtime-agent-hook` or a legacy `alera-<agent>-hook` name. Keep every other entry. For Antigravity, drop the `alera-status` object if it is empty after that.
3. Codex `config.toml`: remove `[hooks.state]` keys that point at `agent-runtime-homes/codex` or at Alera commands in `hooks.json`. Do not disable `features.hooks` if other hooks remain.
4. Older overlay leftovers under the runtime directory (`agent-runtime-homes/`, `agent-runtime-overlays/`): delete those directories. Host start already does this. Desktop application-support copies of the same names from older app versions can be deleted the same way; they are not user config.

Unparseable user files are left untouched.

## Activity after migrate

New terminals do not set `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, or a Cursor wrapper `PATH` entry. Agents read their own global config, so activity recognition keeps working for the supported agents listed above as long as the matching toggle stays on. Nested Alera terminals still strip inherited overlay variables from older hosts so a parent runtime home cannot shadow the user config.
