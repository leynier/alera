use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::alera_account::PushEventRequest;

#[derive(Debug, Clone)]
pub(crate) struct PushLocation {
    pub(crate) terminal_session_id: Option<String>,
    pub(crate) workspace_id: Option<String>,
    pub(crate) tab_id: Option<String>,
    pub(crate) project_name: Option<String>,
    pub(crate) workspace_name: Option<String>,
    pub(crate) tab_title: Option<String>,
}

#[derive(Debug, Clone)]
pub(crate) struct PushEvent {
    pub(crate) event_id: String,
    pub(crate) category: String,
    pub(crate) event_type: String,
    pub(crate) title: String,
    pub(crate) body: String,
    pub(crate) data: Value,
    pub(crate) occurred_at: DateTime<Utc>,
}

impl PushEvent {
    pub(crate) fn agent(
        agent_type: &str,
        state: &str,
        location: PushLocation,
        state_started_at: DateTime<Utc>,
    ) -> Option<Self> {
        let category = match state {
            "waiting" | "blocked" => "attention",
            "done" => "done",
            _ => return None,
        };
        let agent = agent_label(agent_type);
        let title = if category == "attention" {
            format!("{agent} needs attention")
        } else {
            format!("{agent} finished")
        };
        Some(Self {
            event_id: Uuid::new_v4().to_string(),
            category: category.to_string(),
            event_type: format!("agent_{state}"),
            title,
            body: location_body(&location),
            data: location_data(
                &location,
                json!({
                    "kind": "agentStatus",
                    "agentType": agent_type,
                    "state": state,
                    "stateStartedAt": state_started_at,
                }),
            ),
            occurred_at: Utc::now(),
        })
    }

    pub(crate) fn terminal_exit(location: PushLocation, exit_code: Option<i32>) -> Self {
        let title = match exit_code {
            Some(0) | None => "Terminal Ended".to_string(),
            Some(code) => format!("Terminal Exited With Code {code}"),
        };
        Self {
            event_id: Uuid::new_v4().to_string(),
            category: "terminalExit".to_string(),
            event_type: "terminal_exit".to_string(),
            title,
            body: location_body(&location),
            data: location_data(
                &location,
                json!({ "kind": "terminalExit", "exitCode": exit_code }),
            ),
            occurred_at: Utc::now(),
        }
    }

    pub(crate) fn decision_gate(task_id: &str, _question: &str, location: PushLocation) -> Self {
        Self {
            event_id: Uuid::new_v4().to_string(),
            category: "attention".to_string(),
            event_type: "decision_gate".to_string(),
            title: "Decision Needed".to_string(),
            body: location_body(&location),
            data: location_data(
                &location,
                json!({
                    "kind": "decisionGate",
                    "taskId": task_id,
                }),
            ),
            occurred_at: Utc::now(),
        }
    }

    pub(crate) fn escalation(task_id: &str, _subject: &str, location: PushLocation) -> Self {
        Self {
            event_id: Uuid::new_v4().to_string(),
            category: "attention".to_string(),
            event_type: "orchestration_escalation".to_string(),
            title: "Orchestration Escalation".to_string(),
            body: location_body(&location),
            data: location_data(
                &location,
                json!({
                    "kind": "orchestrationEscalation",
                    "taskId": task_id,
                }),
            ),
            occurred_at: Utc::now(),
        }
    }

    pub(crate) fn automation(
        automation_id: &str,
        run_id: &str,
        name: &str,
        status: &str,
        summary: Option<&str>,
        location: PushLocation,
    ) -> Self {
        let attention = matches!(status, "failure" | "blocked" | "timeout");
        let (category, title) = if attention {
            ("attention", format!("Automation {name} needs attention"))
        } else {
            ("done", format!("Automation {name} finished"))
        };
        Self {
            event_id: Uuid::new_v4().to_string(),
            category: category.to_string(),
            event_type: format!("automation_{status}"),
            title,
            body: summary
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| location_body(&location)),
            data: location_data(
                &location,
                json!({
                    "kind": "automation",
                    "automationId": automation_id,
                    "runId": run_id,
                    "status": status,
                    "route": "automation",
                }),
            ),
            occurred_at: Utc::now(),
        }
    }

    pub(crate) fn into_request(self, runtime_id: &str) -> PushEventRequest {
        PushEventRequest {
            runtime_id: runtime_id.to_string(),
            event_id: self.event_id,
            category: self.category,
            event_type: self.event_type,
            title: self.title,
            body: self.body,
            data: self.data,
            occurred_at: self.occurred_at,
        }
    }
}

pub(crate) fn grouped_event(events: Vec<PushEvent>) -> PushEvent {
    if events.len() == 1 {
        return events.into_iter().next().expect("single push event");
    }
    let count = events.len();
    let category = events
        .first()
        .map(|event| event.category.clone())
        .expect("non-empty push batch");
    debug_assert!(events.iter().all(|event| event.category == category));
    let mut labels = Vec::new();
    for event in &events {
        if !labels.contains(&event.body) {
            labels.push(event.body.clone());
        }
    }
    let body = labels.into_iter().take(3).collect::<Vec<_>>().join(", ");
    let first = events.into_iter().next().expect("non-empty push batch");
    let mut data = first.data;
    data["batched"] = Value::Bool(true);
    data["count"] = json!(count);
    PushEvent {
        event_id: Uuid::new_v4().to_string(),
        category: category.clone(),
        event_type: "grouped".to_string(),
        title: match category.as_str() {
            "attention" => format!("{count} Updates Need Attention"),
            "terminalExit" => format!("{count} Terminal Updates"),
            _ => format!("{count} Alera Updates"),
        },
        body,
        data,
        occurred_at: Utc::now(),
    }
}

/// Subscription filters are category-specific, so a batch must never cross a
/// category boundary. A terminal exit must not be delivered to an attention
/// subscription merely because it arrived in the same three-second window.
pub(crate) fn grouped_events_by_category(events: Vec<PushEvent>) -> Vec<PushEvent> {
    let mut groups = BTreeMap::<String, Vec<PushEvent>>::new();
    for event in events {
        groups
            .entry(event.category.clone())
            .or_default()
            .push(event);
    }
    groups.into_values().map(grouped_event).collect()
}

fn location_body(location: &PushLocation) -> String {
    let project = location.project_name.as_deref().unwrap_or_default().trim();
    let workspace = location
        .workspace_name
        .as_deref()
        .unwrap_or_default()
        .trim();
    if !workspace.is_empty() && !project.is_empty() && !workspace.eq_ignore_ascii_case(project) {
        return format!("Workspace {workspace} in {project}");
    }
    if !workspace.is_empty() {
        return format!("Workspace {workspace}");
    }
    let tab = location.tab_title.as_deref().unwrap_or_default().trim();
    if !tab.is_empty() {
        return format!("Terminal {tab}");
    }
    "Open Alera".to_string()
}

fn location_data(location: &PushLocation, mut data: Value) -> Value {
    data["terminalSessionId"] = json!(location.terminal_session_id);
    data["workspaceId"] = json!(location.workspace_id);
    data["tabId"] = json!(location.tab_id);
    data
}

fn agent_label(agent_type: &str) -> &'static str {
    match agent_type {
        "codex" => "Codex",
        "claude" => "Claude",
        "copilot" => "GitHub Copilot",
        "cursor" => "Cursor",
        "agy" => "Antigravity",
        "opencode" => "OpenCode",
        "opencode2" => "OpenCode 2",
        "pi" => "Pi",
        "amp" => "Amp",
        "grok" => "Grok Build",
        _ => "Agent",
    }
}

#[cfg(test)]
mod tests {
    use chrono::Utc;

    use super::{grouped_events_by_category, PushEvent, PushLocation};

    #[test]
    fn agent_payload_has_desktop_parity_without_prompt_content() {
        let event = PushEvent::agent(
            "codex",
            "waiting",
            PushLocation {
                terminal_session_id: Some("session".to_string()),
                workspace_id: Some("workspace".to_string()),
                tab_id: Some("tab".to_string()),
                project_name: Some("Alera".to_string()),
                workspace_name: Some("Push".to_string()),
                tab_title: Some("Secret prompt".to_string()),
            },
            Utc::now(),
        )
        .unwrap();
        assert_eq!(event.title, "Codex needs attention");
        assert_eq!(event.body, "Workspace Push in Alera");
        assert!(!event.data.to_string().contains("Secret prompt"));
    }

    #[test]
    fn batches_are_partitioned_before_grouping_categories() {
        let location = PushLocation {
            terminal_session_id: Some("session".to_string()),
            workspace_id: Some("workspace".to_string()),
            tab_id: Some("tab".to_string()),
            project_name: Some("Project".to_string()),
            workspace_name: Some("Workspace".to_string()),
            tab_title: Some("Terminal".to_string()),
        };
        let done =
            PushEvent::agent("codex", "done", location.clone(), Utc::now()).expect("done event");
        let terminal = PushEvent::terminal_exit(location, Some(0));
        let groups = grouped_events_by_category(vec![done, terminal]);

        assert_eq!(groups.len(), 2);
        assert!(groups.iter().any(|event| event.category == "done"));
        assert!(groups.iter().any(|event| event.category == "terminalExit"));
    }

    #[test]
    fn automation_events_use_attention_and_done_categories_with_tap_route() {
        let location = PushLocation {
            terminal_session_id: None,
            workspace_id: None,
            tab_id: None,
            project_name: None,
            workspace_name: None,
            tab_title: None,
        };
        let blocked = PushEvent::automation(
            "automation",
            "run-blocked",
            "Review",
            "blocked",
            Some("approval is required"),
            location.clone(),
        );
        assert_eq!(blocked.category, "attention");
        assert_eq!(blocked.data["kind"], "automation");
        assert_eq!(blocked.data["route"], "automation");
        assert_eq!(blocked.data["runId"], "run-blocked");

        let success = PushEvent::automation(
            "automation",
            "run-success",
            "Review",
            "success",
            None,
            location,
        );
        assert_eq!(success.category, "done");
        assert_eq!(success.data["status"], "success");
    }
}
