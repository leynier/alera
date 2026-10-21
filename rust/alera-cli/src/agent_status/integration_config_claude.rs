use std::path::Path;

use serde_json::{json, Map, Value};

use super::{is_alera_managed_command, managed_hook_definition, object_field};

// `Stop` never fires for an interrupted turn or an API error, so the turn can
// only be closed from `PostToolUseFailure.is_interrupt`, `StopFailure` and the
// `idle_prompt` notification. `SessionStart`/`SessionEnd` bracket each
// conversation so a resumed, cleared or exited agent does not keep its state.
// `SubagentStart`/`SubagentStop` track background sub-agents that keep working
// after the main turn's `Stop`.
pub(super) const CLAUDE_HOOK_EVENTS: &[(&str, Option<&str>)] = &[
    ("SessionStart", None),
    ("SessionEnd", None),
    ("UserPromptSubmit", None),
    ("Stop", None),
    ("StopFailure", None),
    ("Notification", None),
    ("SubagentStart", None),
    ("SubagentStop", None),
    ("PreToolUse", Some("*")),
    ("PostToolUse", Some("*")),
    ("PostToolUseFailure", Some("*")),
    ("PermissionRequest", Some("*")),
];

pub(super) fn install_claude_hooks_into(settings: &mut Map<String, Value>, script: &Path) {
    let hooks = object_field(settings, "hooks");
    for (event, matcher) in CLAUDE_HOOK_EVENTS {
        #[cfg(windows)]
        let command =
            super::super::integration_hook_scripts::claude_windows::managed_command(script, event);
        #[cfg(not(windows))]
        let command = super::managed_command(script, "claude", event);
        let mut definitions = clean_claude_definitions(hooks.remove(*event));
        let mut definition = managed_hook_definition(*matcher, &command);
        // Claude gives `SessionEnd` hooks 1.5 s unless they ask for more, and
        // the Windows hook starts PowerShell first.
        if *event == "SessionEnd" {
            definition["hooks"][0]["timeout"] = json!(5);
        }
        definitions.push(definition);
        hooks.insert((*event).to_string(), Value::Array(definitions));
    }
}

pub(super) fn clean_claude_definitions(value: Option<Value>) -> Vec<Value> {
    value
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .filter_map(|mut definition| {
            if let Some(handlers) = definition.get_mut("hooks").and_then(Value::as_array_mut) {
                let had = handlers.len();
                handlers.retain(|handler| !is_managed_handler(handler));
                if had > 0 && handlers.is_empty() {
                    return None;
                }
                Some(definition)
            } else if is_managed_handler(&definition) {
                None
            } else {
                Some(definition)
            }
        })
        .collect()
}

fn is_managed_handler(handler: &Value) -> bool {
    ["command", "bash", "powershell"]
        .into_iter()
        .filter_map(|key| handler.get(key).and_then(Value::as_str))
        .any(is_alera_managed_command)
}

#[cfg(test)]
#[path = "integration_config_claude_tests.rs"]
mod tests;
