//! The `request.opened` payload of an ACP permission request: the command
//! and working directory it asks to run, as T3 Code's
//! `extractToolCallCommand` reads them.

use alera_provider_protocol::RequestKind;
use serde_json::{json, Value};

fn command_value(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(command) => Some(command.trim().to_owned()).filter(|c| !c.is_empty()),
        Value::Array(parts) => {
            let parts: Vec<&str> = parts
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|part| !part.is_empty())
                .collect();
            (!parts.is_empty()).then(|| parts.join(" "))
        }
        _ => None,
    }
}

/// The command of a permission request's `toolCall`: `rawInput.command`,
/// then `executable` with its `args`, then, only for a command kind, the
/// first backtick span of the title.
pub(crate) fn permission_command(tool_call: &Value) -> Option<String> {
    if let Some(input) = tool_call.get("rawInput").filter(|input| input.is_object()) {
        if let Some(command) = command_value(input.get("command")) {
            return Some(command);
        }
        let executable = input
            .get("executable")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|executable| !executable.is_empty());
        if let Some(executable) = executable {
            return Some(match command_value(input.get("args")) {
                Some(args) => format!("{executable} {args}"),
                None => executable.to_owned(),
            });
        }
    }
    if !matches!(
        tool_call.get("kind").and_then(Value::as_str),
        Some("execute" | "command")
    ) {
        return None;
    }
    let title = tool_call.get("title").and_then(Value::as_str)?;
    let start = title.find('`')? + 1;
    let end = start + title[start..].find('`')?;
    Some(title[start..end].trim().to_owned()).filter(|command| !command.is_empty())
}

fn permission_cwd(tool_call: &Value) -> Option<&str> {
    let input = tool_call.get("rawInput")?;
    [
        "cwd",
        "Cwd",
        "workingDirectory",
        "WorkingDirectory",
        "working_dir",
        "workingDir",
    ]
    .iter()
    .find_map(|key| input.get(*key).and_then(Value::as_str))
    .map(str::trim)
    .filter(|cwd| !cwd.is_empty())
}

/// The `request.opened` payload of an approval request.
pub(crate) fn approval_payload(kind: RequestKind, params: &Value) -> Value {
    let tool_call = params.get("toolCall").unwrap_or(&Value::Null);
    let detail = params
        .get("title")
        .or_else(|| params.get("description"))
        .or_else(|| tool_call.get("title"));
    let mut payload = json!({
        "requestType": kind,
        "detail": detail,
        "args": params.get("subject").unwrap_or(params),
        "options": params.get("options").cloned().unwrap_or_else(|| json!([])),
    });
    if let Some(command) = permission_command(tool_call) {
        payload["command"] = Value::String(command);
    }
    if let Some(cwd) = permission_cwd(tool_call) {
        payload["cwd"] = Value::String(cwd.to_owned());
    }
    payload
}

#[cfg(test)]
mod tests {
    use super::permission_command;
    use serde_json::json;

    #[test]
    fn commands_follow_t3_codes_order() {
        assert_eq!(
            permission_command(&json!({"rawInput":{"command":["git","status"],"executable":"x"}}))
                .as_deref(),
            Some("git status")
        );
        assert_eq!(
            permission_command(&json!({"rawInput":{"executable":"npm","args":["test"]}}))
                .as_deref(),
            Some("npm test")
        );
        assert_eq!(
            permission_command(&json!({"rawInput":{"executable":"make"}})).as_deref(),
            Some("make")
        );
        assert_eq!(
            permission_command(&json!({"kind":"execute","title":"Run `cargo test` now"}))
                .as_deref(),
            Some("cargo test")
        );
        assert_eq!(
            permission_command(&json!({"kind":"edit","title":"Edit `main.rs`"})),
            None
        );
    }
}
