use crate::error::OpenCodeError;
use crate::model::OpenCodeSession;
use serde_json::{json, Value};

pub(crate) fn parse_session(body: Value) -> Result<OpenCodeSession, OpenCodeError> {
    let value = body.get("data").cloned().unwrap_or(body.clone());
    let id = value
        .get("id")
        .or_else(|| value.get("sessionID"))
        .and_then(Value::as_str)
        .ok_or_else(|| OpenCodeError::protocol("OpenCode session response has no id"))?;
    Ok(OpenCodeSession {
        id: id.to_owned(),
        title: value
            .get("title")
            .and_then(Value::as_str)
            .map(str::to_owned),
        directory: value
            .get("directory")
            .and_then(Value::as_str)
            .map(str::to_owned),
        parent_id: value
            .get("parentID")
            .and_then(Value::as_str)
            .map(str::to_owned),
        raw: body,
    })
}

pub(crate) fn model_value(model: &str) -> Value {
    let mut split = model.splitn(2, '/');
    match (split.next(), split.next()) {
        (Some(provider), Some(model)) => json!({ "providerID": provider, "modelID": model }),
        _ => Value::String(model.to_owned()),
    }
}

pub(crate) fn prompt_body(parts: Vec<Value>) -> Value {
    let mut text = String::new();
    let mut files = Vec::new();
    for part in parts {
        match part.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(value) = part.get("text").and_then(Value::as_str) {
                    if !text.is_empty() {
                        text.push('\n');
                    }
                    text.push_str(value);
                }
            }
            Some("file") => {
                if let Some(uri) = part
                    .get("uri")
                    .or_else(|| part.get("url"))
                    .and_then(Value::as_str)
                {
                    files.push(json!({ "uri": uri }));
                }
            }
            _ => {}
        }
    }
    let mut body = json!({ "text": text });
    if !files.is_empty() {
        body["files"] = Value::Array(files);
    }
    body
}

pub(crate) fn percent_encode(value: &str) -> String {
    value.bytes().fold(String::new(), |mut encoded, byte| {
        if byte.is_ascii_alphanumeric() || b"-._~/".contains(&byte) {
            encoded.push(byte as char);
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
        encoded
    })
}

pub(crate) fn percent_encode_query(value: &str) -> String {
    value.bytes().fold(String::new(), |mut encoded, byte| {
        if byte.is_ascii_alphanumeric() || b"-._~".contains(&byte) {
            encoded.push(byte as char);
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
        encoded
    })
}

pub(crate) fn is_execution_boundary(event_type: &str) -> bool {
    event_type.contains(".execution.")
        && ["started", "succeeded", "failed", "interrupted"]
            .iter()
            .any(|suffix| event_type.ends_with(suffix))
}

pub(crate) fn is_unknown_v2(event_type: &str) -> bool {
    const KNOWN: &[&str] = &[
        "server.connected",
        "message.updated",
        "message.part.updated",
        "message.part.delta",
        "session.created",
        "session.updated",
        "session.deleted",
        "session.status",
        "session.idle",
        "session.error",
        "session.compacted",
        "session.execution.started",
        "session.execution.succeeded",
        "session.execution.failed",
        "session.execution.interrupted",
        "session.step.started",
        "session.step.streamed",
        "session.step.ended",
        "session.step.failed",
        "session.text.started",
        "session.text.ended",
        "session.text.delta",
        "session.reasoning.started",
        "session.reasoning.ended",
        "session.reasoning.delta",
        "session.tool.input.started",
        "session.tool.input.ended",
        "session.tool.input.delta",
        "session.tool.called",
        "session.tool.progress",
        "session.tool.success",
        "session.tool.failed",
        "session.compaction.started",
        "session.compaction.delta",
        "session.compaction.ended",
        "session.compaction.failed",
        "session.usage.updated",
        "session.message.content.updated",
        "permission.asked",
        "permission.replied",
        "form.created",
        "form.replied",
        "form.cancelled",
        "question.asked",
        "question.replied",
        "question.rejected",
        "todo.updated",
        "command.updated",
        "unreadable.execution.started",
        "unreadable.execution.ended",
    ];
    !KNOWN.contains(&event_type)
}
