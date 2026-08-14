//! Alera-owned presentation metadata for user messages sent to Codex.

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Map, Value};

use super::codex_state::{
    persist_snapshot, render_markdown, snapshot, snapshot_delta, tab_thread_id, trim_cells,
};
use super::codex_tab_lifecycle::{active_cwd, configuration};
use super::ServerActor;

const MAX_PRESENTATION_ATTACHMENTS: usize = 64;
const MAX_PRESENTATION_PATH_BYTES: usize = 8 * 1024;
const MAX_PRESENTATION_NAME_BYTES: usize = 512;

impl ServerActor {
    pub(super) async fn persist_codex_user_input(
        &mut self,
        tab_id: &str,
        input: &Value,
        user_message: Option<&Value>,
        turn_id: &str,
        client_user_message_id: Option<&str>,
        is_steering: bool,
    ) {
        let mut next = match self.codex_tab(tab_id).await {
            Ok(next) => next,
            Err(error) => {
                tracing::warn!(
                    tab_id,
                    turn_id,
                    is_steering,
                    "could not load the Codex tab to persist user presentation: {error}"
                );
                return;
            }
        };
        let previous_snapshot = snapshot(&next);
        let next_snapshot = append_user_input(
            &mut next,
            input,
            user_message,
            turn_id,
            client_user_message_id,
            is_steering,
        );
        let saved = match self.runtime_store.upsert_workspace_tab(next).await {
            Ok(saved) => saved,
            Err(error) => {
                tracing::warn!(
                    tab_id,
                    turn_id,
                    is_steering,
                    "could not persist Codex user presentation after the app-server accepted it: {error}"
                );
                return;
            }
        };
        self.refresh_codex_presence(&saved);
        self.schedule_codex_presence_changed();
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": tab_thread_id(&saved),
                "cwd": active_cwd(&saved),
                "configuration": configuration(&saved),
                "snapshot": snapshot(&saved),
                "snapshotDelta": snapshot_delta(&previous_snapshot, &next_snapshot, &[]),
            }),
        ));
    }
}

pub(super) fn append_user_input(
    tab: &mut WorkspaceTabRecord,
    input: &Value,
    user_message: Option<&Value>,
    turn_id: &str,
    client_user_message_id: Option<&str>,
    is_steering: bool,
) -> Value {
    let text = visible_text(input, user_message);
    let attachments = presentation_attachments(input, user_message);
    let cell_id = client_user_message_id
        .filter(|value| !value.trim().is_empty())
        .map(|value| format!("user-{value}"))
        .unwrap_or_else(|| format!("user-{turn_id}"));
    let mut metadata = Map::new();
    if !attachments.is_empty() {
        metadata.insert("attachments".to_string(), Value::Array(attachments));
    }
    if is_steering {
        metadata.insert("isSteering".to_string(), Value::Bool(true));
    }
    if let Some(client_id) = client_user_message_id.filter(|value| !value.trim().is_empty()) {
        metadata.insert(
            "clientUserMessageId".to_string(),
            Value::String(client_id.to_string()),
        );
    }

    let mut next = snapshot(tab);
    let cells = next
        .as_object_mut()
        .and_then(|object| object.get_mut("timelineCells"))
        .and_then(Value::as_array_mut);
    if let Some(cells) = cells {
        let now = Utc::now().to_rfc3339();
        let cell = json!({
            "id": cell_id,
            "turnId": turn_id,
            "kind": "userMessage",
            "status": "completed",
            "createdAt": now,
            "updatedAt": now,
            "isStreaming": false,
            "isCollapsed": false,
            "markdownText": text,
            "renderedMarkdownText": render_markdown(&text),
            "metadata": metadata,
        });
        if let Some(index) = cells.iter().position(|candidate| {
            candidate.get("id").and_then(Value::as_str) == cell.get("id").and_then(Value::as_str)
        }) {
            cells[index] = cell;
        } else {
            cells.push(cell);
        }
        trim_cells(cells);
    }
    if !is_steering {
        if let Some(object) = next.as_object_mut() {
            object.insert(
                "activeTurnId".to_string(),
                Value::String(turn_id.to_string()),
            );
        }
    }
    persist_snapshot(tab, next.clone());
    next
}

pub(super) fn append_goal_user_input(
    tab: &mut WorkspaceTabRecord,
    objective: &str,
    client_user_message_id: &str,
) -> Value {
    let previous_active_turn_id = snapshot(tab).get("activeTurnId").cloned();
    let turn_id = format!("goal-{client_user_message_id}");
    let input = json!([{"type": "text", "text": objective}]);
    let mut next = append_user_input(
        tab,
        &input,
        None,
        &turn_id,
        Some(client_user_message_id),
        false,
    );
    if let Some(object) = next.as_object_mut() {
        match previous_active_turn_id {
            Some(active_turn_id) => {
                object.insert("activeTurnId".to_string(), active_turn_id);
            }
            None => {
                object.remove("activeTurnId");
            }
        }
        let cell_id = format!("user-{client_user_message_id}");
        if let Some(cell) = object
            .get_mut("timelineCells")
            .and_then(Value::as_array_mut)
            .and_then(|cells| {
                cells
                    .iter_mut()
                    .find(|cell| cell.get("id").and_then(Value::as_str) == Some(cell_id.as_str()))
            })
        {
            if let Some(metadata) = cell.get_mut("metadata").and_then(Value::as_object_mut) {
                metadata.insert("isGoal".to_string(), Value::Bool(true));
            }
        }
    }
    persist_snapshot(tab, next.clone());
    next
}

fn visible_text(input: &Value, user_message: Option<&Value>) -> String {
    if let Some(text) = user_message
        .and_then(|message| message.get("text"))
        .and_then(Value::as_str)
    {
        return text.to_string();
    }
    input
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|part| {
            (part.get("type").and_then(Value::as_str) == Some("text"))
                .then(|| part.get("text").and_then(Value::as_str))
                .flatten()
        })
        .collect::<String>()
}

fn presentation_attachments(input: &Value, user_message: Option<&Value>) -> Vec<Value> {
    if let Some(attachments) = user_message
        .and_then(|message| message.get("attachments"))
        .and_then(Value::as_array)
    {
        return attachments
            .iter()
            .filter_map(normalize_attachment)
            .take(MAX_PRESENTATION_ATTACHMENTS)
            .collect();
    }
    input
        .as_array()
        .into_iter()
        .flatten()
        .filter(|part| part.get("type").and_then(Value::as_str) != Some("text"))
        .take(MAX_PRESENTATION_ATTACHMENTS)
        .cloned()
        .collect()
}

fn normalize_attachment(value: &Value) -> Option<Value> {
    let source = value.as_object()?;
    let path = source.get("path")?.as_str()?;
    if path.trim().is_empty() || path.len() > MAX_PRESENTATION_PATH_BYTES {
        return None;
    }
    let mut normalized = Map::new();
    normalized.insert("path".to_string(), Value::String(path.to_string()));
    for key in [
        "type",
        "kind",
        "origin",
        "mimeType",
        "detail",
        "annotationContext",
        "annotationUrl",
        "annotationTitle",
    ] {
        if let Some(value) = source
            .get(key)
            .and_then(Value::as_str)
            .filter(|value| value.len() <= MAX_PRESENTATION_NAME_BYTES)
        {
            normalized.insert(key.to_string(), Value::String(value.to_string()));
        }
    }
    for key in ["displayName", "name"] {
        if let Some(value) = source
            .get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .filter(|value| value.len() <= MAX_PRESENTATION_NAME_BYTES)
        {
            normalized.insert(key.to_string(), Value::String(value.to_string()));
        }
    }
    for key in ["isImage", "isDirectory"] {
        if let Some(value) = source.get(key).and_then(Value::as_bool) {
            normalized.insert(key.to_string(), Value::Bool(value));
        }
    }
    if let Some(value) = source.get("sizeBytes").and_then(Value::as_u64) {
        normalized.insert("sizeBytes".to_string(), Value::Number(value.into()));
    }
    if let Some(value) = source.get("annotationCount").and_then(Value::as_u64) {
        normalized.insert(
            "annotationCount".to_string(),
            Value::Number(value.min(20).into()),
        );
    }
    Some(Value::Object(normalized))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::protocol::CODEX_TAB_KIND;

    fn tab() -> WorkspaceTabRecord {
        WorkspaceTabRecord {
            id: "tab".to_string(),
            workspace_id: "workspace".to_string(),
            kind: CODEX_TAB_KIND.to_string(),
            title: "Codex Chat".to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({}),
        }
    }

    #[test]
    fn presentation_text_hides_model_only_file_references() {
        let input = json!([
            {"type": "text", "text": "Inspect this"},
            {"type": "text", "text": "\n\n/tmp/data.csv"}
        ]);
        let message = json!({
            "text": "Inspect this",
            "attachments": [{"type": "file", "path": "/tmp/data.csv"}]
        });
        assert_eq!(visible_text(&input, Some(&message)), "Inspect this");
        assert_eq!(presentation_attachments(&input, Some(&message)).len(), 1);
    }

    #[test]
    fn presentation_attachments_are_bounded_and_sanitized() {
        let message = json!({
            "attachments": [{
                "path": "/tmp/data.csv",
                "displayName": "data.csv",
                "unknown": {"large": true}
            }]
        });
        let attachments = presentation_attachments(&json!([]), Some(&message));
        assert_eq!(attachments[0]["displayName"], "data.csv");
        assert!(attachments[0].get("unknown").is_none());
    }

    #[test]
    fn structured_presentation_persists_exact_text_and_visual_attachments() {
        let mut record = tab();
        append_user_input(
            &mut record,
            &json!([
                {"type": "text", "text": "Y este?"},
                {
                    "type": "text",
                    "text": "\n\n/tmp/data.csv",
                    "text_elements": [{
                        "byteRange": {"start": 2, "end": 15},
                        "placeholder": "data.csv"
                    }]
                }
            ]),
            Some(&json!({
                "text": "Y este?",
                "attachments": [{
                    "path": "/tmp/data.csv",
                    "displayName": "data.csv",
                    "kind": "file",
                    "origin": "attachment",
                    "isImage": false,
                    "isDirectory": false
                }]
            })),
            "turn-1",
            Some("message-1"),
            false,
        );

        let saved = snapshot(&record);
        let cell = &saved["timelineCells"][0];
        assert_eq!(cell["id"], "user-message-1");
        assert_eq!(cell["markdownText"], "Y este?");
        assert_eq!(cell["metadata"]["attachments"][0]["path"], "/tmp/data.csv");
        assert_eq!(cell["metadata"]["clientUserMessageId"], "message-1");
        assert_eq!(saved["activeTurnId"], "turn-1");
    }

    #[test]
    fn goal_presentation_is_owned_by_alera_without_claiming_an_active_turn() {
        let mut record = tab();

        append_goal_user_input(&mut record, "Ship the release", "goal-message");

        let saved = snapshot(&record);
        let cell = &saved["timelineCells"][0];
        assert_eq!(cell["markdownText"], "Ship the release");
        assert_eq!(cell["metadata"]["isGoal"], true);
        assert_eq!(cell["metadata"]["clientUserMessageId"], "goal-message");
        assert!(saved.get("activeTurnId").is_none());
    }

    #[test]
    fn goal_presentation_preserves_an_existing_active_turn() {
        let mut record = tab();
        record.payload["codexSnapshot"]["activeTurnId"] = json!("turn-active");

        append_goal_user_input(&mut record, "Refine the release", "goal-message");

        assert_eq!(snapshot(&record)["activeTurnId"], "turn-active");
    }

    #[test]
    fn steering_presentation_keeps_the_existing_active_turn() {
        let mut record = tab();
        record.payload["codexSnapshot"] = json!({"activeTurnId": "turn-active"});

        append_user_input(
            &mut record,
            &json!([{"type": "text", "text": "Follow up"}]),
            None,
            "turn-active",
            Some("message-2"),
            true,
        );

        assert_eq!(snapshot(&record)["activeTurnId"], "turn-active");
    }

    #[test]
    fn app_server_echo_keeps_alera_owned_user_presentation() {
        let mut record = tab();
        append_user_input(
            &mut record,
            &json!([{"type": "text", "text": "Visible\n\n/tmp/data.csv"}]),
            Some(&json!({
                "text": "Visible",
                "attachments": [{"path": "/tmp/data.csv", "kind": "file"}]
            })),
            "turn-1",
            Some("message-1"),
            false,
        );
        super::super::codex_state::append_message(
            &mut record,
            json!({
                "method": "item/completed",
                "params": {
                    "turnId": "turn-1",
                    "item": {
                        "id": "item-1",
                        "type": "userMessage",
                        "clientId": "message-1",
                        "text": "Visible\n\n/tmp/data.csv"
                    }
                }
            }),
        );

        let saved = snapshot(&record);
        let cells = saved["timelineCells"].as_array().unwrap();
        assert_eq!(cells.len(), 1);
        assert_eq!(cells[0]["markdownText"], "Visible");
        assert_eq!(
            cells[0]["metadata"]["attachments"][0]["path"],
            "/tmp/data.csv"
        );
    }
}
