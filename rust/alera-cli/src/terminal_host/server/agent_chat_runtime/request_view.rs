//! Projects a provider's runtime request into the client request record,
//! offering exactly the decisions that adapter can honor.

use alera_provider_protocol::{RequestKind, RuntimeRequest};
use serde_json::{json, Value};

use super::wire::{json, ChatRequest};

const ACCEPT: &str = "accept";
const ACCEPT_FOR_SESSION: &str = "acceptForSession";
const ACCEPT_ALWAYS: &str = "acceptAlways";
const DECLINE: &str = "decline";
const CANCEL: &str = "cancel";

pub(crate) fn request_kind_wire(kind: RequestKind) -> String {
    json(&kind).as_str().unwrap_or("unknown").to_string()
}

pub(crate) fn is_approval(kind: RequestKind) -> bool {
    matches!(
        kind,
        RequestKind::CommandExecutionApproval
            | RequestKind::FileReadApproval
            | RequestKind::FileChangeApproval
            | RequestKind::ApplyPatchApproval
            | RequestKind::ExecCommandApproval
            | RequestKind::PermissionApproval
    )
}

pub(crate) fn build_request_view(
    provider: &str,
    request_id: String,
    request: &RuntimeRequest,
    event_payload: &Value,
    turn_id: Option<String>,
    item_id: Option<String>,
    now: &str,
) -> ChatRequest {
    let native = &request.payload;
    let args = event_payload.get("args").unwrap_or(native);
    let lookup = |key: &str| -> Option<String> {
        [args, native, event_payload]
            .iter()
            .find_map(|value| value.get(key).and_then(Value::as_str))
            .map(str::to_string)
            .filter(|value| !value.trim().is_empty())
    };
    let command = lookup("command").or_else(|| {
        args.get("command")
            .and_then(Value::as_array)
            .map(|parts| {
                parts
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .filter(|joined| !joined.is_empty())
    });
    let decisions = if is_approval(request.kind) {
        approval_decisions(provider, native)
    } else {
        Vec::new()
    };
    ChatRequest {
        request_id,
        kind: request_kind_wire(request.kind),
        turn_id,
        item_id,
        created_at: now.to_string(),
        title: lookup("title").or_else(|| Some(default_title(request.kind).to_string())),
        detail: event_payload
            .get("detail")
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| lookup("reason"))
            .or_else(|| lookup("message")),
        command,
        cwd: lookup("cwd"),
        path: lookup("path").or_else(|| lookup("filePath")),
        questions: request.questions.iter().map(json).collect(),
        decisions,
        elicitation: (request.kind == RequestKind::McpElicitationApproval)
            .then(|| elicitation(args, native)),
        expires_at: None,
        supports_feedback: request.supports_feedback && is_approval(request.kind),
        full_access_override: lookup("fullAccessOverride")
            .filter(|value| matches!(value.as_str(), "ask_rule" | "provider_check")),
    }
}

fn default_title(kind: RequestKind) -> &'static str {
    match kind {
        RequestKind::CommandExecutionApproval | RequestKind::ExecCommandApproval => "Run a command",
        RequestKind::FileReadApproval => "Read a file",
        RequestKind::FileChangeApproval | RequestKind::ApplyPatchApproval => "Change files",
        RequestKind::PermissionApproval => "Grant a permission",
        RequestKind::McpElicitationApproval => "An MCP server needs input",
        RequestKind::ToolUserInput => "The agent asked a question",
        RequestKind::DynamicToolCall => "The agent called a client tool",
        RequestKind::AuthTokensRefresh => "Refresh credentials",
        RequestKind::Unknown => "The agent needs a response",
    }
}

fn elicitation(args: &Value, native: &Value) -> Value {
    let pick = |key: &str| args.get(key).or_else(|| native.get(key)).cloned();
    let url = pick("url").filter(Value::is_string);
    json!({
        "mode": pick("mode").and_then(|mode| mode.as_str().map(str::to_string))
            .unwrap_or_else(|| if url.is_some() { "url".into() } else { "form".into() }),
        "message": pick("message").unwrap_or(Value::String(String::new())),
        "schema": pick("requestedSchema").or_else(|| pick("schema")).unwrap_or_else(|| json!({})),
        "url": url,
    })
}

/// What each adapter maps a decision onto. Anything not listed would be
/// silently folded into another decision, so it is not offered.
pub(crate) fn approval_decisions(provider: &str, native: &Value) -> Vec<String> {
    let list = |values: &[&str]| values.iter().map(|value| value.to_string()).collect();
    match provider {
        "codex" => list(&[ACCEPT, ACCEPT_FOR_SESSION, DECLINE, CANCEL]),
        "claudeAgent" | "pi" => list(&[ACCEPT, DECLINE, CANCEL]),
        "opencode" => list(&[ACCEPT, DECLINE]),
        "muse" => muse_decisions(native),
        "grok" | "antigravity" | "acpRegistry" => acp_decisions(provider == "grok", native),
        _ => Vec::new(),
    }
}

fn acp_decisions(grok: bool, native: &Value) -> Vec<String> {
    let Some(options) = native.get("options").and_then(Value::as_array) else {
        return vec![CANCEL.into()];
    };
    let kind = |option: &Value| {
        option
            .get("kind")
            .and_then(Value::as_str)
            .map(str::to_string)
    };
    let mut decisions = Vec::new();
    let mut push = |decision: &str| {
        if !decisions.iter().any(|existing| existing == decision) {
            decisions.push(decision.to_string());
        }
    };
    for option in options {
        match kind(option).as_deref() {
            Some("allow_once") => push(ACCEPT),
            Some("allow_always")
                if grok
                    && option.get("optionId").and_then(Value::as_str)
                        == Some("allow-edits-session") =>
            {
                push(ACCEPT_FOR_SESSION)
            }
            Some("allow_always") => push(ACCEPT_ALWAYS),
            Some("reject_once") => push(DECLINE),
            Some("reject_always") if !grok => push(DECLINE),
            _ => {}
        }
    }
    push(CANCEL);
    decisions
}

fn muse_decisions(native: &Value) -> Vec<String> {
    let Some(choices) = native.get("availableChoices").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut decisions: Vec<String> = Vec::new();
    for choice in choices {
        let decision = match choice.get("decision").and_then(Value::as_str) {
            Some("approved") => ACCEPT,
            Some("approvedForSession" | "approvedPolicyAmendment") => ACCEPT_FOR_SESSION,
            Some("abort" | "denied") => DECLINE,
            _ => continue,
        };
        if !decisions.iter().any(|existing| existing == decision) {
            decisions.push(decision.into());
        }
    }
    decisions
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acp_decisions_follow_the_offered_options() {
        let native = json!({"options": [
            {"kind": "allow_once", "optionId": "a"},
            {"kind": "reject_once", "optionId": "r"},
        ]});
        assert_eq!(
            approval_decisions("acpRegistry", &native),
            vec!["accept", "decline", "cancel"]
        );
        let grok = json!({"options": [
            {"kind": "allow_always", "optionId": "allow-edits-session"},
            {"kind": "allow_always", "optionId": "forever"},
        ]});
        assert_eq!(
            approval_decisions("grok", &grok),
            vec!["acceptForSession", "acceptAlways", "cancel"]
        );
    }

    #[test]
    fn providers_without_session_scope_do_not_offer_it() {
        assert!(!approval_decisions("pi", &json!({})).contains(&"acceptForSession".to_string()));
        assert!(approval_decisions("cursor", &json!({})).is_empty());
    }
}
