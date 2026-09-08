use std::path::Path;

use serde_json::{json, Value};

use super::managed_command;
use super::user_hooks::{cleanup_managed_hooks_file, read_jsonc_object};
use super::{object_field, write_json_object};

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

/// Writes Alera Cursor hooks into the user's own `~/.cursor/hooks.json`.
///
/// Older Alera versions used a per-session plugin and `cursor-agent` wrapper
/// so this file was never rewritten. The wrapper path is gone: this is the
/// same merge used for Claude, scoped to Alera-marked command entries.
pub(super) fn install_cursor_user_hooks(home: &Path, script: &Path) -> anyhow::Result<()> {
    let path = home.join(".cursor/hooks.json");
    let config = read_jsonc_object(&path)?.unwrap_or_default();
    let mut updated = config.clone();
    if !updated.contains_key("version") {
        updated.insert("version".to_string(), json!(1));
    }
    let hooks = object_field(&mut updated, "hooks");
    for event in CURSOR_HOOK_EVENTS {
        let command = managed_command(script, "cursor", event);
        let mut definitions = super::clean_managed_definitions(hooks.remove(event));
        definitions.push(json!({
            "command": command,
            "timeout": CURSOR_HOOK_TIMEOUT_SECONDS,
        }));
        hooks.insert(event.to_string(), Value::Array(definitions));
    }
    if updated == config {
        return Ok(());
    }
    write_json_object(&path, &updated)
}

/// Strips Alera-managed definitions from the user's `~/.cursor/hooks.json`.
/// User entries stay. Missing files are a no-op.
pub(super) fn cleanup_cursor_user_hooks(home: &Path) -> anyhow::Result<()> {
    cleanup_managed_hooks_file(&home.join(".cursor/hooks.json"))
}

#[cfg(test)]
#[path = "integration_config_cursor_tests.rs"]
mod tests;
