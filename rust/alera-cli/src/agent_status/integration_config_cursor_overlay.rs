use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use super::path_string;
#[cfg(not(windows))]
use super::sh_quote;
use super::{clean_managed_definitions, managed_command, object_field};
use super::{read_json_object, write_json_object};

/// Events Alera registers with Cursor. `sessionStart` is deliberately absent:
/// it fires when the CLI opens, before any prompt, and the normalizer maps it
/// to `working`, which would mark an idle terminal as busy.
pub(super) const CURSOR_HOOK_EVENTS: [&str; 11] = [
    "beforeSubmitPrompt",
    "stop",
    "sessionEnd",
    "preToolUse",
    "postToolUse",
    "postToolUseFailure",
    "beforeShellExecution",
    "afterShellExecution",
    "beforeMCPExecution",
    "afterMCPExecution",
    "afterAgentResponse",
];

/// Cursor's own default is 60s, long enough for one unreachable socket to hold
/// an agent turn. The hook only posts to a loopback port.
const CURSOR_HOOK_TIMEOUT_SECONDS: u64 = 5;

/// Builds the per-session Cursor plugin and the `cursor-agent` wrapper that
/// loads it, and exports the environment the terminal needs to reach them.
///
/// Cursor resolves hooks from `~/.cursor/hooks.json` and from plugins passed
/// with `--plugin-dir`. Alera uses the plugin so the user's own configuration
/// is never rewritten, and so each terminal session gets its own copy.
pub(super) fn prepare_cursor(
    runtime_dir: &Path,
    session_id: &str,
    script: &Path,
    environment: &mut BTreeMap<String, String>,
) -> anyhow::Result<()> {
    let overlay = overlay_root(runtime_dir).join(session_id);
    let plugin_root = overlay.join("plugin");
    let wrapper_directory = overlay.join("bin");
    if overlay.exists() {
        std::fs::remove_dir_all(&overlay)?;
    }
    std::fs::create_dir_all(&wrapper_directory)?;

    let hooks = CURSOR_HOOK_EVENTS
        .into_iter()
        .map(|event| {
            (
                event.to_string(),
                json!([{
                    "command": managed_command(script, "cursor", event),
                    "timeout": CURSOR_HOOK_TIMEOUT_SECONDS,
                }]),
            )
        })
        .collect::<Map<_, _>>();
    write_json_object(
        &plugin_root.join("hooks/hooks.json"),
        &Map::from_iter([
            ("version".to_string(), json!(1)),
            ("hooks".to_string(), Value::Object(hooks)),
        ]),
    )?;
    write_json_object(
        &plugin_root.join(".cursor-plugin/plugin.json"),
        &Map::from_iter([
            ("name".to_string(), json!("alera-agent-status")),
            ("displayName".to_string(), json!("Alera Agent Status")),
            (
                "description".to_string(),
                json!("Alera terminal agent status hooks."),
            ),
            ("version".to_string(), json!("0.1.0")),
            ("hooks".to_string(), json!("hooks/hooks.json")),
        ]),
    )?;

    let wrapper = wrapper_directory.join(wrapper_file_name());
    std::fs::write(&wrapper, wrapper_source(&plugin_root, &wrapper_directory))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&wrapper, std::fs::Permissions::from_mode(0o755))?;
    }

    environment.insert(
        "ALERA_CURSOR_PLUGIN_DIR".to_string(),
        path_string(&plugin_root),
    );
    environment.insert(
        "ALERA_AGENT_WRAPPER_PATH".to_string(),
        path_string(&wrapper_directory),
    );
    Ok(())
}

fn overlay_root(runtime_dir: &Path) -> PathBuf {
    runtime_dir.join("agent-runtime-overlays/cursor")
}

/// Startup housekeeping: drops every session overlay and strips the Alera
/// definitions older versions left in the user's own `~/.cursor/hooks.json`.
///
/// Both belong to host start rather than to a terminal launch. The overlays are
/// keyed by session id and the host owns no PTY yet, so every directory here is
/// from a session that no longer exists; pruning anywhere else would have to
/// guess which ones are still live. The hooks.json cleanup has to run even when
/// every hook toggle is off, and start is the only point that always runs.
pub(super) fn clear_stale_state(runtime_dir: &Path, home: &Path) -> anyhow::Result<()> {
    let root = overlay_root(runtime_dir);
    if root.exists() {
        std::fs::remove_dir_all(&root)?;
    }
    cleanup_user_hooks(home)
}

/// Strips Alera-managed definitions from the user's `~/.cursor/hooks.json`.
///
/// Older Alera versions installed the Cursor hooks globally. Those entries
/// still fire, so leaving them behind would deliver every event twice once the
/// plugin is in place. Definitions the user wrote are left untouched.
fn cleanup_user_hooks(home: &Path) -> anyhow::Result<()> {
    let path = home.join(".cursor/hooks.json");
    let Some(mut config) = read_json_object(&path)? else {
        return Ok(());
    };
    let mut changed = false;
    {
        let hooks = object_field(&mut config, "hooks");
        let mut kept = Map::new();
        for (event, value) in std::mem::take(hooks) {
            let Some(definitions) = value.as_array() else {
                // Not an array Alera could have written; leave it alone.
                kept.insert(event, value);
                continue;
            };
            let had = definitions.len();
            let cleaned = clean_managed_definitions(Some(value));
            if cleaned.len() != had {
                changed = true;
            }
            if !cleaned.is_empty() || had == 0 {
                kept.insert(event, Value::Array(cleaned));
            }
        }
        *hooks = kept;
    }
    if !changed {
        return Ok(());
    }
    if config
        .get("hooks")
        .and_then(Value::as_object)
        .is_some_and(Map::is_empty)
    {
        config.remove("hooks");
    }
    write_json_object(&path, &config)
}

fn wrapper_file_name() -> &'static str {
    if cfg!(windows) {
        "cursor-agent.cmd"
    } else {
        "cursor-agent"
    }
}

fn wrapper_source(plugin_root: &Path, wrapper_directory: &Path) -> String {
    #[cfg(windows)]
    {
        let _ = wrapper_directory;
        format!(
            r#"@echo off
setlocal
set "ALERA_PLUGIN_DIR={plugin}"
set "ALERA_REAL_COMMAND="
for /f "delims=" %%P in ('where cursor-agent 2^>nul') do (
  if /I not "%%~fP"=="%~f0" if not defined ALERA_REAL_COMMAND set "ALERA_REAL_COMMAND=%%~fP"
)
if not defined ALERA_REAL_COMMAND (
  echo Alera Cursor wrapper could not find cursor-agent on PATH. 1^>^&2
  exit /b 127
)
"%ALERA_REAL_COMMAND%" --plugin-dir "%ALERA_PLUGIN_DIR%" %*
exit /b %ERRORLEVEL%
"#,
            plugin = cmd_env_value(&path_string(plugin_root)),
        )
    }
    #[cfg(not(windows))]
    {
        // The wrapper directory leads PATH, so `command -v cursor-agent` would
        // resolve back to this script. Drop it before looking the real one up.
        format!(
            r#"#!/bin/sh
ALERA_WRAPPER_DIR={wrapper}
ALERA_STRIPPED_PATH=
ALERA_OLD_IFS=${{IFS}}
IFS=:
for ALERA_ENTRY in ${{PATH:-}}; do
  if [ "$ALERA_ENTRY" = "$ALERA_WRAPPER_DIR" ]; then
    continue
  fi
  if [ -z "$ALERA_STRIPPED_PATH" ]; then
    ALERA_STRIPPED_PATH=$ALERA_ENTRY
  else
    ALERA_STRIPPED_PATH=$ALERA_STRIPPED_PATH:$ALERA_ENTRY
  fi
done
IFS=$ALERA_OLD_IFS
PATH=$ALERA_STRIPPED_PATH
export PATH
ALERA_PLUGIN_DIR={plugin}
ALERA_REAL_COMMAND=$(command -v cursor-agent 2>/dev/null || true)
if [ -z "$ALERA_REAL_COMMAND" ]; then
  echo "Alera Cursor wrapper could not find cursor-agent on PATH." >&2
  exit 127
fi
exec "$ALERA_REAL_COMMAND" --plugin-dir "$ALERA_PLUGIN_DIR" "$@"
"#,
            wrapper = sh_quote(&path_string(wrapper_directory)),
            plugin = sh_quote(&path_string(plugin_root)),
        )
    }
}

#[cfg(windows)]
fn cmd_env_value(value: &str) -> String {
    value.replace('%', "%%").replace('"', "\"\"")
}

#[cfg(test)]
#[path = "integration_config_cursor_overlay_tests.rs"]
mod tests;
