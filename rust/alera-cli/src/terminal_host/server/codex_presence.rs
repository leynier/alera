//! Projects persisted Codex tabs into the existing sidebar agent presence.
//!
//! Codex conversations are not PTY sessions, so they use a synthetic handle
//! (`codex:<tabId>`) while retaining the same sidebar contract as agents.

use chrono::Utc;
use serde_json::{json, Value};

use super::codex_state::{is_codex_tab, snapshot};
use super::ServerActor;
use alera_core::runtime::WorkspaceTabRecord;

impl ServerActor {
    pub(super) fn schedule_codex_presence_changed(&mut self) {
        if self.codex_presence_scheduled {
            return;
        }
        self.codex_presence_scheduled = true;
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(24)).await;
            let _ = inbox.send(super::ServerCommand::CodexPresenceTick);
        });
    }

    pub(super) fn handle_codex_presence_tick(&mut self) {
        self.codex_presence_scheduled = false;
        self.broadcast_agent_presence_changed();
    }

    pub(super) async fn reconcile_codex_presence(&mut self) {
        let Ok(workspaces) = self.runtime_store.list_all_workspaces().await else {
            return;
        };
        let mut next = std::collections::HashMap::new();
        for workspace in workspaces {
            let Ok(tabs) = self.runtime_store.list_workspace_tabs(&workspace.id).await else {
                continue;
            };
            for tab in tabs.into_iter().filter(is_codex_tab) {
                let handle = codex_handle(&tab.id);
                if let Some(presence) = presence_for_tab(&tab, self.codex_presence.get(&handle)) {
                    next.insert(handle, presence);
                }
            }
        }
        self.codex_presence = next;
    }

    pub(super) fn refresh_codex_presence(&mut self, tab: &WorkspaceTabRecord) {
        if !is_codex_tab(tab) {
            return;
        }
        let handle = codex_handle(&tab.id);
        if let Some(presence) = presence_for_tab(tab, self.codex_presence.get(&handle)) {
            self.codex_presence.insert(handle, presence);
        } else {
            self.codex_presence.remove(&handle);
        }
    }

    pub(super) fn remove_codex_presence(&mut self, tab_id: &str) {
        self.codex_presence.remove(&codex_handle(tab_id));
    }
}

pub(super) fn codex_handle(tab_id: &str) -> String {
    format!("codex:{tab_id}")
}

fn presence_for_tab(tab: &WorkspaceTabRecord, previous: Option<&Value>) -> Option<Value> {
    let saved = snapshot(tab);
    let cells = saved.get("timelineCells").and_then(Value::as_array)?;
    let has_user_turn = cells
        .iter()
        .any(|cell| cell.get("kind").and_then(Value::as_str) == Some("userMessage"));
    if !has_user_turn {
        return None;
    }
    let pending = saved
        .get("pendingRequests")
        .and_then(Value::as_array)
        .is_some_and(|requests| !requests.is_empty());
    let active = saved
        .get("activeTurnId")
        .and_then(Value::as_str)
        .is_some_and(|turn| !turn.trim().is_empty());
    let failed = cells.iter().any(|cell| {
        cell.get("status").and_then(Value::as_str) == Some("failed")
            || cell.get("kind").and_then(Value::as_str) == Some("systemNotice")
                && cell.get("status").and_then(Value::as_str) == Some("failed")
    });
    let interrupted = saved
        .get("events")
        .and_then(Value::as_array)
        .and_then(|events| events.iter().rev().find_map(|event| event.get("method")))
        .and_then(Value::as_str)
        .is_some_and(|method| method == "turn/interrupted" || method == "turn/aborted");
    let state = if failed {
        "blocked"
    } else if pending {
        "waiting"
    } else if active {
        "working"
    } else {
        "done"
    };
    let handle = codex_handle(&tab.id);
    let previous_state = previous
        .and_then(|entry| entry.get("agentState"))
        .and_then(Value::as_str);
    let state_started_at = if previous_state == Some(state) {
        previous
            .and_then(|entry| entry.get("stateStartedAt"))
            .cloned()
            .unwrap_or_else(|| Value::String(Utc::now().to_rfc3339()))
    } else {
        Value::String(Utc::now().to_rfc3339())
    };
    let prompt = latest_cell_text(cells, "userMessage");
    let last_assistant_message = latest_cell_text(cells, "assistantMessage");
    let active_item = cells.iter().rev().find(|cell| {
        matches!(
            cell.get("kind").and_then(Value::as_str),
            Some("command" | "toolCall" | "diff" | "plan" | "subAgent")
        ) && cell.get("isStreaming").and_then(Value::as_bool) == Some(true)
    });
    Some(json!({
        "handle": handle,
        "terminalSessionId": handle,
        "workspaceId": tab.workspace_id,
        "tabId": tab.id,
        "running": active,
        "agentType": "codex",
        "agentState": state,
        "stateStartedAt": state_started_at,
        "updatedAt": Utc::now(),
        "prompt": prompt,
        "toolName": active_item.and_then(|cell| cell.get("title")).cloned(),
        "toolInput": active_item.and_then(|cell| cell.get("detailsText")).cloned(),
        "lastAssistantMessage": last_assistant_message,
        "interrupted": interrupted.then_some(true),
    }))
}

fn latest_cell_text(cells: &[Value], kind: &str) -> String {
    cells
        .iter()
        .rev()
        .find(|cell| cell.get("kind").and_then(Value::as_str) == Some(kind))
        .and_then(|cell| cell.get("markdownText"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::presence_for_tab;
    use alera_core::runtime::WorkspaceTabRecord;
    use chrono::Utc;
    use serde_json::{json, Value};

    fn tab(snapshot: Value) -> WorkspaceTabRecord {
        WorkspaceTabRecord {
            id: "tab-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "codex".to_string(),
            title: "Codex".to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({"codexSnapshot": snapshot}),
        }
    }

    #[test]
    fn does_not_advertise_an_empty_thread() {
        assert!(presence_for_tab(&tab(json!({"timelineCells": []})), None).is_none());
    }

    #[test]
    fn projects_working_waiting_and_blocked_states() {
        let working = tab(json!({
            "activeTurnId": "turn-1",
            "timelineCells": [
                {"kind": "userMessage", "markdownText": "Fix it"},
                {"kind": "toolCall", "title": "Search", "detailsText": "{}", "isStreaming": true}
            ]
        }));
        let working_presence = presence_for_tab(&working, None).unwrap();
        assert_eq!(working_presence["handle"], "codex:tab-1");
        assert_eq!(working_presence["terminalSessionId"], "codex:tab-1");
        assert_eq!(working_presence["agentState"], "working");
        assert_eq!(working_presence["toolName"], "Search");

        let waiting = tab(json!({
            "timelineCells": [{"kind": "userMessage", "markdownText": "Answer"}],
            "pendingRequests": [{"id": 3, "method": "item/tool/request_user_input"}]
        }));
        assert_eq!(
            presence_for_tab(&waiting, None).unwrap()["agentState"],
            "waiting"
        );

        let blocked = tab(json!({
            "timelineCells": [
                {"kind": "userMessage", "markdownText": "Fail"},
                {"kind": "systemNotice", "status": "failed"}
            ]
        }));
        assert_eq!(
            presence_for_tab(&blocked, None).unwrap()["agentState"],
            "blocked"
        );
    }

    #[test]
    fn preserves_state_started_at_when_state_is_unchanged() {
        let first = tab(json!({
            "timelineCells": [{"kind": "userMessage", "markdownText": "Done"}]
        }));
        let previous = presence_for_tab(&first, None).unwrap();
        let second = presence_for_tab(&first, Some(&previous)).unwrap();
        assert_eq!(second["stateStartedAt"], previous["stateStartedAt"]);
        assert_eq!(second["prompt"], "Done");
    }
}
