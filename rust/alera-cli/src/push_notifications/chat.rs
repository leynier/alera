use std::collections::{HashMap, HashSet};

use alera_provider_protocol::RequestKind;
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use super::{PushEvent, PushLocation};

#[derive(Default)]
pub(crate) struct ChatPushTracker {
    cursors: HashMap<String, i64>,
    requests: HashMap<String, HashSet<String>>,
    tasks: HashMap<String, i64>,
}

pub(crate) struct ChatPushRequest {
    pub(crate) request_id: String,
    pub(crate) kind: &'static str,
    pub(crate) created_at: DateTime<Utc>,
}

impl ChatPushTracker {
    /// Only committed request-list changes can create attention. Replayed
    /// cursors, removals, and updates to an existing request stay quiet.
    pub(crate) fn new_requests(
        &mut self,
        chat_id: &str,
        cursor: i64,
        delta: &Value,
    ) -> Vec<ChatPushRequest> {
        if self
            .cursors
            .get(chat_id)
            .is_some_and(|known| *known >= cursor)
        {
            return Vec::new();
        }
        self.cursors.insert(chat_id.into(), cursor);
        let Some(requests) = delta["requests"].as_array() else {
            return Vec::new();
        };
        let seen = self.requests.entry(chat_id.into()).or_default();
        let mut added = Vec::new();
        for request in requests {
            let Some(id) = request["requestId"].as_str().filter(|id| !id.is_empty()) else {
                continue;
            };
            if seen.insert(id.to_owned()) {
                if let (Some(kind), Some(created_at)) = (
                    request_attention_kind(&request["kind"]),
                    request["createdAt"]
                        .as_str()
                        .and_then(|at| DateTime::parse_from_rfc3339(at).ok()),
                ) {
                    added.push(ChatPushRequest {
                        request_id: id.into(),
                        kind,
                        created_at: created_at.with_timezone(&Utc),
                    });
                }
            }
        }
        added
    }

    pub(crate) fn new_task_revision(&mut self, task_id: &str, revision: i64) -> bool {
        if self
            .tasks
            .get(task_id)
            .is_some_and(|known| *known >= revision)
        {
            return false;
        }
        self.tasks.insert(task_id.into(), revision);
        true
    }

    pub(crate) fn forget_chat(&mut self, chat_id: &str) {
        self.cursors.remove(chat_id);
        self.requests.remove(chat_id);
    }
}

fn request_attention_kind(kind: &Value) -> Option<&'static str> {
    match serde_json::from_value(kind.clone()).ok()? {
        RequestKind::CommandExecutionApproval
        | RequestKind::FileReadApproval
        | RequestKind::FileChangeApproval
        | RequestKind::ApplyPatchApproval
        | RequestKind::ExecCommandApproval
        | RequestKind::PermissionApproval => Some("approval"),
        RequestKind::ToolUserInput | RequestKind::McpElicitationApproval => Some("question"),
        _ => None,
    }
}

impl PushEvent {
    pub(crate) fn chat_request(
        chat_id: &str,
        request_id: &str,
        kind: &str,
        occurred_at: DateTime<Utc>,
        location: PushLocation,
    ) -> Self {
        Self {
            event_id: domain_event_id("chat-request", &[chat_id, request_id]),
            category: "attention".into(),
            event_type: "agent_chat_request".into(),
            title: match kind {
                "question" | "elicitation" => "Agent Chat needs an answer",
                _ => "Agent Chat needs approval",
            }
            .into(),
            body: super::event::location_body(&location),
            data: json!({
                "kind": "agentChat", "chatId": chat_id, "requestId": request_id,
                "workspaceId": location.workspace_id, "tabId": location.tab_id,
            }),
            occurred_at,
        }
    }

    pub(crate) fn chat_task_attention(
        task_id: &str,
        revision: i64,
        needs_input: bool,
        chat_id: Option<&str>,
        occurred_at: DateTime<Utc>,
        location: Option<PushLocation>,
    ) -> Self {
        Self {
            event_id: domain_event_id("chat-task", &[task_id, &revision.to_string()]),
            category: "attention".into(),
            event_type: if needs_input {
                "chat_task_needs_input"
            } else {
                "chat_task_attention"
            }
            .into(),
            title: "Chat Task needs attention".into(),
            body: location
                .as_ref()
                .map(super::event::location_body)
                .unwrap_or_else(|| "Open Activity in Alera".into()),
            data: json!({
                "kind": "chatTask", "taskId": task_id, "chatId": chat_id,
                "workspaceId": location.as_ref().and_then(|location| location.workspace_id.as_deref()),
                "tabId": location.as_ref().and_then(|location| location.tab_id.as_deref()),
            }),
            occurred_at,
        }
    }
}

fn domain_event_id(domain: &str, ids: &[&str]) -> String {
    let mut digest = Sha256::new();
    for id in ids {
        digest.update((id.len() as u64).to_be_bytes());
        digest.update(id.as_bytes());
    }
    format!("{domain}:{}", hex::encode(digest.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn committed_requests_ignore_replay_updates_and_removals() {
        let mut tracker = ChatPushTracker::default();
        let request = json!({"requestId":"request", "kind":"tool_user_input", "createdAt":Utc::now().to_rfc3339(), "questions":["private"]});
        assert_eq!(
            tracker
                .new_requests("chat", 1, &json!({"requests":[request]}))
                .len(),
            1
        );
        assert!(tracker
            .new_requests("chat", 1, &json!({"requests":[request]}))
            .is_empty());
        assert!(tracker
            .new_requests("chat", 2, &json!({"requests":[request]}))
            .is_empty());
        assert!(tracker
            .new_requests("chat", 3, &json!({"requests":[]}))
            .is_empty());
        assert!(tracker
            .new_requests("chat", 4, &json!({"requests":[request]}))
            .is_empty());
        assert!(tracker
            .new_requests("chat", 2, &json!({"requests":[request]}))
            .is_empty());
    }

    #[test]
    fn request_push_contains_only_identifiers_and_is_idempotent() {
        let location = PushLocation {
            terminal_session_id: None,
            workspace_id: Some("workspace".into()),
            tab_id: Some("tab".into()),
            project_name: None,
            workspace_name: None,
            tab_title: None,
        };
        let first =
            PushEvent::chat_request("chat", "request", "question", Utc::now(), location.clone());
        let duplicate =
            PushEvent::chat_request("chat", "request", "question", Utc::now(), location);
        assert_eq!(first.event_id, duplicate.event_id);
        assert_eq!(first.category, "attention");
        assert_eq!(
            first.data,
            json!({"kind":"agentChat","chatId":"chat","requestId":"request","workspaceId":"workspace","tabId":"tab"})
        );
    }

    #[test]
    fn task_changes_dedupe_revisions_and_route_even_without_a_chat() {
        let mut tracker = ChatPushTracker::default();
        assert!(tracker.new_task_revision("task", 2));
        assert!(!tracker.new_task_revision("task", 2));
        assert!(!tracker.new_task_revision("task", 1));
        let event = PushEvent::chat_task_attention("task", 2, false, None, Utc::now(), None);
        assert_eq!(event.data["taskId"], "task");
        assert_eq!(event.data["kind"], "chatTask");
        assert_eq!(event.body, "Open Activity in Alera");
    }

    #[test]
    fn nearby_chats_keep_distinct_tap_targets_and_same_chat_can_batch() {
        let location = PushLocation {
            terminal_session_id: None,
            workspace_id: Some("workspace".into()),
            tab_id: Some("tab".into()),
            project_name: None,
            workspace_name: None,
            tab_title: None,
        };
        let first = PushEvent::chat_request(
            "first-chat",
            "request-1",
            "approval",
            Utc::now(),
            location.clone(),
        );
        let second = PushEvent::chat_request(
            "second-chat",
            "request-2",
            "question",
            Utc::now(),
            location.clone(),
        );
        let groups = super::super::grouped_events_by_category(vec![first.clone(), second]);
        assert_eq!(groups.len(), 2);
        assert!(groups
            .iter()
            .any(|group| group.data["chatId"] == "first-chat"));
        assert!(groups
            .iter()
            .any(|group| group.data["chatId"] == "second-chat"));
        let same_chat =
            PushEvent::chat_request("first-chat", "request-3", "question", Utc::now(), location);
        let groups = super::super::grouped_events_by_category(vec![first, same_chat]);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].data["chatId"], "first-chat");
        assert_eq!(groups[0].data["count"], 2);
    }
}
