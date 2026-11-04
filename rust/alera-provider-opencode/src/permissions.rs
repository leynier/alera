//! Session permission rules for the chat's runtime mode, as T3 Code writes
//! them. OpenCode has no OS sandbox, so the rules enforce the mode; the last
//! matching rule wins. A mode change restarts the provider with a new native
//! session, so rules are written when a session is created or resumed, and
//! for 1.x when a sub-agent session appears.

use crate::provider::{opencode_kind, OpenCodeProvider};
use alera_provider_protocol::{EventKind, ProviderError, ProviderEvent, RuntimeMode};
use opencode_agent_sdk::{
    Generation, HttpTransport, LegacyPermissionRule, OpenCodeEvent, PermissionRule,
};
use serde_json::{json, Value};

const ALWAYS_ALLOWED: [&str; 8] = [
    "question",
    "read",
    "glob",
    "grep",
    "lsp",
    "todowrite",
    "task",
    "skill",
];
const RESTRICTED: [&str; 7] = [
    "bash",
    "edit",
    "webfetch",
    "websearch",
    "codesearch",
    "external_directory",
    "doom_loop",
];

/// The runtime modes OpenCode enforces. `auto` has no OpenCode reviewer to
/// decide approvals, so it is refused rather than run as approval-required.
pub(crate) fn validate_mode(mode: RuntimeMode) -> Result<(), ProviderError> {
    match mode {
        RuntimeMode::ApprovalRequired | RuntimeMode::AutoAcceptEdits | RuntimeMode::FullAccess => {
            Ok(())
        }
        RuntimeMode::Auto => Err(ProviderError::Unsupported(
            "OpenCode has no auto runtime mode".into(),
        )),
    }
}

fn v2_rule(action: &str, effect: &str) -> PermissionRule {
    PermissionRule {
        action: action.into(),
        resource: "*".into(),
        effect: effect.into(),
    }
}

/// OpenCode 2.x rules: the mode's rules, then the chat's MCP rules.
pub(crate) fn v2_rules(mode: RuntimeMode, mcp: Vec<PermissionRule>) -> Vec<PermissionRule> {
    let mut rules = if mode == RuntimeMode::FullAccess {
        vec![v2_rule("*", "allow")]
    } else {
        let edit = if mode == RuntimeMode::AutoAcceptEdits {
            "allow"
        } else {
            "ask"
        };
        vec![
            v2_rule("shell", "ask"),
            v2_rule("edit", edit),
            v2_rule("external_directory", "ask"),
        ]
    };
    rules.extend(mcp);
    rules
}

/// OpenCode 1.x rules. Children inherit only deny and external-directory
/// rules, so denials come first and protect a child until its own rules land.
pub(crate) fn legacy_rules(mode: RuntimeMode) -> Vec<LegacyPermissionRule> {
    let rule = LegacyPermissionRule::new;
    if mode == RuntimeMode::FullAccess {
        return vec![rule("*", "*", "allow")];
    }
    let mut rules = vec![rule("*", "*", "deny")];
    rules.extend(RESTRICTED.iter().map(|name| rule(name, "*", "deny")));
    rules.push(rule("*", "*", "ask"));
    rules.extend(RESTRICTED.iter().map(|name| rule(name, "*", "ask")));
    rules.extend(ALWAYS_ALLOWED.iter().map(|name| rule(name, "*", "allow")));
    rules.extend([
        rule("read", "*.env", "ask"),
        rule("read", "*.env.*", "ask"),
        rule("read", "*.env.example", "allow"),
    ]);
    if mode == RuntimeMode::AutoAcceptEdits {
        rules.push(rule("edit", "*", "allow"));
    }
    rules
}

/// A 1.x sub-agent's rules: the parent's policy, then the agent's own
/// restrictions without the rules it inherited from the parent.
pub(crate) fn legacy_child_rules(
    mode: RuntimeMode,
    child: &[LegacyPermissionRule],
) -> Vec<LegacyPermissionRule> {
    let parent = legacy_rules(mode);
    let inherited: Vec<_> = parent
        .iter()
        .filter(|rule| rule.permission == "external_directory" || rule.action == "deny")
        .collect();
    let own: Vec<_> = child
        .iter()
        .filter(|rule| !inherited.contains(rule))
        .cloned()
        .collect();
    parent.into_iter().chain(own).collect()
}

impl<T: HttpTransport> OpenCodeProvider<T> {
    /// Writes the mode's rules into a 1.x sub-agent session of this chat
    /// when it is created. A failure leaves the inherited denials in place
    /// and is reported as a warning.
    pub(crate) async fn govern_child_session(&mut self, event: &OpenCodeEvent) {
        if event.event_type != "session.created"
            || self.client.config().generation != Generation::Legacy1
        {
            return;
        }
        let info = event
            .payload
            .get("properties")
            .and_then(|properties| properties.get("info"))
            .cloned()
            .unwrap_or(Value::Null);
        let (Some(id), Some(parent)) = (
            info.get("id").and_then(Value::as_str),
            info.get("parentID").and_then(Value::as_str),
        ) else {
            return;
        };
        if !self.session_family.contains(parent) || self.session_family.contains(id) {
            return;
        }
        let id = id.to_owned();
        self.session_family.insert(id.clone());
        let timeout = self.config.request_timeout;
        let result = async {
            let native = match LegacyPermissionRule::from_session(&info) {
                Some(rules) => rules,
                None => {
                    let record = crate::provider::timed(
                        timeout,
                        "session.get",
                        self.client.session_record(&id),
                    )
                    .await?;
                    LegacyPermissionRule::from_session(&record).unwrap_or_default()
                }
            };
            let rules = legacy_child_rules(self.runtime_mode, &native);
            crate::provider::timed(
                timeout,
                "session.update",
                self.client.update_session_legacy_permission(&id, &rules),
            )
            .await
        }
        .await;
        if let Err(error) = result {
            if let Ok(thread_id) = self.thread_id() {
                let message = format!(
                    "OpenCode could not apply the chat's runtime mode to sub-agent session {id}: {error}"
                );
                let mut warning = ProviderEvent::new(
                    opencode_kind(),
                    self.config.provider_instance_id.clone(),
                    thread_id,
                    EventKind::RuntimeWarning,
                    json!({ "message": message }),
                    None,
                );
                warning.turn_id = self.active_turn.as_ref().map(|turn| turn.id.clone());
                self.queued_events.push_back(warning);
            }
        }
    }
}
