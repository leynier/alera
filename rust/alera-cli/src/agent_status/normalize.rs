use serde_json::Value;

use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};

use super::AgentHookEvent;

#[derive(Debug, Clone)]
pub struct NormalizedAgentStatus {
    pub state: AgentPresenceState,
    pub prompt: String,
    pub tool_name: Option<String>,
    pub tool_input: Option<String>,
    pub last_assistant_message: Option<String>,
    pub interrupted: Option<bool>,
    pub closes_session: bool,
    pub resets_session: bool,
}

pub fn normalize_hook_event(
    event: &AgentHookEvent,
    previous: Option<&AgentPresence>,
) -> Option<NormalizedAgentStatus> {
    let event_name = normalized_event_name(event)?;
    let tool_name = first_string(&event.payload, &["tool_name", "toolName", "name", "tool"]);
    let state = normalize_state(event, &event_name, tool_name.as_deref(), previous)?;
    let closes_session = matches!(
        (event.agent_type.as_str(), event_name.as_str()),
        ("copilot", "SessionEnd")
            | ("cursor", "sessionEnd")
            | ("pi", "session_shutdown")
            | ("grok", "SessionEnd")
    );
    let resets_session = event.agent_type == "grok" && event_name == "SessionStart";
    let prompt = first_string(
        &event.payload,
        &[
            "prompt",
            "user_prompt",
            "userPrompt",
            "initial_prompt",
            "initialPrompt",
            "user_message",
            "userMessage",
            "message",
        ],
    )
    .unwrap_or_else(|| previous.map_or_else(String::new, |entry| entry.prompt.clone()));
    let tool_input = first_value(
        &event.payload,
        &[
            "tool_input",
            "toolInput",
            "input",
            "arguments",
            "args",
            "command",
        ],
    )
    .map(value_preview)
    .or_else(|| previous.and_then(|entry| entry.tool_input.clone()));
    let last_assistant_message = assistant_message(event, &event_name)
        .or_else(|| previous.and_then(|entry| entry.last_assistant_message.clone()));
    Some(NormalizedAgentStatus {
        state,
        prompt,
        tool_name: tool_name.or_else(|| previous.and_then(|entry| entry.tool_name.clone())),
        tool_input,
        last_assistant_message,
        interrupted: interrupted(event, &event_name, state),
        closes_session,
        resets_session,
    })
}

fn normalize_state(
    event: &AgentHookEvent,
    name: &str,
    tool_name: Option<&str>,
    previous: Option<&AgentPresence>,
) -> Option<AgentPresenceState> {
    let human_input = tool_name.is_some_and(|tool| {
        let normalized = tool.to_ascii_lowercase();
        normalized.contains("askuser")
            || normalized.contains("request_user_input")
            || normalized.contains("human")
    });
    match event.agent_type.as_str() {
        "codex" => match name {
            "SessionStart" | "UserPromptSubmit" | "PostToolUse" => {
                Some(AgentPresenceState::Working)
            }
            "PreToolUse" if human_input => Some(AgentPresenceState::Waiting),
            "PreToolUse" => Some(AgentPresenceState::Working),
            "PermissionRequest" => Some(AgentPresenceState::Waiting),
            "Stop" => Some(AgentPresenceState::Done),
            _ => None,
        },
        "claude" => match name {
            "UserPromptSubmit" | "PostToolUse" | "PostToolUseFailure" => {
                Some(AgentPresenceState::Working)
            }
            "PreToolUse" if human_input => Some(AgentPresenceState::Waiting),
            "PreToolUse" => Some(AgentPresenceState::Working),
            "PermissionRequest" | "AskUserQuestion" => Some(AgentPresenceState::Waiting),
            "Stop" => Some(AgentPresenceState::Done),
            _ => None,
        },
        "copilot" => normalize_copilot(event, name, human_input),
        "cursor" => match name {
            "beforeSubmitPrompt" | "sessionStart" | "preToolUse" | "postToolUse"
            | "postToolUseFailure" => Some(AgentPresenceState::Working),
            "beforeShellExecution" | "beforeMCPExecution" => Some(AgentPresenceState::Waiting),
            "afterAgentResponse"
                if previous.is_some_and(|entry| entry.state == AgentPresenceState::Done) =>
            {
                Some(AgentPresenceState::Done)
            }
            "afterAgentResponse" => Some(AgentPresenceState::Working),
            "stop" | "sessionEnd" => Some(AgentPresenceState::Done),
            _ => None,
        },
        "agy" => match name {
            "PreInvocation" | "PostInvocation" | "PostToolUse" => Some(AgentPresenceState::Working),
            "PreToolUse" if human_input => Some(AgentPresenceState::Waiting),
            "PreToolUse" => Some(AgentPresenceState::Working),
            "Stop"
                if bool_field(&event.payload, "fullyIdle") == Some(false)
                    || bool_field(&event.payload, "fully_idle") == Some(false) =>
            {
                Some(AgentPresenceState::Working)
            }
            "Stop" => Some(AgentPresenceState::Done),
            _ => None,
        },
        "opencode" => match name {
            "SessionBusy" | "MessagePart" => Some(AgentPresenceState::Working),
            "PermissionRequest" | "AskUserQuestion" => Some(AgentPresenceState::Waiting),
            "SessionIdle" => Some(AgentPresenceState::Done),
            _ => None,
        },
        "pi" => match name {
            "before_agent_start"
            | "agent_start"
            | "tool_call"
            | "tool_execution_start"
            | "tool_execution_end"
            | "message_end" => Some(AgentPresenceState::Working),
            "agent_end" | "session_shutdown" => Some(AgentPresenceState::Done),
            _ => None,
        },
        "amp" => match name {
            "agent.start" | "tool.call" | "tool.result" => Some(AgentPresenceState::Working),
            "agent.end" => Some(AgentPresenceState::Done),
            _ => None,
        },
        "grok" => normalize_grok(event, name),
        _ => None,
    }
}

fn normalize_copilot(
    event: &AgentHookEvent,
    name: &str,
    human_input: bool,
) -> Option<AgentPresenceState> {
    let notification = first_string(&event.payload, &["notification_type", "notificationType"]);
    if (name == "Notification"
        && matches!(
            notification.as_deref(),
            Some("permission_prompt" | "elicitation_dialog")
        ))
        || ((name == "PreToolUse" || name == "PermissionRequest") && human_input)
    {
        return Some(AgentPresenceState::Blocked);
    }
    match name {
        "SessionStart" | "UserPromptSubmit" | "PreToolUse" | "PostToolUse"
        | "PostToolUseFailure" | "PermissionRequest" => Some(AgentPresenceState::Working),
        "Stop" | "SessionEnd" => Some(AgentPresenceState::Done),
        "ErrorOccurred" if bool_field(&event.payload, "recoverable") == Some(true) => {
            Some(AgentPresenceState::Working)
        }
        "ErrorOccurred" => Some(AgentPresenceState::Done),
        _ => None,
    }
}

fn normalize_grok(event: &AgentHookEvent, name: &str) -> Option<AgentPresenceState> {
    if name == "Notification" {
        let message = first_string(&event.payload, &["message"])?.to_ascii_lowercase();
        if [
            "type your message",
            "enter send",
            "shift-tab normal",
            "ask a side question",
        ]
        .iter()
        .any(|needle| message.contains(needle))
        {
            return Some(AgentPresenceState::Done);
        }
        if [
            "permission",
            "approval",
            "approve",
            "allow",
            "confirm",
            "feedback",
            "question",
        ]
        .iter()
        .any(|needle| message.contains(needle))
        {
            return Some(AgentPresenceState::Waiting);
        }
        return None;
    }
    match name {
        "UserPromptSubmit" | "PreToolUse" | "PostToolUse" | "PostToolUseFailure" => {
            Some(AgentPresenceState::Working)
        }
        "Stop" | "StopFailure" | "SessionEnd" => Some(AgentPresenceState::Done),
        _ => None,
    }
}

fn normalized_event_name(event: &AgentHookEvent) -> Option<String> {
    let raw = event.event_name.clone().or_else(|| {
        first_string(
            &event.payload,
            &["hook_event_name", "hookEventName", "hook_type", "hookType"],
        )
    })?;
    if event.agent_type == "copilot" {
        return Some(
            match raw.as_str() {
                "sessionStart" => "SessionStart",
                "sessionEnd" => "SessionEnd",
                "userPromptSubmitted" | "userPromptSubmit" => "UserPromptSubmit",
                "preToolUse" => "PreToolUse",
                "postToolUse" => "PostToolUse",
                "postToolUseFailure" => "PostToolUseFailure",
                "agentStop" | "stop" => "Stop",
                "errorOccurred" => "ErrorOccurred",
                "permissionRequest" => "PermissionRequest",
                "notification" => "Notification",
                _ => return Some(raw),
            }
            .to_string(),
        );
    }
    if event.agent_type == "grok" {
        let compact = raw
            .chars()
            .filter(|char| char.is_ascii_alphanumeric())
            .collect::<String>()
            .to_ascii_lowercase();
        return Some(
            match compact.as_str() {
                "sessionstart" => "SessionStart",
                "userpromptsubmit" => "UserPromptSubmit",
                "pretooluse" => "PreToolUse",
                "posttooluse" => "PostToolUse",
                "posttoolusefailure" => "PostToolUseFailure",
                "notification" => "Notification",
                "stop" => "Stop",
                "stopfailure" => "StopFailure",
                "sessionend" => "SessionEnd",
                _ => return Some(raw),
            }
            .to_string(),
        );
    }
    Some(raw)
}

fn assistant_message(event: &AgentHookEvent, name: &str) -> Option<String> {
    if matches!(
        (event.agent_type.as_str(), name),
        ("opencode", "MessagePart") | ("pi", "message_end")
    ) && first_string(&event.payload, &["role"]).as_deref() == Some("assistant")
    {
        return first_string(&event.payload, &["text"]);
    }
    if event.agent_type == "cursor" && name == "afterAgentResponse" {
        return first_string(&event.payload, &["text"]);
    }
    first_string(
        &event.payload,
        &[
            "lastAssistantMessage",
            "assistant_message",
            "assistantMessage",
        ],
    )
}

fn interrupted(event: &AgentHookEvent, name: &str, state: AgentPresenceState) -> Option<bool> {
    if state != AgentPresenceState::Done {
        return None;
    }
    let interrupted = bool_field(&event.payload, "interrupted") == Some(true)
        || first_string(&event.payload, &["status"]).as_deref() == Some("cancelled")
        || name.contains("Failure");
    interrupted.then_some(true)
}

fn first_string(value: &Value, keys: &[&str]) -> Option<String> {
    let record = value.as_object()?;
    keys.iter().find_map(|key| {
        let value = record.get(*key)?.as_str()?.trim();
        (!value.is_empty()).then(|| value.to_string())
    })
}

fn first_value<'a>(value: &'a Value, keys: &[&str]) -> Option<&'a Value> {
    let record = value.as_object()?;
    keys.iter().find_map(|key| record.get(*key))
}

fn bool_field(value: &Value, key: &str) -> Option<bool> {
    value.as_object()?.get(key)?.as_bool()
}

fn value_preview(value: &Value) -> String {
    let text = value
        .as_str()
        .map(str::to_string)
        .unwrap_or_else(|| value.to_string());
    text.chars().take(2_000).collect()
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn event(agent_type: &str, event_name: &str, payload: Value) -> AgentHookEvent {
        AgentHookEvent {
            terminal_session_id: "session-1".into(),
            workspace_id: "workspace-1".into(),
            tab_id: "tab-1".into(),
            agent_type: agent_type.into(),
            payload,
            event_name: Some(event_name.into()),
        }
    }

    #[test]
    fn every_supported_agent_reports_working() {
        for (agent_type, event_name) in [
            ("codex", "UserPromptSubmit"),
            ("claude", "UserPromptSubmit"),
            ("copilot", "userPromptSubmitted"),
            ("cursor", "beforeSubmitPrompt"),
            ("agy", "PreInvocation"),
            ("opencode", "SessionBusy"),
            ("pi", "agent_start"),
            ("amp", "agent.start"),
            ("grok", "UserPromptSubmit"),
        ] {
            let status = normalize_hook_event(&event(agent_type, event_name, json!({})), None)
                .unwrap_or_else(|| panic!("{agent_type} event was not normalized"));
            assert_eq!(status.state, AgentPresenceState::Working, "{agent_type}");
        }
    }

    #[test]
    fn codex_waiting_status_preserves_prompt_and_tool_details() {
        let status = normalize_hook_event(
            &event(
                "codex",
                "PreToolUse",
                json!({
                    "prompt": "Choose a deployment",
                    "tool_name": "request_user_input",
                    "tool_input": {"environment": "production"}
                }),
            ),
            None,
        )
        .expect("codex status");

        assert_eq!(status.state, AgentPresenceState::Waiting);
        assert_eq!(status.prompt, "Choose a deployment");
        assert_eq!(status.tool_name.as_deref(), Some("request_user_input"));
        assert!(status.tool_input.as_deref().is_some_and(|value| {
            value.contains("environment") && value.contains("production")
        }));
    }
}
