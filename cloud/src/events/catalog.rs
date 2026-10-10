//! The v1 runtime event catalog and its payload policy: events carry ids and states only,
//! never prompts, terminal output, code, commands, or message text.

use serde_json::{Map, Value};

/// The synthetic event a webhook test sends. Never accepted from a runtime.
pub const TEST_EVENT_KIND: &str = "alera.test";

/// One catalog entry: the event name and the `data` keys it may carry besides the
/// envelope fields (`runtimeId`, `workspaceId`, `projectId`, `seq`).
pub struct EventKind {
    pub name: &'static str,
    pub description: &'static str,
    pub keys: &'static [&'static str],
    /// Optional MCP Events filter arguments besides `runtime` and `workspaceId`.
    pub filters: &'static [&'static str],
}

/// Display names the policy allows on every event, as in mobile push payloads.
pub const NAME_KEYS: [&str; 2] = ["workspaceName", "projectName"];

pub const EVENT_KINDS: [EventKind; 11] = [
    EventKind {
        name: "inbox.reply",
        description: "An agent replied to a question in an Alera inbox. Read the thread with show_inbox_thread or wait_for_reply.",
        keys: &["inbox", "threadId", "questionId", "messageId", "originClientId"],
        filters: &["threadId", "questionId"],
    },
    EventKind {
        name: "inbox.question.status",
        description: "A question in an Alera inbox changed status (delivered, answered, expired, cancelled).",
        keys: &["questionId", "threadId", "status"],
        filters: &["threadId", "questionId"],
    },
    EventKind {
        name: "agent.status",
        description: "An agent in a workspace tab is waiting, blocked, or done.",
        keys: &["workspaceId", "tabId", "sessionId", "state"],
        filters: &["tabId"],
    },
    EventKind {
        name: "terminal.exit",
        description: "A terminal session exited.",
        keys: &["workspaceId", "tabId", "sessionId", "exitCode"],
        filters: &["tabId"],
    },
    EventKind {
        name: "orchestration.task.state",
        description: "An orchestration task changed state.",
        keys: &["taskId", "runId", "state"],
        filters: &["taskId", "runId"],
    },
    EventKind {
        name: "orchestration.gate.created",
        description: "An orchestration decision gate was created and waits for a person in Alera.",
        keys: &["gateId", "taskId", "runId"],
        filters: &["taskId", "runId"],
    },
    EventKind {
        name: "orchestration.escalation",
        description: "An orchestration task escalated.",
        keys: &["taskId", "runId"],
        filters: &["taskId", "runId"],
    },
    EventKind {
        name: "automation.run.state",
        description: "An automation run changed status.",
        keys: &["automationId", "runId", "status"],
        filters: &["automationId", "runId"],
    },
    EventKind {
        name: "workspace.start.state",
        description: "A New Workspace from Prompt operation changed phase or status.",
        keys: &["operationId", "status", "phase", "workspaceId"],
        filters: &["operationId"],
    },
    EventKind {
        name: "workspace.lifecycle",
        description: "A workspace was created, archived, unarchived, slept, woken, or removed.",
        keys: &["workspaceId", "action"],
        filters: &[],
    },
    EventKind {
        name: "pullRequest.watch",
        description: "Watch and Fix dispatched a fix, merged, or stopped for a pull request.",
        keys: &["workspaceId", "number", "action"],
        filters: &[],
    },
];

pub const MAX_DATA_KEYS: usize = 20;
pub const MAX_DATA_TEXT: usize = 512;

pub fn kind(name: &str) -> Option<&'static EventKind> {
    EVENT_KINDS.iter().find(|kind| kind.name == name)
}

/// Key fragments that may never name an event field, compared case-insensitively.
const SENSITIVE_FRAGMENTS: [&str; 9] = [
    "prompt",
    "body",
    "text",
    "output",
    "command",
    "subject",
    "scrollback",
    "terminalbytes",
    "content",
];

pub fn sensitive_key(key: &str) -> bool {
    let normalized = key.to_ascii_lowercase();
    SENSITIVE_FRAGMENTS
        .iter()
        .any(|fragment| normalized.contains(fragment))
}

/// Why a runtime's event `data` was refused.
#[derive(Debug, PartialEq, Eq)]
pub enum DataViolation {
    NotObject,
    TooManyKeys,
    InvalidKey,
    SensitiveKey,
    NotScalar,
    InvalidText,
}

/// Checks the generic payload policy: a flat object of at most 20 scalar fields whose
/// names are short identifiers that never suggest free text.
pub fn check_data(data: &Value) -> Result<(), DataViolation> {
    let object = data.as_object().ok_or(DataViolation::NotObject)?;
    if object.len() > MAX_DATA_KEYS {
        return Err(DataViolation::TooManyKeys);
    }
    for (key, value) in object {
        let valid_key = !key.is_empty()
            && key.len() <= 64
            && key
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'.');
        if !valid_key {
            return Err(DataViolation::InvalidKey);
        }
        if sensitive_key(key) {
            return Err(DataViolation::SensitiveKey);
        }
        match value {
            Value::String(text) => {
                if text.len() > MAX_DATA_TEXT || text.chars().any(char::is_control) {
                    return Err(DataViolation::InvalidText);
                }
            }
            Value::Bool(_) | Value::Number(_) | Value::Null => {}
            Value::Array(_) | Value::Object(_) => return Err(DataViolation::NotScalar),
        }
    }
    Ok(())
}

/// Keeps only the keys the catalog lists for this kind (plus display names). Anything
/// else is dropped before storage, so a new runtime field never leaks by default.
pub fn project_data(kind: &EventKind, data: &Value) -> Value {
    let mut projected = Map::new();
    if let Some(object) = data.as_object() {
        for (key, value) in object {
            let allowed = kind.keys.contains(&key.as_str()) || NAME_KEYS.contains(&key.as_str());
            if allowed && !value.is_null() {
                projected.insert(key.clone(), value.clone());
            }
        }
    }
    Value::Object(projected)
}

/// JSON Schema for an MCP Events subscription's arguments.
pub fn input_schema(kind: &EventKind) -> Value {
    let mut properties = Map::new();
    properties.insert(
        "runtime".to_owned(),
        string_property(
            "Runtime name or id. Omit to follow every runtime this connection reaches.",
        ),
    );
    properties.insert(
        "workspaceId".to_owned(),
        string_property("Only events for this workspace."),
    );
    for filter in kind.filters {
        properties.insert(
            (*filter).to_owned(),
            string_property("Only events whose data carries this value."),
        );
    }
    serde_json::json!({
        "type": "object",
        "properties": properties,
        "additionalProperties": false,
    })
}

/// JSON Schema for the `data` object of a delivered event.
pub fn payload_schema(kind: &EventKind) -> Value {
    let mut properties = Map::new();
    properties.insert(
        "runtimeId".to_owned(),
        serde_json::json!({"type": "string"}),
    );
    properties.insert(
        "workspaceId".to_owned(),
        serde_json::json!({"type": "string"}),
    );
    properties.insert(
        "projectId".to_owned(),
        serde_json::json!({"type": "string"}),
    );
    properties.insert("seq".to_owned(), serde_json::json!({"type": "integer"}));
    for key in kind.keys.iter().chain(NAME_KEYS.iter()) {
        let schema = match *key {
            "exitCode" | "number" => serde_json::json!({"type": "integer"}),
            _ => serde_json::json!({"type": "string"}),
        };
        properties.entry((*key).to_owned()).or_insert(schema);
    }
    serde_json::json!({
        "type": "object",
        "properties": properties,
        "required": ["runtimeId", "seq"],
        "additionalProperties": false,
    })
}

fn string_property(description: &str) -> Value {
    serde_json::json!({"type": "string", "minLength": 1, "maxLength": 128, "description": description})
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn every_kind_is_unique_and_lists_only_safe_keys() {
        let mut names: Vec<&str> = EVENT_KINDS.iter().map(|kind| kind.name).collect();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), EVENT_KINDS.len());
        for kind in &EVENT_KINDS {
            for key in kind.keys.iter().chain(kind.filters).chain(NAME_KEYS.iter()) {
                assert!(
                    !sensitive_key(key),
                    "{} lists sensitive key {key}",
                    kind.name
                );
            }
            for filter in kind.filters {
                assert!(kind.keys.contains(filter), "{} filter {filter}", kind.name);
            }
        }
    }

    #[test]
    fn rejects_free_text_and_nested_fields() {
        for key in [
            "prompt",
            "messageBody",
            "replyText",
            "terminalOutput",
            "command",
            "subject",
            "Scrollback",
        ] {
            assert_eq!(
                check_data(&json!({key: "x"})),
                Err(DataViolation::SensitiveKey),
                "{key}"
            );
        }
        assert_eq!(
            check_data(&json!({"ids": ["a"]})),
            Err(DataViolation::NotScalar)
        );
        assert_eq!(
            check_data(&json!({"meta": {"a": 1}})),
            Err(DataViolation::NotScalar)
        );
        assert_eq!(check_data(&json!(["a"])), Err(DataViolation::NotObject));
        assert_eq!(
            check_data(&json!({"bad key": 1})),
            Err(DataViolation::InvalidKey)
        );
        assert_eq!(
            check_data(&json!({"state": "x".repeat(513)})),
            Err(DataViolation::InvalidText)
        );
        let many: Map<String, Value> = (0..21)
            .map(|index| (format!("k{index}"), json!(index)))
            .collect();
        assert_eq!(
            check_data(&Value::Object(many)),
            Err(DataViolation::TooManyKeys)
        );
        assert_eq!(
            check_data(&json!({"threadId": "t", "exitCode": 1, "done": true, "x": null})),
            Ok(())
        );
    }

    #[test]
    fn projection_keeps_only_catalog_keys() {
        let Some(reply) = kind("inbox.reply") else {
            panic!("inbox.reply must exist");
        };
        let data = json!({"threadId": "t1", "questionId": "q1", "workspaceName": "Alpha", "unknown": "x", "inbox": null});
        assert_eq!(
            project_data(reply, &data),
            json!({"threadId": "t1", "questionId": "q1", "workspaceName": "Alpha"})
        );
    }

    #[test]
    fn schemas_name_every_filter_and_key() {
        let Some(start) = kind("workspace.start.state") else {
            panic!("workspace.start.state must exist");
        };
        let input = input_schema(start);
        assert!(input["properties"]["operationId"].is_object());
        assert!(input["properties"]["runtime"].is_object());
        assert_eq!(input["additionalProperties"], json!(false));
        let payload = payload_schema(start);
        assert_eq!(payload["properties"]["phase"]["type"], "string");
        assert_eq!(payload["properties"]["seq"]["type"], "integer");
    }
}

#[cfg(test)]
#[path = "catalog_edge_tests.rs"]
mod edge_tests;
