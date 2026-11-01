//! Parsing and reading the inputs of the chat orchestration CLI: targets,
//! runtime responses, objects and text from flags, files or stdin.

use std::io::Read;

use anyhow::{bail, Context, Result};
use serde_json::Value;
use uuid::Uuid;

pub(super) fn parse_target(raw: &str) -> Result<Value> {
    let value = parse_object(raw, "target")?;
    let object = value.as_object().expect("parse_object returns an object");
    let keys = ["chat", "workspace", "newWorkspace"];
    let present = keys
        .iter()
        .filter(|key| object.get(**key).is_some())
        .count();
    if present != 1 || object.len() != 1 {
        bail!("target must contain exactly one of chat, workspace, or newWorkspace");
    }
    if let Some(chat) = object.get("chat") {
        require_nested_id(chat, "chatId", "target.chat")?;
    }
    if let Some(workspace) = object.get("workspace") {
        require_nested_id(workspace, "workspaceId", "target.workspace")?;
    }
    if let Some(workspace) = object.get("newWorkspace") {
        let object = workspace
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("target.newWorkspace must be an object"))?;
        require_nested_id(workspace, "projectId", "target.newWorkspace")?;
        require_nested_id(workspace, "hostId", "target.newWorkspace")?;
        match object.get("mode").and_then(Value::as_str) {
            Some("worktree") | Some("shared") => {}
            _ => bail!("target.newWorkspace.mode must be worktree or shared"),
        }
        if let Some(setup) = object.get("setup").and_then(Value::as_str) {
            if !matches!(setup, "inline" | "deferred") {
                bail!("target.newWorkspace.setup must be inline or deferred");
            }
        }
    }
    Ok(value)
}

pub(crate) fn validate_response(response: &Value) -> Result<()> {
    let object = response
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("response must be a JSON object"))?;
    let kind = object
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("response.type is required"))?;
    match kind {
        "approval" => match object.get("decision").and_then(Value::as_str) {
            Some("accept")
            | Some("acceptForSession")
            | Some("acceptAlways")
            | Some("decline")
            | Some("cancel") => Ok(()),
            _ => bail!("approval.decision is unsupported"),
        },
        "userInput" => {
            if object.get("answers").is_some_and(Value::is_object) {
                Ok(())
            } else {
                bail!("userInput.answers must be an object")
            }
        }
        "elicitation" => match object.get("action").and_then(Value::as_str) {
            Some("accept") | Some("decline") | Some("cancel") => Ok(()),
            _ => bail!("elicitation.action is unsupported"),
        },
        "native" => {
            if object.get("result").is_some() {
                Ok(())
            } else {
                bail!("native.result is required")
            }
        }
        _ => bail!("response.type must be approval, userInput, elicitation, or native"),
    }
}

pub(super) fn parse_object(raw: &str, label: &str) -> Result<Value> {
    let value: Value =
        serde_json::from_str(raw).with_context(|| format!("{label} is invalid JSON"))?;
    if !value.is_object() {
        bail!("{label} must be a JSON object");
    }
    Ok(value)
}

pub(super) fn require_nested_id(value: &Value, key: &str, label: &str) -> Result<()> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("{label} must be an object"))?;
    require_text(
        object.get(key).and_then(Value::as_str).unwrap_or_default(),
        &format!("{label}.{key}"),
    )?;
    Ok(())
}

pub(super) fn require_text(value: &str, label: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        bail!("{label} cannot be empty");
    }
    Ok(value.to_owned())
}

pub(super) fn optional_text(value: Option<String>, label: &str) -> Result<Option<String>> {
    value.map(|value| require_text(&value, label)).transpose()
}

pub(super) fn request_id(value: Option<String>) -> Result<String> {
    match value {
        Some(value) => require_text(&value, "request-id"),
        None => Ok(format!("cli-{}", Uuid::new_v4())),
    }
}

pub(super) fn read_text_source(
    inline: Option<String>,
    file: Option<&str>,
    stdin: bool,
    label: &str,
) -> Result<String> {
    let raw = if let Some(value) = inline {
        value
    } else if let Some(path) = file {
        std::fs::read_to_string(path)
            .with_context(|| format!("could not read {label} file: {path}"))?
    } else if stdin {
        let mut value = String::new();
        std::io::stdin()
            .read_to_string(&mut value)
            .with_context(|| format!("could not read {label} from stdin"))?;
        value
    } else {
        bail!("{label} is required");
    };
    require_text(&raw, label)
}

pub(super) fn read_json_source(
    inline: Option<String>,
    file: Option<&str>,
    stdin: bool,
    label: &str,
) -> Result<Value> {
    let raw = read_text_source(inline, file, stdin, label)?;
    serde_json::from_str(&raw).with_context(|| format!("{label} is invalid JSON"))
}
